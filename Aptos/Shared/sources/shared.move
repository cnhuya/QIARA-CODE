module dev::QiaraSharedV17 {
    use std::signer;
    use std::table::{Self, Table};
    use std::vector;
    use std::bcs;
    use std::string::{String, utf8};
    use std::timestamp;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use event::QiaraEventV1::{Self as Event};
    
    // === NEW IMPORTS FOR FUNGIBLE ASSETS === //
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::fungible_asset::{Self, FungibleStore, TransferRef, Metadata};
    use aptos_framework::object::{Self, Object, ExtendRef, ConstructorRef};
    use aptos_framework::primary_fungible_store;

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
    const ERROR_REF_CODE_DOESNT_EXISTS: u64 = 14;
    const ERROR_NEW_USED_REF_CODE_IS_SAME_AS_CURRENT_USED_REF_CODE: u64 = 15;
    const ERROR_ALREADY_USING_SOME_REF_CODE: u64 = 16;
    const MAX_ALLOWED_TAX: u64 = 100_000_000;
    
    // === NEW ERRORS === //
    const ERROR_FUNGIBLE_STORE_ALREADY_EXISTS: u64 = 14;
    const ERROR_FUNGIBLE_STORE_DOESNT_EXISTS: u64 = 15;

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

    struct SharedMetadata has store, drop {
        extend_ref: ExtendRef,
    }

    struct RefCodeParams has store, copy, drop {
        xp_tax: u64, // 100_000_000 = 100%
        fee_tax: u64, // 100_000_000 = 100%
    }

    struct Ownership has store, drop {
        owner: vector<u8>,
        sub_owners: vector<vector<u8>>,
        selected_validator: String,
        ref_code: String,
        ref_code_params: RefCodeParams,
        used_ref_code: String,
        amount_of_users_using_ref_code: u64,
        users: vector<String>,
        gas_index: u256,
        last_updated: u64,
        metadata: SharedMetadata, // Contains ExtendRef, so Ownership cannot have copy
    }

    struct OwnershipView has copy, drop, store {
        owner: vector<u8>,
        sub_owners: vector<vector<u8>>,
        selected_validator: String,
        ref_code: String,
        ref_code_params: RefCodeParams,
        used_ref_code: String,
        amount_of_users_using_ref_code: u64,
        users: vector<String>,
        gas_index: u256,
        last_updated: u64,
    }

    struct SharedStorage has key {
        storage: Table<String, Ownership>,
        storage_registry: Table<vector<u8>, vector<String>>,
        ref_code_registry: Table<String, RefCodeParams>,
        ref_code_to_shared: Table<String, String>, 
        fungible_stores: Table<String, Table<Object<Metadata>, Object<FungibleStore>>>,
    }

    // ----------------------------------------------------------------
    // Module init
    // ----------------------------------------------------------------
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_ADMIN);

        if (!exists<SharedStorage>(@dev)) {
            move_to(admin, SharedStorage { 
                storage: table::new<String, Ownership>(), 
                storage_registry: table::new<vector<u8>, vector<String>>(),
                ref_code_registry: table::new<String, RefCodeParams>(),
                ref_code_to_shared: table::new<String, String>(), 
                fungible_stores: table::new<String, Table<Object<Metadata>, Object<FungibleStore>>>(),
            });
        };
    }

    // ----------------------------------------------------------------
    // EXISTING SHARED STORAGE LOGIC
    // ----------------------------------------------------------------

    public entry fun create_non_user_shared_storage(signer: &signer, name: String) acquires SharedStorage {
        let shared = borrow_global_mut<SharedStorage>(@dev);
        let non_user_key = bcs::to_bytes(&name);

        if (!table::contains(&shared.storage, name)) {
            let name_bytes = *std::string::bytes(&name);

            let constructor_ref = object::create_named_object(signer, name_bytes);
            let extend_ref = object::generate_extend_ref(&constructor_ref);
            let metadata = SharedMetadata {
                extend_ref: extend_ref,
            };

            table::add(&mut shared.storage, name, Ownership { 
                owner: non_user_key, 
                sub_owners: vector::empty<vector<u8>>(),
                selected_validator: utf8(b""),
                ref_code: utf8(b""), 
                ref_code_params: RefCodeParams { xp_tax: 0, fee_tax: 0, }, 
                used_ref_code: utf8(b""),
                users: vector::empty<String>(),
                gas_index: 0,
                amount_of_users_using_ref_code: 0,
                last_updated: 0,
                metadata: metadata 
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

    public entry fun create_shared_storage(signer: &signer, name: String, ref_code: String, used_ref_code: String, selected_validator: String, xp_tax: u64, fee_tax: u64) acquires SharedStorage {
        let shared = borrow_global_mut<SharedStorage>(@dev);
        let sender_addr = signer::address_of(signer);
        let signer_addr_bytes = bcs::to_bytes(&sender_addr);

        if (table::contains(&shared.storage, name)) {
            abort ERROR_SHARED_STORAGE_WITH_THIS_NAME_ALREADY_EXISTS
        };

        if (ref_code == utf8(b"")) {
            abort ERROR_REF_CODE_CANT_BE_EMPTY
        };
        
        let sub_owners = vector::empty<vector<u8>>();
        vector::push_back(&mut sub_owners, signer_addr_bytes);

        assert!(xp_tax <= MAX_ALLOWED_TAX, ERROR_XP_TAX_CANNOT_BE_ABOVE_100_PERCENT);
        assert!(fee_tax <= MAX_ALLOWED_TAX, ERROR_FEE_TAX_CANNOT_BE_ABOVE_100_PERCENT);
        let ref_code_params = RefCodeParams { xp_tax: xp_tax, fee_tax: fee_tax, };

        assert!(!table::contains(&shared.ref_code_registry, ref_code), ERROR_REF_CODE_ALREADY_EXISTS);

        if (used_ref_code != utf8(b"")) {
            assert!(table::contains(&shared.ref_code_registry, used_ref_code), ERROR_REF_CODE_DOESNT_EXISTS);
            
            let referrer_shared_name = *table::borrow(&shared.ref_code_to_shared, used_ref_code);
            let used_ref_code_ownership_record = table::borrow_mut(&mut shared.storage, referrer_shared_name);
            used_ref_code_ownership_record.amount_of_users_using_ref_code = used_ref_code_ownership_record.amount_of_users_using_ref_code + 1;
        
            let data = vector[
                Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&referrer_shared_name)),
                Event::create_data_struct(utf8(b"ref_code_users"), utf8(b"u64"), bcs::to_bytes(&used_ref_code_ownership_record.amount_of_users_using_ref_code)),
            ];
            Event::emit_qiara_shared_stats(data);
        };

        table::add(&mut shared.ref_code_registry, copy ref_code, copy ref_code_params);
        table::add(&mut shared.ref_code_to_shared, copy ref_code, copy name); 
        
        let name_bytes = *std::string::bytes(&name);

        let constructor_ref = object::create_named_object(signer, name_bytes);
        let extend_ref = object::generate_extend_ref(&constructor_ref);
        let metadata = SharedMetadata {
            extend_ref: extend_ref,
        };

        table::add(&mut shared.storage, copy name, Ownership { 
            owner: signer_addr_bytes,  
            sub_owners: sub_owners,
            ref_code: ref_code,
            selected_validator: selected_validator,
            ref_code_params: ref_code_params,
            used_ref_code: used_ref_code,
            users: vector::empty<String>(),
            gas_index: 0,
            amount_of_users_using_ref_code: 0,
            last_updated: timestamp::now_seconds(),
            metadata: metadata, 
        });

        if (!table::contains(&shared.storage_registry, signer_addr_bytes)) {
            table::add(&mut shared.storage_registry, signer_addr_bytes, vector::empty<String>());
        };

        let registry = table::borrow_mut(&mut shared.storage_registry, signer_addr_bytes);

        if (vector::contains(registry, &name)) {
            abort ERROR_IS_ALREADY_SUB_OWNER
        } else {
            vector::push_back(registry, name);
        };

        let data = vector[
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&sender_addr)),
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

        if (new_used_ref_code != utf8(b"")) {
            abort ERROR_ALREADY_USING_SOME_REF_CODE
        };

        if (ownership_record.used_ref_code == new_used_ref_code) {
            abort ERROR_NEW_USED_REF_CODE_IS_SAME_AS_CURRENT_USED_REF_CODE
        };

        ownership_record.used_ref_code = new_used_ref_code;

        let data = vector[
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"none"))),
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&sender_addr)),
            Event::create_data_struct(utf8(b"shared_storage"), utf8(b"string"), bcs::to_bytes(&name)),
            Event::create_data_struct(utf8(b"used_ref_code"), utf8(b"string"), bcs::to_bytes(&new_used_ref_code)),
        ];
        Event::emit_shared_storage_event(utf8(b"Used Ref Code Updated"), data);
    }

    // ----------------------------------------------------------------
    // PERMISSIONLESS INTERFACE
    // ----------------------------------------------------------------

    public fun p_create_shared_storage(
        validator: &signer, 
        user: vector<u8>, 
        name: String, 
        ref_code: String, 
        used_ref_code: String, 
        selected_validator: String, 
        xp_tax: u64, 
        fee_tax: u64, 
        perm: Permission
    ) acquires SharedStorage {
        let shared = borrow_global_mut<SharedStorage>(@dev);

        if (table::contains(&shared.storage, name)) {
            abort ERROR_SHARED_STORAGE_WITH_THIS_NAME_ALREADY_EXISTS
        };

        let sub_owners = vector::empty<vector<u8>>();
        vector::push_back(&mut sub_owners, user);

        assert!(xp_tax <= MAX_ALLOWED_TAX, ERROR_XP_TAX_CANNOT_BE_ABOVE_100_PERCENT);
        assert!(fee_tax <= MAX_ALLOWED_TAX, ERROR_FEE_TAX_CANNOT_BE_ABOVE_100_PERCENT);
        let ref_code_params = RefCodeParams { xp_tax: xp_tax, fee_tax: fee_tax };

        assert!(!table::contains(&shared.ref_code_registry, ref_code), ERROR_REF_CODE_ALREADY_EXISTS);
        
        if (used_ref_code != utf8(b"")) {
            assert!(table::contains(&shared.ref_code_registry, used_ref_code), ERROR_REF_CODE_DOESNT_EXISTS);
            
            let referrer_shared_name = *table::borrow(&shared.ref_code_to_shared, used_ref_code);
            let used_ref_code_ownership_record = table::borrow_mut(&mut shared.storage, referrer_shared_name);
            used_ref_code_ownership_record.amount_of_users_using_ref_code = used_ref_code_ownership_record.amount_of_users_using_ref_code + 1;
     
            let data = vector[
                Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&referrer_shared_name)),
                Event::create_data_struct(utf8(b"ref_code_users"), utf8(b"u64"), bcs::to_bytes(&used_ref_code_ownership_record.amount_of_users_using_ref_code)),
            ];
            Event::emit_qiara_shared_stats(data);
        };

        table::add(&mut shared.ref_code_registry, copy ref_code, copy ref_code_params);
        table::add(&mut shared.ref_code_to_shared, copy ref_code, copy name); 

        let name_bytes = *std::string::bytes(&name);

        let constructor_ref = object::create_named_object(validator, name_bytes);
        let extend_ref = object::generate_extend_ref(&constructor_ref);
        let metadata = SharedMetadata {
            extend_ref: extend_ref,
        };

        table::add(&mut shared.storage, copy name, Ownership { 
            owner: user, 
            sub_owners: sub_owners,
            selected_validator: selected_validator,
            ref_code: ref_code,
            ref_code_params: ref_code_params,
            used_ref_code: used_ref_code,
            users: vector::empty<String>(),
            gas_index: 0,
            amount_of_users_using_ref_code: 0,
            last_updated: timestamp::now_seconds(),
            metadata: metadata, 
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

    public fun p_allow_sub_owner(validator: &signer, user: vector<u8>, name: String, sub_owner: vector<u8>, perm: Permission) acquires SharedStorage {
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

    public fun p_remove_sub_owner(validator: &signer, user: vector<u8>, name: String, sub_owner: vector<u8>, perm: Permission) acquires SharedStorage {
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

    public fun p_change_used_ref_code(validator: &signer, user: vector<u8>, name: String, _sub_owner: vector<u8>, new_used_ref_code: String, perm: Permission) acquires SharedStorage {
        let shared = borrow_global_mut<SharedStorage>(@dev);
        assert!(table::contains(&shared.storage, name), ERROR_SHARED_STORAGE_WITH_THIS_NAME_DOESNT_EXISTS);

        let ownership_record = table::borrow_mut(&mut shared.storage, name);
        assert!(ownership_record.owner == user, ERROR_NOT_OWNER_OF_THIS_SHARED_STORAGE);

        if (new_used_ref_code != utf8(b"")) {
            abort ERROR_ALREADY_USING_SOME_REF_CODE
        };

        if (ownership_record.used_ref_code == new_used_ref_code) {
            abort ERROR_NEW_USED_REF_CODE_IS_SAME_AS_CURRENT_USED_REF_CODE
        };

        ownership_record.used_ref_code = new_used_ref_code;

        let data = vector[
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"main"))),
            Event::create_data_struct(utf8(b"validator"), utf8(b"vector<u8>"), bcs::to_bytes(&signer::address_of(validator))),
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&user)),
            Event::create_data_struct(utf8(b"shared_storage"), utf8(b"string"), bcs::to_bytes(&name)),
            Event::create_data_struct(utf8(b"used_ref_code"), utf8(b"string"), bcs::to_bytes(&new_used_ref_code)),
        ];
        Event::emit_shared_storage_event(utf8(b"Used Ref Code Updated"), data);
    }

    // ----------------------------------------------------------------
    // === EXTERNAL CONTRACTS PUBLIC INTERFACE === //
    // ----------------------------------------------------------------

    public fun update_selected_validator(name: String, new_validator: String, _perm: Permission) acquires SharedStorage {
        let shared = borrow_global_mut<SharedStorage>(@dev);
        
        if (!table::contains(&shared.storage, name)) {
            abort ERROR_SHARED_STORAGE_WITH_THIS_NAME_DOESNT_EXISTS
        };

        let ownership_record = table::borrow_mut(&mut shared.storage, name);
        ownership_record.selected_validator = new_validator;
    }

    public fun update_gas_index(name: String, new_gas_index: u256, _perm: Permission) acquires SharedStorage {
        let shared = borrow_global_mut<SharedStorage>(@dev);
        
        if (!table::contains(&shared.storage, name)) {
            abort ERROR_SHARED_STORAGE_WITH_THIS_NAME_DOESNT_EXISTS
        };

        let ownership_record = table::borrow_mut(&mut shared.storage, name);
        ownership_record.gas_index = new_gas_index;
        ownership_record.last_updated = timestamp::now_seconds();
    }

    public fun ensure_shared_fungible_storage(
        shared_name: String, 
        asset_metadata: Object<Metadata>, 
        _perm: Permission
    ): Object<FungibleStore> acquires SharedStorage {
        let shared = borrow_global_mut<SharedStorage>(@dev);
        assert!(table::contains(&shared.storage, shared_name), ERROR_SHARED_STORAGE_WITH_THIS_NAME_DOESNT_EXISTS);
        
        if (!table::contains(&shared.fungible_stores, shared_name)) {
            table::add(&mut shared.fungible_stores, shared_name, table::new<Object<Metadata>, Object<FungibleStore>>());
        };
        
        let token_map = table::borrow_mut(&mut shared.fungible_stores, shared_name);
        if (!table::contains(token_map, asset_metadata)) {
            let ownership_record = table::borrow(&shared.storage, shared_name);
            let derived_address = object::address_from_extend_ref(&ownership_record.metadata.extend_ref);
            let vault_store = primary_fungible_store::ensure_primary_store_exists(derived_address, asset_metadata);
            table::add(token_map, asset_metadata, vault_store);
        };

        *table::borrow(token_map, asset_metadata)
    }

    public fun temp_allow_sub_owner(validator: &signer, name: String, sub_owner: vector<u8>, perm: Permission) acquires SharedStorage {
        let shared = borrow_global_mut<SharedStorage>(@dev);
        assert!(table::contains(&shared.storage, name), ERROR_SHARED_STORAGE_WITH_THIS_NAME_DOESNT_EXISTS);

        let ownership_record = table::borrow_mut(&mut shared.storage, name);
        
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
    }

    public fun temp_remove_sub_owner(validator: &signer, name: String, sub_owner: vector<u8>, perm: Permission) acquires SharedStorage {
        let shared = borrow_global_mut<SharedStorage>(@dev);
        assert!(table::contains(&shared.storage, name), ERROR_SHARED_STORAGE_WITH_THIS_NAME_DOESNT_EXISTS);

        let ownership_record = table::borrow_mut(&mut shared.storage, name);
        assert!(vector::contains(&ownership_record.sub_owners, &sub_owner), ERROR_THIS_SUB_OWNER_IS_NOT_ALLOWED_FOR_THIS_SHARED_STORAGE);

        vector::remove_value(&mut ownership_record.sub_owners, &sub_owner);
        let registry = table::borrow_mut(&mut shared.storage_registry, sub_owner);
        vector::remove_value(registry, &name);
    }

    // ----------------------------------------------------------------
    // === VIEW FUNCTIONS === //
    // ----------------------------------------------------------------

    #[view]
    public fun return_list_shared_storages(owner: vector<u8>): vector<String> acquires SharedStorage {
        let shared = borrow_global<SharedStorage>(@dev);
        if (!table::contains(&shared.storage_registry, owner)) {
            return vector::empty<String>()
        };
        *table::borrow(&shared.storage_registry, owner)
    }

    #[view]
    public fun return_shared_storages(owner: vector<u8>): Map<String, OwnershipView> acquires SharedStorage {
        let shared = borrow_global<SharedStorage>(@dev);
        let map = map::new<String, OwnershipView>();

        if (!table::contains(&shared.storage_registry, owner)) {
            return map
        };

        let list = table::borrow(&shared.storage_registry, owner);
        let len = vector::length(list);
        while (len > 0) {
            let name = *vector::borrow(list, len-1);
            if (table::contains(&shared.storage, name)) {
                let ownership = table::borrow(&shared.storage, name);
                let view = make_ownership_view(ownership);
                map::add(&mut map, name, view);
            };
            len = len - 1;
        };
        map
    }

   #[view]
    public fun return_shared_ownership(owner: vector<u8>, name: String): OwnershipView acquires SharedStorage {
        let shared = borrow_global<SharedStorage>(@dev);

        if (!table::contains(&shared.storage, name)) {
            abort ERROR_SHARED_STORAGE_WITH_THIS_NAME_DOESNT_EXISTS
        };

        let ownership = table::borrow(&shared.storage, name);
        make_ownership_view(ownership)
    }     

    public fun return_shared_raw_ref_params(owner: vector<u8>, name: String): (u64, u64) acquires SharedStorage {
        let shared = borrow_global<SharedStorage>(@dev);

        if (!table::contains(&shared.storage, name)) {
            abort ERROR_SHARED_STORAGE_WITH_THIS_NAME_DOESNT_EXISTS
        };

        let ref_code_params = table::borrow(&shared.storage, name).ref_code_params;
        (ref_code_params.xp_tax, ref_code_params.fee_tax)
    }

    #[view]
    public fun return_shared_ownership_new(name: String): OwnershipView acquires SharedStorage {
        let shared = borrow_global<SharedStorage>(@dev);

        if (!table::contains(&shared.storage, name)) {
            abort ERROR_SHARED_STORAGE_WITH_THIS_NAME_DOESNT_EXISTS
        };

        let ownership = table::borrow(&shared.storage, name);
        make_ownership_view(ownership)
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
    public fun return_shared_name_by_ref_code(ref_code: String): String acquires SharedStorage {
        let shared = borrow_global<SharedStorage>(@dev);
        if (table::contains(&shared.ref_code_to_shared, ref_code)) {
            *table::borrow(&shared.ref_code_to_shared, ref_code)
        } else {
            utf8(b"")
        }
    }

    #[view]
    public fun assert_shared_storage(name: String): bool acquires SharedStorage {
        let shared = borrow_global<SharedStorage>(@dev);
        return table::contains(&shared.storage, name)
    }

    #[view]
    public fun return_fungible_store(shared_name: String, asset_metadata: Object<Metadata>): Object<FungibleStore> acquires SharedStorage {
        let shared = borrow_global<SharedStorage>(@dev);
        
        assert!(table::contains(&shared.fungible_stores, shared_name), ERROR_SHARED_STORAGE_WITH_THIS_NAME_DOESNT_EXISTS);
        let token_map = table::borrow(&shared.fungible_stores, shared_name);
        assert!(table::contains(token_map, asset_metadata), ERROR_SHARED_STORAGE_DOESNT_EXIST);
        
        *table::borrow(token_map, asset_metadata)
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

    // 🟢 UPDATED: Change functions to accept OwnershipView to fix compilation error [1]
    public fun extract_raw_params(ownership_record: OwnershipView): (u64, u64) acquires SharedStorage {
        if (ownership_record.used_ref_code == utf8(b"")) {
            return (0, 0)
        };

        let params = return_ref_code_params(ownership_record.used_ref_code);
        (params.xp_tax, params.fee_tax)
    }

    // 🟢 UPDATED: Change functions to accept OwnershipView to fix compilation error [1]
    public fun extract_used_ref_code(ownership_record: OwnershipView): String {
        if (ownership_record.used_ref_code == utf8(b"")) {
            return utf8(b"")
        };

        ownership_record.used_ref_code
    }

    // 🟢 UPDATED: Change functions to accept OwnershipView to fix compilation error [1]
    public fun extract_used_ref_code_params(ownership_record: OwnershipView): RefCodeParams acquires SharedStorage {
        let used_ref_code_params = create_empty_raw_params();
        if (ownership_record.used_ref_code != utf8(b"")) {
            used_ref_code_params = return_ref_code_params(ownership_record.used_ref_code);
        };
        return used_ref_code_params
    }

    // 🟢 UPDATED: Change functions to accept OwnershipView to fix compilation error [1]
    public fun extract_raw_gas_relations(ownership_record: OwnershipView): (u256, u64) {
        (ownership_record.gas_index, ownership_record.last_updated)
    }

    public fun create_empty_raw_params(): RefCodeParams {
        RefCodeParams { xp_tax: 0, fee_tax: 0,}
    }

    public fun get_shared_signer(shared_name: String,_cap: &Permission): signer acquires SharedStorage {
        let shared = borrow_global<SharedStorage>(@dev);
        let ownership_record = table::borrow(&shared.storage, shared_name);
        object::generate_signer_for_extending(&ownership_record.metadata.extend_ref)
    }

    /// Helper to convert a stored Ownership record into a copyable view
    fun make_ownership_view(record: &Ownership): OwnershipView {
        OwnershipView {
            owner: record.owner,
            sub_owners: record.sub_owners,
            selected_validator: record.selected_validator,
            ref_code: record.ref_code,
            ref_code_params: record.ref_code_params,
            used_ref_code: record.used_ref_code,
            amount_of_users_using_ref_code: record.amount_of_users_using_ref_code,
            users: record.users,
            gas_index: record.gas_index,
            last_updated: record.last_updated,
        }
    }
}