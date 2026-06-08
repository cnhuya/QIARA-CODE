module dev::QiaraSharedV5 {
    use std::signer;
    use std::table::{Self, Table};
    use std::vector;
    use std::bcs;
    use std::string::{String, utf8};
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use event::QiaraEventV1::{Self as Event};
    
    use aptos_framework::fungible_asset::{Self, FungibleStore, Metadata};
    use aptos_framework::object::{Self, Object};

    // === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 0;
    const ERROR_SHARED_STORAGE_DOESNT_EXISTS_FOR_THIS_ADDRESS: u64 = 1;
    const ERROR_THIS_SUB_OWNER_IS_NOT_ALLOWED_FOR_THIS_SHARED_STORAGE: u64 = 2;
    const ERROR_IS_ALREADY_SUB_OWNER: u64 = 3;
    const ERROR_SUB_OWNER_DOESNT_EXISTS_IN_ANY_SHARED_STORAGE: u64 = 4;
    const ERROR_SHARED_STORAGE_WITH_THIS_NAME_ALREADY_EXISTS: u64 = 5;
    const ERROR_ADDRESS_DOESNT_MATCH_SIGNER: u64 = 6;
    const ERROR_NOT_OWNER_OF_THIS_SHARED_STORAGE: u64 = 7;
    const ERROR_SHARED_STORAGE_WITH_THIS_NAME_DOESNT_EXISTS: u64 = 8;
    const ERROR_SHARED_STORAGE_DOESNT_EXIST: u64 = 9;
    const ERROR_XP_TAX_CANNOT_BE_ABOVE_100_PERCENT: u64 = 10;
    const ERROR_FEE_TAX_CANNOT_BE_ABOVE_100_PERCENT: u64 = 11;
    const ERROR_REF_CODE_ALREADY_EXISTS: u64 = 12;
    const ERROR_REF_CODE_CANT_BE_EMPTY: u64 = 13;
    const MAX_ALLOWED_TAX: u64 = 100_000_000;

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
    struct Permissions has key {}

    struct RefCodeParams has store, copy, drop {
        xp_tax: u64, // 100_000_000 = 100%
        fee_tax: u64, // 100_000_000 = 100%
    }

    struct Ownership has store, copy, drop {
        owner: vector<u8>,
        storages: map::SimpleMap<String, Object<FungibleStore>>,
        sub_owners: vector<vector<u8>>,
        selected_validator: String,
        ref_code: String,
        ref_code_params: RefCodeParams,
        used_ref_code: String,
        users: vector<String>,
    }

    // STORAGE: owner -> allowed sub-owners
    // STORAGE_REGISTRY: sub_owner -> shared storages names, in which he is allowed as sub-owner
    struct SharedStorage has key {
        storage: Table<String, Ownership>,
        storage_registry: Table<vector<u8>, vector<String>>,
        ref_code_registry: Table<String, RefCodeParams>,
    }

    // ----------------------------------------------------------------
    // Module init
    // ----------------------------------------------------------------
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @dev, 1);

        if (!exists<SharedStorage>(@dev)) {
            move_to(admin, SharedStorage { 
                storage: table::new<String, Ownership>(), 
                storage_registry: table::new<vector<u8>, vector<String>>(),
                ref_code_registry: table::new<String, RefCodeParams>(),
            });
        };
    }


    public entry fun create_non_user_shared_storage(name: String) acquires SharedStorage {
        let shared = borrow_global_mut<SharedStorage>(@dev);
        let non_user_key = bcs::to_bytes(&name);

        if (!table::contains(&shared.storage, name)) {
            table::add(&mut shared.storage, name, Ownership { 
                owner: non_user_key, 
                storages: map::new<String, Object<FungibleStore>>(),
                sub_owners: vector::empty<vector<u8>>(),
                selected_validator: utf8(b""),
                ref_code: utf8(b""), 
                ref_code_params: RefCodeParams { xp_tax: 0, fee_tax: 0 }, 
                used_ref_code: utf8(b""),
                users: vector::empty<String>(),
            });
            table::add(&mut shared.storage_registry, non_user_key, vector::empty<String>());
        } else {
            abort ERROR_SHARED_STORAGE_WITH_THIS_NAME_ALREADY_EXISTS
        };

        let registry = table::borrow_mut(&mut shared.storage_registry, non_user_key);

        if (vector::contains(registry, &name)) {
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


    // NATIVE INTERFACE
    public entry fun create_shared_storage(signer: &signer, name: String, ref_code: String, used_ref_code: String, selected_validator: String, xp_tax: u64, fee_tax: u64) acquires SharedStorage {
        let shared = borrow_global_mut<SharedStorage>(@dev);
        let signer_addr = signer::address_of(signer);
        let signer_addr_bytes = bcs::to_bytes(&signer_addr);

        // 1. Check if this specific storage name is globally unique
        if (table::contains(&shared.storage, name)) {
            abort ERROR_SHARED_STORAGE_WITH_THIS_NAME_ALREADY_EXISTS
        };


        if (ref_code == utf8(b"")) {
            abort ERROR_REF_CODE_CANT_BE_EMPTY
        };
        
        // 2. Initialize sub_owners WITH the creator already inside
        let sub_owners = vector::empty<vector<u8>>();
        vector::push_back(&mut sub_owners, signer_addr_bytes);

        assert!(xp_tax <= MAX_ALLOWED_TAX, ERROR_XP_TAX_CANNOT_BE_ABOVE_100_PERCENT);
        assert!(fee_tax <= MAX_ALLOWED_TAX, ERROR_FEE_TAX_CANNOT_BE_ABOVE_100_PERCENT);
        let ref_code_params = RefCodeParams { xp_tax: xp_tax, fee_tax: fee_tax };

        assert!(!table::contains(&shared.ref_code_registry, ref_code), ERROR_REF_CODE_ALREADY_EXISTS);

        table::add(&mut shared.ref_code_registry, ref_code, ref_code_params);
        
        // 3. Add the storage ownership with all fields populated (storages mapping initialized)
        table::add(&mut shared.storage, name, Ownership { 
            owner: signer_addr_bytes, 
            storages: map::new<String, Object<FungibleStore>>(), 
            sub_owners: sub_owners,
            ref_code: ref_code,
            selected_validator: selected_validator,
            ref_code_params: RefCodeParams { xp_tax: xp_tax, fee_tax: fee_tax },
            used_ref_code: used_ref_code,
            users: vector::empty<String>(),
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

    public entry fun allow_sub_owner(signer: &signer, name: String, sub_owner: vector<u8>) acquires SharedStorage {
        let shared = borrow_global_mut<SharedStorage>(@dev);
        let sender_addr = signer::address_of(signer);

        assert!(table::contains(&shared.storage, name), ERROR_SHARED_STORAGE_WITH_THIS_NAME_DOESNT_EXISTS);

        let ownership_record = table::borrow_mut(&mut shared.storage, name);
        assert!(ownership_record.owner == bcs::to_bytes(&sender_addr), ERROR_NOT_OWNER_OF_THIS_SHARED_STORAGE);

        if (!vector::contains(&ownership_record.sub_owners, &sub_owner)) {
            vector::push_back(&mut ownership_record.sub_owners, sub_owner);
        };

        if (!table::contains(&shared.storage_registry, sub_owner)) {
            table::add(&mut shared.storage_registry, sub_owner, vector::empty<String>());
        };

        let registry = table::borrow_mut(&mut shared.storage_registry, sub_owner);

        if (!vector::contains(registry, &name)) {
            vector::push_back(registry, name);
        };

        let data = vector[
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"none"))),
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&sender_addr)),
            Event::create_data_struct(utf8(b"shared_storage"), utf8(b"string"), bcs::to_bytes(&name)),
            Event::create_data_struct(utf8(b"sub_owner"), utf8(b"vector<u8>"), bcs::to_bytes(&sub_owner)),
        ];
        Event::emit_shared_storage_event(utf8(b"Sub Owner Added"), data);
    }

    public entry fun remove_sub_owner(signer: &signer, name: String, sub_owner: vector<u8>) acquires SharedStorage {
        let shared = borrow_global_mut<SharedStorage>(@dev);
        assert!(table::contains(&shared.storage, name), ERROR_SHARED_STORAGE_WITH_THIS_NAME_DOESNT_EXISTS);

        let ownership_record = table::borrow_mut(&mut shared.storage, name);
        assert!(ownership_record.owner == bcs::to_bytes(&signer::address_of(signer)), ERROR_NOT_OWNER_OF_THIS_SHARED_STORAGE);
        assert!(vector::contains(&ownership_record.sub_owners, &sub_owner), ERROR_THIS_SUB_OWNER_IS_NOT_ALLOWED_FOR_THIS_SHARED_STORAGE);

        vector::remove_value(&mut ownership_record.sub_owners, &sub_owner);
        let registry = table::borrow_mut(&mut shared.storage_registry, sub_owner);
        vector::remove_value(registry, &name);

        let data = vector[
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"none"))),
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&signer::address_of(signer))),
            Event::create_data_struct(utf8(b"shared_storage"), utf8(b"string"), bcs::to_bytes(&name)),
            Event::create_data_struct(utf8(b"sub_owner"), utf8(b"vector<u8>"), bcs::to_bytes(&sub_owner)),
        ];
        Event::emit_shared_storage_event(utf8(b"Sub Owner Removed"), data);
    }

    public entry fun change_used_ref_code(signer: &signer, name: String, _sub_owner: vector<u8>, new_used_ref_code: String) acquires SharedStorage {
        let shared = borrow_global_mut<SharedStorage>(@dev);
        let sender_addr = signer::address_of(signer);

        assert!(table::contains(&shared.storage, name), ERROR_SHARED_STORAGE_WITH_THIS_NAME_DOESNT_EXISTS);

        let ownership_record = table::borrow_mut(&mut shared.storage, name);
        assert!(ownership_record.owner == bcs::to_bytes(&sender_addr), ERROR_NOT_OWNER_OF_THIS_SHARED_STORAGE);

        ownership_record.used_ref_code = new_used_ref_code;

        // Emit Event matching the module's existing standard
        let data = vector[
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"none"))),
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&sender_addr)),
            Event::create_data_struct(utf8(b"shared_storage"), utf8(b"string"), bcs::to_bytes(&name)),
            Event::create_data_struct(utf8(b"used_ref_code"), utf8(b"string"), bcs::to_bytes(&new_used_ref_code)),
        ];
        Event::emit_shared_storage_event(utf8(b"Used Ref Code Updated"), data);
    }

    // PERMISSIONLESS INTERFACE
    public entry fun p_create_shared_storage(validator: &signer, user: vector<u8>, name: String, ref_code: String, used_ref_code: String, selected_validator: String, xp_tax: u64, fee_tax: u64 ) acquires SharedStorage {
        let shared = borrow_global_mut<SharedStorage>(@dev);

        if (table::contains(&shared.storage, name)) {
            abort ERROR_SHARED_STORAGE_WITH_THIS_NAME_ALREADY_EXISTS
        };

        let sub_owners = vector::empty<vector<u8>>();
        vector::push_back(&mut sub_owners, user);

        table::add(&mut shared.storage, name, Ownership { 
            owner: user, 
            storages: map::new<String, Object<FungibleStore>>(),
            sub_owners: sub_owners,
            selected_validator: selected_validator,
            ref_code: ref_code,
            ref_code_params: RefCodeParams { xp_tax: xp_tax, fee_tax: fee_tax },
            used_ref_code: used_ref_code,
            users: vector::empty<String>(),
        });

        if (!table::contains(&shared.storage_registry, user)) {
            table::add(&mut shared.storage_registry, user, vector::empty<String>());
        };

        let registry = table::borrow_mut(&mut shared.storage_registry, user);

        if (vector::contains(registry, &name)) {
            abort ERROR_IS_ALREADY_SUB_OWNER
        } else {
            vector::push_back(registry, name);
        };

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
        assert!(table::contains(&shared.storage, name), ERROR_SHARED_STORAGE_WITH_THIS_NAME_DOESNT_EXISTS);

        let ownership_record = table::borrow_mut(&mut shared.storage, name);
        assert!(ownership_record.owner == user, ERROR_NOT_OWNER_OF_THIS_SHARED_STORAGE);
        
        if (!vector::contains(&ownership_record.sub_owners, &sub_owner)) {
            vector::push_back(&mut ownership_record.sub_owners, sub_owner);
        };

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

    public entry fun p_remove_sub_owner(validator: &signer, user: vector<u8>, name: String, sub_owner: vector<u8>) acquires SharedStorage {
        let shared = borrow_global_mut<SharedStorage>(@dev);
        assert!(table::contains(&shared.storage, name), ERROR_SHARED_STORAGE_WITH_THIS_NAME_DOESNT_EXISTS);

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

    public entry fun p_change_used_ref_code(validator: &signer, user: vector<u8>, name: String, _sub_owner: vector<u8>, new_used_ref_code: String) acquires SharedStorage {
        let shared = borrow_global_mut<SharedStorage>(@dev);
        assert!(table::contains(&shared.storage, name), ERROR_SHARED_STORAGE_WITH_THIS_NAME_DOESNT_EXISTS);

        let ownership_record = table::borrow_mut(&mut shared.storage, name);
        assert!(ownership_record.owner == user, ERROR_NOT_OWNER_OF_THIS_SHARED_STORAGE);

        ownership_record.used_ref_code = new_used_ref_code;

        // Emit Event matching the module's existing standard
        let data = vector[
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"main"))),
            Event::create_data_struct(utf8(b"validator"), utf8(b"vector<u8>"), bcs::to_bytes(&signer::address_of(validator))),
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&user)),
            Event::create_data_struct(utf8(b"shared_storage"), utf8(b"string"), bcs::to_bytes(&name)),
            Event::create_data_struct(utf8(b"used_ref_code"), utf8(b"string"), bcs::to_bytes(&new_used_ref_code)),
        ];
        Event::emit_shared_storage_event(utf8(b"Used Ref Code Updated"), data);
    }


    // === EXTERNAL CONTRACTS PUBLIC INTERFACE === //

    // Public function requiring Permission capability to change the selected validator
    public fun update_selected_validator(name: String, new_validator: String, _perm: Permission) acquires SharedStorage {
        let shared = borrow_global_mut<SharedStorage>(@dev);
        
        if (!table::contains(&shared.storage, name)) {
            abort ERROR_SHARED_STORAGE_WITH_THIS_NAME_DOESNT_EXISTS
        };

        let ownership_record = table::borrow_mut(&mut shared.storage, name);
        ownership_record.selected_validator = new_validator;
    }

    // === NEW HELPER FUNCTIONS === //

    /// Dynamically registers a new standard autonomous FungibleStore for a given asset metadata
    /// inside an existing shared storage record. The store object is owned by itself (keyless).
    public fun ensure_shared_store(name: String, user: vector<u8>, asset_name: String, metadata: Object<Metadata>) acquires SharedStorage {
        let shared = borrow_global_mut<SharedStorage>(@dev);

        assert!(table::contains(&shared.storage, name), ERROR_SHARED_STORAGE_WITH_THIS_NAME_DOESNT_EXISTS);

        let ownership_record = table::borrow_mut(&mut shared.storage, name);
        
        assert!(vector::contains(&ownership_record.sub_owners, &user), ERROR_THIS_SUB_OWNER_IS_NOT_ALLOWED_FOR_THIS_SHARED_STORAGE);

        if (!map::contains_key(&ownership_record.storages, &asset_name)) {
            // 1. Create a secure, non-transferable vault object (initially owned by @dev)
            let constructor_ref = object::create_object(@dev);
            let store_address = object::address_from_constructor_ref(&constructor_ref);
            
            // 2. Create the FungibleStore inside the object
            let store = fungible_asset::create_store(&constructor_ref, metadata);
            
            // 3. Transfer ownership of the store object to its own address so it is autonomous (keyless)
            let transfer_ref = object::generate_transfer_ref(&constructor_ref);
            let linear_transfer_ref = object::generate_linear_transfer_ref(&transfer_ref);
            object::transfer_with_ref(linear_transfer_ref, store_address);

            // 4. Record the store in the storages map
            map::add(&mut ownership_record.storages, asset_name, store);
        };
    }

    // === VIEW FUNCTIONS === //

    /// Returns the unique FungibleStore object associated with an asset in a shared storage
    #[view]
    public fun get_shared_store(name: String, asset_name: String): Object<FungibleStore> acquires SharedStorage {
        let shared = borrow_global<SharedStorage>(@dev);

        assert!(table::contains(&shared.storage, name), ERROR_SHARED_STORAGE_WITH_THIS_NAME_DOESNT_EXISTS);

        let ownership_record = table::borrow(&shared.storage, name);
        assert!(map::contains_key(&ownership_record.storages, &asset_name), ERROR_SHARED_STORAGE_DOESNT_EXIST);

        *map::borrow(&ownership_record.storages, &asset_name)
    }

    #[view]
    public fun return_list_shared_storages(owner: vector<u8>): vector<String> acquires SharedStorage {
        let shared = borrow_global<SharedStorage>(@dev);
        if (!table::contains(&shared.storage_registry, owner)) {
            return vector::empty<String>()
        };
        *table::borrow(&shared.storage_registry, owner)
    }

    #[view]
    public fun return_shared_storages(owner: vector<u8>): Map<String, Ownership> acquires SharedStorage {
        let shared = borrow_global<SharedStorage>(@dev);
        let map = map::new<String, Ownership>();

        if (!table::contains(&shared.storage_registry, owner)) {
            return map
        };

        let list = table::borrow(&shared.storage_registry, owner);
        let len = vector::length(list);
        while (len > 0) {
            let name = *vector::borrow(list, len-1);
            if (table::contains(&shared.storage, name)) {
                let ownership = *table::borrow(&shared.storage, name);
                map::add(&mut map, name, ownership);
            };
            len = len - 1;
        };
        map
    }

    #[view]
    public fun return_shared_ownership(owner: vector<u8>, name: String): Ownership acquires SharedStorage {
        let shared = borrow_global<SharedStorage>(@dev);

        if (!table::contains(&shared.storage, name)) {
            abort ERROR_SHARED_STORAGE_WITH_THIS_NAME_DOESNT_EXISTS
        };

        *table::borrow(&shared.storage, name)
    }

    // useles remove later
    public fun return_shared_raw_ref_params(owner: vector<u8>, name: String): (u64, u64) acquires SharedStorage {
        let shared = borrow_global<SharedStorage>(@dev);

        if (!table::contains(&shared.storage, name)) {
            abort ERROR_SHARED_STORAGE_WITH_THIS_NAME_DOESNT_EXISTS
        };

        let ref_code_params = table::borrow(&shared.storage, name).ref_code_params;
        (ref_code_params.xp_tax, ref_code_params.fee_tax)
    }

    #[view]
    public fun return_shared_ownership_new(name: String): Ownership acquires SharedStorage {
        let shared = borrow_global<SharedStorage>(@dev);

        if (!table::contains(&shared.storage, name)) {
            abort ERROR_SHARED_STORAGE_WITH_THIS_NAME_DOESNT_EXISTS
        };

        *table::borrow(&shared.storage, name)
    }

    #[view]
    public fun return_shared_owner(name: String): vector<u8> acquires SharedStorage {
        let shared = borrow_global<SharedStorage>(@dev);

        if (!table::contains(&shared.storage, name)) {
            abort ERROR_SHARED_STORAGE_WITH_THIS_NAME_DOESNT_EXISTS
        };

        table::borrow(&shared.storage, name).owner
    }

    #[view]
    public fun return_ref_code_params(name: String): RefCodeParams acquires SharedStorage {
        let shared = borrow_global<SharedStorage>(@dev);

        if (!table::contains(&shared.storage, name)) {
            abort ERROR_SHARED_STORAGE_WITH_THIS_NAME_DOESNT_EXISTS
        };

        table::borrow(&shared.storage, name).ref_code_params
    }

    #[view]
    public fun assert_shared_storage(name: String): bool acquires SharedStorage {
        let shared = borrow_global<SharedStorage>(@dev);
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

    public fun extract_raw_params(ownership_record: Ownership): (u64, u64) {
        (ownership_record.ref_code_params.xp_tax, ownership_record.ref_code_params.fee_tax)
    }

    public fun create_empty_raw_params(): RefCodeParams {
        RefCodeParams { xp_tax: 0, fee_tax: 0 }
    }

}