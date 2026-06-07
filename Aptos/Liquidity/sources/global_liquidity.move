module dev::QiaraLiquidityV17 {
    use std::signer;
    use std::timestamp;
    use std::vector;    
    use std::string::{Self as String, String, utf8};
    use std::table::{Self as table, Table};
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use aptos_std::string_utils::{Self as string_utils};
    use aptos_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata, FungibleAsset, FungibleStore};
    use aptos_framework::dispatchable_fungible_asset;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::account;

    use dev::QiaraTokensMetadataV16::{Self as TokensMetadata};
    use dev::QiaraTokensCoreV16::{Self as TokensCore, CoinMetadata, Access as TokensCoreAccess};
    use dev::QiaraTokensRatesV16::{Self as TokensRates, Access as TokensRatesAccess};
    use dev::QiaraTokensTiersV16::{Self as TokensTiers};

    use dev::QiaraMarginV13::{Self as Margin, Access as MarginAccess};
    use dev::QiaraRanksV13::{Self as Points, Access as PointsAccess};

    use dev::QiaraSharedV4::{Self as Shared};
    use dev::QiaraChainTypesV16::{Self as ChainTypes};
    use dev::QiaraGenesisV2::{Self as Genesis};
// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_WITHDRAW_LIMIT_EXCEEDED: u64 = 2;
    const ERROR_EPOCH_MUST_BE_HIGHER_THAN_CURRENT: u64 = 3;
    const ERROR_EPOCH_MUST_BE_HIGHER_THAN_STARTING_EPOCH: u64 = 4;

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
        epoch_start: u64,
        epoch_end: u64,
        storage: Object<FungibleStore>,
        deployer: address,
        total_amount: u64,
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
        incentives: vector<Incentive>, // XP | or some gamefi system
        w_tracker: WithdrawTracker,
        last_update: u64,
    }

    struct FullVault has key, store, copy, drop {
        vault: Vault,
        data: Data
    }

    struct Data has key, store, copy, drop {
        utilization: u64,
        native_provider_apr: u64,
        qiara_native_apr: u64,
        final_lend_rate: u64,
        final_borrow_rate: u64
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

    public fun add_incentive(deployer: address, token: String, chain: String, provider: String, fa: FungibleAsset, epoch_start: u64, epoch_end: u64, _cap: Permission) acquires GlobalVault {
        let vaults = borrow_global_mut<GlobalVault>(@dev);
        let vault = find_vault(vaults, token, chain, provider);

        // Derive unique object address for the incentive store
        let metadata = fungible_asset::asset_metadata(&fa);
        let constructor_ref = object::create_object(@dev);
        let incentive_store = fungible_asset::create_store(&constructor_ref, metadata);

        // Deposit the fungible asset reward into the store
        fungible_asset::deposit(incentive_store, fa);
        assert!(epoch_start > (Genesis::return_epoch() as u64), ERROR_EPOCH_MUST_BE_HIGHER_THAN_CURRENT);
        assert!(epoch_end > epoch_start, ERROR_EPOCH_MUST_BE_HIGHER_THAN_STARTING_EPOCH);

        let new_incentive = Incentive {
            epoch_start,
            epoch_end,
            storage: incentive_store,
            deployer: deployer,
            total_amount: fungible_asset::balance(incentive_store),
        };

        vector::push_back(&mut vault.incentives, new_incentive);
    }

    public fun withdraw_token(token: String, chain: String,provider: String, amount:u256, cap: Permission): FungibleAsset acquires GlobalVault{
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
        let storage_address_string = non_user_storage_helper(&vault.storage);

        vault.total_deposited = vault.total_deposited - amount*1000000000000000000;
        internal_daily_withdraw_limit(token, vault, amount*1000000000000000000);
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

    public fun distribute_rewards(token: String, chain: String, provider: String, total_deposited: u256, user_deposited: u256, user_time_diff: u64, _cap: Permission): vector<FungibleAsset> acquires GlobalVault {
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
        let rewards = vector::empty<FungibleAsset>();
        
        if (total_deposited == 0 || user_deposited == 0 || user_time_diff == 0) {
            return rewards
        };

        let current_epoch = (Genesis::return_epoch() as u64);
        let len = vector::length(&vault.incentives);
        let i = 0;
        
        while (i < len) {
            let incentive = vector::borrow(&vault.incentives, i);
            
            // Only distribute rewards if the epoch window is active
            if (current_epoch >= incentive.epoch_start && current_epoch <= incentive.epoch_end) {
                let duration = (incentive.epoch_end - incentive.epoch_start);
                if (duration > 0) {
                    // 1. Calculate rate per epoch
                    let rate_per_epoch = incentive.total_amount / duration;
                    
                    // 2. Calculate the pool's distributed amount for user's elapsed time
                    let total_pool_reward = rate_per_epoch * (user_time_diff);
                    
                    // 3. Calculate user's proportional share
                    let user_reward_amount = (total_pool_reward * (user_deposited as u64)) / (total_deposited as u64);
                    
                    // 4. Ensure we don't attempt to withdraw more than is available in the store
                    let balance = fungible_asset::balance(incentive.storage);
                    if (user_reward_amount > balance) {
                        user_reward_amount = balance;
                    };
                    
                    if (user_reward_amount > 0) {
                        let storage_address_string = non_user_storage_helper(&incentive.storage);
                        let withdrawn_fa = TokensCore::withdraw(
                            storage_address_string, 
                            incentive.storage, 
                            (user_reward_amount as u64), 
                            chain
                        );
                        vector::push_back(&mut rewards, withdrawn_fa);
                    };
                };
            };
            i = i + 1;
        };
        
        rewards
    }

    public fun update(token: String, chain: String, provider: String, _cap: Permission) acquires GlobalVault {
        let vaults = borrow_global_mut<GlobalVault>(@dev);
        let vault = find_vault(vaults, token, chain, provider);
        let current_epoch = (Genesis::return_epoch() as u64);
        vault.last_update = timestamp::now_seconds();

        // Process incentives and remove finished ones to reclaim storage
        let len = vector::length(&vault.incentives);
        let i = len;
        while (i > 0) {
            let idx = i - 1;
            let incentive = vector::borrow(&vault.incentives, idx);
            if (current_epoch >= incentive.epoch_end) {
                let storage_address_string = non_user_storage_helper(&incentive.storage);
                let balance = fungible_asset::balance(incentive.storage);
                
                // If there is any leftover asset inside, return it back to deployers's primary store
                if (balance > 0) {
                    let leftover_fa = TokensCore::withdraw(storage_address_string, incentive.storage, balance, chain);
                    primary_fungible_store::deposit(incentive.deployer, leftover_fa);
                };
                
                // Safely remove the expired incentive
                vector::swap_remove(&mut vault.incentives, idx);
            };
            i = i - 1;
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
    public fun return_raw_vault(token: String, chain: String,provider: String): (u256, u256, u256, u256, u256, u256, u256, u64) acquires GlobalVault{
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);

        return (vault.total_borrowed, vault.total_deposited, vault.total_staked, vault.total_accumulated_rewards, vault.total_accumulated_interest, vault.virtual_borrowed, vault.virtual_deposited, vault.last_update)
    }

    #[view]
    public fun return_raw_vault_incentive(token: String, chain: String,provider: String): (u64, u64, u256) acquires GlobalVault{
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
        
        if (vector::is_empty(&vault.incentives)) {
            return (0, 0, 0)
        };

        let incentive = vector::borrow(&vault.incentives, 0);
        let duration = incentive.epoch_end - incentive.epoch_start;
        let per_second = if (duration > 0) {
            (fungible_asset::balance(incentive.storage) as u256) / (duration as u256)
        } else {
            0
        };

        return (incentive.epoch_start, incentive.epoch_end, per_second)
    }

    #[view]
    public fun return_storage(token: String, chain: String,provider: String): Object<FungibleStore> acquires GlobalVault{
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
        return vault.storage
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

        let x = (qiara_base_apr * utilx5) / 1_000_000;
        let final_apr = (x / slashing) + qiara_base_apr;
        let borrow_apr = (final_apr * (utilization / 50)) / 100 + final_apr;
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
                total_deposited: 1000000000000000000 * 1000000000,
                w_tracker: WithdrawTracker { day: ((timestamp::now_seconds() / 86400) as u16), amount: 0, limit: 0 },
                storage: vault_store,
                incentives: vector::empty<Incentive>()
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
            vault.total_staked
        );
        
        let (native_chain_lend_apr, _) = TokensRates::get_vault_raw(token, chain, provider);
        
        // 25% of native provider APR passed to minimal APR calculator
        let (qiara_base_apr, _, final_lend_rate, final_borrow_rate) = calculate_minimal_apr(
            id,
            utilization,
            ((native_chain_lend_apr / 4) as u256)
        );
        
        Data {
            utilization: (utilization as u64),
            native_provider_apr: native_chain_lend_apr,
            qiara_native_apr: (qiara_base_apr as u64),
            final_lend_rate: (final_lend_rate as u64),
            final_borrow_rate: (final_borrow_rate as u64)
        }
    }
}