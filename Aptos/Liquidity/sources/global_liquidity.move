module dev::QiaraLiquidityV76 {
    use std::signer;
    use std::timestamp;
    use std::vector;    
    use std::bcs;
    use std::string::{Self as String, String, utf8};
    use std::table::{Self as table, Table};
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use aptos_std::string_utils::{Self as string_utils};
    use aptos_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata, FungibleAsset, FungibleStore};
    use aptos_framework::dispatchable_fungible_asset;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::account;
    use aptos_framework::from_bcs;

    use dev::QiaraTokensMetadataV56::{Self as TokensMetadata};
    use dev::QiaraTokensCoreV56::{Self as TokensCore, CoinMetadata, Access as TokensCoreAccess};
    use dev::QiaraTokensTiersV56::{Self as TokensTiers};

    use dev::QiaraMarginV58::{Self as Margin, Access as MarginAccess};
    use dev::QiaraRanksV58::{Self as Points, Access as PointsAccess};
    use dev::QiaraBurnedQiaraV58::{Self as BurnedQiara};
    use dev::QiaraSharedV17::{Self as Shared, Access as SharedAccess};
    use dev::QiaraChainTypesV56::{Self as ChainTypes};
    use dev::QiaraProviderTypesV56::{Self as ProviderTypes};
    use dev::QiaraGenesisV2::{Self as Genesis};

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_WITHDRAW_LIMIT_EXCEEDED: u64 = 2;
    const ERROR_EPOCH_MUST_BE_HIGHER_THAN_CURRENT: u64 = 3;
    const ERROR_EPOCH_MUST_BE_HIGHER_THAN_STARTING_EPOCH: u64 = 4;
    const ERROR_DURATION_MUST_BE_GREATER_THAN_ZERO: u64 = 5;
    const ERROR_INSUFFICIENT_BALANCE: u64 = 6;
    const ERROR_INVALID_LP_TOKEN: u64 = 7;
    const ERROR_WEIGHTS_MUST_ADD_TO_100: u64 = 8;

const ERROR_USER_INSUFFICIENT_LP_SHARES: u64 = 1001;
const ERROR_VAULT_INSUFFICIENT_LIQUIDITY: u64 = 1002;

// === ACCESS === //
    struct Access has store, key, drop {}
    struct Permission has key, drop {}

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @dev, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_permission(access: &Access): Permission {
        Permission {}
    }

    struct Permissions has key, store, drop {
        margin: MarginAccess,
        points: PointsAccess,
        tokens_core: TokensCoreAccess,
        shared_access: SharedAccess
    }

// === STRUCTS === //
     struct WithdrawTracker has key, store, copy, drop {
        day: u16,
        amount: u256,
        limit: u256,
    }

    struct Incentive has key, store, copy, drop {
        deployer: address,
        total_amount: u256,       
        reward_rate: u256,        // Virtual credits distributed per second globally
        deposit_weight: u256,     // Split weight for Lenders (scaled by 1e8, e.g. 70_000_000 = 70%)
        borrow_weight: u256,      // Split weight for Borrowers (scaled by 1e8, e.g. 30_000_000 = 30%)
        period_finish: u64,       
        last_update_time: u64,    
        deposit_index: u128,      // Global reward-per-share accumulator for Lenders
        borrow_index: u128,       // Global reward-per-debt accumulator for Borrowers
    }

    struct Vault has key, store, copy, drop {
        total_shares: u256,       // Actual supply of LP Share tokens in circulation
        total_borrowed: u256,
        total_deposited: u256,
        total_staked: u256,
        total_native_accumulated_rewards: u256, // bridged amount of actual total rewards (for everyone)
        total_accumulated_rewards: u256,        // Global tracking of collected fees (for burned qiara holders)
        accumulated_rewards_index: u128,        // Discrete Jump-Index for fees (for burned qiara holders)
        total_accumulated_interest: u256,       // Lending interest (for everyone)
        total_staked_locked_fee: u256,
        virtual_borrowed: u256, 
        virtual_deposited: u256, 
        storage: Object<FungibleStore>,         // Storage of the underlying asset
        incentive: Incentive,           
        w_tracker: WithdrawTracker,
        last_update: u64,
    }

    struct FullVault has key, store, copy, drop {
        vault: Vault,
        data: Data
    }

    struct Data has key, store, copy, drop {
        utilization: u256,
        qiara_native_apr: u256,
        final_lend_rate: u256,
        final_borrow_rate: u256
    }

    struct GlobalVault has key {
        //  token, chain, provider
        balances: Table<String, Map<String, Map<String, Vault>>>,
    }

    // === LP Token Capability Storage === //
    struct LPCapabilities has store {
        mint_ref: MintRef,
        burn_ref: BurnRef,
        lp_metadata: Object<Metadata>,
    }

    struct GlobalLPCapabilities has key {
        // Key: unique Vault resource address
        caps: Table<address, LPCapabilities>,
    }

// === INIT === //
    fun init_module(admin: &signer){
        if (!exists<GlobalVault>(@dev)) {
            move_to(admin, GlobalVault { balances: table::new<String, Map<String, Map<String, Vault>>>() });
        };
        if (!exists<GlobalLPCapabilities>(@dev)) {
            move_to(admin, GlobalLPCapabilities { caps: table::new<address, LPCapabilities>() });
        };
        if (!exists<Permissions>(@dev)) {
            move_to(admin, Permissions {shared_access: Shared::give_access(admin), margin: Margin::give_access(admin), points: Points::give_access(admin), tokens_core: TokensCore::give_access(admin)});
        };

        initialize_all_registered_vaults(admin);
    }

