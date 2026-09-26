module dev::QiaraTokensOmnichainV75 {
    use std::signer;
    use std::timestamp;
    use std::vector;
    use std::string::String;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use std::table::{Self, Table};
    use aptos_framework::event;

    use dev::QiaraNonceV4::{Self as Nonce, Access as NonceAccess};

    // === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 0;
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

    public fun give_permission(_access: &Access): Permission {
        Permission {}
    }

    // === STRUCTS === //
    struct Permissions has key {
        nonce: NonceAccess,
    }

    // For Pagination purposes
    struct AddressCounter has key {
        counter: u64,
        counter_outflow: u64,
        counter_qiara_outflow: u64,
    }

    // Needed to track addresses, to avoid duplication
    struct AddressDatabase has key {
        table: Table<String, u64>,
        table_outflow: Table<vector<u8>, u64>,
        table_qiara_outflow: Table<vector<u8>, u64>,
    }

    // Tracks allowed/supported chains for each Token.
    // i.e Ethereum (token) -> Base/Sui/Solana (chains)
    struct TokensChains has key {
        book: Map<String, vector<String>>,
    }

    // Tracks overall "liquidity" across chains for each token type (the string argument)
    // i.e Ethereum (token) -> Base/Sui/Solana (chains)... -> supply
    struct CrosschainBook has key {
        book: Map<String, Map<String, u256>>,
    }

    // Tracks "liquidity" across chains for each address
    // i.e 0/1/2...(page) -> 0x...123 (user) -> Base/Sui/Solana (chains).. -> Ethereum (token) -> supply
    struct UserCrosschainBook has key {
        outflows: Table<u64, Map<vector<u8>, Map<String, Map<String, u256>>>>,
    }

    // Paged QIARA outflow tracker:
    // i.e 0/1/2...(page) -> 0x...123 (user) -> Base/Sui/Solana (chains).. -> supply
    struct UserQiaraCrosschainBook has key {
        outflows: Table<u64, Map<vector<u8>, Map<String, u256>>>,
    }

    // === EVENTS === //
    #[event]
    struct MintEvent has copy, drop, store {
        shared: String,
        token: String,
        chain: String,
        amount: u64,
        time: u64,
    }

    #[event]
    struct BurnEvent has copy, drop, store {
        shared: String,
        token: String,
        chain: String,
        amount: u64,
        time: u64,
    }

    // === INIT === //
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_ADMIN);

        if (!exists<AddressCounter>(@dev)) {
            move_to(admin, AddressCounter { 
                counter: 0, 
                counter_outflow: 0, 
                counter_qiara_outflow: 0 
            });
        };
        if (!exists<AddressDatabase>(@dev)) {
            move_to(admin, AddressDatabase { 
                table: table::new(), 
                table_outflow: table::new(),
                table_qiara_outflow: table::new()
            });
        };
        if (!exists<TokensChains>(@dev)) {
            move_to(admin, TokensChains { book: map::new() });
        };
        if (!exists<CrosschainBook>(@dev)) {
            move_to(admin, CrosschainBook { book: map::new() });
        };
        if (!exists<UserCrosschainBook>(@dev)) {
            move_to(admin, UserCrosschainBook { outflows: table::new() });
        };
        if (!exists<UserQiaraCrosschainBook>(@dev)) {
            move_to(admin, UserQiaraCrosschainBook { outflows: table::new() });
        };
        if (!exists<Permissions>(@dev)) {
            move_to(admin, Permissions { nonce: Nonce::give_access(admin) });
        };
    }

    // === QIARA TRACKER FUNCTIONS === //

    public fun increment_QiaraUserOutflow(
        chain: String,
        shared: String,
        address: vector<u8>,
        amount: u64,
        isMint: bool,
        _perm: Permission
    ) acquires AddressCounter, AddressDatabase, UserQiaraCrosschainBook {
        let book = borrow_global_mut<UserQiaraCrosschainBook>(@dev);
        let addressCounter_ref = borrow_global_mut<AddressCounter>(@dev);
        let addressDatabase_ref = borrow_global_mut<AddressDatabase>(@dev);

        // Deduplication check: assign page on first interaction; reuse on subsequent ones
        if (!table::contains(&addressDatabase_ref.table_qiara_outflow, address)) {
            let page_number = addressCounter_ref.counter_qiara_outflow / 100;
            table::add(&mut addressDatabase_ref.table_qiara_outflow, address, page_number);
            addressCounter_ref.counter_qiara_outflow = addressCounter_ref.counter_qiara_outflow + 1;
        };

        let page_number = *table::borrow(&addressDatabase_ref.table_qiara_outflow, address);
        if (!table::contains(&book.outflows, page_number)) {
            table::add(&mut book.outflows, page_number, map::new());
        };

        let users = table::borrow_mut(&mut book.outflows, page_number);
        if (!map::contains_key(users, &address)) {
            map::add(users, address, map::new());
        };

        let user_map = map::borrow_mut(users, &address);
        let amount_u256 = (amount as u256);

        if (!map::contains_key(user_map, &chain)) {
            let initial = if (isMint) { amount_u256 } else { 0 };
            map::add(user_map, chain, initial);
        } else {
            let bal = map::borrow_mut(user_map, &chain);
            if (isMint) {
                *bal = *bal + amount_u256;
            } else {
                assert!(*bal >= amount_u256, ERROR_INSUFFICIENT_BALANCE);
                *bal = *bal - amount_u256;
            };
        };

        let now = timestamp::now_seconds();
        let token_name = std::string::utf8(b"QIARA");
        if (isMint) {
            event::emit(MintEvent { shared, token: token_name, chain, amount, time: now });
        } else {
            event::emit(BurnEvent { shared, token: token_name, chain, amount, time: now });
        };
    }


    #[view]
    public fun return_qiara_outflow_page(page_number: u64): Map<vector<u8>, Map<String, u256>> acquires UserQiaraCrosschainBook {
        *table::borrow(&borrow_global<UserQiaraCrosschainBook>(@dev).outflows, page_number)
    }

    #[view]
    public fun return_qiara_user_page(address: vector<u8>): u64 acquires AddressDatabase {
        let addressDatabase_ref = borrow_global<AddressDatabase>(@dev);
        assert!(table::contains(&addressDatabase_ref.table_qiara_outflow, address), ERROR_ADDRESS_NOT_INITIALIZED);
        *table::borrow(&addressDatabase_ref.table_qiara_outflow, address)
    }

    #[view]
    public fun return_qiara_outflow_path(address: vector<u8>, chain: String): u256 acquires UserQiaraCrosschainBook, AddressDatabase {
        let addressDatabase_ref = borrow_global<AddressDatabase>(@dev);
        if (!table::contains(&addressDatabase_ref.table_qiara_outflow, address)) return 0;
        let page = *table::borrow(&addressDatabase_ref.table_qiara_outflow, address);
        let book = borrow_global<UserQiaraCrosschainBook>(@dev);
        if (!table::contains(&book.outflows, page)) return 0;
        let users = table::borrow(&book.outflows, page);
        if (!map::contains_key(users, &address)) return 0;
        let user_map = map::borrow(users, &address);
        if (!map::contains_key(user_map, &chain)) return 0;
        *map::borrow(user_map, &chain)
    }

    #[view]
    public fun return_address_qiara_full_outflow(address: vector<u8>): Map<String, u256> acquires UserQiaraCrosschainBook, AddressDatabase {
        let addressDatabase_ref = borrow_global<AddressDatabase>(@dev);
        assert!(table::contains(&addressDatabase_ref.table_qiara_outflow, address), ERROR_ADDRESS_NOT_INITIALIZED);
        let page = *table::borrow(&addressDatabase_ref.table_qiara_outflow, address);
        let book = borrow_global<UserQiaraCrosschainBook>(@dev);
        *map::borrow(table::borrow(&book.outflows, page), &address)
    }

    // === STANDARD MULTI-TOKEN HELPERS === //

    public fun change_TokenSupply(token: String, chain: String, amount: u64, isMint: bool, _perm: Permission) acquires CrosschainBook, TokensChains {
        let book = borrow_global_mut<CrosschainBook>(@dev);
        let chains = borrow_global_mut<TokensChains>(@dev);
        
        if (!map::contains_key(&chains.book, &token)) {
            map::add(&mut chains.book, token, vector::empty());
        };
        let chain_list = map::borrow_mut(&mut chains.book, &token);
        if (!vector::contains(chain_list, &chain)) {
            vector::push_back(chain_list, chain);
        };

        if (!map::contains_key(&book.book, &chain)) {
            map::add(&mut book.book, chain, map::new());
        };
        
        let token_book = map::borrow_mut(&mut book.book, &chain);
        let amount_u256 = (amount as u256);

        if (map::contains_key(token_book, &token)) {
            let current_supply = map::borrow_mut(token_book, &token);
            if (isMint) {
                *current_supply = *current_supply + amount_u256;
            } else {
                assert!(*current_supply >= amount_u256, ERROR_INSUFFICIENT_BALANCE);
                *current_supply = *current_supply - amount_u256;
            };
        } else {
            map::add(token_book, token, amount_u256);
        };
    }

    public fun increment_UserOutflow(
        token: String,
        chain: String,
        shared: String,
        address: vector<u8>,
        amount: u64,
        isMint: bool,
        _perm: Permission
    ) acquires AddressCounter, AddressDatabase, UserCrosschainBook {
        let book = borrow_global_mut<UserCrosschainBook>(@dev);
        let addressCounter_ref = borrow_global_mut<AddressCounter>(@dev);
        let addressDatabase_ref = borrow_global_mut<AddressDatabase>(@dev);

        if (!table::contains(&addressDatabase_ref.table_outflow, address)) {
            let page_number = addressCounter_ref.counter_outflow / 100;
            table::add(&mut addressDatabase_ref.table_outflow, address, page_number);
            addressCounter_ref.counter_outflow = addressCounter_ref.counter_outflow + 1;
        };
        
        let page_number = *table::borrow(&addressDatabase_ref.table_outflow, address);
        if (!table::contains(&book.outflows, page_number)) {
            table::add(&mut book.outflows, page_number, map::new());
        };

        let users = table::borrow_mut(&mut book.outflows, page_number);
        if (!map::contains_key(users, &address)) {
            map::add(users, address, map::new());
        };

        let user = map::borrow_mut(users, &address);
        if (!map::contains_key(user, &chain)) {
            map::add(user, chain, map::new());
        };

        let token_map = map::borrow_mut(user, &chain);
        let amount_u256 = (amount as u256);

        if (!map::contains_key(token_map, &token)) {
            let initial = if (isMint) { amount_u256 } else { 0 };
            map::add(token_map, token, initial);
        } else {
            let balance = map::borrow_mut(token_map, &token);
            if (isMint) {
                *balance = *balance + amount_u256;
            } else {
                assert!(*balance >= amount_u256, ERROR_INSUFFICIENT_BALANCE);
                *balance = *balance - amount_u256;
            };
        };

        let now = timestamp::now_seconds();
        if (isMint) {
            event::emit(MintEvent { shared, token, chain, amount, time: now });
        } else {
            event::emit(BurnEvent { shared, token, chain, amount, time: now });
        };
    }

    public fun increment_UserInflow(address: vector<u8>, _perm: Permission) acquires Permissions {
        Nonce::increment_nonce(address, std::string::utf8(b"native"), Nonce::give_permission(&borrow_global<Permissions>(@dev).nonce));
    }

    // === VIEW FUNCTIONS === //
    
    #[view]
    public fun return_registry(): Map<String, vector<String>> acquires TokensChains {
        borrow_global<TokensChains>(@dev).book
    }

    #[view]
    public fun return_supported_chains(token: String): vector<String> acquires TokensChains {
        let book = borrow_global<TokensChains>(@dev);
        assert!(map::contains_key(&book.book, &token), ERROR_TOKEN_NOT_INITIALIZED);
        *map::borrow(&book.book, &token)
    }

    public fun ensure_token_supports_chain(token: String, chain: String) acquires TokensChains {
        assert!(vector::contains(&return_supported_chains(token), &chain), ERROR_TOKEN_NOT_INITIALIZED_FOR_THIS_CHAIN);
    }

    #[view]
    public fun return_global_supply(token: String): Map<String, u256> acquires CrosschainBook {
        let book = borrow_global<CrosschainBook>(@dev);
        assert!(map::contains_key(&book.book, &token), ERROR_TOKEN_NOT_INITIALIZED);
        *map::borrow(&book.book, &token)
    }

    #[view]
    public fun return_supply(chain: String, token: String): u256 acquires CrosschainBook {
        let book = borrow_global<CrosschainBook>(@dev);
        assert!(map::contains_key(&book.book, &chain), ERROR_TOKEN_NOT_INITIALIZED_FOR_THIS_CHAIN);
        let token_map = map::borrow(&book.book, &chain);
        assert!(map::contains_key(token_map, &token), ERROR_TOKEN_NOT_INITIALIZED);
        *map::borrow(token_map, &token)
    }

    #[view]
    public fun return_outflow_page(page_number: u64): Map<vector<u8>, Map<String, Map<String, u256>>> acquires UserCrosschainBook {
        *table::borrow(&borrow_global<UserCrosschainBook>(@dev).outflows, page_number)
    }

    #[view]
    public fun return_user_page(address: vector<u8>): u64 acquires AddressDatabase {
        let addressDatabase_ref = borrow_global<AddressDatabase>(@dev);
        assert!(table::contains(&addressDatabase_ref.table_outflow, address), ERROR_ADDRESS_NOT_INITIALIZED);
        *table::borrow(&addressDatabase_ref.table_outflow, address)
    }

    #[view]
    public fun return_address_full_outflow(address: vector<u8>): Map<String, Map<String, u256>> acquires UserCrosschainBook, AddressDatabase {
        let addressDatabase_ref = borrow_global<AddressDatabase>(@dev);
        assert!(table::contains(&addressDatabase_ref.table_outflow, address), ERROR_ADDRESS_NOT_INITIALIZED);
        let page = *table::borrow(&addressDatabase_ref.table_outflow, address);
        let book = borrow_global<UserCrosschainBook>(@dev);
        *map::borrow(table::borrow(&book.outflows, page), &address)
    }

    #[view]
    public fun return_address_outflow_by_chain_for_token(address: vector<u8>, chain: String, token: String): u256 acquires UserCrosschainBook, AddressDatabase {
        return_specified_outflow_path(address, chain, token)
    }

    #[view]
    public fun return_specified_outflow_path(address: vector<u8>, chain: String, token: String): u256 acquires UserCrosschainBook, AddressDatabase {
        let addressDatabase_ref = borrow_global<AddressDatabase>(@dev);
        if (!table::contains(&addressDatabase_ref.table_outflow, address)) return 0;
        let page = *table::borrow(&addressDatabase_ref.table_outflow, address);
        let book = borrow_global<UserCrosschainBook>(@dev);
        let users = table::borrow(&book.outflows, page);
        if (!map::contains_key(users, &address)) return 0;
        let user_book = map::borrow(users, &address);
        if (!map::contains_key(user_book, &chain)) return 0;
        let token_map = map::borrow(user_book, &chain);
        if (!map::contains_key(token_map, &token)) return 0;
        *map::borrow(token_map, &token)
    }
}