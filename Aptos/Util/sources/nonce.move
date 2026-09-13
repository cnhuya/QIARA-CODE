module dev::QiaraNonceV2 {
    use std::signer;
    use std::table::{Self, Table};
    use std::string::{String, utf8};
    use aptos_framework::event;

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
    struct UserNonce has copy, drop, store {
        zk_nonce: u256,
        main_nonce: u256,
    }

    struct Nonces has key, store {
        table: Table<vector<u8>, UserNonce>,
    }

    struct GlobalNonce has key {
        value: u64,
    }

// === EVENTS === //
    #[event]
    struct NonceAdd has copy, drop, store {
        addr: vector<u8>,
        type: String,
    }

    #[event]
    struct GlobalNonceIncrement has copy, drop, store {
        new_value: u64,
    }

    // ----------------------------------------------------------------
    // Module init
    // ----------------------------------------------------------------
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_ADMIN);

        if (!exists<Nonces>(@dev)) {
            move_to(admin, Nonces { table: table::new<vector<u8>, UserNonce>() });
        };
        if (!exists<GlobalNonce>(@dev)) {
            move_to(admin, GlobalNonce { value: 0 });
        };
    }

    // ----------------------------------------------------------------
    // Standalone Init (for existing deployments)
    // ----------------------------------------------------------------
    public entry fun init_global_nonce(admin: &signer) {
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_ADMIN);
        if (!exists<GlobalNonce>(@dev)) {
            move_to(admin, GlobalNonce { value: 0 });
        };
    }

    // ----------------------------------------------------------------
    // Global Nonce Operations
    // ----------------------------------------------------------------
    public fun increment_global_nonce(_perm: &Permission): u64 acquires GlobalNonce {
        let gn = borrow_global_mut<GlobalNonce>(@dev);
        gn.value = gn.value + 1;
        event::emit(GlobalNonceIncrement { new_value: gn.value });
        gn.value
    }

    public entry fun dev_set_global_nonce(signer: &signer, value: u64) acquires GlobalNonce {
        assert!(signer::address_of(signer) == @dev, ERROR_NOT_ADMIN);
        let gn = borrow_global_mut<GlobalNonce>(@dev);
        gn.value = value;
    }

    // ----------------------------------------------------------------
    // User Nonce Operations
    // ----------------------------------------------------------------
    public entry fun test_increment(signer: &signer, type: String, addr: vector<u8>) acquires Nonces {
        increment_nonce(addr, type, give_permission(&give_access(signer)));
    }

    public fun increment_nonce(user: vector<u8>, type: String, _perm: Permission) acquires Nonces {
        let nonces = borrow_global_mut<Nonces>(@dev);
        if (!table::contains(&nonces.table, user)) {
            table::add(&mut nonces.table, user, UserNonce { zk_nonce: 0, main_nonce: 0 });
        };

        let nonce_ref = table::borrow_mut(&mut nonces.table, user);
        if (type == utf8(b"zk") || type == utf8(b"proof")) {
            nonce_ref.zk_nonce = nonce_ref.zk_nonce + 1;
        } else if (type == utf8(b"native")) {
            nonce_ref.main_nonce = nonce_ref.main_nonce + 1;
        };

        event::emit(NonceAdd {
            addr: user,
            type,
        });
    }

    public entry fun dev_delete_user_nonce(signer: &signer, addr: vector<u8>) acquires Nonces {
        delete_user_nonce(addr, give_permission(&give_access(signer)));
    }

    public fun delete_user_nonce(user: vector<u8>, _perm: Permission) acquires Nonces {
        let nonces = borrow_global_mut<Nonces>(@dev);
        if (table::contains(&nonces.table, user)) {
            table::remove(&mut nonces.table, user);
        };
    }

    public entry fun dev_reset_user_nonce(signer: &signer, addr: vector<u8>) acquires Nonces {
        reset_user_nonce(addr, give_permission(&give_access(signer)));
    }

    public fun reset_user_nonce(user: vector<u8>, _perm: Permission) acquires Nonces {
        let nonces = borrow_global_mut<Nonces>(@dev);
        if (table::contains(&nonces.table, user)) {
            let nonce_ref = table::borrow_mut(&mut nonces.table, user);
            nonce_ref.zk_nonce = 0;
            nonce_ref.main_nonce = 0;
        };
    }

    // ----------------------------------------------------------------
    // Views
    // ----------------------------------------------------------------
    #[view]
    public fun get_global_nonce(): u64 acquires GlobalNonce {
        if (!exists<GlobalNonce>(@dev)) { 0 }
        else { borrow_global<GlobalNonce>(@dev).value }
    }

    #[view]
    public fun return_user_nonce_by_type(user: vector<u8>, type: String): u256 acquires Nonces {
        let nonces = borrow_global<Nonces>(@dev);
        if (!table::contains(&nonces.table, user)) {
            return 0
        };
        let user_ref = table::borrow(&nonces.table, user);
        if (type == utf8(b"zk") || type == utf8(b"proof")) {
            user_ref.zk_nonce
        } else if (type == utf8(b"native")) {
            user_ref.main_nonce
        } else {
            0
        }
    }

    #[view]
    public fun return_user_nonce(user: vector<u8>): UserNonce acquires Nonces {
        let nonces = borrow_global<Nonces>(@dev);
        if (!table::contains(&nonces.table, user)) {
            UserNonce { zk_nonce: 0, main_nonce: 0 }
        } else {
            *table::borrow(&nonces.table, user)
        }
    }
}