// === ENTRY FUN === //
    fun tttta(number: u64){
        abort(number);
    }

    fun non_user_storage_helper<T: key>(signer: &signer, obj: &Object<T>): String{
        let storage_address_bytes = string_utils::to_string(&object::object_address(obj));
            if(!Shared::assert_shared_storage((storage_address_bytes))){
                Shared::create_non_user_shared_storage(signer, (storage_address_bytes));
            };
        return (storage_address_bytes)
    }

    public entry fun initialize_all_registered_vaults(admin: &signer) acquires GlobalVault, GlobalLPCapabilities {
        let admin_addr = std::signer::address_of(admin);
        assert!(admin_addr == @dev, ERROR_NOT_ADMIN);

        let vaults = borrow_global_mut<GlobalVault>(@dev);
        let providers_ref = ProviderTypes::return_all_providers();
        
        let provider_keys = map::keys(&providers_ref);
        let i = 0;
        let num_providers = std::vector::length(&provider_keys);
        
        while (i < num_providers) {
            let provider = *std::vector::borrow(&provider_keys, i);
            let chains_map = map::borrow(&providers_ref, &provider);
            
            let chain_keys = map::keys(chains_map);
            let j = 0;
            let num_chains = std::vector::length(&chain_keys);
            
            while (j < num_chains) {
                let chain = *std::vector::borrow(&chain_keys, j);
                let provider_data = map::borrow(chains_map, &chain);
                let tokens = ProviderTypes::get_provider_tokens(provider_data);
                
                let k = 0;
                let num_tokens = std::vector::length(tokens);
                
                while (k < num_tokens) {
                    let token = *std::vector::borrow(tokens, k);
                    find_vault(vaults, token, chain, provider);
                    k = k + 1;
                };
                j = j + 1;
            };
            i = i + 1;
        };
    }

    public entry fun add_incentive(signer: &signer, shared: String, amount: u256,token: String, chain: String, provider: String, credits: u256, duration_seconds: u64,deposit_weight: u256,borrow_weight: u256) acquires GlobalVault, GlobalLPCapabilities, Permissions {
        Shared::assert_is_sub_owner(shared, bcs::to_bytes(&signer::address_of(signer)));
        assert!(duration_seconds > 0, ERROR_DURATION_MUST_BE_GREATER_THAN_ZERO);
        assert!(deposit_weight + borrow_weight == 100000000, ERROR_WEIGHTS_MUST_ADD_TO_100); // 1e8 = 100%
        assert!(amount > 0, 101);

        let vaults = borrow_global_mut<GlobalVault>(@dev);
        let vault = find_vault(vaults, token, chain, provider);

        // 2. Escrow REAL underlying - not just delete Margin record
        // amount is 1e18 scaled, FA amount is u64
        let fa_amount_u64 = (amount / 1000000000000000000 as u64);
        assert!(fa_amount_u64 > 0, ERROR_INSUFFICIENT_BALANCE);
        
        // withdraw from user's shared storage
        let user_shared_store = Shared::ensure_shared_fungible_storage(shared, TokensCore::get_metadata(token), Shared::give_permission(&borrow_global<Permissions>(@dev).shared_access));
        let fa_to_lock = TokensCore::withdraw(shared, user_shared_store, fa_amount_u64, chain);
        
        // deposit to vault's storage so it actually backs the rewards
        let storage_address_string = non_user_storage_helper(signer,&vault.storage);
        TokensCore::deposit(storage_address_string, vault.storage, fa_to_lock, chain);

        // 3. Sync incentive index before changing reward_rate
        let current_time = timestamp::now_seconds();
        let last_applicable_time = if (current_time < vault.incentive.period_finish) { current_time } else { vault.incentive.period_finish };
        
        if (vault.incentive.period_finish != 0 && last_applicable_time > vault.incentive.last_update_time) {
            let elapsed = last_applicable_time - vault.incentive.last_update_time;
            let total_rewards_accrued = vault.incentive.reward_rate * (elapsed as u256);
            let scale = 1000000000000000000;   
            if (vault.total_shares > 0) {
                let deposit_rewards = (total_rewards_accrued * vault.incentive.deposit_weight) / 100000000;
                vault.incentive.deposit_index = vault.incentive.deposit_index + ((deposit_rewards * scale / vault.total_shares) as u128);
            };
            if (vault.total_borrowed > 0) {
                let borrow_rewards = (total_rewards_accrued * vault.incentive.borrow_weight) / 100000000;
                vault.incentive.borrow_index = vault.incentive.borrow_index + ((borrow_rewards * scale / vault.total_borrowed) as u128);
            };
        };

        if (vault.incentive.period_finish == 0) {
            // new incentive
            vault.incentive = Incentive {
                deployer: signer::address_of(signer),
                total_amount: amount,
                reward_rate: amount / (duration_seconds as u256),
                deposit_weight,
                borrow_weight,
                period_finish: current_time + duration_seconds,
                last_update_time: current_time,
                deposit_index: if (vault.incentive.deposit_index == 0) { 0 } else { vault.incentive.deposit_index },
                borrow_index: if (vault.incentive.borrow_index == 0) { 0 } else { vault.incentive.borrow_index },
            };
        } else {
            // add to existing - combine remaining + new
            let remaining_time = if (current_time < vault.incentive.period_finish) { vault.incentive.period_finish - current_time } else { 0 };
            let remaining_credits = vault.incentive.reward_rate * (remaining_time as u256);
            let combined_credits = remaining_credits + amount;

            vault.incentive.reward_rate = combined_credits / (duration_seconds as u256);
            vault.incentive.period_finish = current_time + duration_seconds;
            vault.incentive.last_update_time = current_time;
            vault.incentive.total_amount = vault.incentive.total_amount + amount;
            vault.incentive.deposit_weight = deposit_weight; // update weights
            vault.incentive.borrow_weight = borrow_weight;
            vault.incentive.deployer = signer::address_of(signer); 
        };
    }

