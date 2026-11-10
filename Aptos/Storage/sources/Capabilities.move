module dev::QiaraCapabilitiesV26{
    use std::string::{Self, String, utf8, bytes as b};
    use std::signer;
    use std::vector;
    use aptos_framework::event;
    use std::table::{Self, Table};
    use aptos_std::type_info;
    use aptos_std::from_bcs;
    use std::bcs::{Self as bc};
    use dev::QiaraSharedV18::{Self as Shared};
    use aptos_framework::account; // 👈 Add this import


  fun is_admin(caller: address): bool {
    let dao_address = account::create_resource_address(&@dev, b"QiaraDAO");
    caller == OWNER || caller == dao_address
    }

    struct Capability has store, drop, key, copy {
        name: String,
        removable: bool,
    }

    struct KeyRegistry has key {
        keys: vector<String>,
    }

    struct Capabilities has key, store {
        table: Table<String, Table<String, vector<Capability>>>
    }

    #[event]
    struct CapabilityCreated has drop, store {
        shared: String,
        capability: Capability,
    }

    const OWNER: address = @dev;
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_HEADER_DOESNT_EXISTS: u64 = 2;
    const ERROR_CAPABILITY_ALREADY_EXISTS: u64 = 3;
    const ERROR_CAPABILITY_DOESNT_EXISTS: u64 = 4;

    fun make_capability(name: String, removable: bool): Capability {
        Capability { name, removable}
    }


    // ----------------------------------------------------------------
    // Module init
    // ----------------------------------------------------------------
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == OWNER, ERROR_NOT_ADMIN);

        if (!exists<KeyRegistry>(OWNER)) {
            move_to(admin,KeyRegistry {keys: vector::empty<String>() });
        };

        if (!exists<Capabilities>(OWNER)) {
            move_to(
                admin,
                Capabilities { table: table::new<String, Table<String, vector<Capability>>>() }
            );
        };

        
        create_capability(admin, utf8(b"huya"), utf8(b"QiaraToken"), utf8(b"TOKEN_CLAIM_CAPABILITY"), true, );
        create_capability(admin, utf8(b"huya"), utf8(b"QiaraGovernance"), utf8(b"BLACKLIST"), true, );
        create_capability(admin, utf8(b"huya"), utf8(b"QiaraAuto"), utf8(b"EXECUTE_AUTO_DELETIONS"), true, );
        create_capability(admin, utf8(b"huya"), utf8(b"QiaraVerifiedTokens"), utf8(b"AUTHORIZED_MODULE_OWNER"), true, );

    }


    public entry fun init_caps(admin: &signer) acquires Capabilities, KeyRegistry{
        create_capability(admin, utf8(b"huya"), utf8(b"QiaraToken"), utf8(b"TOKEN_CLAIM_CAPABILITY"), true, );
        create_capability(admin, utf8(b"huya"), utf8(b"QiaraGovernance"), utf8(b"BLACKLIST"), true, );
        create_capability(admin, utf8(b"huya"), utf8(b"QiaraAuto"), utf8(b"EXECUTE_AUTO_DELETIONS"), true, );
        create_capability(admin, utf8(b"huya"), utf8(b"QiaraVerifiedTokens"), utf8(b"AUTHORIZED_MODULE_OWNER"), true, );
        create_capability(admin, utf8(b"huya"), utf8(b"QiaraPerps"), utf8(b"ORDER_EXECUTION"), true, );
    }

public fun create_capability(
    admin: &signer,         // 👈 Now accepts admin: &signer
    shared: String,
    header: String,
    name: String,
    removable: bool
) acquires Capabilities, KeyRegistry {
    assert!(is_admin(signer::address_of(admin)), ERROR_NOT_ADMIN); // 👈 Secure check

    let db = borrow_global_mut<Capabilities>(OWNER);
    let key_registry = borrow_global_mut<KeyRegistry>(OWNER);
    let new_cap = make_capability(name, removable);

    if (!vector::contains(&key_registry.keys, &header)) {
        vector::push_back(&mut key_registry.keys, header);
    };

    let inner_table = if (table::contains(&db.table, shared)) {
        table::borrow_mut(&mut db.table, shared)
    } else {
        let new_table = table::new<String, vector<Capability>>();
        table::add(&mut db.table, shared, new_table);
        table::borrow_mut(&mut db.table, shared)
    };

    if (table::contains(inner_table, header)) {
        let constants = table::borrow_mut(inner_table, header);
        let len = vector::length(constants);
        let i = 0;
        while (i < len) {
            let c_ref = vector::borrow(constants, i);
            if (c_ref.name == name) {
                abort ERROR_CAPABILITY_ALREADY_EXISTS
            };
            i = i + 1;
        };
        vector::push_back(constants, new_cap);
    } else {
        let vec = vector::empty<Capability>();
        vector::push_back(&mut vec, new_cap);
        table::add(inner_table, header, vec);
    };
}



