module Qiara::QiaraValidatorsV1 {
    use std::vector;
    use sui::event;
    use std::debug;
    use sui::hash;
    use sui::tx_context::{Self, TxContext};
    use sui::object::{Self, UID, ID};
    use sui::clock::{Self, Clock};
    use sui::ecdsa_k1;
    use sui::transfer;
    use Qiara::QiaraDelegatorV1::{Self as delegator, AdminCap, Vault, SupportedTokenKey, Nullifiers, ProviderManager};
    use Qiara::QiaraEventsV1::{Self as Event};
    use Qiara::QiaraEpochManagerV1::{Self as epoch_manager, Config};
    use Qiara::QiaraVerifierV1::{Self as zk};

    // ==================== ERRORS ====================
    const E_NOT_AUTHORIZED: u64 = 0;
    const EInvalidSignatureLength: u64 = 1;
    const ENotValidator: u64 = 2;

    // ==================== STRUCTS ====================

    public struct PendingUpdate has store, drop, copy {
        pubkey: vector<u8>,
        is_removal: bool,
    }

    // ==================== MAIN STATE OBJECT ====================
    public struct ValidatorState has key {
        id: UID,
        active_pubkeys: vector<vector<u8>>,
        pending_updates: vector<PendingUpdate>, // Changed to structured updates queue [1]
        last_processed_epoch: u64,
    }

    // ==================== FUNCTIONS ====================
    /// Initialize the validator state - called once by the creator
    fun init(ctx: &mut TxContext) {
        let state = ValidatorState {
            id: object::new(ctx),
            active_pubkeys: vector::empty(),
            pending_updates: vector::empty(),
            last_processed_epoch: 0,
        };
        
        transfer::share_object(state);
    }


    // ==================== CORE LOGIC ====================

    /// Add a pending address update - only authorized contract can call
    public entry fun add_pending_pubkey(
        state: &mut ValidatorState,
        epoch_manager_state: &Config, 
        public_inputs: vector<u8>, 
        proof_points: vector<u8>, 
        signatures: vector<vector<u8>>, 
        clock: &Clock,
        _ctx: &TxContext
    ) {
        verify_signatures(state, signatures, public_inputs);


        // 2. Consume public_inputs to verify proof
        let (pubkey, is_removal) = zk::verify_validator(public_inputs, proof_points);

        // 3. Check and handle epoch rollover
        check_and_handle_epoch_rollover(state, epoch_manager_state, clock);
        
        // 4. Push structured update to the queue [1]
        let update = PendingUpdate {
            pubkey,
            is_removal,
        };
        vector::push_back(&mut state.pending_updates, update);
    }

    /// Internal function to handle epoch rollover
    fun check_and_handle_epoch_rollover(state: &mut ValidatorState, epoch_manager_state: &Config, clock: &Clock) {
        let current_epoch = epoch_manager::get_current_epoch(epoch_manager_state, clock);
        
        if (current_epoch > state.last_processed_epoch) {
            let updates = &state.pending_updates;
            let mut active = state.active_pubkeys;

            let len = vector::length(updates);
            let mut i = 0;
            
            // Process updates sequentially in FIFO order [1]
            while (i < len) {
                let update = vector::borrow(updates, i);
                if (update.is_removal) {
                    // Search and remove the public key [1]
                    let (found, index) = vector::index_of(&active, &update.pubkey);
                    if (found) {
                        vector::remove(&mut active, index);
                    };
                } else {
                    // Append the public key if not already active [1]
                    if (!vector::contains(&active, &update.pubkey)) {
                        vector::push_back(&mut active, update.pubkey);
                    };
                };
                i = i + 1;
            };

            // Set state to updated active set [1]
            state.active_pubkeys = active;
            
            // Clear pending updates queue [1]
            state.pending_updates = vector::empty();
            
            // Update last processed epoch
            state.last_processed_epoch = current_epoch;
        }
    }

    /// Admin function to directly add an active pubkey
    public entry fun add_active_pubkey_direct(state: &mut ValidatorState, pubkey: vector<u8>, _ctx: &TxContext) {
        vector::push_back(&mut state.active_pubkeys, pubkey);
    }

