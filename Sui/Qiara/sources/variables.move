module Qiara::QiaraVariablesV1 {
    use std::string::{Self, String};
    use std::vector;
    use sui::vec_map::{Self, VecMap};
    use sui::tx_context::{Self, TxContext};
    use sui::clock::Clock;
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::address;
    use sui::hash;
    use sui::bcs;

    use Qiara::QiaraEpochManagerV1::{Self as epoch_manager, Config};
    use Qiara::QiaraValidatorsV1::{Self as validators, ValidatorState};

    // --- Errors ---
    const ERegistryLocked: u64 = 0;
    const EVariableNotFound: u64 = 1;
    const EInvalidActionHash: u64 = 2;
    const EWrongChainId: u64 = 3;

    const LOCAL_CHAIN_ID: u64 = 901;

    // --- Structs ---

    public struct AdminCap has key, store { id: UID }
    public struct FriendCap has key, store { id: UID }

    /// Matches Solana/EVM TimedVariable
    public struct TimedVariable has store, drop, copy {
        name: String,
        active_data: vector<u8>,
        pending_data: vector<u8>,
        effective_epoch: u64,
    }

    /// BCS payload struct matching Solana VariablePayload
    public struct VariablePayload has drop {
        header: String,
        name: String,
        data: vector<u8>,
        chain_id: u64,
    }

    public struct Registry has key {
        id: UID,
        variables: VecMap<String, VecMap<String, TimedVariable>>,
        is_locked: bool,
    }

    fun init(ctx: &mut TxContext) {
        let admin_cap = AdminCap { id: object::new(ctx) };
        transfer::transfer(admin_cap, tx_context::sender(ctx));

        let registry = Registry {
            id: object::new(ctx),
            variables: vec_map::empty(),
            is_locked: false,
        };
        transfer::share_object(registry);
    }

    // --- Authorization Helpers ---

    public entry fun issue_friend_cap(_: &AdminCap, recipient: address, ctx: &mut TxContext) {
        let cap = FriendCap { id: object::new(ctx) };
        transfer::transfer(cap, recipient);
    }

    public entry fun lock_registry(_: &AdminCap, registry: &mut Registry) {
        registry.is_locked = true;
    }

    // --- Core Operations ---

    /// Matches Solana handle_admin_add_variable: immediate overwrite
    public entry fun admin_add_variable(
        _: &AdminCap,
        registry: &mut Registry,
        header: String,
        name: String,
        data: vector<u8>
    ) {
        assert!(!registry.is_locked, ERegistryLocked);

        if (!vec_map::contains(&registry.variables, &header)) {
            let mut inner = vec_map::empty();
            vec_map::insert(&mut inner, name, TimedVariable {
                name,
                active_data: data,
                pending_data: vector::empty(),
                effective_epoch: 0,
            });
            vec_map::insert(&mut registry.variables, header, inner);
        } else {
            let inner = vec_map::get_mut(&mut registry.variables, &header);
            if (vec_map::contains(inner, &name)) {
                let var = vec_map::get_mut(inner, &name);
                var.active_data = data;
                var.pending_data = vector::empty();
                var.effective_epoch = 0;
            } else {
                vec_map::insert(inner, name, TimedVariable {
                    name,
                    active_data: data,
                    pending_data: vector::empty(),
                    effective_epoch: 0,
                });
            };
        };
    }

    /// Matches Solana handle_friend_add_variable: stages variable for effective_epoch (current_epoch + 1)
    public entry fun friend_add_variable(
        state: &ValidatorState,
        registry: &mut Registry,
        epoch_manager_state: &Config,
        message_hash: vector<u8>,
        raw_payload: vector<u8>,
        signatures: vector<vector<u8>>,
        clock: &Clock,
        _ctx: &mut TxContext
    ) {
        // 1. Assert canonical keccak256 hash matches Solana require!(message_hash == computed_hash)
        let computed_hash = hash::keccak256(&raw_payload);
        assert!(message_hash == computed_hash, EInvalidActionHash);

        assert!(!registry.is_locked, ERegistryLocked);
        let current_epoch = epoch_manager::get_current_epoch(epoch_manager_state, clock);

        // 2. Verify validator signatures against current epoch active validator set
        validators::verify_signatures(state, signatures, message_hash, current_epoch);

        // 3. Deserialize canonical BCS payload
        let payload = unpack_variable_payload(&raw_payload);

        // 4. Assert chain_id if specified
        if (payload.chain_id != 0) {
            assert!(payload.chain_id == LOCAL_CHAIN_ID, EWrongChainId);
        };

        // 5. Stage variable to activate at effective_epoch (current_epoch + 1)
        let effective_epoch = current_epoch + 1;

        if (!vec_map::contains(&registry.variables, &payload.header)) {
            let mut inner = vec_map::empty();
            vec_map::insert(&mut inner, payload.name, TimedVariable {
                name: payload.name,
                active_data: vector::empty(),
                pending_data: payload.data,
                effective_epoch,
            });
            vec_map::insert(&mut registry.variables, payload.header, inner);
        } else {
            let inner = vec_map::get_mut(&mut registry.variables, &payload.header);
            if (vec_map::contains(inner, &payload.name)) {
                let var = vec_map::get_mut(inner, &payload.name);
                // Auto-promote matured value before overwriting (exact Solana/EVM match)
                if (var.effective_epoch != 0 && current_epoch >= var.effective_epoch) {
                    var.active_data = var.pending_data;
                };
                var.pending_data = payload.data;
                var.effective_epoch = effective_epoch;
            } else {
                vec_map::insert(inner, payload.name, TimedVariable {
                    name: payload.name,
                    active_data: vector::empty(),
                    pending_data: payload.data,
                    effective_epoch,
                });
            };
        };
    }

    // --- BCS Helper ---

    fun unpack_variable_payload(raw_payload: &vector<u8>): VariablePayload {
        let mut bcs_data = bcs::new(*raw_payload);
        let header_bytes = bcs::peel_vec_u8(&mut bcs_data);
        let header = string::utf8(header_bytes);
        let name_bytes = bcs::peel_vec_u8(&mut bcs_data);
        let name = string::utf8(name_bytes);
        let data = bcs::peel_vec_u8(&mut bcs_data);
        let chain_id = bcs::peel_u64(&mut bcs_data);

        VariablePayload { header, name, data, chain_id }
    }

    // --- Getters ---

    /// Reads variable data with auto-evaluation for a specific epoch
    public fun get_variable_at_epoch(
        registry: &Registry,
        header: String,
        name: String,
        current_epoch: u64
    ): vector<u8> {
        assert!(vec_map::contains(&registry.variables, &header), EVariableNotFound);
        let inner = vec_map::get(&registry.variables, &header);
        assert!(vec_map::contains(inner, &name), EVariableNotFound);
        let var = vec_map::get(inner, &name);

        if (var.effective_epoch != 0 && current_epoch >= var.effective_epoch) {
            var.pending_data
        } else {
            var.active_data
        }
    }

    /// Standard reader returning active data (or pending data if newly initialized)
    public fun get_variable(registry: &Registry, header: String, name: String): vector<u8> {
        assert!(vec_map::contains(&registry.variables, &header), EVariableNotFound);
        let inner = vec_map::get(&registry.variables, &header);
        assert!(vec_map::contains(inner, &name), EVariableNotFound);
        let var = vec_map::get(inner, &name);

        if (!vector::is_empty(&var.active_data)) {
            var.active_data
        } else {
            var.pending_data
        }
    }

    public fun has_variable(registry: &Registry, header: String, name: String): bool {
        if (!vec_map::contains(&registry.variables, &header)) return false;
        let inner = vec_map::get(&registry.variables, &header);
        vec_map::contains(inner, &name)
    }

    // --- Helper Type Converters ---

    public fun get_variable_to_u8(registry: &Registry, header: String, name: String): u8 {
        let data = get_variable(registry, header, name);
        let len = vector::length(&data);
        assert!(len > 0, EVariableNotFound);
        *vector::borrow(&data, len - 1)
    }

    public fun get_variable_to_u16(registry: &Registry, header: String, name: String): u16 {
        let data = get_variable(registry, header, name);
        let len = vector::length(&data);
        let mut res: u16 = 0;
        let mut i = if (len >= 2) { len - 2 } else { 0 };
        while (i < len) {
            res = (res << 8) | (*vector::borrow(&data, i) as u16);
            i = i + 1;
        };
        res
    }

    public fun get_variable_to_u32(registry: &Registry, header: String, name: String): u32 {
        let data = get_variable(registry, header, name);
        let len = vector::length(&data);
        let mut res: u32 = 0;
        let mut i = if (len >= 4) { len - 4 } else { 0 };
        while (i < len) {
            res = (res << 8) | (*vector::borrow(&data, i) as u32);
            i = i + 1;
        };
        res
    }

    public fun get_variable_to_u64(registry: &Registry, header: String, name: String): u64 {
        let data = get_variable(registry, header, name);
        let len = vector::length(&data);
        let mut res: u64 = 0;
        let mut i = if (len >= 8) { len - 8 } else { 0 };
        while (i < len) {
            res = (res << 8) | (*vector::borrow(&data, i) as u64);
            i = i + 1;
        };
        res
    }

    public fun get_variable_to_u128(registry: &Registry, header: String, name: String): u128 {
        let data = get_variable(registry, header, name);
        let len = vector::length(&data);
        let mut res: u128 = 0;
        let mut i = if (len >= 16) { len - 16 } else { 0 };
        while (i < len) {
            res = (res << 8) | (*vector::borrow(&data, i) as u128);
            i = i + 1;
        };
        res
    }

    public fun get_variable_to_u256(registry: &Registry, header: String, name: String): u256 {
        let data = get_variable(registry, header, name);
        let len = vector::length(&data);
        let mut res: u256 = 0;
        let mut i = if (len >= 32) { len - 32 } else { 0 };
        while (i < len) {
            res = (res << 8) | (*vector::borrow(&data, i) as u256);
            i = i + 1;
        };
        res
    }

    public fun get_variable_to_vecu8(registry: &Registry, header: String, name: String): vector<u8> {
        let data = get_variable(registry, header, name);
        let mut trimmed = vector::empty<u8>();
        let mut i = 0;
        let len = vector::length(&data);
        while (i < len) {
            let byte = *vector::borrow(&data, i);
            if (byte != 0) {
                vector::push_back(&mut trimmed, byte);
            };
            i = i + 1;
        };
        trimmed
    }

    public fun get_variable_as_string(registry: &Registry, header: String, name: String): String {
        let bytes = get_variable_to_vecu8(registry, header, name);
        string::utf8(bytes)
    }

    public fun get_variable_to_bool(registry: &Registry, header: String, name: String): bool {
        let data = get_variable(registry, header, name);
        let len = vector::length(&data);
        assert!(len > 0, EVariableNotFound);
        *vector::borrow(&data, len - 1) != 0
    }

    public fun get_variable_to_address(registry: &Registry, header: String, name: String): address {
        let data = get_variable(registry, header, name);
        address::from_bytes(data)
    }
}