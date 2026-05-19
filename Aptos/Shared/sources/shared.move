module dev::QiaraSharedV1{
    use std::signer;
    use std::table::{Self, Table};
    use std::vector;
    use std::bcs;
    use aptos_std::from_bcs;
    use std::string::{Self as string, String, utf8};
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use event::QiaraEventV1::{Self as Event};
// === ERRORS === //
    const ERROR_NOT_ADMIN:u64 = 0;
    const ERROR_SHARED_STORAGE_DOESNT_EXISTS_FOR_THIS_ADDRESS:u64 = 1;
    const ERROR_THIS_SUB_OWNER_IS_NOT_ALLOWED_FOR_THIS_SHARED_STORAGE:u64 = 2;
    const ERROR_IS_ALREADY_SUB_OWNER: u64 = 3;
    const ERROR_SUB_OWNER_DOESNT_EXISTS_IN_ANY_SHARED_STORAGE: u64 = 4;
    const ERROR_SHARED_STORAGE_WITH_THIS_NAME_ALREADY_EXISTS: u64 = 5;
    const ERROR_ADDRESS_DOESNT_MATCH_SIGNER: u64 = 6;
    const ERROR_NOT_OWNER_OF_THIS_SHARED_STORAGE: u64 = 7;
    const ERROR_SHARED_STORAGE_WITH_THIS_NAME_DOESNT_EXISTS: u64 = 8;
    const ERROR_SHARED_STORAGE_DOESNT_EXIST: u64 = 9;

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

    struct Ownership has key, store, copy, drop{
        owner: vector<u8>,
        sub_owners: vector<vector<u8>>,
    }

    //STORAGE: owner -> allowed sub-owners
    //STORAGE_REGISTRY: sub_owner -> shared storages names, in which he is allowed as sub-owner
    struct SharedStorage has key{
        storage: Table<String, Ownership>,
        storage_registry: Table<vector<u8>, vector<String>>
    }

    // ----------------------------------------------------------------
    // Module init
    // ----------------------------------------------------------------
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @dev, 1);

        if (!exists<SharedStorage>(@dev)) {
            move_to(admin, SharedStorage { storage: table::new<String, Ownership>(), storage_registry: table::new<vector<u8>, vector<String>>() });
        };
    }

