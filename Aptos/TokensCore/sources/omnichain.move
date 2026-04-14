module dev::QiaraTokensOmnichainV2{
    use std::signer;
    use std::bcs;
    use std::timestamp;
    use std::vector;
    use std::string::{Self as string, String, utf8};
    use std::type_info::{Self, TypeInfo};
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use std::table::{Self, Table};
    use aptos_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata, FungibleAsset, FungibleStore};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::event;

    use dev::QiaraNonceV1::{Self as Nonce, Access as NonceAccess};
    use dev::QiaraSharedV1::{Self as Shared};

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 0;
    const ERROR_NOT_VALIDATOR: u64 = 1;
    const ERROR_TOKEN_IN_ADDRESS_NOT_INITIALIZED: u64 = 2;
    const ERROR_TOKEN_ON_CHAIN_IN_ADDRESS_NOT_INITIALIZED: u64 = 3;
    const ERROR_ADDRESS_NOT_INITIALIZED: u64 = 4;
    const ERROR_TOKEN_NOT_INITIALIZED: u64 = 5;
    const ERROR_TOKEN_NOT_INITIALIZED_FOR_THIS_CHAIN: u64 = 6;
    const ERROR_INSUFFICIENT_BALANCE: u64 = 7;
    
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
        nonce: NonceAccess,
    }


    // For Pagination purposes
    struct AddressCounter has key {
        counter: u64,
        counter_outflow: u64
    }
    // Needed to track addresses, to avoid duplication
    struct AddressDatabase has key {
        table: Table<String, u64>,
        table_outflow: Table<vector<u8>, u64>,
    }
    // Tracks allowed/supported chains for each Token.
    // i.e Ethereum (token) -> Base/Sui/Solana (chains)
    struct TokensChains has key{
        book: Map<String, vector<String>>
    }
    // Tracks overall "liqudity" across chains for each token type (the string argument)
    // i.e Ethereum (token) -> Base/Sui/Solana (chains)... -> supply
    struct CrosschainBook has key{
        book: Map<String, Map<String, u256>>
    }
    // Tracks "liqudity" across chains for each address
    // i.e 0/1/2...(page) -> 0x...123 (user) -> Base/Sui/Solana (chains).. -> Ethereum (token) -> supply
    struct UserCrosschainBook has key{
        book: Table<u64,Map<String, Map<String, Map<String, u256>>>>,
        outflows: Table<u64,Map<vector<u8>, Map<String, Map<String, u256>>>>,
        nonce: Table<vector<u8>, u256>
    }


// === EVENTS === //
    #[event]
    struct MintEvent has copy, drop, store {
        shared: String,
        token: String,
        chain: String,
        amount: u64,
        time: u64
    }

    #[event]
    struct BurnEvent has copy, drop, store {
        shared: String,
        token: String,
        chain: String,
        amount: u64,
        time: u64
    }

// === INIT === //
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @dev, 1);

        if (!exists<AddressCounter>(@dev)) {
            move_to(admin, AddressCounter { counter: 0, counter_outflow: 0 });
        };
        if (!exists<AddressDatabase>(@dev)) {
            move_to(admin, AddressDatabase { table: table::new<String, u64>(), table_outflow: table::new<vector<u8>, u64>() });
        };
        if (!exists<TokensChains>(@dev)) {
            move_to(admin, TokensChains { book: map::new<String, vector<String>>() });
        };
        if (!exists<CrosschainBook>(@dev)) {
            move_to(admin, CrosschainBook { book: map::new<String,Map<String, u256>>() });
        };
        if (!exists<UserCrosschainBook>(@dev)) {
            move_to(admin, UserCrosschainBook { nonce: table::new<vector<u8>, u256>(), book: table::new<u64, Map<String, Map<String, Map<String, u256>>>>(), outflows: table::new<u64, Map<vector<u8>, Map<String, Map<String, u256>>>>() });
        };
        if (!exists<Permissions>(@dev)) {
            move_to(admin, Permissions { nonce: Nonce::give_access(admin)});
        };
    }

    fun tttta(id: u64){
        abort(id);
    }

