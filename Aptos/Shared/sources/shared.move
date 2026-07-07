module dev::QiaraSharedV13{
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
    use aptos_framework::object::{Self, Object};
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

    struct RefCodeParams has store, copy, drop {
        xp_tax: u64, // 100_000_000 = 100%
        fee_tax: u64, // 100_000_000 = 100%
    }

    struct Ownership has store, copy, drop {
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
        // NEW: shared_name -> asset_metadata -> vault_store
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
                fungible_stores: table::new<String, Table<Object<Metadata>, Object<FungibleStore>>>(),
            });
        };

    }

    // ----------------------------------------------------------------
    // EXISTING SHARED STORAGE LOGIC
    // ----------------------------------------------------------------

    public entry fun create_non_user_shared_storage(name: String) acquires SharedStorage {
        let shared = borrow_global_mut<SharedStorage>(@dev);
        let non_user_key = bcs::to_bytes(&name);

        if (!table::contains(&shared.storage, name)) {
            table::add(&mut shared.storage, name, Ownership { 
                owner: non_user_key, 
                sub_owners: vector::empty<vector<u8>>(),
                selected_validator: utf8(b""),
                ref_code: utf8(b""), 
                ref_code_params: RefCodeParams { xp_tax: 0, fee_tax: 0 }, 
                used_ref_code: utf8(b""),
                users: vector::empty<String>(),
                gas_index: 0,
                amount_of_users_using_ref_code: 0,
                last_updated: 0
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
        let signer_addr = signer::address_of(signer);
        let signer_addr_bytes = bcs::to_bytes(&signer_addr);

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
        let ref_code_params = RefCodeParams { xp_tax: xp_tax, fee_tax: fee_tax };

        assert!(!table::contains(&shared.ref_code_registry, ref_code), ERROR_REF_CODE_ALREADY_EXISTS);
        assert!(table::contains(&shared.ref_code_registry, used_ref_code), ERROR_REF_CODE_DOESNT_EXISTS);

        let used_ref_code_ownership_record = table::borrow_mut(&mut shared.storage, used_ref_code);
        used_ref_code_ownership_record.amount_of_users_using_ref_code += 1;

        table::add(&mut shared.ref_code_registry, ref_code, ref_code_params);
        
        table::add(&mut shared.storage, name, Ownership { 
            owner: signer_addr_bytes,  
            sub_owners: sub_owners,
            ref_code: ref_code,
            selected_validator: selected_validator,
            ref_code_params: RefCodeParams { xp_tax: xp_tax, fee_tax: fee_tax },
            used_ref_code: used_ref_code,
            users: vector::empty<String>(),
            gas_index: 0,
            amount_of_users_using_ref_code: 0,
            last_updated: timestamp::now_seconds(),
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

        // Scope 1: Immutable borrow to verify owner [1.2.2]
        {
            let ownership_record = table::borrow(&shared.storage, name);
            assert!(ownership_record.owner == bcs::to_bytes(&sender_addr), ERROR_NOT_OWNER_OF_THIS_SHARED_STORAGE);
        }; // <- Borrow expires here! [1.2.2]

        assert!(table::contains(&shared.ref_code_registry, new_used_ref_code), ERROR_REF_CODE_DOESNT_EXISTS);

        // Scope 2: Mutably borrow and increment amount_of_users_using_ref_code [1.2.2]
        {
            let used_ref_code_ownership_record = table::borrow_mut(&mut shared.storage, new_used_ref_code);
            used_ref_code_ownership_record.amount_of_users_using_ref_code = used_ref_code_ownership_record.amount_of_users_using_ref_code + 1;
        }; // <- Borrow expires here! [1.2.2]

        // Scope 3: Mutably borrow and update the used_ref_code of the storage [1.2.2]
        {
            let ownership_record = table::borrow_mut(&mut shared.storage, name);
            ownership_record.used_ref_code = new_used_ref_code;
        }; // <- Borrow expires here! [1.2.2]

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

    public fun p_create_shared_storage(validator: &signer, user: vector<u8>, name: String, ref_code: String, used_ref_code: String, selected_validator: String, xp_tax: u64, fee_tax: u64, perm: Permission ) acquires SharedStorage {
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
        assert!(table::contains(&shared.ref_code_registry, used_ref_code), ERROR_REF_CODE_DOESNT_EXISTS);

        let used_ref_code_ownership_record = table::borrow_mut(&mut shared.storage, used_ref_code);
        used_ref_code_ownership_record.amount_of_users_using_ref_code += 1;

        table::add(&mut shared.storage, name, Ownership { 
            owner: user, 
            sub_owners: sub_owners,
            selected_validator: selected_validator,
            ref_code: ref_code,
            ref_code_params: RefCodeParams { xp_tax: xp_tax, fee_tax: fee_tax },
            used_ref_code: used_ref_code,
            users: vector::empty<String>(),
            gas_index: 0,
            amount_of_users_using_ref_code: 0,
            last_updated: timestamp::now_seconds(),
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

            // Scope 1: Immutable borrow to verify owner [1.2.2]
            {
                let ownership_record = table::borrow(&shared.storage, name);
                assert!(ownership_record.owner == user, ERROR_NOT_OWNER_OF_THIS_SHARED_STORAGE);
            }; // <- Borrow expires here! [1.2.2]

            assert!(table::contains(&shared.ref_code_registry, new_used_ref_code), ERROR_REF_CODE_DOESNT_EXISTS);

            // Scope 2: Mutably borrow and increment amount_of_users_using_ref_code [1.2.2]
            {
                let used_ref_code_ownership_record = table::borrow_mut(&mut shared.storage, new_used_ref_code);
                used_ref_code_ownership_record.amount_of_users_using_ref_code = used_ref_code_ownership_record.amount_of_users_using_ref_code + 1;
            }; // <- Borrow expires here! [1.2.2]

            // Scope 3: Mutably borrow and update the used_ref_code of the storage [1.2.2]
            {
                let ownership_record = table::borrow_mut(&mut shared.storage, name);
                ownership_record.used_ref_code = new_used_ref_code;
            }; // <- Borrow expires here! [1.2.2]

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

        // deprecated remove in future
        public fun create_shared_vault(shared_name: String, asset_metadata: Object<Metadata>, _perm: Permission) acquires SharedStorage {
            let shared = borrow_global_mut<SharedStorage>(@dev);
            assert!(table::contains(&shared.storage, shared_name), ERROR_SHARED_STORAGE_WITH_THIS_NAME_DOESNT_EXISTS);
            if (!table::contains(&shared.fungible_stores, shared_name)) {
                table::add(&mut shared.fungible_stores, shared_name, table::new<Object<Metadata>, Object<FungibleStore>>());
            };
            
            let token_map = table::borrow_mut(&mut shared.fungible_stores, shared_name);
            if (!table::contains(token_map, asset_metadata)) {
                // The vault is just a primary store owned by @dev.
                // It doesn't need TransferRef here because TokensCore handles the transfers.
                let vault_store = primary_fungible_store::ensure_primary_store_exists(@dev, asset_metadata);
                table::add(token_map, asset_metadata, vault_store);
            };
        }

        public fun ensure_shared_fungible_storage(shared_name: String, asset_metadata: Object<Metadata>, _perm: Permission): Object<FungibleStore> acquires SharedStorage {
            let shared = borrow_global_mut<SharedStorage>(@dev);
            assert!(table::contains(&shared.storage, shared_name), ERROR_SHARED_STORAGE_WITH_THIS_NAME_DOESNT_EXISTS);
            
            if (!table::contains(&shared.fungible_stores, shared_name)) {
                table::add(&mut shared.fungible_stores, shared_name, table::new<Object<Metadata>, Object<FungibleStore>>());
            };
            
            let token_map = table::borrow_mut(&mut shared.fungible_stores, shared_name);
            if (!table::contains(token_map, asset_metadata)) {
                
                // 1. Convert the shared_name string to bytes
                let name_bytes = *std::string::bytes(&shared_name);
                
                // 2. Derive a deterministic address based on this name and the contract address
                let derived_address = object::create_object_address(&@dev, name_bytes);
                
                // 3. Create/Ensure the store exists at that derived address instead of @dev
                let vault_store = primary_fungible_store::ensure_primary_store_exists(derived_address, asset_metadata);
                
                table::add(token_map, asset_metadata, vault_store);
            };

            *table::borrow(token_map, asset_metadata)
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

        public fun extract_raw_params(ownership_record: Ownership): (u64, u64) {

        if(ownership_record.used_ref_code == utf8(b"")){
                return (0,0)
            };

            let params = return_ref_code_params(ownership_record.used_ref_code);
            (params.xp_tax, params.fee_tax)
        }

        public fun extract_used_ref_code_params(ownership_record: Ownership): RefCodeParams {
            let used_ref_code_params = create_empty_raw_params();
            if(ownership_record.used_ref_code != utf8(b"")){
                used_ref_code_params = return_ref_code_params(ownership_record.used_ref_code);
            };
            return used_ref_code_params
        }


        public fun extract_raw_gas_relations(ownership_record: Ownership): (u256, u64) {

            (ownership_record.gas_index, ownership_record.last_updated)
        }

        public fun create_empty_raw_params(): RefCodeParams {
            RefCodeParams { xp_tax: 0, fee_tax: 0 }
        }



    }