// NATIVE INTERFACE
    public entry fun create_shared_storage(signer: &signer, name: String) acquires SharedStorage {
        let shared = borrow_global_mut<SharedStorage>(@dev);
        let signer_addr = signer::address_of(signer);
        let signer_addr_bytes = bcs::to_bytes(&signer_addr);

        // 1. Check if this specific storage name is globally unique
        if (table::contains(&shared.storage, name)) {
            abort ERROR_SHARED_STORAGE_WITH_THIS_NAME_ALREADY_EXISTS
        };

        // 2. Initialize sub_owners WITH the creator already inside
        let sub_owners = vector::empty<vector<u8>>();
        vector::push_back(&mut sub_owners, signer_addr_bytes); //  Add creator here

        // 3. Add the storage ownership
        table::add(&mut shared.storage, name, Ownership { 
            owner: signer_addr_bytes, 
            sub_owners: sub_owners //  Now contains the creator
        });

        // 4. Ensure the user has a spot in the registry table
        if (!table::contains(&shared.storage_registry, signer_addr_bytes)) {
            table::add(&mut shared.storage_registry, signer_addr_bytes, vector::empty<String>());
        };

        // 5. Update the user list of owned storages
        let registry = table::borrow_mut(&mut shared.storage_registry, signer_addr_bytes);

        if (vector::contains(registry, &name)) {
            abort ERROR_IS_ALREADY_SUB_OWNER
        } else {
            vector::push_back(registry, name);
        };

        // 6. Emit Event
        let data = vector[
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"none"))),
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&signer_addr)),
            Event::create_data_struct(utf8(b"shared_storage"), utf8(b"string"), bcs::to_bytes(&name)),
        ];
        Event::emit_shared_storage_event(utf8(b"Storage Created"), data);
    }

    public entry fun create_non_user_shared_storage(name: String) acquires SharedStorage {
        let shared = borrow_global_mut<SharedStorage>(@dev);

        if (!table::contains(&shared.storage, name)) {
            table::add(&mut shared.storage, name, Ownership { owner: bcs::to_bytes(&name), sub_owners: vector::empty<vector<u8>>() });
            table::add(&mut shared.storage_registry, bcs::to_bytes(&name), vector::empty<String>());
        } else {
            abort ERROR_SHARED_STORAGE_WITH_THIS_NAME_ALREADY_EXISTS
        };

        let registry = table::borrow_mut(&mut shared.storage_registry, bcs::to_bytes(&name));

        if(vector::contains(registry, &name)) {
            abort ERROR_IS_ALREADY_SUB_OWNER
        } else {
            vector::push_back(registry, name);
        };

        let data = vector[
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"none"))),
            Event::create_data_struct(utf8(b"shared_storage"), utf8(b"string"), bcs::to_bytes(&name)),
        ];
        Event::emit_shared_storage_event(utf8(b"Storage Created"), data);

    }

    public entry fun allow_sub_owner(signer: &signer, name: String, sub_owner: vector<u8>) acquires SharedStorage {
        let shared = borrow_global_mut<SharedStorage>(@dev);

        if (!table::contains(&shared.storage, name)) {
            table::add(&mut shared.storage, name, Ownership { owner: bcs::to_bytes(&signer::address_of(signer)), sub_owners: vector::empty<vector<u8>>() });
        };

        let ownership_record = table::borrow_mut(&mut shared.storage, name);
        assert!(ownership_record.owner == bcs::to_bytes(&signer::address_of(signer)), ERROR_NOT_OWNER_OF_THIS_SHARED_STORAGE);
        vector::push_back(&mut ownership_record.sub_owners, sub_owner);

        if (!table::contains(&shared.storage_registry, sub_owner)) {
            table::add(&mut shared.storage_registry, sub_owner, vector::empty<String>());
        };

        let registry = table::borrow_mut(&mut shared.storage_registry, bcs::to_bytes(&sub_owner));

        if (!vector::contains(registry, &name)) {
            vector::push_back(registry, name);
        };

        let data = vector[
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"none"))),
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&signer::address_of(signer))),
            Event::create_data_struct(utf8(b"shared_storage"), utf8(b"string"), bcs::to_bytes(&name)),
            Event::create_data_struct(utf8(b"sub_owner"), utf8(b"vector<u8>"), bcs::to_bytes(&sub_owner)),
        ];
        Event::emit_shared_storage_event(utf8(b"Sub Owner Added"), data);
    }

    public entry fun remove_sub_owner(signer: &signer, name: String, sub_owner: vector<u8>) acquires SharedStorage{
        let shared = borrow_global_mut<SharedStorage>(@dev);

        let ownership_record = table::borrow_mut(&mut shared.storage, name);
        assert!(ownership_record.owner == bcs::to_bytes(&signer::address_of(signer)), ERROR_NOT_OWNER_OF_THIS_SHARED_STORAGE);
        assert!(vector::contains(&ownership_record.sub_owners, &sub_owner), ERROR_THIS_SUB_OWNER_IS_NOT_ALLOWED_FOR_THIS_SHARED_STORAGE);

        vector::remove_value(&mut ownership_record.sub_owners, &sub_owner);
        let registry = table::borrow_mut(&mut shared.storage_registry,sub_owner);
        vector::remove_value(registry, &name);

        let data = vector[
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"none"))),
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&signer::address_of(signer))),
            Event::create_data_struct(utf8(b"shared_storage"), utf8(b"string"), bcs::to_bytes(&name)),
            Event::create_data_struct(utf8(b"sub_owner"), utf8(b"vector<u8>"), bcs::to_bytes(&sub_owner)),
        ];
        Event::emit_shared_storage_event(utf8(b"Sub Owner Removed"), data);
    }

