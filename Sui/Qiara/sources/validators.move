module Qiara::QiaraValidatorsV1 {
    use std::vector;
    use sui::event;
    use sui::tx_context::{Self, TxContext};
    use sui::object::{Self, UID, ID};
    use sui::clock::{Self, Clock};

    use Qiara::QiaraDelegatorV1::{Self as delegator, AdminCap, Vault, SupportedTokenKey, Nullifiers, ProviderManager};
    use Qiara::QiaraEventsV1::{Self as Event};
    use Qiara::QiaraEpochManagerV1::{Self as epoch_manager, Config};
    use Qiara::QiaraVerifierV1::{Self as zk};

    // ==================== ERRORS ====================
    const E_NOT_AUTHORIZED: u64 = 0;


    // ==================== MAIN STATE OBJECT ====================
    public struct ValidatorState has key {
        id: UID,
        active_pubkeys: vector<vector<u8>>,
        pending_pubkeys: vector<vector<u8>>,
        last_processed_epoch: u64,
    }

    // ==================== FUNCTIONS ====================
    /// Initialize the validator state - called once by the creator
    fun init(ctx: &mut TxContext) {
        let state = ValidatorState {
            id: object::new(ctx),
            active_pubkeys: vector::empty(),
            pending_pubkeys: vector::empty(),
            last_processed_epoch: 0,
        };
        
        transfer::share_object(state);
    }


    // ==================== CORE LOGIC ====================

    /// Add a pending address (as pubkey bytes) - only authorized contract can call
    public entry fun add_pending_pubkey(state: &mut ValidatorState,pubkey: vector<u8>,epoch_manager_state: &Config, clock: &Clock,ctx: &TxContext) {
        // Authorization check - sender must be the authorized contract
        //assert!(object::id_from_address(tx_context::sender(ctx)) == state.authorized_contract_id,E_NOT_AUTHORIZED);
        
        // Check and handle epoch rollover
        check_and_handle_epoch_rollover(state, epoch_manager_state, clock);
        
        // Add to pending
        vector::push_back(&mut state.pending_pubkeys, pubkey);

    }

    /// Internal function to handle epoch rollover
    fun check_and_handle_epoch_rollover(state: &mut ValidatorState,epoch_manager_state: &Config, clock: &Clock) {
        let current_epoch = epoch_manager::get_current_epoch(epoch_manager_state, clock);
        
        if (current_epoch > state.last_processed_epoch) {
            // Move pending to active
            state.active_pubkeys = state.pending_pubkeys;
            
            // Clear pending
            state.pending_pubkeys = vector::empty();
            
            // Update last processed epoch
            let old_epoch = state.last_processed_epoch;
            state.last_processed_epoch = current_epoch;
            
        }
    }

    /// Admin function to directly add an active pubkey
    public entry fun add_active_pubkey_direct(state: &mut ValidatorState,pubkey: vector<u8>,ctx: &TxContext) {
        vector::push_back(&mut state.active_pubkeys, pubkey);
    }

    // ==================== VIEW FUNCTIONS ====================

    /// Get all active pubkeys
    public fun get_active_pubkeys(state: &ValidatorState): vector<vector<u8>> {
        state.active_pubkeys
    }

    /// Get all pending pubkeys
    public fun get_pending_pubkeys(state: &ValidatorState): vector<vector<u8>> {
        state.pending_pubkeys
    }

    /// Get active pubkeys count
    public fun get_active_count(state: &ValidatorState): u64 {
        vector::length(&state.active_pubkeys)
    }

    /// Get pending pubkeys count
    public fun get_pending_count(state: &ValidatorState): u64 {
        vector::length(&state.pending_pubkeys)
    }
}