module dev::QiaraNonceV4 {
    use std::signer;
    use std::string::{String, utf8};
    use aptos_framework::event;
    use aptos_std::table::{Self, Table};
    use aptos_std::simple_map::{Self, SimpleMap as Map};

    // === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 0;

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
    struct Nonces has key, store {
        table: Table<vector<u8>, Map<String, u256>>,
        // User Nonces Tracker
        // Balances & Qiara
    }

    struct GlobalNonces has key {
        table: Map<String, u64>,
        // Global Nonce Tracker
        // Validators & Variables 
    }

    // === EVENTS === //
    #[event]
    struct NonceAdd has copy, drop, store {
        addr: vector<u8>,
        type: String,
    }

    #[event]
    struct GlobalNonceIncrement has copy, drop, store {
        type: String,
        new_value: u64,
    }

    // === INIT === //
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_ADMIN);
        if (!exists<Nonces>(@dev)) move_to(admin, Nonces { table: table::new() });
        if (!exists<GlobalNonces>(@dev)) move_to(admin, GlobalNonces { table: simple_map::new() });
    }

    // === GLOBAL NONCE OPERATIONS === //
    public fun increment_global_nonce_by_type(type: String, _perm: Permission): u64 acquires GlobalNonces {
        let gn = borrow_global_mut<GlobalNonces>(@dev);
        if (!simple_map::contains_key(&gn.table, &type)) {
            simple_map::add(&mut gn.table, copy type, 0);
        };
        let val = simple_map::borrow_mut(&mut gn.table, &type);
        *val = *val + 1;
        event::emit(GlobalNonceIncrement { type, new_value: *val });
        *val
    }

    public entry fun dev_set_global_nonce(signer: &signer, value: u64) acquires GlobalNonces {
        dev_set_global_nonce_by_type(signer, utf8(b"global"), value);
    }

    public entry fun dev_set_global_nonce_by_type(signer: &signer, type: String, value: u64) acquires GlobalNonces {
        assert!(signer::address_of(signer) == @dev, ERROR_NOT_ADMIN);
        let gn = borrow_global_mut<GlobalNonces>(@dev);
        simple_map::upsert(&mut gn.table, type, value);
    }

    // === USER NONCE OPERATIONS === //
    public entry fun test_increment(signer: &signer, type: String, addr: vector<u8>) acquires Nonces {
        increment_nonce(addr, type, give_permission(&give_access(signer)));
    }

    public fun increment_nonce(user: vector<u8>, type: String, _perm: Permission) acquires Nonces {
        let nonces = borrow_global_mut<Nonces>(@dev);
        if (!table::contains(&nonces.table, user)) {
            table::add(&mut nonces.table, copy user, simple_map::new());
        };
        let type_map = table::borrow_mut(&mut nonces.table, user);
        if (!simple_map::contains_key(type_map, &type)) {
            simple_map::add(type_map, copy type, 1);
        } else {
            let val = simple_map::borrow_mut(type_map, &type);
            *val = *val + 1;
        };
        event::emit(NonceAdd { addr: user, type });
    }

    public entry fun dev_reset_user_nonce(signer: &signer, type: String, addr: vector<u8>) acquires Nonces {
        reset_user_nonce(addr, type, give_permission(&give_access(signer)));
    }

    public fun reset_user_nonce(user: vector<u8>, type: String, _perm: Permission) acquires Nonces {
        let nonces = borrow_global_mut<Nonces>(@dev);
        if (table::contains(&nonces.table, user)) {
            let type_map = table::borrow_mut(&mut nonces.table, user);
            if (simple_map::contains_key(type_map, &type)) {
                let val = simple_map::borrow_mut(type_map, &type);
                *val = 0;
            };
        };
    }

    // === VIEWS === //
    #[view]
    public fun get_global_nonce(): Map<String, u64> acquires GlobalNonces {
        if (!exists<GlobalNonces>(@dev)) simple_map::new() else borrow_global<GlobalNonces>(@dev).table
    }

    #[view]
    public fun get_global_nonce_by_type(type: String): u64 acquires GlobalNonces {
        if (!exists<GlobalNonces>(@dev)) return 0;
        let gn = borrow_global<GlobalNonces>(@dev);
        if (!simple_map::contains_key(&gn.table, &type)) 0 else *simple_map::borrow(&gn.table, &type)
    }

    #[view]
    public fun return_user_nonce_by_type(user: vector<u8>, type: String): u256 acquires Nonces {
        if (!exists<Nonces>(@dev)) return 0;
        let nonces = borrow_global<Nonces>(@dev);
        if (!table::contains(&nonces.table, user)) return 0;
        let type_map = table::borrow(&nonces.table, user);
        if (!simple_map::contains_key(type_map, &type)) 0 else *simple_map::borrow(type_map, &type)
    }

    #[view]
    public fun get_all_user_nonces(user: vector<u8>): Map<String, u256> acquires Nonces {
        if (!exists<Nonces>(@dev)) return simple_map::new();
        let nonces = borrow_global<Nonces>(@dev);
        if (!table::contains(&nonces.table, user)) simple_map::new() else *table::borrow(&nonces.table, user)
    }

    #[view]
    public fun return_user_nonce(user: vector<u8>, type: String): u256 acquires Nonces {
        return_user_nonce_by_type(user, type)
    }
}