public fun admin_accrue_rewards_from_lz(
    signer: &signer,
    token: String, 
    chain: String, 
    provider: String, 
    yield: u64, 
    _cap: Permission
) acquires Permissions, GlobalVault, GlobalLPCapabilities {
    let vaults = borrow_global_mut<GlobalVault>(@dev);
    let vault = find_vault(vaults, token, chain, provider);
    let storage_address_string = non_user_storage_helper(signer, &vault.storage);

    // 1. Physically mint and deposit the 6-decimal tokens
    let yield_fa = TokensCore::mint(token, chain, yield, TokensCore::give_permission(&borrow_global<Permissions>(@dev).tokens_core));
    TokensCore::deposit(storage_address_string, vault.storage, yield_fa, chain);

    // 2. Scale the rewards accounting by 10^18 so it matches total_deposited in get_total_assets()
    let yield_scaled = (yield as u256) * 1000000000000000000;
    vault.total_native_accumulated_rewards = vault.total_native_accumulated_rewards + yield_scaled;
}
public fun claim_accumulated_fee_rewards(
        signer: &signer, 
        shared: String, 
        user: vector<u8>, 
        token: String, 
        chain: String, 
        provider: String, 
        user_shares: u256, 
        user_last_fee_index: u128, 
        _cap: Permission
    ): u128 acquires GlobalVault, GlobalLPCapabilities, Permissions {
        let vaults = borrow_global_mut<GlobalVault>(@dev);
        let vault = find_vault(vaults, token, chain, provider);
        let current_global_index = vault.accumulated_rewards_index;

        if (current_global_index <= user_last_fee_index || user_shares == 0) {
            return current_global_index
        };

        let index_diff = current_global_index - user_last_fee_index;
        let scale = 1000000000000000000;
        let pending_fee_rewards = (user_shares * (index_diff as u256)) / scale;

        if (pending_fee_rewards > 0) {
            let (_, _, enoughLocked) = BurnedQiara::calculate_required_locked_tokens_u256(shared, vault.total_deposited);
            if (enoughLocked) {
                Margin::add_credit(shared, user, pending_fee_rewards, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
            } else {
                // 🟢 FIX: Divide 1e18 scaled rewards down to u64 6-decimal units
                let forfeited_u64 = (pending_fee_rewards / 1000000000000000000 as u64);
                let vault_balance = fungible_asset::balance(vault.storage);
                
                // Clamp to available vault storage balance
                if (forfeited_u64 > vault_balance) {
                    forfeited_u64 = vault_balance;
                };

                if (forfeited_u64 > 0) {
                    let storage_address_string = non_user_storage_helper(signer, &vault.storage);
                    let forfeited_assets = TokensCore::withdraw(storage_address_string, vault.storage, forfeited_u64, chain);
                    
                    if (pending_fee_rewards <= vault.total_accumulated_rewards) {
                        vault.total_accumulated_rewards = vault.total_accumulated_rewards - pending_fee_rewards;
                    } else {
                        vault.total_accumulated_rewards = 0;
                    };
                    primary_fungible_store::deposit(@dev, forfeited_assets);
                };
            }
        };
        current_global_index
    }

   public fun deposit_token(
    signer: &signer, 
    token: String, 
    chain: String,
    provider: String, 
    fa: FungibleAsset, 
    _cap: Permission
): FungibleAsset acquires GlobalVault, GlobalLPCapabilities {
    let vaults = borrow_global_mut<GlobalVault>(@dev);
    let vault = find_vault(vaults, token, chain, provider);
    let storage_address_string = non_user_storage_helper(signer, &vault.storage);

    let deposit_amount = (fungible_asset::amount(&fa) as u256) * 1000000000000000000;
    
    let total_assets = get_total_assets(vault);
    let total_shares = vault.total_shares;

    let shares_to_mint = if (total_shares == 0 || total_assets == 0) {
        deposit_amount 
    } else {
        (deposit_amount * total_shares) / total_assets
    };

    assert!(shares_to_mint > 0, ERROR_INSUFFICIENT_BALANCE);

    // 1. Physically store assets
    TokensCore::deposit(storage_address_string, vault.storage, fa, chain);

    // 2. 🟢 UNCOMMENT THIS: Update total_deposited so total_assets matches total_shares!
    vault.total_deposited = vault.total_deposited + deposit_amount;

    let vault_seed = *String::bytes(&token);
    vector::append(&mut vault_seed, *String::bytes(&chain));
    vector::append(&mut vault_seed, *String::bytes(&provider));
    let vault_address = account::create_resource_address(&@dev, vault_seed);

    let lp_caps = borrow_global<GlobalLPCapabilities>(@dev);
    let cap = table::borrow(&lp_caps.caps, vault_address);

    let shares_fa = fungible_asset::mint(&cap.mint_ref, (shares_to_mint / 1000000000000000000 as u64));
    vault.total_shares = vault.total_shares + shares_to_mint;

    shares_fa
}
 /// Accepts physical LP shares, burns them, and returns the pro-rata underlying asset.
   /// Accepts physical LP shares, burns them, and returns the pro-rata underlying asset.
    public fun withdraw_token(
        signer: &signer,
        shared: String, 
        token: String, 
        chain: String,
        provider: String, 
        raw_scaled: u256,
        net_scaled: u256,
        _cap: Permission
    ) acquires GlobalVault, GlobalLPCapabilities, Permissions {
        let vaults = borrow_global_mut<GlobalVault>(@dev);
        let vault = find_vault(vaults, token, chain, provider);
        let storage_address_string = non_user_storage_helper(signer, &vault.storage);

        // 🟢 1. AUTO-SCALE UP: If amount came in unscaled (< 1e18), scale it to 1e18
        if (raw_scaled < 1000000000000000000 && raw_scaled > 0) {
            raw_scaled = raw_scaled * 1000000000000000000;
            net_scaled = net_scaled * 1000000000000000000;
        };

        // 🟢 2. AUTO-NORMALIZE: If amount came in as 18-decimal wei (> 10^29), scale it to 1e24
        if (raw_scaled > 100000000000000000000000000000) {
            raw_scaled = raw_scaled / 1000000000000;
            net_scaled = net_scaled / 1000000000000;
        };

        internal_daily_withdraw_limit(token, vault, raw_scaled);

        let total_assets = get_total_assets(vault);
        let total_shares = vault.total_shares;

        assert!(total_shares > 0, ERROR_INSUFFICIENT_BALANCE);
        assert!(total_assets > 0, ERROR_INSUFFICIENT_BALANCE);

        // 3. Calculate LP shares to burn based on vault ratio
        let shares_to_burn_scaled = if (total_assets == 0 || total_shares == 0) {
            raw_scaled
        } else {
            (raw_scaled * total_shares) / total_assets
        };
        let shares_to_burn_u64 = (shares_to_burn_scaled / 1000000000000000000 as u64);

        // 🟢 4. ROUND UP: Guarantee at least 1 share is burned so integer division never rounds to 0
        if (shares_to_burn_u64 == 0 && raw_scaled > 0) {
            shares_to_burn_u64 = 1;
        };

        // 5. Fetch Vault LP Capabilities and Metadata
        let vault_seed = *String::bytes(&token);
        vector::append(&mut vault_seed, *String::bytes(&chain));
        vector::append(&mut vault_seed, *String::bytes(&provider));
        let vault_address = account::create_resource_address(&@dev, vault_seed);

        let lp_caps = borrow_global<GlobalLPCapabilities>(@dev);
        let cap = table::borrow(&lp_caps.caps, vault_address);

        // 6. 🟢 Fetch Shared Signer, Primary Store AND Custom Store
        let shared_perm = Shared::give_permission(&borrow_global<Permissions>(@dev).shared_access);
        let shared_signer = Shared::get_shared_signer(shared, &shared_perm);
        let derived_address = Shared::return_shared_derived_address(shared);
        let shared_lp_store = Shared::ensure_shared_fungible_storage(shared, cap.lp_metadata, shared_perm);

        let primary_balance = primary_fungible_store::balance(derived_address, cap.lp_metadata);
        let custom_balance = fungible_asset::balance(shared_lp_store);
        let user_lp_balance = primary_balance + custom_balance; // 🟢 Combines both stores!

        assert!(user_lp_balance > 0, ERROR_USER_INSUFFICIENT_LP_SHARES);

        // 7. Tolerance & Safety Clamps
        if (shares_to_burn_u64 > user_lp_balance && (shares_to_burn_u64 - user_lp_balance) <= 5) {
            shares_to_burn_u64 = user_lp_balance;
        };

        if (shares_to_burn_u64 > user_lp_balance) {
            let one_to_one_shares = (raw_scaled / 1000000000000000000 as u64);
            if (one_to_one_shares == 0 && raw_scaled > 0) {
                one_to_one_shares = 1;
            };
            if (one_to_one_shares <= user_lp_balance) {
                shares_to_burn_u64 = one_to_one_shares;
                shares_to_burn_scaled = (one_to_one_shares as u256) * 1000000000000000000;
            } else {
                shares_to_burn_u64 = user_lp_balance;
                shares_to_burn_scaled = (user_lp_balance as u256) * 1000000000000000000;
            };
        };

        assert!(user_lp_balance >= shares_to_burn_u64, ERROR_USER_INSUFFICIENT_LP_SHARES);
        assert!(shares_to_burn_u64 > 0, ERROR_INSUFFICIENT_BALANCE);

        // 8. 🟢 Burn LP Shares from whichever store holds them
        let shares_fa = if (primary_balance >= shares_to_burn_u64) {
            primary_fungible_store::withdraw(&shared_signer, cap.lp_metadata, shares_to_burn_u64)
        } else if (custom_balance >= shares_to_burn_u64) {
            fungible_asset::withdraw(&shared_signer, shared_lp_store, shares_to_burn_u64)
        } else {
            let p_fa = primary_fungible_store::withdraw(&shared_signer, cap.lp_metadata, primary_balance);
            let rem = shares_to_burn_u64 - primary_balance;
            let c_fa = fungible_asset::withdraw(&shared_signer, shared_lp_store, rem);
            fungible_asset::merge(&mut p_fa, c_fa);
            p_fa
        };
        fungible_asset::burn(&cap.burn_ref, shares_fa);
        
        if (shares_to_burn_scaled <= vault.total_shares) {
            vault.total_shares = vault.total_shares - shares_to_burn_scaled;
        } else {
            vault.total_shares = 0;
        };

        // 9. Ensure vault storage has enough liquidity to pay out
        let net_amount_u64 = (net_scaled / 1000000000000000000 as u64);
        if (net_amount_u64 == 0 && net_scaled > 0) {
            net_amount_u64 = 1;
        };
        let vault_balance = fungible_asset::balance(vault.storage);
        assert!(vault_balance >= net_amount_u64, ERROR_VAULT_INSUFFICIENT_LIQUIDITY);

        // 10. Withdraw NET underlying tokens from Vault and credit to user's shared store
        let underlying_fa = TokensCore::withdraw(storage_address_string, vault.storage, net_amount_u64, chain);
        let shared_lp_store_token = Shared::ensure_shared_fungible_storage(shared, TokensCore::get_metadata(token), shared_perm);
        TokensCore::deposit(shared, shared_lp_store_token, underlying_fa, chain);
    }
    // ========================================================================
    // 🔍 SIMULATION & PREVIEW VIEW FUNCTION
    // ========================================================================
    #[view]
    public fun preview_withdraw_math(
        shared: String, 
        token: String, 
        chain: String, 
        provider: String, 
        amount: u64
    ): (u64, u64, bool, u64, u64, bool) acquires GlobalVault, GlobalLPCapabilities {
        let vaults = borrow_global_mut<GlobalVault>(@dev);
        let vault = find_vault(vaults, token, chain, provider);

        let raw_scaled = (amount as u256) * 1000000000000000000;
        let total_assets = get_total_assets(vault);
        let total_shares = vault.total_shares;

        let shares_to_burn_scaled = if (total_assets == 0 || total_shares == 0) {
            raw_scaled
        } else {
            (raw_scaled * total_shares) / total_assets
        };
        let shares_to_burn_u64 = (shares_to_burn_scaled / 1000000000000000000 as u64);

        let user_lp_balance = get_shared_lp_balance(shared, token, chain, provider);
        let has_enough_shares = user_lp_balance >= shares_to_burn_u64;

        let vault_underlying_balance = fungible_asset::balance(vault.storage);
        let has_enough_liquidity = vault_underlying_balance >= amount;

        (
            shares_to_burn_u64,        // 0: LP shares required to burn
            user_lp_balance,           // 1: User's actual LP shares
            has_enough_shares,         // 2: Will LP share check pass?
            amount,                    // 3: Amount requested
            vault_underlying_balance,  // 4: Vault liquidity available
            has_enough_liquidity       // 5: Will liquidity check pass?
        )
    }

// 1. Returns the user's LP Shares balance (Reconstructs LP Metadata from token, chain, provider)
    #[view]
    public fun get_shared_lp_balance(
        shared: String, 
        token: String, 
        chain: String, 
        provider: String
    ): u64 acquires GlobalLPCapabilities {
        let vault_seed = *String::bytes(&token);
        vector::append(&mut vault_seed, *String::bytes(&chain));
        vector::append(&mut vault_seed, *String::bytes(&provider));
        let vault_address = account::create_resource_address(&@dev, vault_seed);

        if (!exists<GlobalLPCapabilities>(@dev)) {
            return 0
        };

        let lp_caps = borrow_global<GlobalLPCapabilities>(@dev);
        if (!table::contains(&lp_caps.caps, vault_address)) {
            return 0
        };
        let cap = table::borrow(&lp_caps.caps, vault_address);

        let derived_address = Shared::return_shared_derived_address(shared);
        if (derived_address == @0x0) {
            return 0
        };

        primary_fungible_store::balance(derived_address, cap.lp_metadata)
    }

    // 2. Returns the user's Underlying Asset balance (e.g. QAUSD / QMON) in their shared storage
    #[view]
    public fun get_shared_underlying_balance(
        shared: String, 
        token: String
    ): u64 {
        let derived_address = Shared::return_shared_derived_address(shared);
        if (derived_address == @0x0) {
            return 0
        };
        
        let metadata = TokensCore::get_metadata(token);
        primary_fungible_store::balance(derived_address, metadata)
    }

    // 3. Combined View: Returns (LP_Shares, Underlying_Tokens) in one single call
    #[view]
    public fun get_all_shared_balances(
        shared: String, 
        token: String, 
        chain: String, 
        provider: String
    ): (u64, u64) acquires GlobalLPCapabilities {
        let lp_balance = get_shared_lp_balance(shared, token, chain, provider);
        let underlying_balance = get_shared_underlying_balance(shared, token);
        (lp_balance, underlying_balance)
    }

    public fun borrow_token(signer: &signer, shared: String, token: String, chain: String,provider: String, amount: u256,_cap: Permission) acquires GlobalVault, GlobalLPCapabilities, Permissions {
        let vaults = borrow_global_mut<GlobalVault>(@dev);
        let vault = find_vault(vaults, token, chain, provider);
        let storage_address_string = non_user_storage_helper(signer, &vault.storage);

        let underlying_fa = TokensCore::withdraw(storage_address_string, vault.storage, (amount/1000000000000000000 as u64), chain);

        // 7. Deposit the underlying assets directly back into the user's shared storage
        let user_shared_store_underlying = Shared::ensure_shared_fungible_storage(shared, TokensCore::get_metadata(token), Shared::give_permission(&borrow_global<Permissions>(@dev).shared_access));
        TokensCore::deposit(shared, user_shared_store_underlying, underlying_fa, chain);
    }

    public fun add_deposit(token: String, chain: String,provider: String, value: u256, cap: Permission) acquires GlobalVault, GlobalLPCapabilities {
        {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
            vault.total_deposited = vault.total_deposited + value;
        };
    }

    public fun remove_deposit(token: String, chain: String,provider: String, value: u256, cap: Permission) acquires GlobalVault, GlobalLPCapabilities {
        {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
            if(value > vault.total_deposited){
                vault.total_deposited = 0
            } else {
                vault.total_deposited = vault.total_deposited - value;
            };
        };
    }

    public fun add_borrow(token: String, chain: String,provider: String, value: u256, cap: Permission) acquires GlobalVault, GlobalLPCapabilities {
        {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
            vault.total_borrowed = vault.total_borrowed + value;
        };
    }

    public fun remove_borrow(token: String, chain: String,provider: String, value: u256, cap: Permission) acquires GlobalVault, GlobalLPCapabilities {
        {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
            if(value > vault.total_borrowed){
                vault.total_borrowed = 0
            } else {
                vault.total_borrowed = vault.total_borrowed - value;
            };
        };
    }

    public fun add_virtual_borrow(token: String, chain: String,provider: String, value: u256, cap: Permission) acquires GlobalVault, GlobalLPCapabilities {
        {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
            vault.virtual_borrowed = vault.virtual_borrowed + value;
        };
    }

    public fun remove_virtual_borrow(token: String, chain: String,provider: String, value: u256, cap: Permission) acquires GlobalVault, GlobalLPCapabilities {
        {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
            if(value > vault.virtual_borrowed){
                vault.virtual_borrowed = 0
            } else {
                vault.virtual_borrowed = vault.virtual_borrowed - value;
            };
        };
    }

    public fun add_virtual_deposit(token: String, chain: String,provider: String, value: u256, cap: Permission) acquires GlobalVault, GlobalLPCapabilities {
        {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
            vault.virtual_deposited = vault.virtual_deposited + value;
        };
    }

    public fun remove_virtual_deposit(token: String, chain: String,provider: String, value: u256, cap: Permission) acquires GlobalVault, GlobalLPCapabilities {
        {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
            if(value > vault.virtual_deposited){
                vault.virtual_deposited = 0
            } else {
                vault.virtual_deposited = vault.virtual_deposited - value;
            };
        };
    }

    public fun add_stake(token: String, chain: String,provider: String, value: u256, cap: Permission) acquires GlobalVault, GlobalLPCapabilities {
        {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
            vault.total_staked = vault.total_staked + value;
        };
    }

    public fun remove_stake(token: String, chain: String,provider: String, value: u256, cap: Permission) acquires GlobalVault, GlobalLPCapabilities {
        {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
            if(value > vault.total_staked){
                vault.total_staked = 0
            } else {
                vault.total_staked = vault.total_staked - value;
            };
        };
    }

    public fun add_staked_locked_fee(token: String, chain: String,provider: String, value: u256, cap: Permission) acquires GlobalVault, GlobalLPCapabilities {
        {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
            vault.total_staked_locked_fee = vault.total_staked_locked_fee + value;
        };
    }

    public fun remove_staked_locked_fee(token: String, chain: String,provider: String, value: u256, cap: Permission) acquires GlobalVault, GlobalLPCapabilities {
        {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
            vault.total_staked_locked_fee = vault.total_staked_locked_fee - value;
        };
    }

    public fun add_accumulated_rewards(token: String, chain: String,provider: String, value: u256, cap: Permission) acquires GlobalVault, GlobalLPCapabilities {
        {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
            vault.total_accumulated_rewards = vault.total_accumulated_rewards + value;
        };
    }
    public fun add_accumulated_interest(signer: &signer, token: String, chain: String,provider: String, value: u256, cap: Permission) acquires GlobalVault, GlobalLPCapabilities, Permissions {
        let vaults = borrow_global_mut<GlobalVault>(@dev);
        let vault = find_vault(vaults, token, chain, provider);
        let storage_address_string = non_user_storage_helper(signer, &vault.storage);

        let interest_fa = TokensCore::mint(token, chain, (value/1000000000000000000 as u64), TokensCore::give_permission(&borrow_global<Permissions>(@dev).tokens_core));
        
        // 1. Physically store the assets in the vault
        TokensCore::deposit(storage_address_string, vault.storage, interest_fa, chain);

        // 2. Increment the rewards counter (which inflates the share price for existing LPs)
        vault.total_accumulated_interest = vault.total_accumulated_interest + value;

    }

    public fun update_incentive_index(token: String, chain: String, provider: String, _cap: Permission) acquires GlobalVault, GlobalLPCapabilities {
        let vaults = borrow_global_mut<GlobalVault>(@dev);
        let vault = find_vault(vaults, token, chain, provider);
        
        if (vault.incentive.period_finish == 0) {
            return
        };

        let current_time = timestamp::now_seconds();
        
        let last_applicable_time = if (current_time < vault.incentive.period_finish) {
            current_time
        } else {
            vault.incentive.period_finish
        };
        
        if (last_applicable_time > vault.incentive.last_update_time) {
            let elapsed = last_applicable_time - vault.incentive.last_update_time;
            let total_rewards_accrued = vault.incentive.reward_rate * (elapsed as u256);
            let scale = 1000000000000000000;   // 1e18 scale factor
            
            // 1. Update Lender index based on active Shares
            if (vault.total_shares > 0) {
                let deposit_rewards = (total_rewards_accrued * vault.incentive.deposit_weight) / 100000000;
                let reward_per_share = (deposit_rewards * scale) / vault.total_shares;
                vault.incentive.deposit_index = vault.incentive.deposit_index + (reward_per_share as u128);
            };

            // 2. Update Borrower index based on active Debt
            if (vault.total_borrowed > 0) {
                let borrow_rewards = (total_rewards_accrued * vault.incentive.borrow_weight) / 100000000;
                let reward_per_borrow = (borrow_rewards * scale) / vault.total_borrowed;
                vault.incentive.borrow_index = vault.incentive.borrow_index + (reward_per_borrow as u128);
            };
        };
        
        vault.incentive.last_update_time = last_applicable_time;
    }

    public fun distribute_rewards(
        shared: String, 
        user: vector<u8>, 
        token: String, 
        chain: String, 
        provider: String, 
        user_shares: u256,              // <--- Lenders now evaluated on LP Shares
        user_borrowed: u256,            // <--- Borrowers evaluated on physical debt
        user_last_deposit_index: u128, 
        user_last_borrow_index: u128,
        _cap: Permission
    ): (u128, u128) acquires GlobalVault, GlobalLPCapabilities, Permissions {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
        
        if (vault.incentive.period_finish == 0) {
            return (user_last_deposit_index, user_last_borrow_index)
        };

        let scale = 1000000000000000000;   
        let total_rewards_to_mint = 0;

        // Process Lender Rewards
        if (user_shares > 0 && vault.incentive.deposit_index > user_last_deposit_index) {
            let index_diff = vault.incentive.deposit_index - user_last_deposit_index;
            let lender_reward = (user_shares * (index_diff as u256)) / scale;
            total_rewards_to_mint = total_rewards_to_mint + lender_reward;
        };

        // Process Borrower Rewards
        if (user_borrowed > 0 && vault.incentive.borrow_index > user_last_borrow_index) {
            let index_diff = vault.incentive.borrow_index - user_last_borrow_index;
            let borrower_reward = (user_borrowed * (index_diff as u256)) / scale;
            total_rewards_to_mint = total_rewards_to_mint + borrower_reward;
        };

        if (total_rewards_to_mint > 0) {
            Margin::add_credit(shared, user, total_rewards_to_mint, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        };
        
        (vault.incentive.deposit_index, vault.incentive.borrow_index)
    }

    public fun update(token: String, chain: String, provider: String, _cap: Permission) acquires GlobalVault, GlobalLPCapabilities {
        let vaults = borrow_global_mut<GlobalVault>(@dev);
        let vault = find_vault(vaults, token, chain, provider);
        
        let current_time = timestamp::now_seconds();
        vault.last_update = current_time;

        if (vault.incentive.period_finish > 0) {
            let claim_grace_period_seconds = 2592000; 

            if (current_time >= vault.incentive.period_finish + claim_grace_period_seconds) {
                vault.incentive = Incentive {
                    deployer: @0x0,
                    total_amount: 0,
                    reward_rate: 0,
                    deposit_weight: 0,
                    borrow_weight: 0,
                    period_finish: 0,
                    last_update_time: 0,
                    deposit_index: 0,
                    borrow_index: 0,
                };
            };
        };
    }

    fun internal_daily_withdraw_limit(token: String, provider_vault: &mut Vault, amount: u256){
        let now_day = (timestamp::now_seconds() / 86400) as u16;
        
        // reset BEFORE check
        if (provider_vault.w_tracker.day != now_day) {
            provider_vault.w_tracker.day = now_day;
            provider_vault.w_tracker.amount = 0;
            // limit = % of deposits that can leave per day
            let metadata = TokensMetadata::get_coin_metadata_by_symbol(token);
            provider_vault.w_tracker.limit = provider_vault.total_deposited * 1_000_000 * 100 
                / (TokensTiers::market_daily_withdraw_limit(TokensMetadata::get_coin_metadata_tier(&metadata)) as u256); 
        };

        //assert!(provider_vault.w_tracker.amount + amount <= provider_vault.w_tracker.limit, ERROR_WITHDRAW_LIMIT_EXCEEDED);
        provider_vault.w_tracker.amount = provider_vault.w_tracker.amount + amount;
    }

// === PUBLIC VIEWS === //
    #[view]
    public fun return_raw_data_vault(token: String, chain: String,provider: String): (u256,u256,u256,u256) acquires GlobalVault, GlobalLPCapabilities {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
        let data = get_vault_data(token, chain, provider, vault);
        return (data.utilization,  data.qiara_native_apr, data.final_lend_rate, data.final_borrow_rate)
    }

    #[view]
    public fun return_raw_vault(token: String, chain: String,provider: String): (u256, u256, u256, u256,u256,u256, u256, u256, u256, u256, u256, u64) acquires GlobalVault, GlobalLPCapabilities {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);

        return (
            ((vault.total_deposited + vault.virtual_deposited) - (vault.total_borrowed + vault.virtual_borrowed)), 
            vault.total_borrowed, 
            vault.total_deposited, 
            vault.total_staked, 
            vault.total_accumulated_rewards, 
            vault.total_native_accumulated_rewards, 
            vault.total_accumulated_interest, 
            vault.virtual_borrowed, 
            vault.virtual_deposited, 
            vault.total_shares,             // Return actual LP share supply
            vault.total_staked_locked_fee,
            vault.last_update
        )
    }

    #[view]
    public fun return_raw_vault_incentive(token: String, chain: String,provider: String): (u64, u64, u256) acquires GlobalVault, GlobalLPCapabilities {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
        
        return (vault.incentive.period_finish, vault.incentive.last_update_time, vault.incentive.reward_rate)
    }

    #[view]
    public fun return_storage(token: String, chain: String,provider: String): Object<FungibleStore> acquires GlobalVault, GlobalLPCapabilities {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
        return vault.storage
    }

    #[view]
    public fun return_lp_metadata(token: String, chain: String, provider: String): Object<Metadata> acquires GlobalLPCapabilities {
        let vault_seed = *String::bytes(&token);
        vector::append(&mut vault_seed, *String::bytes(&chain));
        vector::append(&mut vault_seed, *String::bytes(&provider));
        let vault_address = account::create_resource_address(&@dev, vault_seed);

        let lp_caps = borrow_global<GlobalLPCapabilities>(@dev);
        let cap = table::borrow(&lp_caps.caps, vault_address);
        cap.lp_metadata
    }

    #[view]
    public fun return_all_vault_keys(tokens: vector<String>): (vector<String>, vector<String>, vector<String>) acquires GlobalVault {
        let vaults = borrow_global<GlobalVault>(@dev);
        let all_tokens = vector::empty<String>();
        let all_chains = vector::empty<String>();
        let all_providers = vector::empty<String>();

        let len = vector::length(&tokens);
        let token_idx = 0;

        while (token_idx < len) {
            let token = *vector::borrow(&tokens, token_idx);
            if (table::contains(&vaults.balances, token)) {
                vector::push_back(&mut all_tokens, token);
                
                let token_table = table::borrow(&vaults.balances, token);
                let chains = map::keys(token_table);
                
                vector::append(&mut all_chains, chains);
                
                let num_chains = vector::length(&chains);
                let chain_idx = 0;
                while (chain_idx < num_chains) {
                    let chain = *vector::borrow(&chains, chain_idx);
                    let providers_map = map::borrow(token_table, &chain);
                    
                    vector::append(&mut all_providers, map::keys(providers_map));
                    
                    chain_idx = chain_idx + 1;
                };
            };
            token_idx = token_idx + 1;
        };

        (all_tokens, all_chains, all_providers)
    }

    #[view]
    public fun return_vaults(tokens: vector<String>): Map<String, Map<String, Map<String, FullVault>>> acquires GlobalVault {
        let vaults = borrow_global<GlobalVault>(@dev);
        let map = map::new<String, Map<String, Map<String, FullVault>>>();
        let len = vector::length(&tokens);

        while (len > 0) {
            let token = *vector::borrow(&tokens, len - 1);
            if (table::contains(&vaults.balances, token)) {
                let token_table = table::borrow(&vaults.balances, token);
                
                let new_chain_map = map::new<String, Map<String, FullVault>>();
                let chains = map::keys(token_table);
                let num_chains = vector::length(&chains);
                let chain_idx = 0;
                
                while (chain_idx < num_chains) {
                    let chain = *vector::borrow(&chains, chain_idx);
                    let providers_map = map::borrow(token_table, &chain);
                    
                    let new_provider_map = map::new<String, FullVault>();
                    let providers = map::keys(providers_map);
                    let num_providers = vector::length(&providers);
                    let provider_idx = 0;
                    
                    while (provider_idx < num_providers) {
                        let provider = *vector::borrow(&providers, provider_idx);
                        let vault = map::borrow(providers_map, &provider);
                        
                        let data = get_vault_data(token, chain, provider, vault);
                        let full_vault = FullVault {
                            vault: *vault,
                            data
                        };
                        map::add(&mut new_provider_map, provider, full_vault);
                        provider_idx = provider_idx + 1;
                    };
                    
                    map::add(&mut new_chain_map, chain, new_provider_map);
                    chain_idx = chain_idx + 1;
                };
                
                map::upsert(&mut map, token, new_chain_map);
            };
            len = len - 1;
        };
        return map
    }

    #[view]
    public fun get_utilization_ratio(deposited: u256, virtual_deposited: u256, borrowed: u256, virtual_borrowed: u256, staked: u256): u256 {
        let positive_supply = deposited + staked + virtual_deposited;
        let negative_supply = borrowed + virtual_borrowed;
        if (positive_supply == 0 || negative_supply == 0) {
            0
        } else {
            ((negative_supply * 100_000_000) / positive_supply)
        }
    }

    #[view]
    public fun calculate_minimal_apr(id: u8, utilization: u256): (u256, u256, u256) {
        utilization = utilization / 10000;
        let utilx5 = (utilization * utilization * utilization * utilization);
        let qiara_base_apr = (TokensTiers::market_base_lending_apr(id) as u256);
        let slashing = 1_000_000_000;
        if (id == 254) {
            slashing = slashing - 100_000_000;
        } else if (id == 255) {
            slashing = slashing;
        } else {
            slashing = slashing - 100_000_000 - ((id as u256) * 100_000_000);
        };

        let x = (qiara_base_apr * (utilx5)) / 1_000_000;
        let final_apr = (x / slashing) + qiara_base_apr;
        let borrow_apr = (final_apr * ((utilization) / 50)) / 100 + final_apr;
        return (qiara_base_apr, final_apr, borrow_apr)
    }

// === MUT RETURNS === //
    fun find_vault(vaults: &mut GlobalVault, token: String, chain: String, provider: String): &mut Vault acquires GlobalLPCapabilities {
        ChainTypes::ensure_valid_chain_name(chain);
        
        let metadata = TokensCore::get_metadata(token);

        if (!table::contains(&vaults.balances, token)) {
            table::add(&mut vaults.balances, token, map::new<String, Map<String,Vault>>());
        };
        let token_table = table::borrow_mut(&mut vaults.balances, token);
        if (!map::contains_key(token_table, &chain)) {
            map::add( token_table, chain, map::new<String, Vault>());
        };

        let chain_map = map::borrow_mut(token_table, &chain);
        if (!map::contains_key(chain_map, &provider)) {
            let vault_seed = *String::bytes(&token);
            vector::append(&mut vault_seed, *String::bytes(&chain));
            vector::append(&mut vault_seed, *String::bytes(&provider));

            let random_address = account::create_resource_address(&@dev, vault_seed);
            let constructor_ref = object::create_object(random_address);
            let vault_store = fungible_asset::create_store(&constructor_ref, metadata);

            // ==========================================
            // NEW: Initialize LP Fungible Asset Token
            // ==========================================
// ==========================================
            // NEW: Initialize LP Fungible Asset Token
            // ==========================================
            let lp_seed = *String::bytes(&token);
            vector::append(&mut lp_seed, *String::bytes(&chain));
            vector::append(&mut lp_seed, *String::bytes(&provider));
            vector::append(&mut lp_seed, b"-LP");

            let lp_random_address = account::create_resource_address(&@dev, lp_seed);
            
            // FIXED: Change from create_object to create_sticky_object to make it non-deletable
            let lp_constructor_ref = object::create_sticky_object(lp_random_address); 

            // Dynamically construct LP Token Name & Symbol based on underlying token
            let name_bytes = b"Qiara LP ";
            vector::append(&mut name_bytes, *String::bytes(&token));
            let lp_name = utf8(name_bytes);

            let symbol_bytes = b"LP_";
            vector::append(&mut symbol_bytes, *String::bytes(&token));
            let lp_symbol = utf8(symbol_bytes);

            let decimals = fungible_asset::decimals(metadata); // Match exact asset decimals

            // Create Metadata & Register primary stores dynamically
            primary_fungible_store::create_primary_store_enabled_fungible_asset(
                &lp_constructor_ref,
                std::option::none(),
                lp_name,
                lp_symbol,
                decimals,
                utf8(b""),
                utf8(b"")
            );

            // Generate Control capabilities
            let mint_ref = fungible_asset::generate_mint_ref(&lp_constructor_ref);
            let burn_ref = fungible_asset::generate_burn_ref(&lp_constructor_ref);
            let lp_metadata = object::object_from_constructor_ref<Metadata>(&lp_constructor_ref);

            let lp_caps = borrow_global_mut<GlobalLPCapabilities>(@dev);
            table::add(&mut lp_caps.caps, random_address, LPCapabilities {
                mint_ref,
                burn_ref,
                lp_metadata,
            });

            map::add(chain_map, provider, Vault {
                last_update: timestamp::now_seconds(),
                total_shares: 0,
                total_staked: 0,
                total_native_accumulated_rewards: 0,
                total_accumulated_interest: 0,
                total_accumulated_rewards: 0,
                virtual_deposited: 0,
                accumulated_rewards_index: 0,
                virtual_borrowed: 0,
                total_borrowed: 0,
                total_deposited: 0,
                total_staked_locked_fee: 0,
                w_tracker: WithdrawTracker { day: ((timestamp::now_seconds() / 86400) as u16), amount: 0, limit: 0 },
                storage: vault_store,
                incentive: Incentive {
                    deployer: @0x0,
                    total_amount: 0,
                    reward_rate: 0,
                    deposit_weight: 0,
                    borrow_weight: 0,
                    period_finish: 0,
                    last_update_time: 0,
                    deposit_index: 0,
                    borrow_index: 0,
                }
            });
        };

        map::borrow_mut(chain_map, &provider)
    }

    // Dynamic calculator helper for Data metrics
    fun get_vault_data(token: String, chain: String, provider: String, vault: &Vault): Data {
        let metadata = TokensMetadata::get_coin_metadata_by_symbol(token);
        let id = (TokensMetadata::get_coin_metadata_tier(&metadata) as u8);
        
        let utilization = get_utilization_ratio(
            vault.total_deposited,
            vault.virtual_deposited,
            vault.total_borrowed,
            vault.virtual_borrowed,
            0 
        );
        
        
        let (qiara_base_apr,final_lend_rate, final_borrow_rate) = calculate_minimal_apr(id,utilization,
        );
        
        Data {
            utilization: (utilization),
            qiara_native_apr: (qiara_base_apr),
            final_lend_rate: (final_lend_rate),
            final_borrow_rate: (final_borrow_rate)
        }
    }

    // === NEW HELPER: Standardizes Asset Accumulation pricing calculation ===
    fun get_total_assets(vault: &Vault): u256 {
        vault.total_deposited + vault.total_accumulated_interest + vault.total_native_accumulated_rewards + vault.total_staked_locked_fee + vault.total_staked
    }

    /// Converts a hex string representation of an address (with or without '0x') to an actual address type.
    fun string_to_address(s: &String): address {
        let bytes = String::bytes(s);
        let len = vector::length(bytes);
        let start = 0;
        
        // Strip out the "0x" or "0X" prefix if present
        if (len > 2 && *vector::borrow(bytes, 0) == 48 && (*vector::borrow(bytes, 1) == 120 || *vector::borrow(bytes, 1) == 88)) {
            start = 2;
        };
        
        let hex_bytes = vector::empty<u8>();
        let i = start;
        while (i < len) {
            vector::push_back(&mut hex_bytes, *vector::borrow(bytes, i));
            i = i + 1;
        };

        // If the hex string has an odd length, prepend a '0'
        if (vector::length(&hex_bytes) % 2 != 0) {
            vector::insert(&mut hex_bytes, 0, 48);
        };

        // Pad with '0' characters until we have exactly 64 hex characters (32 bytes)
        while (vector::length(&hex_bytes) < 64) {
            vector::insert(&mut hex_bytes, 0, 48);
        };

        let addr_bytes = vector::empty<u8>();
        let k = 0;
        let hex_len = vector::length(&hex_bytes);
        while (k < hex_len) {
            let high = hex_char_to_val(*vector::borrow(&hex_bytes, k));
            let low = hex_char_to_val(*vector::borrow(&hex_bytes, k + 1));
            vector::push_back(&mut addr_bytes, (high << 4) | low);
            k = k + 2;
        };

        from_bcs::to_address(addr_bytes)
    }

    fun hex_char_to_val(c: u8): u8 {
        if (c >= 48 && c <= 57) { c - 48 } // '0'..'9'
        else if (c >= 97 && c <= 102) { c - 97 + 10 } // 'a'..'f'
        else if (c >= 65 && c <= 70) { c - 65 + 10 } // 'A'..'F'
        else { 0 }
    }

}