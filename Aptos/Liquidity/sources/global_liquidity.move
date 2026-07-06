module dev::QiaraLiquidityV42 {
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

    use dev::QiaraTokensMetadataV33::{Self as TokensMetadata};
    use dev::QiaraTokensCoreV33::{Self as TokensCore, CoinMetadata, Access as TokensCoreAccess};
    use dev::QiaraTokensRatesV33::{Self as TokensRates, Access as TokensRatesAccess};
    use dev::QiaraTokensTiersV33::{Self as TokensTiers};

    use dev::QiaraMarginV27::{Self as Margin, Access as MarginAccess};
    use dev::QiaraRanksV27::{Self as Points, Access as PointsAccess};

    use dev::QiaraSharedV12::{Self as Shared};
    use dev::QiaraChainTypesV33::{Self as ChainTypes};
    use dev::QiaraGenesisV2::{Self as Genesis};

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_WITHDRAW_LIMIT_EXCEEDED: u64 = 2;
    const ERROR_EPOCH_MUST_BE_HIGHER_THAN_CURRENT: u64 = 3;
    const ERROR_EPOCH_MUST_BE_HIGHER_THAN_STARTING_EPOCH: u64 = 4;
    const ERROR_DURATION_MUST_BE_GREATER_THAN_ZERO: u64 = 5;
    const ERROR_INSUFFICIENT_BALANCE: u64 = 6;

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
        total_amount: u256,       // Total credit budget allocated to this campaign
        reward_rate: u256,        // Amount of virtual credits distributed per second globally
        period_finish: u64,       // Timestamp (in seconds) when the campaign ends
        last_update_time: u64,    // Last timestamp the index was updated
        index: u128,              // Global reward-per-share accumulator (scaled by 1e18)
    }

    struct Vault has key, store, copy, drop {
        total_borrowed: u256,
        total_deposited: u256,
        total_staked: u256,
        total_native_accumulated_rewards: u256,
        total_accumulated_rewards: u256,
        total_accumulated_interest: u256,
        virtual_borrowed: u256,
        virtual_deposited: u256,
        storage: Object<FungibleStore>, // the actual wrapped balance in object,
        incentive: Incentive,           // Direct flat struct (no Option, no Vector)
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

// === INIT === //
    fun init_module(admin: &signer){
        if (!exists<GlobalVault>(@dev)) {
            move_to(admin, GlobalVault { balances: table::new<String, Map<String, Map<String, Vault>>>() });
        };
        if (!exists<Permissions>(@dev)) {
            move_to(admin, Permissions {margin: Margin::give_access(admin), points: Points::give_access(admin), tokens_rates:  TokensRates::give_access(admin), tokens_core: TokensCore::give_access(admin)});
        };
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




    public entry fun add_incentive(signer: &signer, shared: String, amount: u256, token: String, chain: String, provider: String, credits: u256, duration_seconds: u64) acquires GlobalVault, Permissions {
        Shared::assert_is_sub_owner(shared, bcs::to_bytes(&signer::address_of(signer)));

        let vaults = borrow_global_mut<GlobalVault>(@dev);
        let vault = find_vault(vaults, token, chain, provider);

        let credit_value = TokensMetadata::getValue(token, credits);
        let amount_u256 = credit_value*1000000000000000000;

        let (deposited, borrowed, virtual_deposit, virtual_borrow, staked, rewards, reward_index_snapshot, interest, interest_index_snapshot, locked_fee, last_update) = Margin::get_user_raw_balance(shared, token, chain, provider);
        assert!(deposited > amount_u256, ERROR_INSUFFICIENT_BALANCE);
        assert!(duration_seconds > 0, ERROR_DURATION_MUST_BE_GREATER_THAN_ZERO);
        let current_time = timestamp::now_seconds();

        Margin::remove_deposit(shared, bcs::to_bytes(&signer::address_of(signer)), token, chain, provider, amount_u256, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));

        if (vault.incentive.period_finish == 0) {
            // ==========================================
            // Scenario 1: Start a brand-new campaign
            // ==========================================
            let reward_rate = amount_u256 / (duration_seconds as u256);

            vault.incentive = Incentive {
                deployer: signer::address_of(signer),
                total_amount: amount_u256,
                reward_rate,
                period_finish: current_time + duration_seconds,
                last_update_time: current_time,
                index: 0,
            };
        } else {
            // ==========================================
            // Scenario 2: Top up and extend active campaign
            // ==========================================
            
            // 1. Sync global index internally to lock in historical rewards under the old rate
            let last_applicable_time = if (current_time < vault.incentive.period_finish) {
                current_time
            } else {
                vault.incentive.period_finish
            };
            
            let total_deposited_snapshot = vault.total_deposited;
            if (last_applicable_time > vault.incentive.last_update_time && total_deposited_snapshot > 0) {
                let elapsed = last_applicable_time - vault.incentive.last_update_time;
                let rewards_accrued = vault.incentive.reward_rate * (elapsed as u256);
                let scale = 1000000000000000000;   // 1e18 scale factor
                let upscale = 1000000000000000000; // 1e18 deposit upscale factor
                
                let reward_per_share = (rewards_accrued * scale * upscale) / total_deposited_snapshot;
                vault.incentive.index = vault.incentive.index + (reward_per_share as u128);
            };
            
            vault.incentive.last_update_time = last_applicable_time;

            // Determine remaining time left in the current active campaign
            let remaining_time = if (current_time < vault.incentive.period_finish) {
                vault.incentive.period_finish - current_time
            } else {
                0
            };

            // Calculate any un-emitted credits from the active program
            let remaining_credits = vault.incentive.reward_rate * (remaining_time as u256);
            let combined_credits = remaining_credits + amount_u256;

            // Re-evaluate parameters based on the new extended duration
            vault.incentive.reward_rate = combined_credits / (duration_seconds as u256);
            vault.incentive.period_finish = current_time + duration_seconds;
            vault.incentive.last_update_time = current_time;
            vault.incentive.total_amount = vault.incentive.total_amount + amount_u256;
            vault.incentive.deployer = signer::address_of(signer); 
        };
    }

    public fun withdraw_token(token: String, chain: String,provider: String, amount:u256, cap: Permission): FungibleAsset acquires GlobalVault{
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
        let storage_address_string = non_user_storage_helper(&vault.storage);

        //internal_daily_withdraw_limit(token, vault, amount*1000000000000000000);

        vault.total_deposited = vault.total_deposited - amount;
        TokensCore::withdraw(storage_address_string, vault.storage, (amount as u64), chain)
    }

    public fun deposit_token(token: String, chain: String,provider: String, fa: FungibleAsset, cap: Permission) acquires GlobalVault{
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
        let storage_address_string = non_user_storage_helper(&vault.storage);

        vault.total_deposited = vault.total_deposited + ((fungible_asset::amount(&fa) as u256)*1000000000000000000);
        TokensCore::deposit(storage_address_string, vault.storage, fa, chain);
    }

    public fun add_deposit(token: String, chain: String,provider: String, value: u256, cap: Permission) acquires GlobalVault{
        {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
            vault.total_deposited = vault.total_deposited + value;
        };
    }

    public fun remove_deposit(token: String, chain: String,provider: String, value: u256, cap: Permission) acquires GlobalVault{
        {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
            if(value > vault.total_deposited){
                vault.total_deposited = 0
            } else {
                vault.total_deposited = vault.total_deposited - value;
            };
        };
    }

    public fun add_borrow(token: String, chain: String,provider: String, value: u256, cap: Permission) acquires GlobalVault{
        {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
            vault.total_borrowed = vault.total_borrowed + value;
        };
    }

    public fun remove_borrow(token: String, chain: String,provider: String, value: u256, cap: Permission) acquires GlobalVault{
        {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
            if(value > vault.total_borrowed){
                vault.total_borrowed = 0
            } else {
                vault.total_borrowed = vault.total_borrowed - value;
            };
        };
    }

    public fun add_virtual_borrow(token: String, chain: String,provider: String, value: u256, cap: Permission) acquires GlobalVault{
        {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
            vault.virtual_borrowed = vault.virtual_borrowed + value;
        };
    }

    public fun remove_virtual_borrow(token: String, chain: String,provider: String, value: u256, cap: Permission) acquires GlobalVault{
        {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
            if(value > vault.virtual_borrowed){
                vault.virtual_borrowed = 0
            } else {
                vault.virtual_borrowed = vault.virtual_borrowed - value;
            };
        };
    }

    public fun add_virtual_deposit(token: String, chain: String,provider: String, value: u256, cap: Permission) acquires GlobalVault{
        {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
            vault.virtual_deposited = vault.virtual_deposited + value;
        };
    }

    public fun remove_virtual_deposit(token: String, chain: String,provider: String, value: u256, cap: Permission) acquires GlobalVault{
        {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
            if(value > vault.virtual_deposited){
                vault.virtual_deposited = 0
            } else {
                vault.virtual_deposited = vault.virtual_deposited - value;
            };
        };
    }

    public fun add_stake(token: String, chain: String,provider: String, value: u256, cap: Permission) acquires GlobalVault{
        {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
            vault.total_staked = vault.total_staked + value;
        };
    }

    public fun remove_stake(token: String, chain: String,provider: String, value: u256, cap: Permission) acquires GlobalVault{
        {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
            if(value > vault.total_staked){
                vault.total_staked = 0
            } else {
                vault.total_staked = vault.total_staked - value;
            };
        };
    }

    public fun add_native_accumulated_rewards(token: String, chain: String,provider: String, value: u256, cap: Permission) acquires GlobalVault{
        {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
            vault.total_native_accumulated_rewards = vault.total_native_accumulated_rewards + value;
        };
    }
    public fun add_accumulated_rewards(token: String, chain: String,provider: String, value: u256, cap: Permission) acquires GlobalVault{
        {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
            vault.total_accumulated_rewards = vault.total_accumulated_rewards + value;
        };
    }
    public fun add_accumulated_interest(token: String, chain: String,provider: String, value: u256, cap: Permission) acquires GlobalVault{
        {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
            vault.total_accumulated_interest = vault.total_accumulated_interest + value;
        };
    }

    public fun update_incentive_index(token: String, chain: String, provider: String, total_deposited: u256, _cap: Permission) acquires GlobalVault {
        let vaults = borrow_global_mut<GlobalVault>(@dev);
        let vault = find_vault(vaults, token, chain, provider);
        
        // Skip index update if the incentive is not initialized
        if (vault.incentive.period_finish == 0) {
            return
        };

        let current_time = timestamp::now_seconds();
        
        let last_applicable_time = if (current_time < vault.incentive.period_finish) {
            current_time
        } else {
            vault.incentive.period_finish
        };
        
        if (last_applicable_time > vault.incentive.last_update_time && total_deposited > 0) {
            let elapsed = last_applicable_time - vault.incentive.last_update_time;
            let rewards_accrued = vault.incentive.reward_rate * (elapsed as u256);
            let scale = 1000000000000000000;   // 1e18 scale factor
            
            // Increase the global reward-per-share accumulator
            let reward_per_share = (rewards_accrued * scale) / total_deposited;
            vault.incentive.index = vault.incentive.index + (reward_per_share as u128);
        };
        
        // Advance the tracking pointer to the last applicable time
        vault.incentive.last_update_time = last_applicable_time;
    }
    public fun distribute_rewards(shared: String, user: vector<u8>, token: String, chain: String, provider: String, total_deposited: u256, user_deposited: u256, user_last_index: u128, _cap: Permission): u128 acquires GlobalVault, Permissions {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
        
        if (total_deposited == 0 || user_deposited == 0 || vault.incentive.period_finish == 0) {
            return user_last_index
        };

        // Only distribute rewards if the global index is ahead of the user's checkpoint
        if (vault.incentive.index > user_last_index) {
            let index_diff = vault.incentive.index - user_last_index;
            let scale = 1000000000000000000;   // 1e18 scale factor
            
            // User's reward = (user_deposited * index_diff) / (scale * upscale)
            let user_reward_amount = (user_deposited * (index_diff as u256)) / scale;
            
            if (user_reward_amount > 0) {
                // Directly allocate rewards as virtual credits in the Margin module
                Margin::add_credit(shared,user,user_reward_amount, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
            };
            
            // Return the new global index so it can be saved as the user's checkpoint
            return vault.incentive.index
        };
        
        user_last_index
    }

    public fun update(token: String, chain: String, provider: String, _cap: Permission) acquires GlobalVault {
        let vaults = borrow_global_mut<GlobalVault>(@dev);
        let vault = find_vault(vaults, token, chain, provider);
        
        let current_time = timestamp::now_seconds();
        vault.last_update = current_time;

        // Reset the incentive back to default zero values if the grace period has passed
        if (vault.incentive.period_finish > 0) {
            // Define a claim grace period in seconds. 
            // e.g., 30 days = 30 days * 86,400 seconds/day = 2,592,000 seconds
            let claim_grace_period_seconds = 2592000; 

            if (current_time >= vault.incentive.period_finish + claim_grace_period_seconds) {
                // Return to clean zero state to enable subsequent campaigns later
                vault.incentive = Incentive {
                    deployer: @0x0,
                    total_amount: 0,
                    reward_rate: 0,
                    period_finish: 0,
                    last_update_time: 0,
                    index: 0,
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
            provider_vault.w_tracker.limit = provider_vault.total_deposited * 1_000_000*100 / (TokensTiers::market_daily_withdraw_limit(TokensMetadata::get_coin_metadata_tier(&metadata)) as u256); // set limit for new day
        };
    }

// === PUBLIC VIEWS === //
    #[view]
    public fun return_raw_data_vault(token: String, chain: String,provider: String): (u256,u256,u256,u256,u256) acquires GlobalVault{
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
        let data = get_vault_data(token, chain, provider, vault);
        return (data.utilization, data.native_provider_apr, data.qiara_native_apr, data.final_lend_rate, data.final_borrow_rate)
    }

    #[view]
    public fun return_raw_vault(token: String, chain: String,provider: String): (u256, u256, u256, u256, u256, u256, u256,u256, u64) acquires GlobalVault{
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);

        return (((vault.total_deposited + vault.virtual_deposited) - (vault.total_borrowed + vault.virtual_borrowed)), vault.total_borrowed, vault.total_deposited, vault.total_staked, vault.total_accumulated_rewards, vault.total_accumulated_interest, vault.virtual_borrowed, vault.virtual_deposited, vault.last_update)
    }

    #[view]
    public fun return_raw_vault_incentive(token: String, chain: String,provider: String): (u64, u64, u256) acquires GlobalVault{
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
        
        return (vault.incentive.period_finish, vault.incentive.last_update_time, vault.incentive.reward_rate)
    }

    #[view]
    public fun return_storage(token: String, chain: String,provider: String): Object<FungibleStore> acquires GlobalVault{
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
        return vault.storage
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
            // 1. Store the active token
            vector::push_back(&mut all_tokens, token);
            
            let token_table = table::borrow(&vaults.balances, token);
            let chains = map::keys(token_table);
            
            // 2. Append all chains for this token at once
            vector::append(&mut all_chains, chains);
            
            let num_chains = vector::length(&chains);
            let chain_idx = 0;
            while (chain_idx < num_chains) {
                let chain = *vector::borrow(&chains, chain_idx);
                let providers_map = map::borrow(token_table, &chain);
                
                // 3. Append all providers for this chain at once (no inner loop needed)
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
    fun find_vault(vaults: &mut GlobalVault, token: String, chain: String, provider: String): &mut Vault {
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
            map::add(chain_map, provider, Vault {
                last_update: timestamp::now_seconds(),
                total_staked: 0,
                total_native_accumulated_rewards: 0,
                total_accumulated_interest: 0,
                total_accumulated_rewards: 0,
                virtual_deposited: 0,
                virtual_borrowed: 0,
                total_borrowed: 0,
                total_deposited: 0,
                w_tracker: WithdrawTracker { day: ((timestamp::now_seconds() / 86400) as u16), amount: 0, limit: 0 },
                storage: vault_store,
                incentive: Incentive {
                    deployer: @0x0,
                    total_amount: 0,
                    reward_rate: 0,
                    period_finish: 0,
                    last_update_time: 0,
                    index: 0,
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
            0 // dont count total staked bcs its already accounted in total deposited...
        );
        
        let (native_chain_lend_apr, _) = TokensRates::get_vault_raw(token, chain, provider);
        
        // 25% of native provider APR passed to minimal APR calculator
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
}