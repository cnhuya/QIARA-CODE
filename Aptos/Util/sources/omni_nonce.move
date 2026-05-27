module dev::QiaraOmniNonceV2{
    use std::signer;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
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
    

    struct OmniNonces has key, store{
        map: Map<String, u256>,
    }

// === EVENTS === //
    #[event]
    struct OmniNonceAdd has copy, drop, store {
        type: String,
    }

    // ----------------------------------------------------------------
    // Module init
    // ----------------------------------------------------------------
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @dev, 1);

        if (!exists<OmniNonces>(@dev)) {
            move_to(admin, OmniNonces {map: map::new<String, u256>()});
        };
    }

    public entry fun test_increment(signer: &signer, type: String) acquires OmniNonces {
        increment_nonce(type, give_permission(&give_access(signer)));
    }

    public fun increment_nonce(type: String, perm: Permission) acquires OmniNonces {
        let nonces = borrow_global_mut<OmniNonces>(@dev);
        if (!map::contains_key(&nonces.map, &type)) {
            map::add(&mut nonces.map, type, 0);
        };
        let nonce_ref = map::borrow_mut(&mut nonces.map, &type);
        *nonce_ref = *nonce_ref + 1;

         event::emit(OmniNonceAdd {
            type: type,
        });

    }

    #[view]
    public fun return_omni_nonce_by_type(type: String): u256 acquires OmniNonces {
        let nonces = borrow_global_mut<OmniNonces>(@dev);
        if (!map::contains_key(&nonces.map, &type)) {
           return 0;
        };
        return *map::borrow(&nonces.map, &type)
    }

 }
