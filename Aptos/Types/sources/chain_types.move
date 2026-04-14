module dev::QiaraChainTypesV4 {
    use std::string::{Self as string, String, utf8};
    use std::vector;
    use std::signer;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use std::table::{Self, Table};

// === ERRORS === //
    const ERROR_INVALID_CHAIN: u64 = 1;
    const ERROR_CHAIN_NAME_ALREADY_REGISTERED: u64 = 2;
    const ERROR_CHAIN_ID_ALREADY_REGISTERED: u64 = 3;
// === STRUCTS === //

    struct Chains has key{
        map: Map<String, u32>
    }

// === INIT === //
    fun init_module(admin: &signer) acquires Chains {
        assert!(signer::address_of(admin) == @dev, 1);

        if (!exists<Chains>(@dev)) {
            move_to(admin, Chains { map: map::new<String, u32>() });
        };
        x_init(admin);
    }

    fun x_init(signer: &signer) acquires Chains{
        register_chain(signer, utf8(b"Aptos"), 2);
        register_chain(signer, utf8(b"Sui"), 103);
        register_chain(signer, utf8(b"Base"), 84532);
        register_chain(signer, utf8(b"Monad"), 10143);
        register_chain(signer, utf8(b"Ethereum"), 11155111);
    } 

// === FUNCTIONS === //
    public entry fun register_chain(signer: &signer, chain_name: String, chain_id: u32) acquires Chains {
        let chains = borrow_global_mut<Chains>(@dev);
        let keys = map::keys(&chains.map);
        let values = map::values(&chains.map);

        assert!(!vector::contains(&keys, &chain_name), ERROR_CHAIN_NAME_ALREADY_REGISTERED);
        assert!(!vector::contains(&values, &chain_id), ERROR_CHAIN_ID_ALREADY_REGISTERED);

        if (!map::contains_key(&chains.map, &chain_name)) {
            map::upsert(&mut chains.map, chain_name, chain_id);
        };

    }

    #[view]
    public fun return_all_chain(): Map<String, u32> acquires Chains  {
        borrow_global_mut<Chains>(@dev).map
    }

    #[view]
    public fun return_all_chain_names(): vector<String> acquires Chains{
        let chains = borrow_global<Chains>(@dev).map;
        map::keys(&chains)
    }

    #[view]
    public fun return_all_chain_ids(): vector<u32> acquires Chains {
        let chains = borrow_global<Chains>(@dev).map;
        map::values(&chains)
    }


    public fun ensure_valid_chain_id(chain_id: u32) acquires Chains{
        let map = borrow_global_mut<Chains>(@dev).map;
        assert!(vector::contains(&map::values(&map), &chain_id), ERROR_INVALID_CHAIN);
    }

    public fun ensure_valid_chain_name(chain_name: String) acquires Chains{
        let map = borrow_global_mut<Chains>(@dev).map;
        assert!(vector::contains(&map::keys(&map), &chain_name), ERROR_INVALID_CHAIN);
    }

}
