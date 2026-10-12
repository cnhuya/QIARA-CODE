module dev::Qiarax38 {
    use std::signer;
    use std::vector;
    use std::bcs;
    use std::timestamp;
    use aptos_std::ed25519;
    use aptos_std::table::{Self, Table};
    //use aptos_std::any::{Self, Any};
    use supra_framework::event;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use std::string::{Self as String, String, utf8};

    use dev::QiaraVv31::{Self as validators, };
    use dev::genesisV24::{Self as genesis, };

    // === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 0;
    const ERROR_NOT_VALIDATOR: u64 = 1;
    const ERROR_NOT_PARENT_VALIDATOR: u64 = 2;
    const ERROR_INVALID_SIGNATURE: u64 = 1001;
    const ERROR_QUORUM_NOT_MET: u64 = 1002;
    const ERROR_STATE_NOT_FOUND: u64 = 1003;
    const ERROR_INVALID_STATE_TYPE: u64 = 1004;
    const ERROR_INVALID_MESSAGE: u64 = 1005;

    // === STRUCTS === //

    struct Any has store, copy, drop{
        value: vector<u8>,
        type: String,
        id: u64
    }
    // for zk proof
    struct ParentBody has key, store, copy, drop {
        message: String,
        s_r8x: String,
        s_r8y: String,
        s: String,
        pub_key_x: String,
        pub_key_y: String,
        staked: u64,
        index: u64, // Position in the 64-validator array (0-63)
    }


    struct States has key {
        table: Table<u64, BridgeState>,
        //type -> message -> validations
        validations: Table<String,Table<String, Validations>>,
    }
    // This resource stores the "Agreed" state before it moves to Ethereum
    struct BridgeState has key, drop, copy, store {
        root: String,
        votes: u64, //Vote Count
        // I need to make it like this, bcs sometimes the validators can be different for different values is it possible? i.e sometimes validators can be offline so other validators validate instead of them
        parents: Map<address, ParentBody>,
    }


    struct Validations has key, drop, copy, store {
        root: String,
        data: vector<vector<u8>>,
        votes: u64, //Vote Count
        // I need to make it like this, bcs sometimes the validators can be different for different values is it possible? i.e sometimes validators can be offline so other validators validate instead of them
        parents: Map<address, ParentBody>,
    }



    #[event]
    struct BridgeUpdateEvent has drop, store {
        epoch: u64,
        poseidon_root: String,
    }
    #[event]
    struct VoteEvent has drop, store {
        validator: address,
        epoch: u64,
        root: String,
        time: u64,
    }


    #[event]
    struct BridgeUpdateEvent2 has drop, store {
        message: String,
        poseidon_root: String,
    }
    #[event]
    struct VoteEvent has drop, store {
        validator: address,
        message: String,
        root: String,
        time: u64,
    }

    // === INIT === //
    fun init_module(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @dev, ERROR_NOT_ADMIN);
        move_to(admin,  States {table: table::new<u64, BridgeState>(), validations: table::new<String, Table<String, Validations>>()});
    }


    // === LOGIC === //

    /// Validators call this to "vote" on a new Shadow Root calculated by the relayer
    public entry fun validate_state(validator: &signer,epoch: u64, old_validator_root: String, s_r8x: String, s_r8y: String, s: String, message: String) acquires States {
        let addr = signer::address_of(validator);

        // 1. Obtain Parent info & Check if sender is valid parent (checked inside the return_parent_raw function)
        let (v_pub_key_x, v_pub_key_y, v_self_staked, v_total_stake, v_isActive, v_sub_validators) = validators::return_parent_raw(addr);
    
        // 3. Updating State (i.e innitializing the state if it doesn't exist)
        let state_table = borrow_global_mut<States>(@dev);
        if (!table::contains(&state_table.table, epoch)) {

            let bridge_state = BridgeState {
                root: old_validator_root,
                votes: 0,
                parents: map::new<address, ParentBody>(), 
            };
                table::add(&mut state_table.table, epoch, bridge_state);
        };
        let state = table::borrow_mut(&mut state_table.table, epoch);
        // 4. Vote mechanism
        state.votes = state.votes + 1;

        if (!map::contains_key(&state.parents   , &addr)) {
            let validator_index = map::length(&state.parents);
            map::add(&mut state.parents, addr, ParentBody {message: message, s_r8x: s_r8x, s_r8y: s_r8y, s: s, staked: v_total_stake, pub_key_x: v_pub_key_x , pub_key_y: v_pub_key_y, index:validator_index});
        };

        event::emit(VoteEvent {
            validator: addr,
            epoch: epoch,
            root: old_validator_root,
            time: timestamp::now_seconds(),
        });

        // 5. Threshold Check (e.g., 19/28 or > 2/3 of 64)
        if (state.votes >= 2) {
            // Emit the event that the Relayer uses to build the ZK Proof
            event::emit(BridgeUpdateEvent {
                epoch: epoch,
                poseidon_root: old_validator_root,
            });
        }
    }

    public entry fun validate(validator: &signer, type: String, old_validator_root: String, s_r8x: String, s_r8y: String, s: String, message: String, data: vector<vector<u8>>) acquires States {
        let addr = signer::address_of(validator);

        // 1. Obtain Parent info & Check if sender is valid parent (checked inside the return_parent_raw function)
        let (v_pub_key_x, v_pub_key_y, v_self_staked, v_total_stake, v_isActive, v_sub_validators) = validators::return_parent_raw(addr);
    
        // 3. Updating State (i.e innitializing the state if it doesn't exist)
        let state_table = borrow_global_mut<States>(@dev);


        if (!table::contains(&state_table.validations, type)) {
            table::add(&mut state_table.validations, type, table::new<String, Validations>());
        };

        let validations_table = table::borrow_mut(&mut state_table.validations, type);

        if (!table::contains(&validations_table.validations, message)) {

            let bridge_state = Validations {
                root: old_validator_root,
                data: data, 
                votes: 0,
                parents: map::new<address, ParentBody>(), 
            };

            table::add(&mut validations_table.validations, message, bridge_state);
        };
        let state = table::borrow_mut(&mut validations_table.validations, message);
        // 4. Vote mechanism
        state.votes = state.votes + 1;

        if (!map::contains_key(&state.parents   , &addr)) {
            let validator_index = map::length(&state.parents);
            map::add(&mut state.parents, addr, ParentBody {message: message, s_r8x: s_r8x, s_r8y: s_r8y, s: s, staked: v_total_stake, pub_key_x: v_pub_key_x , pub_key_y: v_pub_key_y, index:validator_index});
        };

        event::emit(VoteEvent2 {
            validator: addr,
            message message,
            root: old_validator_root,
            time: timestamp::now_seconds(),
        });

        // 5. Threshold Check (e.g., 19/28 or > 2/3 of 64)
        if (state.votes >= 2) {
            // Emit the event that the Relayer uses to build the ZK Proof
            event::emit(BridgeUpdateEvent2 {
                message: message,
                poseidon_root: old_validator_root,
            });
        }
    }


    public entry fun delete_validation(validator: &signer, epoch: u64) acquires States {
        let state_table = borrow_global_mut<States>(@dev);
        if (table::contains(&state_table.table, epoch)) {
            table::remove(&mut state_table.table, epoch);
        }
    }

    #[view]
    public fun return_state(epoch: u64): BridgeState acquires States {
        let state = borrow_global<States>(@dev);
        if(!table::contains(&state.table, epoch)) {
            abort ERROR_STATE_NOT_FOUND
        } else {
            *table::borrow(&state.table, epoch)
        }
    }

    #[view]
    public fun return_current_state(): BridgeState acquires States {
        let epoch = genesis::return_epoch();
        return return_state((epoch as u64))

    }

    #[view]
    public fun return_current_state(type: String, message: String): Validations acquires States {
        let state = borrow_global<States>(@dev);
        
        if (!table::contains(&state_table.validations, type)) {
            abort ERROR_INVALID_STATE_TYPE
        };

        let validations_table = table::borrow_mut(&mut state_table.validations, type);

        if (!table::contains(&validations_table.validations, message)) {
            abort ERROR_INVALID_MESSAGE
        };
        return *table::borrow_mut(&mut validations_table.validations, message);

    }

}