    public fun verify_signatures(state: &ValidatorState, signatures: vector<vector<u8>>, inputs: vector<u8>) {
        let mut n = vector::length(&signatures);
        let validator_pubkeys = get_active_pubkeys(state);
        
        while (n > 0) {
            let i = n - 1;
            let sig = &signatures[i];
            
            // Ensure signature is valid length before calling native function to avoid aborts
            assert!(vector::length(sig) == 65, EInvalidSignatureLength);

            // 1. Recover compressed key from signature
            let recovered_compressed = ecdsa_k1::secp256k1_ecrecover(sig, &inputs, 0);

            // 2. Decompress to get uncompressed (65 bytes, starts with 0x04)
            let recovered_uncompressed = ecdsa_k1::decompress_pubkey(&recovered_compressed);

            assert!(vector::contains(&validator_pubkeys, &recovered_uncompressed), ENotValidator);
            
            n = i;
        }
    }

    // ==================== VIEW FUNCTIONS ====================

    /// Get all active pubkeys
    public fun get_active_pubkeys(state: &ValidatorState): vector<vector<u8>> {
        state.active_pubkeys
    }

    /// Get all pending updates
    public fun get_pending_updates(state: &ValidatorState): vector<PendingUpdate> {
        state.pending_updates
    }

    /// Get active pubkeys count
    public fun get_active_count(state: &ValidatorState): u64 {
        vector::length(&state.active_pubkeys)
    }

    /// Get pending updates count
    public fun get_pending_count(state: &ValidatorState): u64 {
        vector::length(&state.pending_updates)
    }

    // ==================== RECONSTRUCTION HELPERS ====================

    fun extract_validator_is_removal(inputs: &vector<u8>): bool {
        // Extract PackedContext (index 2)
        let packed_context = bytes_to_u256(extract_chunk(inputs, 2));

        // Shift right by 16 bits and mask the LSB
        ((packed_context >> 16) & 1) == 1
    }

    fun extract_chunk(inputs: &vector<u8>, index: u64): vector<u8> {
        let start = index * 32;
        let mut chunk = vector::empty<u8>();
        let mut i = 0;
        while (i < 32) {
            vector::push_back(&mut chunk, *vector::borrow(inputs, start + i));
            i = i + 1;
        };
        chunk
    }

    fun bytes_to_u256(bytes: vector<u8>): u256 {
        let mut res: u256 = 0;
        let mut i = 32;
        while (i > 0) {
            i = i - 1;
            res = (res << 8) | (*vector::borrow(&bytes, i) as u256);
        };
        res
    }

    // ==================== UNIT TESTING ====================

    // Data from your Go logs
    const RAW_INPUTS: vector<u8> = x"7751b1419426e73e04eed985ff6401464c4e4933e12d3bba90f3a32ec77ada2ed74588d9a377c174565f37f426aa1d491a76b6582ae9efe9685b7c5bfe5e84009311a2cb4e72057f29a9edabd7d76f6300000000000000000000000000000000c1faaa92140000000000000000000000000000000000000000000000000000006e696665756c4200000000000000000000000000000000000000000000000000131a000000000000670000000100000043445355000000000000000000000000";
    const RAW_SIGNATURE: vector<u8> = x"fc4c58421dfc3c9281888cba72dc9179b3127039d04d0b0b91604607fc19dedc7eb2cb1f58cd4d43434b767f28877aca48cc56cb3fb02869e42b24e757fab1d500";
    const RAW_PUBKEY: vector<u8> = x"04437e14e19b814339b143d47d23ff2703cddd7624ee50ad5b40f032d511695b4a7d7833e780533ca86fb1edd4ced0a548b9e9f1cf1f2eecdb45cfa913e67f633f";


