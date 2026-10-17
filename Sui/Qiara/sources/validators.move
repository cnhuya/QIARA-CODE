module Qiara::QiaraValidatorsV1 {
    use std::vector;
    use sui::hash;
    use sui::bcs;
    use sui::tx_context::{Self, TxContext};
    use sui::object::{Self, UID};
    use sui::clock::Clock;
    use sui::ecdsa_k1;
    use sui::transfer;

    use Qiara::QiaraEpochManagerV1::{Self as epoch_manager, Config};

    // ==================== ERRORS ====================
    const E_NOT_AUTHORIZED: u64 = 0;
    const EInvalidSignatureLength: u64 = 1;
    const ENotValidator: u64 = 2;
    const EInvalidActionHash: u64 = 3;
    const EDuplicateSigner: u64 = 4;

    // ==================== STRUCTS ====================

    /// Matches Solana/EVM TimedValidator
    public struct TimedValidator has store, drop, copy {
        pubkey: vector<u8>,
        is_active: bool,
        target_status: bool,
        effective_epoch: u64,
    }

    /// BCS payload struct matching Solana ValidatorRotationPayload
    public struct ValidatorRotationPayload has drop {
        pubkey: vector<u8>,
        is_removal: bool,
    }

    // ==================== MAIN STATE OBJECT ====================
    public struct ValidatorState has key {
        id: UID,
        validators: vector<TimedValidator>,
    }

    // ==================== INIT ====================
    fun init(ctx: &mut TxContext) {
        let state = ValidatorState {
            id: object::new(ctx),
            validators: vector::empty(),
        };
        transfer::share_object(state);
    }

    // ==================== CORE LOGIC ====================

    /// Matches Solana handle_add_pending_pubkey: stages validator for effective_epoch (current_epoch + 1)
    public entry fun add_pending_pubkey(
        state: &mut ValidatorState,
        epoch_manager_state: &Config,
        message_hash: vector<u8>,
        raw_payload: vector<u8>,
        signatures: vector<vector<u8>>,
        clock: &Clock,
        _ctx: &TxContext
    ) {
        // 1. Assert canonical keccak256 hash matches Solana require!(message_hash == computed_hash)
        let computed_hash = hash::keccak256(&raw_payload);
        assert!(message_hash == computed_hash, EInvalidActionHash);

        let current_epoch = epoch_manager::get_current_epoch(epoch_manager_state, clock);

        // 2. Verify validator signatures against current epoch active validator set
        verify_signatures(state, signatures, message_hash, current_epoch);

        // 3. Unpack canonical BCS payload
        let payload = unpack_validator_payload(&raw_payload);

        // 4. Stage validator to take effect next epoch (effective_epoch = current_epoch + 1)
        let effective_epoch = current_epoch + 1;
        let target_status = !payload.is_removal;

        let len = vector::length(&state.validators);
        let mut found = false;
        let mut i = 0;

        while (i < len) {
            let val = vector::borrow_mut(&mut state.validators, i);
            if (val.pubkey == payload.pubkey) {
                // Auto-promote previous status if already matured (exact Solana/EVM match)
                if (val.effective_epoch != 0 && current_epoch >= val.effective_epoch) {
                    val.is_active = val.target_status;
                };
                val.target_status = target_status;
                val.effective_epoch = effective_epoch;
                found = true;
                break;
            };
            i = i + 1;
        };

        if (!found) {
            let new_val = TimedValidator {
                pubkey: payload.pubkey,
                is_active: false,
                target_status,
                effective_epoch,
            };
            vector::push_back(&mut state.validators, new_val);
        };
    }

    /// Admin fallback matching Solana handle_add_active_pubkey_direct
    public entry fun add_active_pubkey_direct(
        state: &mut ValidatorState,
        pubkey: vector<u8>,
        is_active: bool,
        _ctx: &TxContext
    ) {
        let len = vector::length(&state.validators);
        let mut found = false;
        let mut i = 0;

        while (i < len) {
            let val = vector::borrow_mut(&mut state.validators, i);
            if (val.pubkey == pubkey) {
                val.is_active = is_active;
                val.effective_epoch = 0;
                val.target_status = false;
                found = true;
                break;
            };
            i = i + 1;
        };

        if (!found) {
            let new_val = TimedValidator {
                pubkey,
                is_active,
                target_status: false,
                effective_epoch: 0,
            };
            vector::push_back(&mut state.validators, new_val);
        };
    }

    // ==================== SIGNATURE VERIFICATION ====================

    /// Verifies Secp256k1 signatures against active validators at `current_epoch`
    public fun verify_signatures(
        state: &ValidatorState,
        signatures: vector<vector<u8>>,
        message_hash: vector<u8>,
        current_epoch: u64
    ) {
        let mut n = vector::length(&signatures);

        // eth_msg = "\x19Ethereum Signed Message:\n32" + message_hash
        let mut eth_msg = vector::empty<u8>();
        vector::push_back(&mut eth_msg, 25); // 0x19
        vector::append(&mut eth_msg, b"Ethereum Signed Message:\n32");
        vector::append(&mut eth_msg, message_hash);

        let mut seen_signers = vector::empty<vector<u8>>();

        while (n > 0) {
            let i = n - 1;
            let raw_sig = vector::borrow(&signatures, i);
            assert!(vector::length(raw_sig) == 65, EInvalidSignatureLength);

            // Normalize recovery ID v (27/28 -> 0/1)
            let mut normalized_sig = *raw_sig;
            let v = vector::borrow_mut(&mut normalized_sig, 64);
            if (*v >= 27) {
                *v = *v - 27;
            };

            // Recover & decompress to 65-byte uncompressed key (0x04...)
            let recovered_compressed = ecdsa_k1::secp256k1_ecrecover(&normalized_sig, &eth_msg, 0);
            let recovered_uncompressed = ecdsa_k1::decompress_pubkey(&recovered_compressed);

            // Check if recovered key is an active validator at current_epoch
            assert!(is_validator_active_internal(state, &recovered_uncompressed, current_epoch), ENotValidator);

            // Check for duplicate signers in the batch
            assert!(!vector::contains(&seen_signers, &recovered_uncompressed), EDuplicateSigner);
            vector::push_back(&mut seen_signers, recovered_uncompressed);

            n = i;
        };
    }

    // ==================== HELPERS & BCS ====================

    fun unpack_validator_payload(raw_payload: &vector<u8>): ValidatorRotationPayload {
        let mut bcs_data = bcs::new(*raw_payload);
        let pubkey = bcs::peel_vec_u8(&mut bcs_data);
        let is_removal = bcs::peel_bool(&mut bcs_data);
        ValidatorRotationPayload { pubkey, is_removal }
    }

    fun is_validator_active_internal(state: &ValidatorState, pubkey: &vector<u8>, current_epoch: u64): bool {
        let len = vector::length(&state.validators);
        let mut i = 0;
        while (i < len) {
            let val = vector::borrow(&state.validators, i);
            if (&val.pubkey == pubkey) {
                return if (val.effective_epoch != 0 && current_epoch >= val.effective_epoch) {
                    val.target_status
                } else {
                    val.is_active
                };
            };
            i = i + 1;
        };
        false
    }

    // ==================== VIEW FUNCTIONS ====================

    public fun is_active_at_epoch(state: &ValidatorState, pubkey: vector<u8>, current_epoch: u64): bool {
        is_validator_active_internal(state, &pubkey, current_epoch)
    }

    public fun get_active_pubkeys(state: &ValidatorState, current_epoch: u64): vector<vector<u8>> {
        let mut active = vector::empty<vector<u8>>();
        let len = vector::length(&state.validators);
        let mut i = 0;
        while (i < len) {
            let val = vector::borrow(&state.validators, i);
            if (if (val.effective_epoch != 0 && current_epoch >= val.effective_epoch) { val.target_status } else { val.is_active }) {
                vector::push_back(&mut active, val.pubkey);
            };
            i = i + 1;
        };
        active
    }

    public fun get_validators(state: &ValidatorState): vector<TimedValidator> {
        state.validators
    }
}