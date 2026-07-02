module dev::QiaraValidatorsV34 {
    use std::signer;
    use std::vector;
    use std::bcs;
    use aptos_std::table::{Self, Table};
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use std::string::{String, utf8};

    use event::QiaraEventV1::{Self as Event};
    use dev::QiaraMarginV23::{Self as Margin, Access as MarginAccess};
    use dev::QiaraSharedV8::{Self as Shared, Access as SharedAccess};
    use dev::QiaraGenesisV2::{Self as Genesis};
    use dev::QiaraStorageV11::{Self as storage};
    use dev::QiaraTokensQiaraV27::{Self as TokensQiara};
    use dev::QiaraTokensCoreV27::{Self as TokensCore, Access as TokensCoreAccess};
    // === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 0;
    const ERROR_NOT_VALIDATOR: u64 = 1;
    const ERROR_VALIDATOR_ALREADY_REGISTERED: u64 = 2;
    const ERROR_VALIDATOR_DOESNT_EXISTS: u64 = 3;
    const ERROR_NOT_REGISTERED_VALIDATOR: u64 = 4;
    const ERROR_NOT_STAKER: u64 = 5;
    const ERROR_KEYS_CANNOT_BE_EMPTY: u64 = 6;

    // === ACCESS === //
    struct Access has store, key, drop {}
    struct Permission has store, key, drop, copy {}

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @dev, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_permission(access: &Access): Permission {
        Permission {}
    }

    // === STRUCTS === //
    // list of all PENDING validators
    struct PendingValidators has key {
        list: vector<String>,
    }

    // list of all ACTIVE validators/relayers
    struct ActiveValidators has key {
        list: vector<String>,
        root: String,
        epoch: u64,
    }
    // list of all validators/relayers
    struct Validators has key {
        map: Map<String, Validator>,
    }
    struct Validator has key, store, copy, drop {
        pub_key: vector<u8>,
        pubkey_evm_address: vector<u8>,
        isActive: bool,
        last_active: u64,
        power: u256,
        snapshot: u64,
        total_power: u256, // stakers power + validator power
        stakers: Map<String, StakerData>,
    }

    struct StakerData has key, store, copy, drop {
        power: u256,
        snapshot: u64,
    }

    struct Permissions has key {
        shared: SharedAccess,
        margin: MarginAccess,
        tokens_core: TokensCoreAccess,
    }

    struct Stakers has key, store {
        table: Table<String, String>,
    }


    struct PerEpoch has copy,key, store{
        epoch: u64,
        total_credits: u256,
        emissions: u256,
        total_weight: u256,
        vote_weights: Map<String, u256>,
        total_staked: u256
    }
    // === INIT === //
    fun init_module(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @dev, ERROR_NOT_ADMIN);
        move_to(admin, ActiveValidators {list: vector::empty<String>(), root: utf8(b""), epoch: 0});
        move_to(admin, PendingValidators {list: vector::empty<String>()});
        move_to(admin, PerEpoch { epoch: (Genesis::return_epoch() as u64), total_credits: 0, emissions: (TokensQiara::calculate_emissions() as u256),  total_weight: 0, total_staked: Margin::get_total_staked_usd(), vote_weights: map::new<String, u256>()});
        move_to(admin, Validators {map: map::new<String, Validator>()});
        if (!exists<Stakers>(@dev)) {
            move_to(admin, Stakers { table: table::new<String, String>() });
        };
        if (!exists<Permissions>(@dev)) {
            move_to(admin, Permissions { shared: Shared::give_access(admin), margin: Margin::give_access(admin), tokens_core: TokensCore::give_access(admin)});
        };
    }

    // === PUBLIC FUNCTIONS === //

    public entry fun dev_register_validator(signer: &signer, shared: String, validator: vector<u8>, pub_key: vector<u8>,pubkey_evm_address: vector<u8>) acquires PendingValidators, ActiveValidators, Validators {
        Shared::assert_is_sub_owner(shared, validator);
        
        let active_validators = borrow_global_mut<ActiveValidators>(@dev); 
        let pending_validators = borrow_global_mut<PendingValidators>(@dev); 
        let validators = borrow_global_mut<Validators>(@dev);

        reg_validator(&mut pending_validators.list, active_validators, &mut validators.map, shared, pub_key, pubkey_evm_address);
    }

    // Interface for users/validators - Executes registration directly on-chain
    public entry fun register_validator(signer: &signer, shared: String, pub_key: vector<u8>, pubkey_evm_address: vector<u8>, power: u256) acquires PendingValidators, ActiveValidators, Validators {
        Shared::assert_is_sub_owner(shared, bcs::to_bytes(&signer::address_of(signer)));
        
        let active_validators = borrow_global_mut<ActiveValidators>(@dev); 
        let pending_validators = borrow_global_mut<PendingValidators>(@dev); 
        let validators = borrow_global_mut<Validators>(@dev);

        reg_validator(&mut pending_validators.list, active_validators, &mut validators.map, shared, pub_key, pubkey_evm_address);

    }

    // Interface for changing a staker's chosen validator on-chain
    public entry fun change_staker_validator(signer: &signer, shared: String, new_validator: String) acquires Permissions, PendingValidators, ActiveValidators, Validators, Stakers {
        Shared::assert_is_sub_owner(shared, bcs::to_bytes(&signer::address_of(signer)));
        Shared::update_selected_validator(shared, new_validator, Shared::give_permission(&borrow_global<Permissions>(@dev).shared));

        let active_validators = borrow_global_mut<ActiveValidators>(@dev); 
        let validators = borrow_global_mut<Validators>(@dev);
        let pending_validators = borrow_global_mut<PendingValidators>(@dev); 
        let stakers = borrow_global_mut<Stakers>(@dev);

        change_staker_validator_internal(
            shared, 
            new_validator, 
            active_validators, 
            &mut validators.map, 
            &mut pending_validators.list, 
            &mut stakers.table
        );

        let data = vector[
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"zk"))),
            Event::create_data_struct(utf8(b"validator"), utf8(b"vector<u8>"), bcs::to_bytes(&signer::address_of(signer))),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(utf8(b"new_validator"), utf8(b"string"), bcs::to_bytes(&new_validator)),
        ];
        Event::emit_consensus_event(utf8(b"Change Staker Validator"), data);
    }

     // Combined entry interface for altering validator keys on-chain
    public entry fun change_validator_keys(signer: &signer, shared: String, pub_key: vector<u8>, pubkey_evm_address: vector<u8>) acquires Validators {
        Shared::assert_is_sub_owner(shared, bcs::to_bytes(&signer::address_of(signer)));

        let is_pub_key_empty = vector::is_empty(&pub_key);
        let is_evm_empty = vector::is_empty(&pubkey_evm_address);
        assert!(!is_pub_key_empty || !is_evm_empty, ERROR_KEYS_CANNOT_BE_EMPTY);

        let validators = borrow_global_mut<Validators>(@dev); 
        if (!map::contains_key(&validators.map, &shared)) {
            abort ERROR_VALIDATOR_DOESNT_EXISTS
        };

        let validator_struct = map::borrow_mut(&mut validators.map, &shared);
        if (!is_pub_key_empty) {
            validator_struct.pub_key = pub_key;
        };
        if (!is_evm_empty) {
            validator_struct.pubkey_evm_address = pubkey_evm_address;
        };

        let data = vector[
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"zk"))),
            Event::create_data_struct(utf8(b"user"), utf8(b"vector<u8>"), bcs::to_bytes(&signer::address_of(signer))),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(utf8(b"pub_key"), utf8(b"vector<u8>"), bcs::to_bytes(&pub_key)),
            Event::create_data_struct(utf8(b"pubkey_evm_address"), utf8(b"vector<u8>"), bcs::to_bytes(&pubkey_evm_address)),
        ];
        Event::emit_consensus_event(utf8(b"Change Validator Keys"), data);
    }


    public entry fun take_snapshot(signer: &signer, shared: String) acquires PendingValidators, ActiveValidators, Validators {
        Shared::assert_is_sub_owner(shared, bcs::to_bytes(&signer::address_of(signer)));
        let active_validators = borrow_global_mut<ActiveValidators>(@dev); 
        let validators = borrow_global_mut<Validators>(@dev);
        let pending_validators = borrow_global_mut<PendingValidators>(@dev);

        take_validator_snapshot_internal(shared, &mut validators.map, &mut pending_validators.list, active_validators);
    } 

    // Updates a specific staker's power, updates their validator's total power, and triggers the ranking update
    public entry fun take_staker_snapshot(signer: &signer, staker: String) acquires PendingValidators, ActiveValidators, Validators, Stakers {
        Shared::assert_is_sub_owner(staker, bcs::to_bytes(&signer::address_of(signer)));
        
        let validators = borrow_global_mut<Validators>(@dev);
        let active_validators = borrow_global_mut<ActiveValidators>(@dev);
        let pending_validators = borrow_global_mut<PendingValidators>(@dev);
        let stakers = borrow_global_mut<Stakers>(@dev);

        assert!(table::contains(&stakers.table, staker), ERROR_NOT_STAKER);
        let validator = *table::borrow(&stakers.table, staker);

        assert!(map::contains_key(&validators.map, &validator), ERROR_VALIDATOR_DOESNT_EXISTS);
        let validator_struct = map::borrow_mut(&mut validators.map, &validator);
        
        let new_power = Margin::get_user_total_staked_usd(staker);
        let old_staker_power = 0;
        
        if (map::contains_key(&validator_struct.stakers, &staker)) {
            let staker_data = map::borrow(&validator_struct.stakers, &staker);
            old_staker_power = staker_data.power;
        };
        
        // Safely adjust total power with delta update (stakers power + validator power)
        if (validator_struct.total_power >= old_staker_power) {
            validator_struct.total_power = validator_struct.total_power - old_staker_power + new_power;
        } else {
            validator_struct.total_power = new_power;
        };
        
        let epoch = active_validators.epoch;
        let new_staker_data = StakerData {
            power: new_power,
            snapshot: epoch,
        };
        map::upsert(&mut validator_struct.stakers, staker, new_staker_data);
        
        // Re-evaluate validator snapshot and ranking
        take_validator_snapshot_internal(validator, &mut validators.map, &mut pending_validators.list, active_validators);
    }

    fun tttta(error: u64){
        abort error
    }

    // === INTERNAL FUNCTIONS === //
    fun reg_validator(pending_validators: &mut vector<String>, active_validators: &mut ActiveValidators, validators: &mut Map<String, Validator>, validator: String, pub_key: vector<u8>,pubkey_evm_address: vector<u8>) {
        if(map::contains_key(validators, &validator)) {
            abort ERROR_VALIDATOR_ALREADY_REGISTERED
        };

        let validator_struct = Validator { 
            pub_key: pub_key, 
            pubkey_evm_address: pubkey_evm_address, 
            isActive: true, 
            last_active: 0, 
            power: 0,
            snapshot: 0,
            total_power: 0,
            stakers: map::new<String, StakerData>() 
        };
        map::upsert(validators, validator, validator_struct);
        take_validator_snapshot_internal(validator, validators, pending_validators, active_validators);
    }

    fun change_staker_validator_internal(staker: String, new_validator: String, active_validators: &mut ActiveValidators, validators: &mut Map<String, Validator>, pending_validators: &mut vector<String>, stakers_table: &mut Table<String, String>) {
        // 1. Check if the staker was previously delegated to some old validator
        if (table::contains(stakers_table, staker)) {
            let old_validator = *table::borrow(stakers_table, staker);
            
            // If the old validator actually exists in our state map
            if (map::contains_key(validators, &old_validator)) {
                let old_val_struct = map::borrow_mut(validators, &old_validator);
                
                // Get the staker's power from the old validator's map
                let staker_power = 0;
                if (map::contains_key(&old_val_struct.stakers, &staker)) {
                    let staker_data = map::borrow(&old_val_struct.stakers, &staker);
                    staker_power = staker_data.power;
                    // Remove staker from old validator
                    map::remove(&mut old_val_struct.stakers, &staker);
                };
                
                // Subtract the staker's power from old validator's total power
                if (old_val_struct.total_power >= staker_power) {
                    old_val_struct.total_power = old_val_struct.total_power - staker_power;
                } else {
                    old_val_struct.total_power = 0;
                };

                // Trigger a snapshot for the old validator to evaluate their rank after losing power
                take_validator_snapshot_internal(old_validator, validators, pending_validators, active_validators);
            };
        };

        // 2. Add the staker to the new validator
        assert!(map::contains_key(validators, &new_validator), ERROR_NOT_REGISTERED_VALIDATOR);
        
        // Fetch the staker's current power from Margin
        let current_staker_power = Margin::get_user_total_staked_usd(staker);
        
        let new_val_struct = map::borrow_mut(validators, &new_validator);
        
        // Add staker to new validator's map
        let new_staker_data = StakerData {
            power: current_staker_power,
            snapshot: active_validators.epoch
        };
        map::upsert(&mut new_val_struct.stakers, staker, new_staker_data);
        
        // Add staker's power to new validator's total power
        new_val_struct.total_power = new_val_struct.total_power + current_staker_power;
        
        // Update the global lookup delegation mapping
        table::upsert(stakers_table, staker, new_validator);
        
        // Trigger snapshot evaluation for the new validator since their power increased
        take_validator_snapshot_internal(new_validator, validators, pending_validators, active_validators);
    }

    fun take_validator_snapshot_internal(validator: String, validators: &mut Map<String, Validator>, pending_validators: &mut vector<String>, active_validators: &mut ActiveValidators) {
        let own_power = Margin::get_user_total_staked_usd(validator);
        
        let pub_key;
        let pubkey_evm_address;
        let total_power;

        // Scope the mutable borrow so it is released immediately after these updates
        {
            let validator_struct = map::borrow_mut(validators, &validator);
            let old_own_power = validator_struct.power;
            validator_struct.power = own_power;
            if (validator_struct.total_power >= old_own_power) {
                validator_struct.total_power = validator_struct.total_power - old_own_power + own_power;
            } else {
                validator_struct.total_power = own_power;
            };
            validator_struct.snapshot = active_validators.epoch;

            total_power = validator_struct.total_power;
            pub_key = *&validator_struct.pub_key;
            pubkey_evm_address = *&validator_struct.pubkey_evm_address;
        }; // The mutable borrow of `validators` is completely released here

        let len = vector::length(pending_validators);
        let i = 0;
        let already_exists = false;

        // Check if the validator is already in the pending list
        while (i < len) {
            let val = vector::borrow(pending_validators, i);
            if (val == &validator) {
                already_exists = true;
                break
            };
            i = i + 1;
        };

        let deleted_validator = utf8(b"");
        if (!already_exists) {
            if (len < 16) {
                // Case A: Room in the list, just add them
                vector::push_back(pending_validators, validator);
            } else {
                // Case B: List is full (16), find the weakest validator
                let min_power = total_power;
                let weakest_index = 0;
                let found_weakest = false;
                
                let j = 0;
                while (j < len) {
                    let current_pending = vector::borrow(pending_validators, j);
                    let current_validator_struct = map::borrow(validators, current_pending);
                    let current_power = current_validator_struct.total_power;
                    if (current_power < min_power) {
                        min_power = current_power;
                        weakest_index = j;
                        found_weakest = true;
                    };
                    j = j + 1;
                };

                // If we found someone weaker than the new validator, replace them
                if (found_weakest) {
                    deleted_validator = vector::remove(pending_validators, weakest_index);
                    vector::push_back(pending_validators, validator);
                };
            };

            let data = vector[
                Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"zk"))),
                Event::create_data_struct(utf8(b"new_validator"), utf8(b"string"), bcs::to_bytes(&validator)),
                Event::create_data_struct(utf8(b"deleted_validator"), utf8(b"string"), bcs::to_bytes(&deleted_validator)),
                Event::create_data_struct(utf8(b"pub_key"), utf8(b"vector<u8>"), bcs::to_bytes(&pub_key)),
                Event::create_data_struct(utf8(b"pubkey_evm_address"), utf8(b"vector<u8>"), bcs::to_bytes(&pubkey_evm_address)),
            ];
            Event::emit_consensus_event(utf8(b"Register Validator"), data);
        };

        // Update active list if epoch progressed
        if (Genesis::return_epoch() > (active_validators.epoch as u256)) {
            let vect = vector::empty<String>();
            let len = vector::length(pending_validators);
            while(len > 0){
                let xv = vector::borrow(pending_validators, len-1);
                vector::push_back(&mut vect, *xv);
                len = len - 1;
            };
            active_validators.list = vect;
            active_validators.epoch = (Genesis::return_epoch() as u64);
        };
    }

    // === VIEW FUNCTIONS === //
    #[view]
    public fun return_all_validators(): Map<String, Validator> acquires Validators {
        let vars = borrow_global<Validators>(@dev);
        vars.map 
    }

    #[view]
    public fun return_all_active_parents(): vector<String> acquires ActiveValidators {
        let vars = borrow_global<ActiveValidators>(@dev);
        vars.list 
    }

    #[view]
    public fun return_all_active_validators_full(): (Map<String, Validator>, u64) acquires ActiveValidators, Validators {
        let vars = borrow_global<ActiveValidators>(@dev);
        let validators = borrow_global<Validators>(@dev);
        let map = map::new<String, Validator>();

        let length = vector::length(&vars.list);
        while(length > 0) {
            let validator_addr = vector::borrow(&vars.list, length-1);
            let validator = return_validator(*validator_addr);
            map::add(&mut map, *validator_addr, validator);
            length = length - 1;
        };
        (map, vars.epoch)
    }

    #[view]
    public fun return_certain_validators(certain_validators: vector<String>): Map<String, Validator> acquires Validators {
        let validators = map::keys(&borrow_global<Validators>(@dev).map);
        let map = map::new<String, Validator>();

        let length = vector::length(&validators);
        while(length > 0) {
            let validator_addr = vector::borrow(&validators, length-1);
            if(vector::contains(&certain_validators, validator_addr)) {
                let validator = return_validator(*validator_addr);
                map::add(&mut map, *validator_addr, validator);
            };
            length = length - 1;
        };
        (map)
    }

    #[view]
    public fun return_validator(val: String): Validator acquires Validators {
        let vars = borrow_global<Validators>(@dev);
        if(!map::contains_key(&vars.map, &val)) {
            abort ERROR_VALIDATOR_DOESNT_EXISTS
        };
        return *map::borrow(&vars.map, &val)
    }

    #[view]
    public fun return_all_pending_validators(val: String): vector<String> acquires PendingValidators {
        let vars = borrow_global<PendingValidators>(@dev);
        return vars.list
    }

    #[view]
    public fun return_per_epoch(): PerEpoch acquires PerEpoch {
        let vars = borrow_global<PerEpoch>(@dev);
        return *vars
    }

    #[view]
    public fun return_validator_raw(val: String): (vector<u8>, vector<u8>, bool, u256, u64, u256, Map<String, StakerData>) acquires Validators {
        let vars = borrow_global<Validators>(@dev);
        if(!map::contains_key(&vars.map, &val)) {
            abort ERROR_VALIDATOR_DOESNT_EXISTS
        };
        let validator  = map::borrow(&vars.map, &val);
        return (validator.pubkey_evm_address, validator.pub_key, validator.isActive, validator.power, validator.snapshot, validator.total_power, validator.stakers)
    }

    public fun acrue_modularity_fee(shared: String, user: vector<u8>) acquires Permissions, PerEpoch{
        let per_epoch = borrow_global_mut<PerEpoch>(@dev);
        let flat_usd_fee = (storage::expect_u64(storage::viewConstant(utf8(b"QiaraBridge"), utf8(b"FLAT_USD_FEE"))) as u256);
        Margin::remove_credit(shared, user, flat_usd_fee, Margin::give_permission(&borrow_global<Permissions>(@dev).margin));
        per_epoch.total_credits = per_epoch.total_credits + flat_usd_fee;
    }

    public fun acrue_vote(shared: String, user: vector<u8>, vote_weight: u256) acquires PerEpoch, Permissions {
        let per_epoch = borrow_global_mut<PerEpoch>(@dev);
        let permissions = borrow_global<Permissions>(@dev);

        // Check if this voter has already voted during the current epoch
        if (map::contains_key(&per_epoch.vote_weights, &shared)) {
            // If the voter exists, retrieve a mutable reference to their weight and add the new weight
            let current_weight = map::borrow_mut(&mut per_epoch.vote_weights, &shared);
            *current_weight = *current_weight + vote_weight;
        } else {
            // If they don't exist, insert them as a new voter
            map::add(&mut per_epoch.vote_weights, shared, vote_weight);
        };

        // Update the sum of all vote weights for the epoch to keep the reward pool calculations accurate
        per_epoch.total_weight = per_epoch.total_weight + vote_weight;
        per_epoch.total_staked = (Margin::get_total_staked_usd() as u256);
        distribute_rewards(per_epoch, permissions);

    }


    fun distribute_rewards(per_epoch: &mut PerEpoch, permissions: &Permissions) {
        let current_epoch = (Genesis::return_epoch() as u64);

        if (Genesis::return_epoch() > (per_epoch.epoch as u256)) {
            per_epoch.epoch = current_epoch;
        } else {
            return
        };
        
        // Avoid division by zero
        if (per_epoch.total_weight == 0) {
            return
        };

        // Extracted keys from the map; map::keys returns a copy (by value)
        let validators = map::keys(&per_epoch.vote_weights);
        let len = vector::length(&validators);

        while (len > 0) {
            let voter = *vector::borrow(&validators, len - 1);
            let weight = *map::borrow(&per_epoch.vote_weights, &voter);

            // Calculate reward with safe order of operations to avoid precision loss
            let validator_emission_reward = (weight * per_epoch.emissions) / per_epoch.total_weight;
            let validator_credit_reward = (weight * per_epoch.total_credits) / per_epoch.total_weight;

            let user_addr = Shared::return_shared_owner(voter);

            Margin::add_credit(
                voter, 
                user_addr, 
                validator_credit_reward, 
                Margin::give_permission(&permissions.margin)
            );
            TokensCore::mint_qiara(
                voter,  
                user_addr,
                (validator_emission_reward as u64), 
                TokensCore::give_permission(&permissions.tokens_core)
            );
            len = len - 1;
        };

        // === RESET STATE FOR THE NEW EPOCH ===
        
        // 1. Reset credits and weights back to 0
        per_epoch.total_credits = 0;
        per_epoch.total_weight = 0;

        // 2. Clear all previous votes so validators must be voted on again
        per_epoch.vote_weights = map::new<String, u256>();

        // 3. Set the new emissions for the upcoming epoch.
        per_epoch.emissions = (TokensQiara::calculate_emissions() as u256); 

    }

}