    // Data from your Go logs
    const RAW_INPUTS2: vector<u8> = x"b02e86a5de52fb7a7db5361bdb038392211cebb4f838c2f24351e6d2505cc02d52970c05948b2d46b0eb11597fad1c6b62a8415832d246cf9fb50287bf89f526000000000000000000000000000000000000000000000000000000000000000066e6347d1eefa51ce8a82c1c2ee8420b000000000000000000000000000000009694015c7a6d092fe155d96c31f8e26c00000000000000000000000000000000c8d76d8ad064a0ec3ad17079942f8dc700000000000000000000000000000000380529914c251981592e96cbf0b092e800000000000000000000000000000000";
    const RAW_SIGNATURE2: vector<u8> = x"c6c0a37fd6461d06e5b217d718660e517f3bfca146ff6910f1539472adcebaa12c3cb705472ca8665fd2b31884932936c00005e5e12739eb71f29c360909388501";
    const RAW_PUBKEY2: vector<u8> = x"04437e14e19b814339b143d47d23ff2703cddd7624ee50ad5b40f032d511695b4a7d7833e780533ca86fb1edd4ced0a548b9e9f1cf1f2eecdb45cfa913e67f633f";

    /// Helper to reverse each 32-byte public input chunk
    fun reverse_32b_chunks(bytes: vector<u8>): vector<u8> {
        let mut res = vector::empty<u8>();
        let len = vector::length(&bytes);
        let num_chunks = len / 32;
        let mut i = 0;
        while (i < num_chunks) {
            let mut j = 32;
            while (j > 0) {
                let byte = *vector::borrow(&bytes, i * 32 + j - 1);
                vector::push_back(&mut res, byte);
                j = j - 1;
            };
            i = i + 1;
        };
        res
    }

    /// Helper to construct the standard Ethereum Signed Message prefix
    fun get_ethereum_prefix(): vector<u8> {
        let mut prefix = vector::empty<u8>();
        vector::push_back(&mut prefix, 25); // 0x19 byte
        vector::append(&mut prefix, b"Ethereum Signed Message:\n32");
        prefix
    }

    #[test]
    public fun test_verify_sig() {
        let sui_inputs_le = RAW_INPUTS2;
        let sui_inputs_be = reverse_32b_chunks(RAW_INPUTS2);

        // --- Candidate 1: Raw Little-Endian (No prefix) ---
        let rec1 = ecdsa_k1::secp256k1_ecrecover(&RAW_SIGNATURE2, &sui_inputs_le, 0);
        let pub1 = ecdsa_k1::decompress_pubkey(&rec1);
        if (pub1 == RAW_PUBKEY2) {
            debug::print(&std::string::utf8(b"MATCH FOUND: Raw Little-Endian (No prefix)"));
            return
        };

        // --- Candidate 2: Raw Big-Endian (No prefix) ---
        let rec2 = ecdsa_k1::secp256k1_ecrecover(&RAW_SIGNATURE2, &sui_inputs_be, 0);
        let pub2 = ecdsa_k1::decompress_pubkey(&rec2);
        if (pub2 == RAW_PUBKEY2) {
            debug::print(&std::string::utf8(b"MATCH FOUND: Raw Big-Endian (No prefix)"));
            return
        };

        // --- Candidate 3: Ethereum Prefixed Little-Endian ---
        let hash_le = hash::keccak256(&sui_inputs_le);
        let mut eth_msg_le = get_ethereum_prefix();
        vector::append(&mut eth_msg_le, hash_le);
        
        let rec3 = ecdsa_k1::secp256k1_ecrecover(&RAW_SIGNATURE2, &eth_msg_le, 0);
        let pub3 = ecdsa_k1::decompress_pubkey(&rec3);
        if (pub3 == RAW_PUBKEY2) {
            debug::print(&std::string::utf8(b"MATCH FOUND: Ethereum Prefixed Little-Endian"));
            return
        };

        // --- Candidate 4: Ethereum Prefixed Big-Endian ---
        let hash_be = hash::keccak256(&sui_inputs_be);
        let mut eth_msg_be = get_ethereum_prefix();
        vector::append(&mut eth_msg_be, hash_be);
        
        let rec4 = ecdsa_k1::secp256k1_ecrecover(&RAW_SIGNATURE2, &eth_msg_be, 0);
        let pub4 = ecdsa_k1::decompress_pubkey(&rec4);
        if (pub4 == RAW_PUBKEY2) {
            debug::print(&std::string::utf8(b"MATCH FOUND: Ethereum Prefixed Big-Endian"));
            return
        };

        // --- Fallback Diagnostics ---
        debug::print(&std::string::utf8(b"FAIL: No match found. This confirms a key derivation mismatch."));
        assert!(false, 9999);
    }
}