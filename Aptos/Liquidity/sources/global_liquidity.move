module dev::QiaraLiquidityV56 {
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

    use dev::QiaraTokensMetadataV39::{Self as TokensMetadata};
    use dev::QiaraTokensCoreV39::{Self as TokensCore, CoinMetadata, Access as TokensCoreAccess};
    use dev::QiaraTokensRatesV39::{Self as TokensRates, Access as TokensRatesAccess};
    use dev::QiaraTokensTiersV39::{Self as TokensTiers};

    use dev::QiaraMarginV41::{Self as Margin, Access as MarginAccess};
    use dev::QiaraRanksV41::{Self as Points, Access as PointsAccess};
    use dev::QiaraBurnedQiaraV41::{Self as BurnedQiara};
    use dev::QiaraSharedV15::{Self as Shared};
    use dev::QiaraChainTypesV39::{Self as ChainTypes};
    use dev::QiaraProviderTypesV39::{Self as ProviderTypes};
    use dev::QiaraGenesisV2::{Self as Genesis};

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_WITHDRAW_LIMIT_EXCEEDED: u64 = 2;
    const ERROR_EPOCH_MUST_BE_HIGHER_THAN_CURRENT: u64 = 3;
    const ERROR_EPOCH_MUST_BE_HIGHER_THAN_STARTING_EPOCH: u64 = 4;
    const ERROR_DURATION_MUST_BE_GREATER_THAN_ZERO: u64 = 5;
    const ERROR_INSUFFICIENT_BALANCE: u64 = 6;
    const ERROR_INVALID_LP_TOKEN: u64 = 7;

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
        tokens_rates: TokensRatesAccess,
        tokens_core: TokensCoreAccess,
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
        native_provider_apr: u256,
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
            move_to(admin, Permissions {margin: Margin::give_access(admin), points: Points::give_access(admin), tokens_rates:  TokensRates::give_access(admin), tokens_core: TokensCore::give_access(admin)});
        };

        initialize_all_registered_vaults(admin);
    }

