module dev::QiaraLiquidityV2{
    use std::signer;
    use std::timestamp;
    use std::vector;    
    use std::string::{Self as String, String, utf8};
    use std::table::{Self as table, Table};
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use aptos_std::string_utils ::{Self as string_utils};
    use aptos_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata, FungibleAsset, FungibleStore};
    use aptos_framework::dispatchable_fungible_asset;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::account;

    use dev::QiaraTokensMetadataV3::{Self as TokensMetadata};
    use dev::QiaraTokensCoreV3::{Self as TokensCore, CoinMetadata, Access as TokensCoreAccess};
    use dev::QiaraTokensRatesV3::{Self as TokensRates, Access as TokensRatesAccess};
    use dev::QiaraTokensTiersV3::{Self as TokensTiers};

    use dev::QiaraMarginV2::{Self as Margin, Access as MarginAccess};
    use dev::QiaraRanksV2::{Self as Points, Access as PointsAccess};

    use dev::QiaraSharedV1::{Self as Shared};
    use dev::QiaraChainTypesV4::{Self as ChainTypes};

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_WITHDRAW_LIMIT_EXCEEDED: u64 = 2;

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
     struct WithdrawTracker has key,store, copy, drop{
        day: u16,
        amount: u256,
        limit: u256,
    }

    struct Incentive has key, store, copy, drop {
        start: u64,
        end: u64,
        per_second: u256, //i.e 1
    }

   // Maybe in the future remove this, and move total borrowed into global vault? idk tho how would it do because of the phantom type tag
    struct Vault has key, store, copy, drop{
        total_borrowed: u256,
        total_deposited: u256,
        total_staked: u256,
        total_accumulated_rewards: u256,
        total_accumulated_interest: u256,
        virtual_borrowed: u256,
        virtual_deposited: u256,
        storage: Object<FungibleStore>, // the actuall wrapped balance in object,
        incentive: Incentive, // XP | or some gamefi system
        w_tracker: WithdrawTracker,
        last_update: u64,
    }

    struct FullVault has key, store, copy, drop{
        token: String,
        total_deposited: u256,
        total_borrowed: u256,
        utilization: u64,
        lend_rate: u64,
        borrow_rate: u64
    }

    struct GlobalVault has key {
        //  token, chain, provider
        balances: Table<String,Map<String, Map<String, Vault>>>,
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

    public fun update(token: String,  chain: String,provider: String, cap: Permission) acquires GlobalVault{
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
        vault.last_update = timestamp::now_seconds();
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

        return (vault.incentive.start, vault.incentive.end, vault.incentive.per_second)
    }

    #[view]
    public fun return_storage(token: String, chain: String,provider: String): Object<FungibleStore> acquires GlobalVault{
        let vault = find_vault(borrow_global_mut<GlobalVault>(@dev), token, chain, provider);
        return vault.storage
    }

    #[view]
    public fun return_vaults(tokens: vector<String>): Map<String, Map<String, Map<String, Vault>>> acquires GlobalVault {
        let vaults = borrow_global<GlobalVault>(@dev);

        let map = map::new<String, Map<String, Map<String, Vault>>>();

        let len = vector::length(&tokens);

        while(len > 0) {
            let token = *vector::borrow(&mut tokens, len-1);
            if (table::contains(&vaults.balances, token)) {
                let token_table = table::borrow(&vaults.balances, token);
                map::upsert(&mut map, token, *token_table);
            };
            len = len - 1;
        };
        return map
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
            // 1. Create a "seed" for a unique named object
            // This creates a unique address for this specific vault
            let vault_seed = *String::bytes(&token);
            vector::append(&mut vault_seed, *String::bytes(&chain));
            vector::append(&mut vault_seed, *String::bytes(&provider));

            let random_address = account::create_resource_address(&@dev,vault_seed);
            let constructor_ref = object::create_object(random_address);
            let vault_store = fungible_asset::create_store(&constructor_ref, metadata);
            map::add(chain_map, provider, Vault {
                last_update: timestamp::now_seconds(),
                total_staked: 0,
                total_accumulated_interest: 0,
                total_accumulated_rewards: 0,
                virtual_deposited: 0,
                virtual_borrowed: 0,
                total_borrowed: 0,
                total_deposited: 1000000000000000000 * 1000000000,
                w_tracker: WithdrawTracker { day: ((timestamp::now_seconds() / 86400) as u16), amount: 0, limit: 0 },
                storage: vault_store, // Now this is a unique Object address!
                incentive: Incentive { start: 0, end: 0, per_second: 0 }
            });
        };

        map::borrow_mut(chain_map, &provider)
    }
}