// === HELPERS === //

    public fun change_TokenSupply(token:String, chain:String, amount: u64, isMint: bool, perm: Permission) acquires CrosschainBook, TokensChains {
       // ChainTypes::ensure_valid_chain_name(&chain);
       // TokensType::ensure_valid_token(&token);
      
        let book = borrow_global_mut<CrosschainBook>(@dev);
        let chains = borrow_global_mut<TokensChains>(@dev);
        let token_type = token;
        let chain_type = chain;
        
        if (!map::contains_key(&chains.book, &token_type)) {
            map::upsert(&mut chains.book, token_type, vector::empty<String>());
        };
        let chains = map::borrow_mut(&mut chains.book, &token_type);
        vector::push_back(chains, chain);

        if (!map::contains_key(&book.book, &chain_type)) {
            map::add(&mut book.book, chain_type, map::new<String, u256>());
        };
        
        let token_book = map::borrow_mut(&mut book.book, &chain_type);
        ensure_token_supports_chain(token, chain);
 
        // Force the logic without else
        if (map::contains_key(token_book, &token_type)) {
            let current_supply = map::borrow_mut(token_book, &token_type);
            if (isMint) {
                *current_supply = *current_supply + (amount as u256);
            } else {
                assert!(*current_supply >= (amount as u256), 99999);
                *current_supply = *current_supply - (amount as u256);
            }
        } else {
            map::upsert(token_book, token_type, (amount as u256));
        }   
    }


    public fun change_UserTokenSupply(token: String, chain: String, shared: String, amount: u64, isMint: bool, _perm: Permission) acquires AddressCounter, AddressDatabase, UserCrosschainBook {
        let book = borrow_global_mut<UserCrosschainBook>(@dev);
        let addressCounter_ref = borrow_global_mut<AddressCounter>(@dev);
        let addressDatabase_ref = borrow_global_mut<AddressDatabase>(@dev);
        let page_number = addressCounter_ref.counter / 100;

        if (!table::contains(&addressDatabase_ref.table, shared)) {
            table::add(&mut addressDatabase_ref.table, shared, page_number); // Store the page!
            addressCounter_ref.counter = addressCounter_ref.counter + 1;
        };
        
        if (!table::contains(&book.book, page_number)) {
            table::add(&mut book.book, page_number, map::new<String, Map<String, Map<String, u256>>>());
        };

        // handling pagination
        let users = table::borrow_mut(&mut book.book, page_number);
        if (!map::contains_key(users, &shared)) {
            map::add(users, shared, map::new<String, Map<String, u256>>());
        };

        // handling user
        let shared_storage = map::borrow_mut(users, &shared);
        if(!map::contains_key(shared_storage, &chain)) {
            map::add(shared_storage, chain, map::new<String, u256>());
        };
        let token_map = map::borrow_mut(shared_storage, &chain);

        // --- CRITICAL FIX: MOVE THIS OUTSIDE THE ELSE BLOCK ---
        if (!map::contains_key(token_map, &token)) {
            let initial_amount = if (isMint) { (amount as u256) } else { 0 };
            map::add(token_map, token, initial_amount);
        } else {
            let current_balance = map::borrow_mut(token_map, &token);
            if (isMint) {
                *current_balance = *current_balance + (amount as u256);
            } else {
                assert!(*current_balance >= (amount as u256), 101); // INSUFFICIENT_BALANCE
                *current_balance = *current_balance - (amount as u256);
            };
        };

        // --- EMIT EVENTS AT THE VERY END ---
        if (isMint) {
            event::emit(MintEvent { shared, token, chain, amount, time: timestamp::now_seconds() });
        } else {
            event::emit(BurnEvent { shared, token, chain, amount, time: timestamp::now_seconds() });
        };
    }

    public fun increment_UserOutflow(token: String, chain: String, shared: String, address: vector<u8>, amount: u64, isMint: bool, _perm: Permission) acquires AddressCounter, AddressDatabase, UserCrosschainBook {
       // Shared::assert_is_sub_owner(shared, address);
        let book = borrow_global_mut<UserCrosschainBook>(@dev);
        let addressCounter_ref = borrow_global_mut<AddressCounter>(@dev);
        let addressDatabase_ref = borrow_global_mut<AddressDatabase>(@dev);
        let page_number = addressCounter_ref.counter / 100;

        if (!table::contains(&addressDatabase_ref.table_outflow, address)) {
            table::add(&mut addressDatabase_ref.table_outflow, address, page_number); // Store the page!
            addressCounter_ref.counter_outflow = addressCounter_ref.counter_outflow + 1;
        };
        
        if (!table::contains(&book.outflows, page_number)) {
            table::add(&mut book.outflows, page_number, map::new<vector<u8>, Map<String, Map<String, u256>>>());
        };

        // handling pagination
        let users = table::borrow_mut(&mut book.outflows, page_number);
        if (!map::contains_key(users, &address)) {
            map::add(users, address, map::new<String, Map<String, u256>>());
        };

        // handling user
        let user = map::borrow_mut(users, &address);
        if(!map::contains_key(user, &chain)) {
            map::add(user, chain, map::new<String, u256>());
        };
        let token_map = map::borrow_mut(user, &chain);

        // --- CRITICAL FIX: MOVE THIS OUTSIDE THE ELSE BLOCK ---
        if (!map::contains_key(token_map, &token)) {
            let initial_amount = if (isMint) { (amount as u256) } else { 0 };
            map::add(token_map, token, initial_amount);
        } else {
            let current_balance = map::borrow_mut(token_map, &token);
            if (isMint) {
                *current_balance = *current_balance + (amount as u256);
            } else {
                assert!(*current_balance >= (amount as u256), 101); // INSUFFICIENT_BALANCE
                *current_balance = *current_balance - (amount as u256);
            };
        };

        //Nonce::increment_nonce(address, utf8(b"zk"), Nonce::give_permission(&borrow_global<Permissions>(@dev).nonce));

        // --- EMIT EVENTS AT THE VERY END ---
        if (isMint) {
            event::emit(MintEvent { shared, token, chain, amount, time: timestamp::now_seconds() });
        } else {
            event::emit(BurnEvent { shared, token, chain, amount, time: timestamp::now_seconds() });
        };
    }

    public fun increment_UserInflow(address: vector<u8>, _perm: Permission){
        Nonce::increment_nonce(address, utf8(b"native"), Nonce::give_permission(&borrow_global<Permissions>(@dev).nonce));
    }