// === ENTRY FUN === //
    fun tttta(number: u64){
        abort(number);
    }

    fun non_user_storage_helper<T: key>(obj: &Object<T>): String{
        let storage_address_bytes = string_utils::to_string(&object::object_address(obj));
            if(!Shared::assert_shared_storage((storage_address_bytes))){
                Shared::create_non_user_shared_storage((storage_address_bytes));
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

    public entry fun add_incentive(signer: &signer, shared: String, amount: u256, token: String, chain: String, provider: String, credits: u256, duration_seconds: u64,deposit_weight: u256,borrow_weight: u256) acquires GlobalVault, GlobalLPCapabilities, Permissions {
        Shared::assert_is_sub_owner(shared, bcs::to_bytes(&signer::address_of(signer)));

        let vaults = borrow_global_mut<GlobalVault>(@dev);
        let vault = find_vault(vaults, token, chain, provider);

        let credit_value = TokensMetadata::getValue(token, credits);
        let amount_u256 = credit_value*1000000000000000000;
        let (deposited, borrowed, _, _, _, _, _, _, _, _, _, _, _,_, _) = Margin::get_user_raw_balance(shared, token, chain, provider);
        assert!(deposited > amount_u256, ERROR_INSUFFICIENT_BALANCE);
        assert!(duration_seconds > 0, ERROR_DURATION_MUST_BE_GREATER_THAN_ZERO);
        let current_time = timestamp::now_seconds();

        Margin::remove_deposit(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, amount_u256, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));

        if (vault.incentive.period_finish == 0) {
            let reward_rate = amount_u256 / (duration_seconds as u256);

            vault.incentive = Incentive {
                deployer: signer::address_of(signer),
                total_amount: amount_u256,
                reward_rate,
                deposit_weight,
                borrow_weight,
                period_finish: current_time + duration_seconds,
                last_update_time: current_time,
                deposit_index: 0,
                borrow_index: 0,
            };
        } else {
            let last_applicable_time = if (current_time < vault.incentive.period_finish) {
                current_time
            } else {
                vault.incentive.period_finish
            };
            
            // Sync current index state before modifying parameters
            if (last_applicable_time > vault.incentive.last_update_time) {
                let elapsed = last_applicable_time - vault.incentive.last_update_time;
                let total_rewards_accrued = vault.incentive.reward_rate * (elapsed as u256);
                let scale = 1000000000000000000;   

                if (vault.total_shares > 0) {
                    let deposit_rewards = (total_rewards_accrued * vault.incentive.deposit_weight) / 100000000;
                    let reward_per_share = (deposit_rewards * scale) / vault.total_shares;
                    vault.incentive.deposit_index = vault.incentive.deposit_index + (reward_per_share as u128);
                };

                if (vault.total_borrowed > 0) {
                    let borrow_rewards = (total_rewards_accrued * vault.incentive.borrow_weight) / 100000000;
                    let reward_per_borrow = (borrow_rewards * scale) / vault.total_borrowed;
                    vault.incentive.borrow_index = vault.incentive.borrow_index + (reward_per_borrow as u128);
                };
            };
            
            vault.incentive.last_update_time = last_applicable_time;

            let remaining_time = if (current_time < vault.incentive.period_finish) {
                vault.incentive.period_finish - current_time
            } else {
                0
            };

            let remaining_credits = vault.incentive.reward_rate * (remaining_time as u256);
            let combined_credits = remaining_credits + amount_u256;

            vault.incentive.reward_rate = combined_credits / (duration_seconds as u256);
            vault.incentive.period_finish = current_time + duration_seconds;
            vault.incentive.last_update_time = current_time;
            vault.incentive.total_amount = vault.incentive.total_amount + amount_u256;
            vault.incentive.deployer = signer::address_of(signer); 
        };
    }

    public fun admin_accrue_rewards_from_lz(token: String, chain: String, provider: String, yield: u64, _cap: Permission) acquires Permissions, GlobalVault , GlobalLPCapabilities {
        let vaults = borrow_global_mut<GlobalVault>(@dev);
        let vault = find_vault(vaults, token, chain, provider);
        let storage_address_string = non_user_storage_helper(&vault.storage);

        let yield_fa = TokensCore::mint(token, chain, yield, TokensCore::give_permission(&borrow_global<Permissions>(@dev).tokens_core));
        let yield_amount = (fungible_asset::amount(&yield_fa) as u256);
        
        // 1. Physically store the assets in the vault
        TokensCore::deposit(storage_address_string, vault.storage, yield_fa, chain);

        // 2. Increment the rewards counter (which inflates the share price for existing LPs)
        vault.total_native_accumulated_rewards = vault.total_native_accumulated_rewards + yield_amount;
    }

    public fun claim_accumulated_fee_rewards(shared: String,user: vector<u8>,token: String,chain: String,provider: String,user_shares: u256,user_last_fee_index: u128,_cap: Permission): u128 acquires GlobalVault, GlobalLPCapabilities, Permissions {
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
                // User is qualified: allocate their reward
                Margin::add_credit(
                    shared, 
                    user, 
                    pending_fee_rewards, 
                    Margin::give_permission(&borrow_global<Permissions>(@dev).margin)
                );
            } else {
                // =============================================================
                // OPTION 2: Physically withdraw and divert forfeited rewards
                // =============================================================
                let storage_address_string = non_user_storage_helper(&vault.storage);
                
                // Extract the forfeited assets from the vault storage
                let forfeited_assets = TokensCore::withdraw(
                    storage_address_string, 
                    vault.storage, 
                    (pending_fee_rewards as u64), 
                    chain
                );

                // Send the forfeited assets to your protocol treasury or buyback contract
                let treasury_address = @dev; 
                primary_fungible_store::deposit(treasury_address, forfeited_assets);
            }
        };

        current_global_index
    }

    /// Deposits underlying assets, mints matching LP shares, and returns them to the user.
    public fun deposit_token(token: String, chain: String,provider: String, fa: FungibleAsset, _cap: Permission): FungibleAsset acquires GlobalVault, GlobalLPCapabilities {
        let vaults = borrow_global_mut<GlobalVault>(@dev);
        let vault = find_vault(vaults, token, chain, provider);
        let storage_address_string = non_user_storage_helper(&vault.storage);

        let deposit_amount = (fungible_asset::amount(&fa) as u256);
        
        // 1. Calculate how many shares to mint (ERC-4626 exchange rate)
        // FIXED: Included total_native_accumulated_rewards to correctly compound LP value
        let total_assets = get_total_assets(vault);
        let total_shares = vault.total_shares;

        let shares_to_mint = if (total_shares == 0 || total_assets == 0) {
            deposit_amount
        } else {
            (deposit_amount * total_shares) / total_assets
        };

        // 2. Deposit underlying asset to storage
        vault.total_deposited = vault.total_deposited + deposit_amount;
        TokensCore::deposit(storage_address_string, vault.storage, fa, chain);

        // 3. Resolve the vault's resource address to locate Mint capabilities
        let vault_seed = *String::bytes(&token);
        vector::append(&mut vault_seed, *String::bytes(&chain));
        vector::append(&mut vault_seed, *String::bytes(&provider));
        let vault_address = account::create_resource_address(&@dev, vault_seed);

        let lp_caps = borrow_global<GlobalLPCapabilities>(@dev);
        let cap = table::borrow(&lp_caps.caps, vault_address);

        // 4. Mint LP shares and update state
        let shares_fa = fungible_asset::mint(&cap.mint_ref, (shares_to_mint as u64));
        vault.total_shares = vault.total_shares + shares_to_mint;

        shares_fa
    }

    /// Accepts physical LP shares, burns them, and returns the pro-rata underlying asset.
    public fun withdraw_token(shared: String, token: String, chain: String,provider: String, shares_amount: u256,_cap: Permission) acquires GlobalVault, GlobalLPCapabilities {
        let vaults = borrow_global_mut<GlobalVault>(@dev);
        let vault = find_vault(vaults, token, chain, provider);
        let storage_address_string = non_user_storage_helper(&vault.storage);

        // 1. Resolve Vault's address to locate Burn capabilities
        let vault_seed = *String::bytes(&token);
        vector::append(&mut vault_seed, *String::bytes(&chain));
        vector::append(&mut vault_seed, *String::bytes(&provider));
        let vault_address = account::create_resource_address(&@dev, vault_seed);

        let lp_caps = borrow_global<GlobalLPCapabilities>(@dev);
        let cap = table::borrow(&lp_caps.caps, vault_address);

        // 2. Parse shared address and withdraw physical LP shares from the user's shared storage
        let user_address = string_to_address(&shared);
        let user_lp_store = primary_fungible_store::primary_store(user_address, cap.lp_metadata);
        
        let shares_fa = TokensCore::withdraw(shared, user_lp_store, (shares_amount as u64), chain);

        // 3. Explicit Check: Ensure the LP asset metadata matches the vault
        let shares_metadata = fungible_asset::asset_metadata(&shares_fa);
        assert!(shares_metadata == cap.lp_metadata, ERROR_INVALID_LP_TOKEN);

        // 4. Calculate the pro-rata underlying assets to withdraw
        // FIXED: Included total_native_accumulated_rewards to correctly compound LP value
        let total_assets = get_total_assets(vault);
        let total_shares = vault.total_shares;

        assert!(total_shares > 0, ERROR_INSUFFICIENT_BALANCE);
        let assets_to_withdraw = (shares_amount * total_assets) / total_shares;

        // 5. Burn the LP tokens
        fungible_asset::burn(&cap.burn_ref, shares_fa);
        vault.total_shares = vault.total_shares - shares_amount;

        // 6. Withdraw underlying assets from vault storage
        vault.total_deposited = vault.total_deposited - assets_to_withdraw;
        let underlying_fa = TokensCore::withdraw(storage_address_string, vault.storage, (assets_to_withdraw as u64), chain);

        // 7. Deposit the underlying assets directly back into the user's shared storage
        let underlying_metadata = TokensCore::get_metadata(token);
        let user_underlying_store = primary_fungible_store::ensure_primary_store_exists(user_address, underlying_metadata);
        TokensCore::deposit(shared, user_underlying_store, underlying_fa, chain);
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

    public fun add_native_accumulated_rewards(token: String, chain: String,provider: String, value: u256, cap: Permission) acquires GlobalVault, GlobalLPCapabilities {
        {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
            vault.total_native_accumulated_rewards = vault.total_native_accumulated_rewards + value;
        };
    }
    public fun add_accumulated_rewards(token: String, chain: String,provider: String, value: u256, cap: Permission) acquires GlobalVault, GlobalLPCapabilities {
        {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
            vault.total_accumulated_rewards = vault.total_accumulated_rewards + value;
        };
    }
    public fun add_accumulated_interest(token: String, chain: String,provider: String, value: u256, cap: Permission) acquires GlobalVault, GlobalLPCapabilities {
        {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
            vault.total_accumulated_interest = vault.total_accumulated_interest + value;
        };
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
        assert!(provider_vault.w_tracker.limit <= amount, ERROR_WITHDRAW_LIMIT_EXCEEDED);
        provider_vault.w_tracker.limit = provider_vault.w_tracker.limit + amount;

        let metadata = TokensMetadata::get_coin_metadata_by_symbol(token);

        if(provider_vault.w_tracker.day != ((timestamp::now_seconds()/86400) as u16)){
            provider_vault.w_tracker.day = ((timestamp::now_seconds()/86400) as u16);
            provider_vault.w_tracker.amount = 0;
            provider_vault.w_tracker.limit = provider_vault.total_deposited * 1_000_000*100 / (TokensTiers::market_daily_withdraw_limit(TokensMetadata::get_coin_metadata_tier(&metadata)) as u256); 
        };
    }

// === PUBLIC VIEWS === //
    #[view]
    public fun return_raw_data_vault(token: String, chain: String,provider: String): (u256,u256,u256,u256,u256) acquires GlobalVault, GlobalLPCapabilities {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
        let data = get_vault_data(token, chain, provider, vault);
        return (data.utilization, data.native_provider_apr, data.qiara_native_apr, data.final_lend_rate, data.final_borrow_rate)
    }

    #[view]
    public fun return_raw_vault(token: String, chain: String,provider: String): (u256, u256, u256, u256,u256, u256, u256, u256, u256, u256, u64) acquires GlobalVault, GlobalLPCapabilities {
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
    public fun calculate_minimal_apr(id: u8, utilization: u256, provider_native_apr: u256): (u256, u256, u256, u256) {
        utilization = utilization / 10000;
        let utilx5 = (utilization * utilization * utilization * utilization);
        let qiara_base_apr = (TokensTiers::market_base_lending_apr(id) as u256) + provider_native_apr;
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
        return (qiara_base_apr, provider_native_apr, final_apr, borrow_apr)
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
        
        let (native_chain_lend_apr, _) = TokensRates::get_vault_raw(token, chain, provider);
        
        let (qiara_base_apr, _, final_lend_rate, final_borrow_rate) = calculate_minimal_apr(
            id,
            utilization,
            ((native_chain_lend_apr / 4) as u256)
        );
        
        Data {
            utilization: (utilization),
            native_provider_apr: (native_chain_lend_apr as u256),
            qiara_native_apr: (qiara_base_apr),
            final_lend_rate: (final_lend_rate),
            final_borrow_rate: (final_borrow_rate)
        }
    }

    // === NEW HELPER: Standardizes Asset Accumulation pricing calculation ===
    fun get_total_assets(vault: &Vault): u256 {
        vault.total_deposited + vault.total_accumulated_interest + vault.total_native_accumulated_rewards
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