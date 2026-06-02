module dev::QiaraValidatorsV16 {
    use std::signer;
    use std::vector;
    use std::bcs;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use std::string::{String, utf8};

    use event::QiaraEventV1::{Self as Event};
    use dev::QiaraMarginV8::{Self as Margin};
    use dev::QiaraSharedV3::{Self as Shared};
    use dev::QiaraGenesisV2::{Self as Genesis};

    // === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 0;
    const ERROR_NOT_VALIDATOR: u64 = 1;
    const ERROR_VALIDATOR_ALREADY_REGISTERED: u64 = 2;
    const ERROR_VALIDATOR_DOESNT_EXISTS: u64 = 3;
    const ERROR_NOT_REGISTERED_VALIDATOR: u64 = 4;
    const ERROR_NOT_STAKER: u64 = 5;

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
    // list of all ACTIVE validators
    struct ActiveValidators has key {
        list: vector<String>,
        root: String,
        epoch: u64,
    }
    // list of all existing validators
    struct Validators has key {
        map: Map<String, Validator>,
    }

    struct Validator has key, store, copy, drop {
        secp256k1_pub_key: vector<u8>,
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

    // === INIT === //
    fun init_module(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @dev, ERROR_NOT_ADMIN);
        move_to(admin, ActiveValidators {list: vector::empty<String>(), root: utf8(b""), epoch: 0});
        move_to(admin, PendingValidators {list: vector::empty<String>()});
        move_to(admin, Validators {map: map::new<String, Validator>()});
    }

    // === PUBLIC FUNCTIONS === //

    public entry fun dev_register_validator(signer: &signer, shared: String, validator: vector<u8>, secp256k1_pub_key: vector<u8>) acquires PendingValidators, ActiveValidators, Validators {
        let admin_addr = signer::address_of(signer);
        assert!(admin_addr == @dev, ERROR_NOT_ADMIN);
        Shared::assert_is_sub_owner(shared, validator);
        
        let active_validators = borrow_global_mut<ActiveValidators>(@dev); 
        let pending_validators = borrow_global_mut<PendingValidators>(@dev); 
        let validators = borrow_global_mut<Validators>(@dev);

        reg_validator(&mut pending_validators.list, active_validators, &mut validators.map, shared, secp256k1_pub_key);
    }

    // Interface for users/validators
    public entry fun register_validator(signer: &signer, shared: String, secp256k1_pub_key: vector<u8>, power: u256) {
        Shared::assert_is_sub_owner(shared, bcs::to_bytes(&signer::address_of(signer)));
        let data = vector[
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"zk"))),
            Event::create_data_struct(utf8(b"validator"), utf8(b"vector<u8>"), bcs::to_bytes(&signer::address_of(signer))),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(utf8(b"secp256k1_pub_key"), utf8(b"string"), bcs::to_bytes(&secp256k1_pub_key)),
            Event::create_data_struct(utf8(b"power"), utf8(b"u256"), bcs::to_bytes(&power)),
        ];
        Event::emit_consensus_event(utf8(b"Register Validator"), data);
    }

    public entry fun change_staker_validator(signer: &signer, shared: String, new_validator: String){
        Shared::assert_is_sub_owner(shared, bcs::to_bytes(&signer::address_of(signer)));
        let data = vector[
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"zk"))),
            Event::create_data_struct(utf8(b"validator"), utf8(b"vector<u8>"), bcs::to_bytes(&signer::address_of(signer))),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(utf8(b"new_validator"), utf8(b"string"), bcs::to_bytes(&new_validator)),
        ];
        Event::emit_consensus_event(utf8(b"Change Staker Validator"), data);
    }

    public entry fun take_validator_snapshot(signer: &signer, shared: String) acquires PendingValidators, ActiveValidators, Validators {
        Shared::assert_is_sub_owner(shared, bcs::to_bytes(&signer::address_of(signer)));
        let active_validators = borrow_global_mut<ActiveValidators>(@dev); 
        let validators = borrow_global_mut<Validators>(@dev);
        let pending_validators = borrow_global_mut<PendingValidators>(@dev);

        take_validator_snapshot_internal(shared, &mut validators.map, &mut pending_validators.list, active_validators);
    } 

    // Updates a specific staker's power, updates the validator's total power, and triggers the validator ranking update
    public entry fun take_staker_snapshot(signer: &signer, validator: String, staker: String) acquires PendingValidators, ActiveValidators, Validators {
        Shared::assert_is_sub_owner(staker, bcs::to_bytes(&signer::address_of(signer)));
        
        let validators = borrow_global_mut<Validators>(@dev);
        let active_validators = borrow_global_mut<ActiveValidators>(@dev);
        let pending_validators = borrow_global_mut<PendingValidators>(@dev);

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

    // Interface for consensus
    public fun c_register_validator(
        signer: &signer, 
        shared: String, 
        validator: vector<u8>, 
        secp256k1_pub_key: vector<u8>, 
        _perm: Permission
    ) acquires PendingValidators, ActiveValidators, Validators {
        Shared::assert_is_sub_owner(shared, bcs::to_bytes(&validator));    
        let active_validators = borrow_global_mut<ActiveValidators>(@dev);
        let pending_validators = borrow_global_mut<PendingValidators>(@dev); 
        let validators = borrow_global_mut<Validators>(@dev);

        reg_validator(&mut pending_validators.list, active_validators, &mut validators.map, shared, secp256k1_pub_key);
    }

    public fun c_update_root(signer: &signer, shared: String, new_root: String, _perm: Permission) acquires ActiveValidators {
        Shared::assert_is_sub_owner(shared, bcs::to_bytes(&signer::address_of(signer)));
        let active_validators = borrow_global_mut<ActiveValidators>(@dev); 
        active_validators.root = new_root;
    }

    fun tttta(error: u64){
        abort error
    }

    // === INTERNAL FUNCTIONS === //
    fun reg_validator(
        pending_validators: &mut vector<String>, 
        active_validators: &mut ActiveValidators, 
        validators: &mut Map<String, Validator>, 
        validator: String, 
        secp256k1_pub_key: vector<u8>
    ) {
        if (map::contains_key(validators, &validator)) {
            abort ERROR_VALIDATOR_ALREADY_REGISTERED
        };

        let validator_struct = Validator { 
            secp256k1_pub_key, 
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

    fun take_validator_snapshot_internal(
        validator: String, 
        validators: &mut Map<String, Validator>, 
        pending_validators: &mut vector<String>, 
        active_validators: &mut ActiveValidators
    ) {
        let validator_struct = map::borrow_mut(validators, &validator);
        let own_power = Margin::get_user_total_staked_usd(validator);
        
        let old_own_power = validator_struct.power;
        validator_struct.power = own_power;
        if (validator_struct.total_power >= old_own_power) {
            validator_struct.total_power = validator_struct.total_power - old_own_power + own_power;
        } else {
            validator_struct.total_power = own_power;
        };
        validator_struct.snapshot = active_validators.epoch;

        let total_power = validator_struct.total_power;
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

        if (!already_exists) {
            if (len < 16) {
                // Case A: Room in the list, just add them
                vector::push_back(pending_validators, validator);

                // --- IMMEDIATE EVENT EMISSION (ADDITION) ---
                let empty_str = utf8(b"");
                let data = vector[
                    Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"zk"))),
                    Event::create_data_struct(utf8(b"epoch"), utf8(b"u64"), bcs::to_bytes(&active_validators.epoch)),
                    Event::create_data_struct(utf8(b"new_validator"), utf8(b"String"), bcs::to_bytes(&validator)),
                    Event::create_data_struct(utf8(b"deleted_validator"), utf8(b"String"), bcs::to_bytes(&empty_str)),
                ];
                Event::emit_validators_event(utf8(b"Validator Change"), data);

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
                    let removed_validator = *vector::borrow(pending_validators, weakest_index);

                    vector::remove(pending_validators, weakest_index);
                    vector::push_back(pending_validators, validator);

                    // --- IMMEDIATE EVENT EMISSION (REPLACEMENT) ---
                    let data = vector[
                        Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"zk"))),
                        Event::create_data_struct(utf8(b"epoch"), utf8(b"u64"), bcs::to_bytes(&active_validators.epoch)),
                        Event::create_data_struct(utf8(b"new_validator"), utf8(b"String"), bcs::to_bytes(&validator)),
                        Event::create_data_struct(utf8(b"deleted_validator"), utf8(b"String"), bcs::to_bytes(&removed_validator)),
                    ];
                    Event::emit_validators_event(utf8(b"Validator Change"), data);
                };
            };
        };

        // Update last active if epoch progressed (strictly state-syncing, no emission)
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

    fun obtain_validator(validators: &Map<String, Validator>, validator: String): Validator {
        if(!map::contains_key(validators, &validator)) {
            abort ERROR_VALIDATOR_DOESNT_EXISTS
        };
        *map::borrow(validators, &validator)
    }

    public entry fun test_validators_change(new_validator: vector<u8>, removed_validator: vector<u8>, epoch: u64) {
        let data = vector[
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"zk"))),
            Event::create_data_struct(utf8(b"epoch"), utf8(b"u64"), bcs::to_bytes(&epoch)),
            Event::create_data_struct(utf8(b"new_validator"), utf8(b"vector<u8>"), bcs::to_bytes(&new_validator)),
            Event::create_data_struct(utf8(b"deleted_validator"), utf8(b"vector<u8>"), bcs::to_bytes(&removed_validator)),
        ];
        Event::emit_validators_event(utf8(b"Validator Change"), data);
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
    public fun return_validator_raw(val: String): (vector<u8>, bool, Map<String, StakerData>) acquires Validators {
        let vars = borrow_global<Validators>(@dev);
        if(!map::contains_key(&vars.map, &val)) {
            abort ERROR_VALIDATOR_DOESNT_EXISTS
        };
        let validator = map::borrow(&vars.map, &val);
        return (validator.secp256k1_pub_key, validator.isActive, validator.stakers)
    }
}