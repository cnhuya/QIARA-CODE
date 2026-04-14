module dev::QiaraStoragesV4 {
    use std::signer;
    use std::string::{Self as string, String, utf8};
    use std::table::{Self, Table};
    use std::bcs;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use aptos_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata, FungibleAsset, FungibleStore};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object::{Self, Object};
    
    use dev::QiaraChainTypesV4::{Self as ChainTypes};
    use dev::QiaraTokenTypesV4::{Self as TokensType};

    // === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 0;
    const ERROR_NO_STORAGE: u64 = 1;
    const ERROR_STORAGE_EXISTS: u64 = 2;
    const ERROR_INVALID_VALIDATOR: u64 = 3;
    const ERROR_TOKEN_NOT_YET_REWARDED: u64 = 4;
    // === ACCESS === //
    struct Access has store, key, drop {}
    struct Permission has copy, key, drop {}

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @dev, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_permission(access: &Access): Permission {
        Permission {}
    }
    
    // === STRUCTS === //
    struct Permissions has key {
    }

    // Stores all lock stores for different tokens on a specific chain
    struct LockStorage has key {
        balances: Table<String, Map<String, Object<FungibleStore>>>
    }

    // Stores all fee stores for different tokens on a specific chain
    struct FeeStorage has key {
        balances: Table<String, Map<String, Object<FungibleStore>>>
    }


    // ----------------------------------------------------------------
    // Module init
    // ----------------------------------------------------------------
    fun init_module(admin: &signer) {
        if (!exists<LockStorage>(@dev)) {
            move_to(admin, LockStorage { balances: table::new<String,Map<String, Object<FungibleStore>>>() });
        };
        if (!exists<FeeStorage>(@dev)) {
            move_to(admin, FeeStorage { balances: table::new<String, Map<String, Object<FungibleStore>>>() });
        };
    }

    // Initialize storages for a specific token and chain
    public fun ensure_storages_exists(token: String, chain: String) acquires FeeStorage, LockStorage {
        ChainTypes::ensure_valid_chain_name(chain);
        let asset_address = object::create_object_address(&@dev, bcs::to_bytes(&TokensType::convert_token_nickName_to_name(token)));
        let metadata = object::address_to_object<Metadata>(asset_address);

        // Get the existing storages
        let lock_storage = borrow_global_mut<LockStorage>(@dev);
        let fee_storage = borrow_global_mut<FeeStorage>(@dev);

        // Lock
        if (!table::contains(&lock_storage.balances, token)) {
            table::add(&mut lock_storage.balances, token, map::new<String, Object<FungibleStore>>());
        };
        let lock = table::borrow_mut(&mut lock_storage.balances, token);
        if (!map::contains_key(lock, &chain)) {
            map::add( lock, chain, primary_fungible_store::ensure_primary_store_exists<Metadata>(@dev, metadata));
        };

        // Fee
        if (!table::contains(&fee_storage.balances, token)) {
            table::add(&mut fee_storage.balances, token, map::new<String, Object<FungibleStore>>());
        };
        let fee = table::borrow_mut(&mut fee_storage.balances, token);
        if (!map::contains_key(fee, &chain)) {
            map::add( fee, chain, primary_fungible_store::ensure_primary_store_exists<Metadata>(@dev, metadata));
        };
    }


    // --------------------------
    // PUBLIC FUNCTIONS
    // --------------------------

    public fun return_fee_storage(token: String, chain: String):Object<FungibleStore> acquires FeeStorage, LockStorage {
        ensure_storages_exists(token, chain);

        let fee_storage = borrow_global<FeeStorage>(@dev);
        let fee = table::borrow(&fee_storage.balances, token);

        return *map::borrow(fee, &chain)

    }

    public fun return_lock_storage(token: String, chain: String): Object<FungibleStore> acquires LockStorage, FeeStorage {
        ensure_storages_exists(token, chain);

        let lock_storage = borrow_global<LockStorage>(@dev);
        let lock = table::borrow(&lock_storage.balances, token);

        return *map::borrow(lock, &chain)

    }


    #[view]
    public fun return_lock_balance(token: String, chain: String): u64 acquires LockStorage {
        ChainTypes::ensure_valid_chain_name(chain);

        let lock_storage = borrow_global<LockStorage>(@dev);
        let lock = table::borrow(&lock_storage.balances, token);

        fungible_asset::balance(*map::borrow(lock, &chain))
    }

    #[view]
    public fun return_fee_balance(token: String, chain: String): u64 acquires FeeStorage {
        ChainTypes::ensure_valid_chain_name(chain);

        let fee_storage = borrow_global<FeeStorage>(@dev);
        let fee = table::borrow(&fee_storage.balances, token);

        fungible_asset::balance(*map::borrow(fee, &chain))
    }


    #[view]
    public fun return_lock_balance1(token: String): Map<String, Object<FungibleStore>> acquires LockStorage {

        let lock_storage = borrow_global<LockStorage>(@dev);
        *table::borrow(&lock_storage.balances, token)

  //      fungible_asset::balance(*map::borrow(lock, &chain))
    }

    #[view]
    public fun return_fee_balance1(token: String): Map<String, Object<FungibleStore>> acquires FeeStorage {

        let fee_storage = borrow_global<FeeStorage>(@dev);
        *table::borrow(&fee_storage.balances, token)

        //fungible_asset::balance(*map::borrow(fee, &chain))
    }

}