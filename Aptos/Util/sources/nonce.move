module dev::QiaraNonceV2{
    use std::signer;
    use std::table::{Self, Table};
    use std::string::{Self as String, String, utf8};
    use std::vector;
    use std::bcs;
    use aptos_framework::event;

// === ERRORS === //
    const ERROR_NOT_ADMIN:u64 = 0;

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
    
    struct UserNonce has copy, drop, store {
        zk_nonce: u256,
        main_nonce: u256,
    }

    struct Nonces has key, store{
        table: Table<vector<u8>, UserNonce>,
    }

// === EVENTS === //
    #[event]
    struct NonceAdd has copy, drop, store {
        addr: vector<u8>,
        type: String,
    }

    // ----------------------------------------------------------------
    // Module init
    // ----------------------------------------------------------------
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @dev, 1);

        if (!exists<Nonces>(@dev)) {
            move_to(admin, Nonces {table: table::new<vector<u8>, UserNonce>()});
        };
    }

    public entry fun test_increment(signer: &signer, type: String, addr: vector<u8>) acquires Nonces {
        // REMOVE bcs::to_bytes here. Just pass 'addr' directly.
        increment_nonce(addr, type, give_permission(&give_access(signer)));
    }

    public fun increment_nonce(user: vector<u8>, type: String, perm: Permission) acquires Nonces {
        let nonces = borrow_global_mut<Nonces>(@dev);
        if (!table::contains(&nonces.table, user)) {
            table::add(&mut nonces.table, user, UserNonce {zk_nonce: 0, main_nonce: 0});
        };

        let nonce_ref = table::borrow_mut(&mut nonces.table, user);
        if(type == utf8(b"zk")) {
            nonce_ref.zk_nonce = nonce_ref.zk_nonce + 1;
        } else if(type == utf8(b"native")) {
            nonce_ref.main_nonce = nonce_ref.main_nonce + 1;
        };
         event::emit(NonceAdd {
            addr: user,
            type: type,
        });

    }

    #[view]
    public fun return_user_nonce_by_type(user: vector<u8>, type: String): u256 acquires Nonces {
        let nonces = borrow_global_mut<Nonces>(@dev);
        if (!table::contains(&nonces.table, user)) {
           return 0;
        };
        if(type == utf8(b"zk")) {
            return table::borrow(&nonces.table, user).zk_nonce
        } else if(type == utf8(b"native")) {
            return table::borrow(&nonces.table, user).main_nonce
        } else {
            return 0
        }
    }
    #[view]
    public fun return_user_nonce(user: vector<u8>): UserNonce acquires Nonces {
        let nonces = borrow_global_mut<Nonces>(@dev);
        if (!table::contains(&nonces.table, user)) {
           return UserNonce {zk_nonce: 0, main_nonce: 0};
        };
        return *table::borrow(&nonces.table, user)
    }
 }
