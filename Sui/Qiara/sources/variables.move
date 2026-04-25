module 0x0::QiaraVariablesV1 {
    use std::string::{Self, String};
    use sui::vec_map::{Self, VecMap};
    use sui::tx_context::{Self, TxContext};
    use sui::bcs;
    use sui::clock::Clock;
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::event;

    use 0x0::QiaraEpochManagerV1 as epoch_manager;
    use 0x0::QiaraEpochManagerV1::Config;
    use 0x0::QiaraVerifierV1 as zk;

    // --- Errors ---
    const ERegistryLocked: u64 = 0;
    const EVariableNotFound: u64 = 1;

    // --- Structs ---

    public struct AdminCap has key, store { id: UID }
    public struct FriendCap has key, store { id: UID }

    public struct PendingVariable has store, drop {
        name: String,
        value: vector<u8>,
    }

    public struct Registry has key {
        id: UID,
        active_variables: VecMap<String, VecMap<String, vector<u8>>>,
        pending_variables: VecMap<String, vector<PendingVariable>>,
        is_locked: bool,
        last_processed_epoch: u64,
    }

    fun init(ctx: &mut TxContext) {
        let admin_cap = AdminCap { id: object::new(ctx) };
        transfer::transfer(admin_cap, tx_context::sender(ctx));

        let registry = Registry {
            id: object::new(ctx),
            active_variables: vec_map::empty(),
            pending_variables: vec_map::empty(),
            is_locked: false,
            last_processed_epoch: 0,
        };
        transfer::share_object(registry);
    }

    // --- Authorization Helpers ---

    public entry fun issue_friend_cap(_: &AdminCap, recipient: address, ctx: &mut TxContext) {
        let cap = FriendCap { id: object::new(ctx) };
        transfer::transfer(cap, recipient);
    }

    // --- Core Logic (Internal) ---

    fun internal_add_direct(registry: &mut Registry, header: String, name: String, data: vector<u8>) {
        assert!(!registry.is_locked, ERegistryLocked);

        if (!vec_map::contains(&registry.active_variables, &header)) {
            let mut inner_map = vec_map::empty();
            vec_map::insert(&mut inner_map, name, data);
            vec_map::insert(&mut registry.active_variables, header, inner_map);
        } else {
            let inner_map = vec_map::get_mut(&mut registry.active_variables, &header);
            if (vec_map::contains(inner_map, &name)) {
                let (_, _) = vec_map::remove(inner_map, &name);
            };
            vec_map::insert(inner_map, name, data);
        }
    }

    fun internal_add_pending(registry: &mut Registry, header: String, name: String, data: vector<u8>) {
        assert!(!registry.is_locked, ERegistryLocked);

        let pending_var = PendingVariable {
            name: name,
            value: data,
        };
        
        if (!vec_map::contains(&registry.pending_variables, &header)) {
            let mut vec = vector::empty();
            vector::push_back(&mut vec, pending_var);
            vec_map::insert(&mut registry.pending_variables, header, vec);
        } else {
            let vec = vec_map::get_mut(&mut registry.pending_variables, &header);
            vector::push_back(vec, pending_var);
        }
    }

    fun check_and_handle_epoch_rollover(
        registry: &mut Registry,
        epoch_manager_state: &Config,
        clock: &Clock,
        _ctx: &mut TxContext
    ) {
        let current_epoch = epoch_manager::get_current_epoch(epoch_manager_state, clock);
        
        if (current_epoch > registry.last_processed_epoch) {
            let mut moved_count = 0;
            
            // Get all headers that have pending variables
            let headers = vec_map::keys(&registry.pending_variables);
            let mut i = 0;
            let headers_len = vector::length(&headers);
            
            while (i < headers_len) {
                let header = vector::borrow(&headers, i);
                
                // Remove the pending vector for this header
                let (_, pending_vec) = vec_map::remove(&mut registry.pending_variables, header);
                
                // Process each pending variable
                let mut j = 0;
                let vec_len = vector::length(&pending_vec);
                while (j < vec_len) {
                    let pending_var = vector::borrow(&pending_vec, j);
                    moved_count = moved_count + 1;
                    
                    // Add to active variables
                    if (!vec_map::contains(&registry.active_variables, header)) {
                        let mut inner_map = vec_map::empty();
                        vec_map::insert(&mut inner_map, pending_var.name, pending_var.value);
                        vec_map::insert(&mut registry.active_variables, *header, inner_map);
                    } else {
                        let inner_map = vec_map::get_mut(&mut registry.active_variables, header);
                        if (vec_map::contains(inner_map, &pending_var.name)) {
                            let (_, _) = vec_map::remove(inner_map, &pending_var.name);
                        };
                        vec_map::insert(inner_map, pending_var.name, pending_var.value);
                    };
                    
                    j = j + 1;
                };
                
                // Clean up the vector
                vector::destroy_empty(pending_vec);
                i = i + 1;
            };
            
            registry.last_processed_epoch = current_epoch;
            
        }
    }

    // --- Entry Points ---
    public entry fun admin_add_variable(_: &AdminCap, registry: &mut Registry, header: String, name: String, data: vector<u8>) {
        internal_add_direct(registry, header, name, data);
    }

    public entry fun friend_add_variable(
        registry: &mut Registry, 
        header: String, 
        name: String, 
        data: vector<u8>, 
        public_inputs: vector<u8>, 
        proof_points: vector<u8>,
        epoch_manager_state: &Config,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        zk::verify_variable(public_inputs, proof_points);
        
        // Handle epoch rollover before adding
        check_and_handle_epoch_rollover(registry, epoch_manager_state, clock, ctx);
        
        internal_add_pending(registry, header, name, data);
    }

    public entry fun lock_registry(_: &AdminCap, registry: &mut Registry) {
        registry.is_locked = true;
    }

    // --- Getters ---
    public fun get_variable(registry: &Registry, header: String, name: String): vector<u8> {
        let inner_map = vec_map::get(&registry.active_variables, &header);
        if (!vec_map::contains(inner_map, &name)) {
            abort EVariableNotFound
        };
        *vec_map::get(inner_map, &name)
    }

    // --- Helper Getters ---
    public fun get_variable_to_u8(registry: &Registry, header: String, name: String): u8 {
        let data = get_variable(registry, header, name);
        let mut bytes = bcs::new(data);
        bcs::peel_u8(&mut bytes)
    }
    
    public fun get_variable_to_u16(registry: &Registry, header: String, name: String): u16 {
        let data = get_variable(registry, header, name);
        let mut bytes = bcs::new(data);
        bcs::peel_u16(&mut bytes)
    }
    
    public fun get_variable_to_u32(registry: &Registry, header: String, name: String): u32 {
        let data = get_variable(registry, header, name);
        let mut bytes = bcs::new(data);
        bcs::peel_u32(&mut bytes)
    }
    
    public fun get_variable_to_u64(registry: &Registry, header: String, name: String): u64 {
        let data = get_variable(registry, header, name);
        let mut bytes = bcs::new(data);
        bcs::peel_u64(&mut bytes)
    }
    
    public fun get_variable_to_u128(registry: &Registry, header: String, name: String): u128 {
        let data = get_variable(registry, header, name);
        let mut bytes = bcs::new(data);
        bcs::peel_u128(&mut bytes)
    }
    
    public fun get_variable_to_u256(registry: &Registry, header: String, name: String): u256 {
        let data = get_variable(registry, header, name);
        let mut bytes = bcs::new(data);
        bcs::peel_u256(&mut bytes)
    }
    
    public fun get_variable_to_vecu8(registry: &Registry, header: String, name: String): vector<u8> {
        let data = get_variable(registry, header, name);
        let mut bytes = bcs::new(data);
        bcs::peel_vec_u8(&mut bytes)
    }
    
    public fun get_variable_as_string(registry: &Registry, header: String, name: String): String {
        let bytes = get_variable_to_vecu8(registry, header, name);
        string::utf8(bytes)
    }
    
    public fun get_variable_to_bool(registry: &Registry, header: String, name: String): bool {
        let data = get_variable(registry, header, name);
        let mut bytes = bcs::new(data);
        bcs::peel_bool(&mut bytes)
    }
    
    public fun get_variable_to_address(registry: &Registry, header: String, name: String): address {
        let data = get_variable(registry, header, name);
        let mut bytes = bcs::new(data);
        bcs::peel_address(&mut bytes)
    }
}