public fun remove_capability(
    admin: &signer,         // 👈 Now accepts admin: &signer
    shared: String,
    header: String,
    name: String
) acquires Capabilities, KeyRegistry {
    assert!(is_admin(signer::address_of(admin)), ERROR_NOT_ADMIN); // 👈 Secure check

    let db = borrow_global_mut<Capabilities>(OWNER);
    let key_registry = borrow_global_mut<KeyRegistry>(OWNER);

    if (!vector::contains(&key_registry.keys, &header)) {
        abort ERROR_HEADER_DOESNT_EXISTS
    };

    if (!table::contains(&db.table, shared)) {
        abort ERROR_CAPABILITY_DOESNT_EXISTS
    };

    let inner_table = table::borrow_mut(&mut db.table, shared);

    if (table::contains(inner_table, header)) {
        let constants = table::borrow_mut(inner_table, header);
        let len = vector::length(constants);
        let i = 0;
        while (i < len) {
            let c_ref = vector::borrow(constants, i);
            if (c_ref.name == name && c_ref.removable) {
                vector::remove(constants, i);
                return
            };
            i = i + 1;
        };
        abort ERROR_CAPABILITY_DOESNT_EXISTS
    } else {
        abort ERROR_CAPABILITY_DOESNT_EXISTS
    };
}



    #[view]
    public fun viewHeaders(): vector<String> acquires KeyRegistry {
        let key_registry = borrow_global<KeyRegistry>(OWNER);
        key_registry.keys
    }

    #[view]
    public fun viewCapabilities(shared: String,header: String): vector<Capability> acquires Capabilities {
        let db = borrow_global<Capabilities>(OWNER);

        if (!table::contains(&db.table, shared)) {
            abort ERROR_CAPABILITY_DOESNT_EXISTS;
        };

        let inner_table = table::borrow(&db.table, shared);

        if (!table::contains(inner_table, header)) {
            abort ERROR_CAPABILITY_DOESNT_EXISTS;
        };

        let constants_ref = table::borrow(inner_table, header);
        *constants_ref // return a copy of the vector
    }


    #[view]
    public fun viewCapability(shared: String,header: String,constant_name: String): Capability acquires Capabilities {
        let db = borrow_global<Capabilities>(OWNER);

        if (!table::contains(&db.table, shared)) {
            abort ERROR_HEADER_DOESNT_EXISTS;
        };

        let inner_table = table::borrow(&db.table, shared);

        if (!table::contains(inner_table, header)) {
            abort ERROR_HEADER_DOESNT_EXISTS;
        };

        let constants_ref: &vector<Capability> = table::borrow(inner_table, header);
        let len = vector::length(constants_ref);

        let i = 0;
        while (i < len) {
            let c_ref = vector::borrow(constants_ref, i);
            if (c_ref.name == constant_name) {
                // clone capability to return
                return make_capability(c_ref.name, c_ref.removable);
            };
            i = i + 1;
        };

        // If not found
        abort ERROR_CAPABILITY_DOESNT_EXISTS
    }

    #[view]
    public fun assert_wallet_capability(shared: String,header: String,constant_name: String): bool acquires Capabilities {
        let db = borrow_global<Capabilities>(OWNER);

        if (!table::contains(&db.table, shared)) {
            return false; // address not found capability can't exist
        };

        let inner_table = table::borrow(&db.table, shared);

        if (!table::contains(inner_table, header)) {
            return false; // header not found  capability can't exist
        };

        let constants_ref: &vector<Capability> = table::borrow(inner_table, header);
        let len = vector::length(constants_ref);

        let i = 0;
        while (i < len) {
            let c_ref = vector::borrow(constants_ref, i);
            if (c_ref.name == constant_name) {
                return true;
            };
            i = i + 1;
        };

        // If not found
        false
    }

}