// PERMISSIONELESS INTERFACE
    public entry fun p_create_shared_storage(validator: &signer, user: vector<u8>, name: String) acquires SharedStorage {
        let shared = borrow_global_mut<SharedStorage>(@dev);

        // 1. Check if this specific storage name is globally unique
        if (table::contains(&shared.storage, name)) {
            abort ERROR_SHARED_STORAGE_WITH_THIS_NAME_ALREADY_EXISTS
        };

        // 2. Initialize sub_owners WITH the creator already inside
        let sub_owners = vector::empty<vector<u8>>();
        vector::push_back(&mut sub_owners, user); //  Add creator here

        // 3. Add the storage ownership
        table::add(&mut shared.storage, name, Ownership { 
            owner: user, 
            sub_owners: sub_owners //  Now contains the creator
        });

        // 4. Ensure the user has a spot in the registry table
        if (!table::contains(&shared.storage_registry, user)) {
            table::add(&mut shared.storage_registry, user, vector::empty<String>());
        };

        // 5. Update the user list of owned storages
        let registry = table::borrow_mut(&mut shared.storage_registry, user);

        if (vector::contains(registry, &name)) {
            abort ERROR_IS_ALREADY_SUB_OWNER
        } else {
            vector::push_back(registry, name);
        };

        // 6. Emit Event
        let data = vector[
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"main"))),
            Event::create_data_struct(utf8(b"validator"), utf8(b"vector<u8>"), bcs::to_bytes(&signer::address_of(validator))),
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&user)),
            Event::create_data_struct(utf8(b"shared_storage"), utf8(b"string"), bcs::to_bytes(&name)),
        ];
        Event::emit_shared_storage_event(utf8(b"Storage Created"), data);
    }

    public entry fun p_allow_sub_owner(validator: &signer, user: vector<u8>, name: String, sub_owner: vector<u8>) acquires SharedStorage {
        let shared = borrow_global_mut<SharedStorage>(@dev);

        if (!table::contains(&shared.storage, name)) {
            table::add(&mut shared.storage, name, Ownership { owner: user, sub_owners: vector::empty<vector<u8>>() });
        };

        let ownership_record = table::borrow_mut(&mut shared.storage, name);
        assert!(ownership_record.owner == user, ERROR_NOT_OWNER_OF_THIS_SHARED_STORAGE);
        vector::push_back(&mut ownership_record.sub_owners, sub_owner);

        if (!table::contains(&shared.storage_registry, sub_owner)) {
            table::add(&mut shared.storage_registry, sub_owner, vector::empty<String>());
        };

        let registry = table::borrow_mut(&mut shared.storage_registry, sub_owner);

        if (!vector::contains(registry, &name)) {
            vector::push_back(registry, name);
        };

        let data = vector[
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"main"))),
            Event::create_data_struct(utf8(b"validator"), utf8(b"vector<u8>"), bcs::to_bytes(&signer::address_of(validator))),
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&user)),
            Event::create_data_struct(utf8(b"shared_storage"), utf8(b"string"), bcs::to_bytes(&name)),
            Event::create_data_struct(utf8(b"sub_owner"), utf8(b"vector<u8>"), bcs::to_bytes(&sub_owner)),
        ];
        Event::emit_shared_storage_event(utf8(b"Sub Owner Added"), data);
    }

    public entry fun p_remove_sub_owner(validator: &signer, user: vector<u8>, name: String, sub_owner: vector<u8>) acquires SharedStorage{
        let shared = borrow_global_mut<SharedStorage>(@dev);

        let ownership_record = table::borrow_mut(&mut shared.storage, name);
        assert!(ownership_record.owner == user, ERROR_NOT_OWNER_OF_THIS_SHARED_STORAGE);
        assert!(vector::contains(&ownership_record.sub_owners, &sub_owner), ERROR_THIS_SUB_OWNER_IS_NOT_ALLOWED_FOR_THIS_SHARED_STORAGE);

        vector::remove_value(&mut ownership_record.sub_owners, &sub_owner);
        let registry = table::borrow_mut(&mut shared.storage_registry, sub_owner);
        vector::remove_value(registry, &name);

        let data = vector[
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"main"))),
            Event::create_data_struct(utf8(b"validator"), utf8(b"vector<u8>"), bcs::to_bytes(&signer::address_of(validator))),
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&user)),
            Event::create_data_struct(utf8(b"shared_storage"), utf8(b"string"), bcs::to_bytes(&name)),
            Event::create_data_struct(utf8(b"sub_owner"), utf8(b"vector<u8>"), bcs::to_bytes(&sub_owner)),
        ];
        Event::emit_shared_storage_event(utf8(b"Sub Owner Removed"), data);
    }

    #[view]
    public fun return_list_shared_storages(owner: vector<u8>): vector<String> acquires SharedStorage{
        let shared = borrow_global_mut<SharedStorage>(@dev);
        *table::borrow_mut(&mut shared.storage_registry, bcs::to_bytes(&owner))
    }

    #[view]
    public fun return_shared_storages(owner: vector<u8>): Map<String, Ownership> acquires SharedStorage{
        let shared = borrow_global_mut<SharedStorage>(@dev);

        let map = map::new<String, Ownership>();

        if(!table::contains(&shared.storage_registry, owner)){
            return map
        };

        let list = table::borrow_mut(&mut shared.storage_registry, owner);
        let len = vector::length(list);
        while(len>0){
            let name = *vector::borrow(list, len-1);
            if(table::contains(&shared.storage, name)) {
                let ownership = *table::borrow_mut(&mut shared.storage, name);
                map::add(&mut map, name, ownership);
            };
            len=len-1;
        };
        map
    }


    #[view]
    public fun return_shared_ownership(owner: vector<u8>, name: String): Ownership acquires SharedStorage{
        let shared = borrow_global_mut<SharedStorage>(@dev);

        if (!table::contains(&shared.storage, name)) {
            abort ERROR_SHARED_STORAGE_WITH_THIS_NAME_DOESNT_EXISTS
        };

        *table::borrow_mut(&mut shared.storage, name)
    }

    #[view]
    public fun return_shared_ownership_new(name: String): Ownership acquires SharedStorage{
        let shared = borrow_global_mut<SharedStorage>(@dev);

        if (!table::contains(&shared.storage, name)) {
            abort ERROR_SHARED_STORAGE_WITH_THIS_NAME_DOESNT_EXISTS
        };

        *table::borrow_mut(&mut shared.storage, name)
    }

    #[view]
    public fun assert_shared_storage(name: String): bool acquires SharedStorage{
        let shared = borrow_global_mut<SharedStorage>(@dev);
        return table::contains(&shared.storage, name)
    }

    public fun assert_is_sub_owner(name: String, sub_owner: vector<u8>) acquires SharedStorage {
        let shared = borrow_global<SharedStorage>(@dev);

        if (!table::contains(&shared.storage, name)) {
            abort ERROR_SHARED_STORAGE_WITH_THIS_NAME_DOESNT_EXISTS
        };

        let ownership_record = table::borrow(&shared.storage, name);

        if (!vector::contains(&ownership_record.sub_owners, &sub_owner)) {
            abort ERROR_THIS_SUB_OWNER_IS_NOT_ALLOWED_FOR_THIS_SHARED_STORAGE
        };
    }

    public fun safe_assert_is_sub_owner(name: String, sub_owner: vector<u8>): bool acquires SharedStorage {
        let shared = borrow_global<SharedStorage>(@dev);

        if (!table::contains(&shared.storage, name)) {
            return false
        };

        let ownership_record = table::borrow(&shared.storage, name);

        if (!vector::contains(&ownership_record.sub_owners, &sub_owner)) {
            return false
        };
        return true
    }

    public fun assert_is_owner(owner: vector<u8>, name: String) acquires SharedStorage {
        let shared = borrow_global<SharedStorage>(@dev);

        if (!table::contains(&shared.storage, name)) {
            abort ERROR_SHARED_STORAGE_WITH_THIS_NAME_DOESNT_EXISTS
        };

        let ownership_record = table::borrow(&shared.storage, name);

        assert!(ownership_record.owner == owner, ERROR_NOT_OWNER_OF_THIS_SHARED_STORAGE);
    }

}