module dev::QiaraValidatorsV5 {
    use std::signer;
    use std::vector;
    use std::bcs;
    use std::timestamp;
    use aptos_std::ed25519;
    use aptos_std::table::{Self, Table};
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use std::string::{Self as String, String, utf8};

    use event::QiaraEventV1::{Self as Event};
    use dev::QiaraMarginV2::{Self as Margin};

    use dev::QiaraSharedV1::{Self as Shared};

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
    struct PendingValidators has key {
        list: vector<PendingValidator>,
    }

    struct PendingValidator has store, copy, drop, key {
        shared: String,
        power: u256,
        snapshot: u64,
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
        pub_key_y: String,
        pub_key_x: String,
        pub_key: vector<u8>,
        isActive: bool,
        last_active: u64,
        sub_validators: Map<String, u256>,
    }


    struct Stakers has key, store {
        table: Table<String, String>,
    }

// === INIT === //
    fun init_module(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @dev, ERROR_NOT_ADMIN);
        move_to(admin, ActiveValidators {list: vector::empty<String>(), root: utf8(b""), epoch: 0});
        move_to(admin, PendingValidators {list: vector::empty<PendingValidator>()});
        move_to(admin, Validators {map: map::new<String, Validator>()});
        if (!exists<Stakers>(@dev)) {
            move_to(admin, Stakers { table: table::new<String, String>() });
        };
    }

// === PUBLIC FUNCTIONS === //

    public entry fun dev_register_validator(signer: &signer, shared: String, validator: vector<u8>, pub_key_x: String, pub_key_y: String, pub_key: vector<u8>) acquires PendingValidators, ActiveValidators, Validators {
        Shared::assert_is_sub_owner(shared, validator);
        
        let active_validators = borrow_global_mut<ActiveValidators>(@dev); 
        let pending_validators = borrow_global_mut<PendingValidators>(@dev); 
        let validators = borrow_global_mut<Validators>(@dev);
         //       tttta(98000);
        reg_validator(&mut pending_validators.list, active_validators, &mut validators.map, shared, pub_key_x, pub_key_y, pub_key);


    }

    // Interface for users/validators
    public entry fun register_validator(signer: &signer, shared: String, pub_key_x: String, pub_key_y: String, pub_key: vector<u8>, power:u256) {
        Shared::assert_is_sub_owner(shared, bcs::to_bytes(&signer::address_of(signer)));
        let data = vector[
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"zk"))),
            Event::create_data_struct(utf8(b"validator"), utf8(b"vector<u8>"), bcs::to_bytes(&signer::address_of(signer))),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(utf8(b"pub_key_x"), utf8(b"string"), bcs::to_bytes(&pub_key_x)),
            Event::create_data_struct(utf8(b"pub_key_y"), utf8(b"string"), bcs::to_bytes(&pub_key_y)),
            Event::create_data_struct(utf8(b"pub_key"), utf8(b"vector<u8>"), bcs::to_bytes(&pub_key)),
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
    public entry fun change_validator_poseidon_pubkeys(signer: &signer, shared: String, pub_key_x: String, pub_key_y: String) {
        Shared::assert_is_sub_owner(shared, bcs::to_bytes(&signer::address_of(signer)));
        let data = vector[
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"zk"))),
            Event::create_data_struct(utf8(b"user"), utf8(b"vector<u8>"), bcs::to_bytes(&signer::address_of(signer))),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(utf8(b"pub_key_x"), utf8(b"string"), bcs::to_bytes(&pub_key_x)),
            Event::create_data_struct(utf8(b"pub_key_y"), utf8(b"string"), bcs::to_bytes(&pub_key_y)),
        ];
        Event::emit_consensus_event(utf8(b"Change Validator Poseidon Pubkeys"), data);
    }
    public entry fun change_validator_pubkey(signer: &signer,  shared: String,  pub_key: vector<u8>) acquires Validators {
        Shared::assert_is_sub_owner(shared, bcs::to_bytes(&signer::address_of(signer)));

        let validators = borrow_global_mut<Validators>(@dev); 
        
        if(!map::contains_key(&mut validators.map, &shared)) {
            abort ERROR_VALIDATOR_DOESNT_EXISTS
        };

        let validator = map::borrow_mut(&mut validators.map, &shared);
        validator.pub_key = pub_key;

        let data = vector[
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"zk"))),
            Event::create_data_struct(utf8(b"user"), utf8(b"address"), bcs::to_bytes(&signer::address_of(signer))),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(utf8(b"pub_key"), utf8(b"string"), bcs::to_bytes(&pub_key)),
        ];
        Event::emit_consensus_event(utf8(b"Change Validator Pubkey"), data);
    }
    public entry fun take_snapshot(signer: &signer, shared: String)  acquires PendingValidators, ActiveValidators, Validators {
        Shared::assert_is_sub_owner(shared, bcs::to_bytes(&signer::address_of(signer)));
        let active_validators = borrow_global_mut<ActiveValidators>(@dev); 
        let validators = borrow_global_mut<Validators>(@dev);
        let pending_validators = borrow_global_mut<PendingValidators>(@dev);

        take_validator_snapshot(shared, &mut validators.map, &mut pending_validators.list, active_validators);


    } 