// === VIEW FUNCTIONS === //
    
    #[view]
    public fun return_registry():  Map<String, vector<String>> acquires TokensChains {
        borrow_global<TokensChains>(@dev).book
    }

    #[view]
    public fun return_supported_chains(token:String): vector<String> acquires TokensChains {
        let book = borrow_global<TokensChains>(@dev);
        if (!map::contains_key(&book.book, &token)) {
            abort ERROR_TOKEN_NOT_INITIALIZED
        };
        return *map::borrow(&book.book, &token)
    }


    public fun ensure_token_supports_chain(token: String, chain:String) acquires TokensChains{
        assert!(vector::contains(&return_supported_chains(token), &chain), ERROR_TOKEN_NOT_INITIALIZED_FOR_THIS_CHAIN)
    }

    #[view]
    public fun return_global_supply(token:String): Map<String, u256> acquires CrosschainBook {
        let book = borrow_global<CrosschainBook>(@dev);
        if (!map::contains_key(&book.book, &token)) {
            abort ERROR_TOKEN_NOT_INITIALIZED
        };

        return *map::borrow(&book.book, &token)

    }

    #[view]
    public fun return_supply(chain:String, token: String): u256 acquires CrosschainBook {
        let book = borrow_global<CrosschainBook>(@dev);
        if (!map::contains_key(&book.book, &chain)) {
            abort ERROR_TOKEN_NOT_INITIALIZED_FOR_THIS_CHAIN
        };

        let map = map::borrow(&book.book, &chain);

        if(!map::contains_key(map, &chain)) {
            abort ERROR_TOKEN_NOT_INITIALIZED
        };

        return *map::borrow(map, &chain)

    }
    
    #[view]
    public fun return_balance_page(page_number: u64): Map<String,Map<String, Map<String, u256>>> acquires UserCrosschainBook {
        let book = borrow_global<UserCrosschainBook>(@dev);

        *table::borrow(&book.book, page_number)
    }
    #[view]
    public fun return_address_full_balance(address: String): Map<String, Map<String, u256>> acquires UserCrosschainBook, AddressDatabase {
        let book = borrow_global<UserCrosschainBook>(@dev);
        let addressDatabase_ref = borrow_global<AddressDatabase>(@dev);

        if (!table::contains(&addressDatabase_ref.table, address)) {
            abort ERROR_ADDRESS_NOT_INITIALIZED
        };
        let user_pagination = table::borrow(&addressDatabase_ref.table, address);

        let users = table::borrow(&book.book, *user_pagination);
        return *map::borrow(users, &address)
    }
    #[view]
    public fun return_address_balance_by_chain_for_token(address: String, chain:String, token:String,): u256 acquires UserCrosschainBook, AddressDatabase {
        let book = borrow_global<UserCrosschainBook>(@dev);
        let addressDatabase_ref = borrow_global<AddressDatabase>(@dev);

        if (!table::contains(&addressDatabase_ref.table, address)) {
            abort ERROR_ADDRESS_NOT_INITIALIZED
        };
        let user_pagination = table::borrow(&addressDatabase_ref.table, address);

        let users = table::borrow(&book.book, *user_pagination);
        if(!map::contains_key(users, &address)) {
            abort ERROR_ADDRESS_NOT_INITIALIZED
        };

        let user_book = map::borrow(users, &address);
        if(!map::contains_key(user_book, &chain)) {
            abort ERROR_TOKEN_ON_CHAIN_IN_ADDRESS_NOT_INITIALIZED 
        };
        let map = map::borrow(user_book, &chain);
        if(!map::contains_key(map, &token)) {
            abort ERROR_TOKEN_IN_ADDRESS_NOT_INITIALIZED
        };
        return *map::borrow(map, &token)

    }

    #[view]
    public fun return_outflow_page(page_number: u64): Map<vector<u8>,Map<String, Map<String, u256>>> acquires UserCrosschainBook {
        let book = borrow_global<UserCrosschainBook>(@dev);

        *table::borrow(&book.outflows, page_number)
    }
    #[view]
    public fun return_address_full_outflow(address: vector<u8>): Map<String, Map<String, u256>> acquires UserCrosschainBook, AddressDatabase {
        let book = borrow_global<UserCrosschainBook>(@dev);
        let addressDatabase_ref = borrow_global<AddressDatabase>(@dev);

        if (!table::contains(&addressDatabase_ref.table_outflow, address)) {
            abort ERROR_ADDRESS_NOT_INITIALIZED
        };
        let user_pagination = table::borrow(&addressDatabase_ref.table_outflow, address);

        let users = table::borrow(&book.outflows, *user_pagination);
        return *map::borrow(users, &address)
    }
    #[view]
    public fun return_address_outflow_by_chain_for_token(address: vector<u8>, chain:String, token:String): u256 acquires UserCrosschainBook, AddressDatabase {
        let book = borrow_global<UserCrosschainBook>(@dev);
        let addressDatabase_ref = borrow_global<AddressDatabase>(@dev);
        abort 100;
        if (!table::contains(&addressDatabase_ref.table_outflow, address)) {
            abort 101
        };
        let user_pagination = table::borrow(&addressDatabase_ref.table_outflow, address);

        let users = table::borrow(&book.outflows, *user_pagination);
        if(!map::contains_key(users, &address)) {
            abort 102
        };

        let user_book = map::borrow(users, &address);
        if(!map::contains_key(user_book, &chain)) {
            abort 103
        };
        let map = map::borrow(user_book, &chain);
        if(!map::contains_key(map, &token)) {
            abort 104
        };
        return *map::borrow(map, &token)

    }

    #[view]
    public fun accq(address: vector<u8>, chain:String, token:String): u256 acquires UserCrosschainBook, AddressDatabase {
        let book = borrow_global<UserCrosschainBook>(@dev);
        let addressDatabase_ref = borrow_global<AddressDatabase>(@dev);
        if (!table::contains(&addressDatabase_ref.table_outflow, address)) {
            return 0
        };
        let user_pagination = table::borrow(&addressDatabase_ref.table_outflow, address);

        let users = table::borrow(&book.outflows, *user_pagination);
        if(!map::contains_key(users, &address)) {
            return 0
        };

        let user_book = map::borrow(users, &address);
        if(!map::contains_key(user_book, &chain)) {
            return 0
        };
        let map = map::borrow(user_book, &chain);
        if(!map::contains_key(map, &token)) {
            return 0
        };
        return *map::borrow(map, &token)

    }

    #[view]
    public fun return_specified_outflow_path(address: vector<u8>, chain:String, token:String): u256 acquires UserCrosschainBook, AddressDatabase {
        let book = borrow_global<UserCrosschainBook>(@dev);
        let addressDatabase_ref = borrow_global<AddressDatabase>(@dev);
        if (!table::contains(&addressDatabase_ref.table_outflow, address)) {
            return 0
        };
        let user_pagination = table::borrow(&addressDatabase_ref.table_outflow, address);

        let users = table::borrow(&book.outflows, *user_pagination);
        if(!map::contains_key(users, &address)) {
            return 0
        };

        let user_book = map::borrow(users, &address);
        if(!map::contains_key(user_book, &chain)) {
            return 0
        };
        let map = map::borrow(user_book, &chain);
        if(!map::contains_key(map, &token)) {
            return 0
        };
        return *map::borrow(map, &token)

    }
    

}