//0x36316438323437666330346330393961383431336433616430623535383537363739373465383834383161666534353239323236613362623066646639356632
//0x36316438323437666330346330393961383431336433616430623535383537363739373465383834383161666534353239323236613362623066646639356632
    // Interface for consensus
    public fun c_register_validator(signer: &signer, shared: String, validator: vector<u8>, pub_key_x: String, pub_key_y: String, pub_key: vector<u8>, perm: Permission) acquires PendingValidators, ActiveValidators, Validators {
        Shared::assert_is_sub_owner(shared, bcs::to_bytes(&validator));    
        let active_validators = borrow_global_mut<ActiveValidators>(@dev);
        let pending_validators = borrow_global_mut<PendingValidators>(@dev); 
        let validators = borrow_global_mut<Validators>(@dev);

        reg_validator(&mut pending_validators.list, active_validators, &mut validators.map, shared, pub_key_x, pub_key_y, pub_key);

    }
    public fun c_change_staker_validator(signer: &signer, shared: String, validator: vector<u8>, new_validator: String, perm: Permission) acquires PendingValidators, ActiveValidators, Validators, Stakers {
        Shared::assert_is_sub_owner(shared, bcs::to_bytes(&validator));
        let active_validators = borrow_global_mut<ActiveValidators>(@dev); 
        let validators = borrow_global_mut<Validators>(@dev);
        let pending_validators = borrow_global_mut<PendingValidators>(@dev); 
        let stakers = borrow_global_mut<Stakers>(@dev);

        if(!table::contains(&stakers.table, shared)) {
            abort ERROR_NOT_STAKER
        };

        if(!map::contains_key(&validators.map, &new_validator)) {
            abort ERROR_NOT_REGISTERED_VALIDATOR
        };

        let staker = table::borrow_mut(&mut stakers.table, shared);
        table::upsert(&mut stakers.table, shared, new_validator);

        let validator = map::borrow_mut(&mut validators.map, &new_validator);
        if(validator.isActive) {
            take_validator_snapshot(new_validator, &mut validators.map, &mut pending_validators.list, active_validators);
        }
    }
    public fun c_change_validator_poseidon_pubkeys(signer: &signer, shared: String, validator: vector<u8>, pub_key_x: String, pub_key_y: String, perm: Permission) acquires Validators {
        Shared::assert_is_sub_owner(shared, bcs::to_bytes(&validator));
        let validators = borrow_global_mut<Validators>(@dev); 
        
        if(!map::contains_key(&mut validators.map, &shared)) {
            abort ERROR_VALIDATOR_DOESNT_EXISTS
        };

        let validator = map::borrow_mut(&mut validators.map, &shared);
        validator.pub_key_x = pub_key_x;
        validator.pub_key_y = pub_key_y;
    }
    public fun c_change_validator_pubkey(signer: &signer,  shared: String, validator: vector<u8>, pub_key: vector<u8>, perm: Permission) acquires Validators {
        Shared::assert_is_sub_owner(shared, bcs::to_bytes(&validator));
        let validators = borrow_global_mut<Validators>(@dev); 
        
        if(!map::contains_key(&mut validators.map, &shared)) {
            abort ERROR_VALIDATOR_DOESNT_EXISTS
        };

        let validator = map::borrow_mut(&mut validators.map, &shared);
        validator.pub_key = pub_key;
    }

    public fun c_update_root(signer: &signer, shared: String, new_root: String, perm: Permission) acquires ActiveValidators {
        Shared::assert_is_sub_owner(shared, bcs::to_bytes(&signer::address_of(signer)));
        let active_validators = borrow_global_mut<ActiveValidators>(@dev); 
        active_validators.root = new_root;
    }

    fun tttta(error: u64){
        abort error
    }

// === INTERNAL FUNCTIONS === //
    fun reg_validator(pending_validators: &mut vector<PendingValidator>, active_validators: &mut ActiveValidators, validators: &mut Map<String, Validator>, validator: String, pub_key_x: String, pub_key_y: String, pub_key: vector<u8>) {
        if(map::contains_key(validators, &validator)) {
            abort ERROR_VALIDATOR_ALREADY_REGISTERED
        };

        let validator_struct = Validator { pub_key: pub_key, pub_key_x: pub_key_x, pub_key_y: pub_key_y, isActive: true, last_active: 0, sub_validators: map::new<String, u256>() };
        map::upsert(validators, validator, validator_struct);
        take_validator_snapshot(validator, validators, pending_validators, active_validators);
    }


    fun take_validator_snapshot(validator: String, validators: &mut Map<String, Validator>, pending_validators: &mut vector<PendingValidator>, active_validators: &mut ActiveValidators) {
        let validator_struct = map::borrow_mut(validators, &validator);
        let power = Margin::get_user_total_staked_usd(validator);
        
        let len = vector::length(pending_validators);
        let i = 0;
        let already_exists = false;

        // 1. Check if the validator is already in the pending list
        while (i < len) {
            let val = vector::borrow(pending_validators, i);
            if (val.shared == validator) {
                already_exists = true;
                break
            };
            i = i + 1;
        };

        if (!already_exists) {
            if (len < 16) {
                // Case A: Room in the list, just add them
                vector::push_back(pending_validators, PendingValidator { 
                    shared: validator, 
                    power: power, 
                    snapshot: active_validators.epoch 
                });
            } else {
                // Case B: List is full (16), find the weakest validator
                let min_power = power;
                let weakest_index = 0;
                let found_weakest = false;
                
                let j = 0;
                while (j < len) {
                    let current_pending = vector::borrow(pending_validators, j);
                    if (current_pending.power < min_power) {
                        min_power = current_pending.power;
                        weakest_index = j;
                        found_weakest = true;
                    };
                    j = j + 1;
                };

                // If we found someone weaker than the new validator, replace them
                if (found_weakest) {
                    vector::remove(pending_validators, weakest_index);
                    vector::push_back(pending_validators, PendingValidator { 
                        shared: validator, 
                        power: power, 
                        snapshot: active_validators.epoch 
                    });
                };
            };
        };

        // Update last active if epoch progressed
        if (Genesis::return_epoch() > (active_validators.epoch as u256)) {

            let vect = vector::empty<String>();
            let len = vector::length(pending_validators);
            while(len>0){
                let xv = vector::borrow(pending_validators, len-1);
                vector::push_back(&mut vect, xv.shared);
                len=len-1;
            };
            active_validators.list = vect;
        };
    }


    fun obtain_validator(validators: &Map<String, Validator>, validator: String): Validator {
        if(!map::contains_key(validators, &validator)) {
            abort ERROR_VALIDATOR_DOESNT_EXISTS
        };
        *map::borrow(validators, &validator)
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
    public fun return_validator_raw(val: String): (String, String, vector<u8>, bool, Map<String, u256>) acquires Validators {
        let vars = borrow_global<Validators>(@dev);
        if(!map::contains_key(&vars.map, &val)) {
            abort ERROR_VALIDATOR_DOESNT_EXISTS
        };
        let validator  = map::borrow(&vars.map, &val);
        return (validator.pub_key_x, validator.pub_key_y,validator.pub_key, validator.isActive, validator.sub_validators)
    }

}