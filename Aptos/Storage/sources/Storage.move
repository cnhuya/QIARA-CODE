module dev::QiaraStorageV13 {
    use std::string::{Self, String, utf8, bytes as b};
    use std::signer;
    use std::vector;
    use aptos_framework::event;
    use std::table::{Self, Table};
    use aptos_std::type_info;
    use aptos_std::from_bcs;
    use std::bcs::{Self as bc};
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    struct Access has key, store, drop { }
    struct Permission has key, drop { }

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @dev, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_permission(access: &Access): Permission {
        Permission {}
    }

    struct KeyRegistry has key {
        keys: vector<String>,
    }


    struct ConstantCounter has key{
        count: u64
    }

    struct ConstantDatabase has key {
        database: Table<String, vector<Constant>>
    }

    struct Constant has store, drop, copy {
        name: String,
        value: Any,
        editable: bool,
        index: u64
    }

    struct U8 has store, key { } 
    struct U16 has store, key { } 
    struct U32 has store, key { } 
    struct U64 has store, key { } 
    struct U128 has store, key { } 
    struct U256 has store, key { } 
    struct Address has store, key { } 
    struct Bool has store, key { } 

    // u8 = 1 byte (LENGTH)

    struct Any has drop, store, copy { type: String, data: vector<u8> }

    #[event]
    struct ConstantChange has drop, store {
        address: address,
        old_constant: Constant,
        new_constant: Constant
    }

    const OWNER: address = @dev;
    const ERROR_CONSTANT_DOES_NOT_EXIST: u64 = 2;
    const ERROR_NOT_ADMIN: u64 = 3;
    const ERROR_CONSTANT_CANT_BE_EDITED: u64 = 4;
    const ERROR_HEADER_DOESNT_EXISTS: u64 = 5;
    const ERROR_CONSTANT_ALREADY_EXISTS: u64 = 6;
    const ERROR_INVALID_VALUE_TYPE: u64 = 7;
    const ERROR_VALUE_NOT_IN_VECTOR: u64 = 8;

    fun make_constant(name: String, value: Any, editable: bool, index: u64): Constant {
        Constant { name, value, editable, index }
    }

    fun make_any<T>(value: vector<u8>): Any {
        Any { type: type_info::type_name<T>(), data: value }
    }


    // ----------------------------------------------------------------
    // Module init
    // ----------------------------------------------------------------
    fun init_module(admin: &signer){
        assert!(signer::address_of(admin) == OWNER, ERROR_NOT_ADMIN);

        if (!exists<ConstantDatabase>(OWNER)) {
            move_to(
                admin,
                ConstantDatabase { database: table::new<String, vector<Constant>>() }
            );
        };

        if (!exists<KeyRegistry>(OWNER)) {
            move_to(
                admin,
                KeyRegistry {keys: vector::empty<String>() }
            );
        };

        if (!exists<ConstantCounter>(OWNER)) {
            move_to(
                admin,
                ConstantCounter {count: 0 }
            );
        };
        // 6 DECIMALS
        // 1% = 1_000_000

    }

    public entry fun more(admin: &signer) acquires KeyRegistry, ConstantDatabase, ConstantCounter{
        assert!(signer::address_of(admin) == OWNER, ERROR_NOT_ADMIN);

        register_constant<u64>(admin, utf8(b"QiaraToken"), utf8(b"MINIMAL_INFLATION"), 1_000_000, true, &give_permission(&give_access(admin))); // 1%
        register_constant<u64>(admin, utf8(b"QiaraToken"), utf8(b"INFLATION"), 25_000_000, true, &give_permission(&give_access(admin))); // 25%
        register_constant<u64>(admin, utf8(b"QiaraToken"), utf8(b"INFLATION_DEBT"), 25_000, false, &give_permission(&give_access(admin))); 
        register_constant<u64>(admin, utf8(b"QiaraToken"), utf8(b"BURN_FEE"), 500, false, &give_permission(&give_access(admin))); // 0,001%
        register_constant<u64>(admin, utf8(b"QiaraToken"), utf8(b"BURN_FEE_MINIMAL"), 100, false, &give_permission(&give_access(admin))); //  0,0001 Qiara token
        register_constant<u64>(admin, utf8(b"QiaraToken"), utf8(b"BURN_INCREASE"), 250, false, &give_permission(&give_access(admin))); // 0,00025% a month
        register_constant<u64>(admin, utf8(b"QiaraToken"), utf8(b"REQUIRED_BURNED_TOKENS_FOR_REWARDS"), 1_000, false, &give_permission(&give_access(admin))); // 0,001 burned tokens per 1$
        register_constant<u64>(admin, utf8(b"QiaraToken"), utf8(b"LOCKED_QIARA_REWARD_RATE"), 25_000_000, true, &give_permission(&give_access(admin))); // 25%  
        register_constant<u64>(admin, utf8(b"QiaraToken"), utf8(b"EMISSIONS_VALIDATORS"), 2_000_000, true, &give_permission(&give_access(admin))); // 25%  


        register_constant<u16>(admin, utf8(b"QiaraTiers"), utf8(b"T0_X"), 100, true, &give_permission(&give_access(admin)));
        register_constant<u16>(admin, utf8(b"QiaraTiers"), utf8(b"T00_X"), 200, true, &give_permission(&give_access(admin)));
        register_constant<u16>(admin, utf8(b"QiaraTiers"), utf8(b"T1_X"), 200, true, &give_permission(&give_access(admin)));
        register_constant<u16>(admin, utf8(b"QiaraTiers"), utf8(b"T2_X"), 300, true, &give_permission(&give_access(admin)));
        register_constant<u16>(admin, utf8(b"QiaraTiers"), utf8(b"T3_X"), 500, true, &give_permission(&give_access(admin)));
        register_constant<u16>(admin, utf8(b"QiaraTiers"), utf8(b"T4_X"), 1000, true, &give_permission(&give_access(admin)));
        register_constant<u16>(admin, utf8(b"QiaraTiers"), utf8(b"T5_X"), 1500, true, &give_permission(&give_access(admin)));
        register_constant<u16>(admin, utf8(b"QiaraTiers"), utf8(b"T6_X"), 2500, true, &give_permission(&give_access(admin)));
        register_constant<u16>(admin, utf8(b"QiaraTiers"), utf8(b"T7_X"), 5000, true, &give_permission(&give_access(admin)));

        register_constant<u16>(admin, utf8(b"QiaraTiers"), utf8(b"T0_EFF"), 8500, true, &give_permission(&give_access(admin)));
        register_constant<u16>(admin, utf8(b"QiaraTiers"), utf8(b"T00_EFF"), 7500, true, &give_permission(&give_access(admin)));
        register_constant<u16>(admin, utf8(b"QiaraTiers"), utf8(b"T1_EFF"), 8000, true, &give_permission(&give_access(admin)));
        register_constant<u16>(admin, utf8(b"QiaraTiers"), utf8(b"T2_EFF"), 7500, true, &give_permission(&give_access(admin)));
        register_constant<u16>(admin, utf8(b"QiaraTiers"), utf8(b"T3_EFF"), 6250, true, &give_permission(&give_access(admin)));
        register_constant<u16>(admin, utf8(b"QiaraTiers"), utf8(b"T4_EFF"), 5000, true, &give_permission(&give_access(admin)));
        register_constant<u16>(admin, utf8(b"QiaraTiers"), utf8(b"T5_EFF"), 3500, true, &give_permission(&give_access(admin)));
        register_constant<u16>(admin, utf8(b"QiaraTiers"), utf8(b"T6_EFF"), 2000, true, &give_permission(&give_access(admin)));
        register_constant<u16>(admin, utf8(b"QiaraTiers"), utf8(b"T7_EFF"), 1000, true, &give_permission(&give_access(admin)));

        register_constant<u64>(admin, utf8(b"QiaraMarket"), utf8(b"DEPOSIT_LIMIT"), 1_000_000, true, &give_permission(&give_access(admin)));
        register_constant<u64>(admin, utf8(b"QiaraMarket"), utf8(b"BORROW_LIMIT"), 500_000, true, &give_permission(&give_access(admin)));
        register_constant<u64>(admin, utf8(b"QiaraMarket"), utf8(b"W_FEE"), 2_500, true, &give_permission(&give_access(admin))); // 0.001%
        register_constant<u64>(admin, utf8(b"QiaraMarket"), utf8(b"W_CAP"), 500, true, &give_permission(&give_access(admin)));
        register_constant<u64>(admin, utf8(b"QiaraMarket"), utf8(b"MARKET_PERCENTAGE_SCALE"), 5000, true, &give_permission(&give_access(admin)));
        register_constant<u64>(admin, utf8(b"QiaraMarket"), utf8(b"MIN_LEND_APR_FACTOR"), 100_000, true, &give_permission(&give_access(admin))); // 0.5%
        register_constant<u64>(admin, utf8(b"QiaraMarket"), utf8(b"APR_SCAILING_FACTOR"), 10_00_000, true, &give_permission(&give_access(admin))); // 10x
        register_constant<u64>(admin, utf8(b"QiaraMarket"), utf8(b"WITHDRAW_LIMIT"), 5_000_000, true, &give_permission(&give_access(admin))); // 0.1x
        register_constant<u64>(admin, utf8(b"QiaraMarket"), utf8(b"NEW_MULTIPLIER_HANDICAP"), 200, true, &give_permission(&give_access(admin)));
        register_constant<u64>(admin, utf8(b"QiaraMarket"), utf8(b"NEW_EFFICIENCY_HANDICAP"), 200, true, &give_permission(&give_access(admin)));
        register_constant<u64>(admin, utf8(b"QiaraMarket"), utf8(b"NEW_PENALTY_TIME"), 604_800, true, &give_permission(&give_access(admin)));

        register_constant<u64>(admin, utf8(b"QiaraPerps"), utf8(b"LEVERAGE"), 1000, true, &give_permission(&give_access(admin)));
        register_constant<u64>(admin, utf8(b"QiaraPerps"), utf8(b"MAX_POSITION"), 1_000_000, true, &give_permission(&give_access(admin)));
        register_constant<u64>(admin, utf8(b"QiaraPerps"), utf8(b"PROFIT_FEE"), 30_000, true, &give_permission(&give_access(admin))); // 0.03%
        register_constant<u64>(admin, utf8(b"QiaraPerps"), utf8(b"PERPS_PERCENTAGE_SCALE"), 75000, true, &give_permission(&give_access(admin)));
        register_constant<u64>(admin, utf8(b"QiaraPerps"), utf8(b"MIN_USD_SIZE_PER_TRADE"), 1_000_000, true, &give_permission(&give_access(admin)));
        register_constant<u64>(admin, utf8(b"QiaraPerps"), utf8(b"MIN_TOKEN_SIZE_PER_TRADE"), 1, true, &give_permission(&give_access(admin)));


        register_constant<u64>(admin, utf8(b"QiaraMargin"), utf8(b"BASE_UTIL_FEE"), 1_000_000, true, &give_permission(&give_access(admin))); // 1%
        register_constant<u64>(admin, utf8(b"QiaraMargin"), utf8(b"EXP_SCALE"), 50_000_000, true, &give_permission(&give_access(admin)));
        register_constant<u64>(admin, utf8(b"QiaraMargin"), utf8(b"EXP_AGGRESION"), 10, true, &give_permission(&give_access(admin)));
        register_constant<u64>(admin, utf8(b"QiaraMargin"), utf8(b"STAKED_LTV_INCREASE"), 10_000_000, true, &give_permission(&give_access(admin))); // 10%
        register_constant<u64>(admin, utf8(b"QiaraMargin"), utf8(b"MAX_LTV_RATE"), 99_000_000, true, &give_permission(&give_access(admin))); // 99%
        register_constant<u64>(admin, utf8(b"QiaraMargin"), utf8(b"CREDIT_SWAP_FEE"), 1_000_000, true, &give_permission(&give_access(admin))); // 99%
 

        register_constant<u64>(admin, utf8(b"QiaraGovernance"), utf8(b"MINIMUM_TOKENS_TO_PROPOSE"), 100_000_000, true, &give_permission(&give_access(admin))); // 100 Qiara Tokens
        register_constant<u64>(admin, utf8(b"QiaraGovernance"), utf8(b"BURN_TAX"), 1_000_000, true, &give_permission(&give_access(admin))); // 1 Qiara Token
        register_constant<u64>(admin, utf8(b"QiaraGovernance"), utf8(b"MINIMUM_TOTAL_VOTES_PERCENTAGE_SUPPLY"), 1_000_000, true, &give_permission(&give_access(admin))); // 1%
        register_constant<u64>(admin, utf8(b"QiaraGovernance"), utf8(b"MINIMUM_QUARUM_FOR_PROPOSAL_TO_PASS"), 500, true, &give_permission(&give_access(admin))); // 50.0%
        
        register_constant<u64>(admin, utf8(b"QiaraAuto"), utf8(b"MAX_DURATION"), 604_800, true, &give_permission(&give_access(admin)));
        register_constant<u64>(admin, utf8(b"QiaraStaking"), utf8(b"UNLOCK_PERIOD"), 604_800, true, &give_permission(&give_access(admin)));
        register_constant<u64>(admin, utf8(b"QiaraStaking"), utf8(b"STAKING_FEE"), 1_000_000, true, &give_permission(&give_access(admin))); // 1%
    }
    public entry fun more2(admin: &signer) acquires ConstantDatabase, KeyRegistry, ConstantCounter{
        assert!(signer::address_of(admin) == OWNER, ERROR_NOT_ADMIN);
        register_constant<u64>(admin, utf8(b"QiaraBridge"), utf8(b"FEE"), 100_000, true, &give_permission(&give_access(admin))); // 0.001%  
        register_constant<u8>(admin, utf8(b"QiaraBridge"), utf8(b"MINIMUM_UNIQUE_VALIDATORS"), 3, true, &give_permission(&give_access(admin))); // 3
        register_constant<u64>(admin, utf8(b"QiaraBridge"), utf8(b"MINIMUM_REQUIRED_VOTED_WEIGHT"), 10_000, true, &give_permission(&give_access(admin))); // 10000$
        register_constant<u64>(admin, utf8(b"QiaraBridge"), utf8(b"MINIMUM_REQUIRED_VOTING_POWER"), 100_000_000, true, &give_permission(&give_access(admin))); // 100$
        register_constant<u64>(admin, utf8(b"QiaraBridge"), utf8(b"FLAT_USD_FEE"), 1_000, true, &give_permission(&give_access(admin))); // 0.001$  

        register_constant<u64>(admin, utf8(b"QiaraOracle"), utf8(b"NATIVE_ORACLE_WEIGHT"), 1_000_000, true, &give_permission(&give_access(admin))); // 1x
        register_constant<u64>(admin, utf8(b"QiaraOracle"), utf8(b"NATIVE_ORACLE_WEIGHT_SLASHING"), 10_000_000, true, &give_permission(&give_access(admin))); // 10
        register_constant<u64>(admin, utf8(b"QiaraPerps"), utf8(b"MAX_LEVERAGE"), 5_000_000, true, &give_permission(&give_access(admin))); // 1x
        register_constant<u64>(admin, utf8(b"QiaraPerps"), utf8(b"MAX_LEVERAGE_SLASHING"), 2_000_000, true, &give_permission(&give_access(admin))); // 25x
        register_constant<u64>(admin, utf8(b"QiaraValidator"), utf8(b"VALIDATOR_COMPUTATION_FEE"), 1_000, true, &give_permission(&give_access(admin))); // 0.001%

        register_constant<u64>(admin, utf8(b"QiaraPoints"), utf8(b"ANY_FEE_CONVERSION"), 1_000_000, true, &give_permission(&give_access(admin))); // 1x
        register_constant<u64>(admin, utf8(b"QiaraPoints"), utf8(b"PERPS_VOLUME_CONVERSION"), 100_000, true, &give_permission(&give_access(admin))); // 0.1x
        register_constant<u64>(admin, utf8(b"QiaraPoints"), utf8(b"MARKET_LIQUIDITY_PROVISION_CONVERSION"), 1_000_000, true, &give_permission(&give_access(admin))); // 0.05/s/$
        register_constant<u64>(admin, utf8(b"QiaraPoints"), utf8(b"DAILY_CLAIM"), 100_000_000, true, &give_permission(&give_access(admin))); // 100*level

        register_constant<u64>(admin, utf8(b"QiaraRanks"), utf8(b"EXPONENT_XP_MULTI_PER_DAY"), 1_000_000_000, true, &give_permission(&give_access(admin))); // 1,25X   
        register_constant<u64>(admin, utf8(b"QiaraRanks"), utf8(b"BASE_XP_MULTI_PER_DAY"), 1_000_000, true, &give_permission(&give_access(admin))); // 0.1%
        register_constant<u64>(admin, utf8(b"QiaraRanks"), utf8(b"INCREASED_QBURNED_REWARD_RATE_PER_POWER"), 5_000_000, true, &give_permission(&give_access(admin))); // 5%
        register_constant<u64>(admin, utf8(b"QiaraRanks"), utf8(b"FEE_DEDUCTION_PER_POWER"), 5_000_000, true, &give_permission(&give_access(admin))); // 5%
        register_constant<u64>(admin, utf8(b"QiaraRanks"), utf8(b"LTVP_INCREASE_PER_POWER"), 2_500_000, true, &give_permission(&give_access(admin))); // 2,5%
        register_constant<u64>(admin, utf8(b"QiaraRanks"), utf8(b"WITHDRAWAL_OVER_LIMIT_PER_POWER"), 2_500_000, true, &give_permission(&give_access(admin))); // 2,5%
        register_constant<u64>(admin, utf8(b"QiaraRanks"), utf8(b"BASE_XP"), 100_000_000, true, &give_permission(&give_access(admin))); // 100
        register_constant<u64>(admin, utf8(b"QiaraRanks"), utf8(b"ANY_FEE_CONVERSION"), 1_000_000, true, &give_permission(&give_access(admin))); // 1x
        register_constant<u64>(admin, utf8(b"QiaraRanks"), utf8(b"PERPS_VOLUME_CONVERSION"), 100_000, true, &give_permission(&give_access(admin))); // 0.1x
        register_constant<u64>(admin, utf8(b"QiaraRanks"), utf8(b"MARKET_LIQUIDITY_PROVISION_CONVERSION"), 1_000_000, true, &give_permission(&give_access(admin))); // 0.05/s/$
        register_constant<u64>(admin, utf8(b"QiaraRanks"), utf8(b"DAILY_CLAIM"), 100_000_000, true, &give_permission(&give_access(admin))); // 100*level
        register_constant<u64>(admin, utf8(b"QiaraRanks"), utf8(b"SCALER_XP_MULTI_PER_DAY"), 25_000, true, &give_permission(&give_access(admin))); // 25%  
        register_constant<u64>(admin, utf8(b"QiaraRanks"), utf8(b"POINTS_PER_PERP_ACTION"), 100, true, &give_permission(&give_access(admin))); // 0.001%  


        register_constant<u64>(admin, utf8(b"QiaraFaucet"), utf8(b"TIME_PERIOD"), 86400, true, &give_permission(&give_access(admin))); // 1x
        register_constant<u64>(admin, utf8(b"QiaraFaucet"), utf8(b"USD_VALUE"), 100_000_000, true, &give_permission(&give_access(admin))); // 0.1x
      
        register_constant<u64>(admin, utf8(b"QiaraShared"), utf8(b"BASE_SHARED_XP_INCREASE"), 25_000_000, true, &give_permission(&give_access(admin))); // 25%  
        register_constant<u64>(admin, utf8(b"QiaraShared"), utf8(b"BASE_SHARED_FEE_REDUCTION"), 10_000_000, true, &give_permission(&give_access(admin))); // 10%  
   

    }

  public entry fun more4(admin: &signer) acquires ConstantDatabase, KeyRegistry, ConstantCounter{
        assert!(signer::address_of(admin) == OWNER, ERROR_NOT_ADMIN);
        register_constant<u64>(admin, utf8(b"QiaraRanks"), utf8(b"POINTS_PER_PERP_ACTION"), 100, true, &give_permission(&give_access(admin))); // 0.001%  
    }


    public entry fun more3(admin: &signer) acquires ConstantDatabase{
        assert!(signer::address_of(admin) == OWNER, ERROR_NOT_ADMIN);
        change_constant(admin, utf8(b"QiaraPerps"), utf8(b"MAX_LEVERAGE"), bc::to_bytes(&5_000_000u64), &give_permission(&give_access(admin))); // 0.001%  

    }



    fun register_constant<T: drop>(address: &signer, header: String, constant_name: String, value: T, editable: bool, permission: &Permission) acquires ConstantCounter, ConstantDatabase, KeyRegistry {
        assert!(signer::address_of(address) == OWNER, ERROR_NOT_ADMIN);
        let db = borrow_global_mut<ConstantDatabase>(OWNER);
        let counter = borrow_global_mut<ConstantCounter>(OWNER);
        let key_registry = borrow_global_mut<KeyRegistry>(OWNER);
        let any = make_any<T>(bc::to_bytes(&value));
        let new_constant = make_constant(constant_name, any, editable, counter.count );
        counter.count = counter.count + 1;
        if(!vector::contains(&key_registry.keys, &header)){
            vector::push_back(&mut key_registry.keys, header);
        };
        if (table::contains(&db.database, header)) {
            // Append to the existing vector after checking for uniqueness
            let constants = table::borrow_mut(&mut db.database, header);
            let len = vector::length(constants);
            let i = 0;
            while (i < len) {
                let c_ref = vector::borrow(constants, i);
                if (c_ref.name == constant_name) {
                    // Constant with this name already exists for this header
                    abort ERROR_CONSTANT_ALREADY_EXISTS
                };
                i = i + 1;
            };
            vector::push_back(constants, new_constant);
        } else {
            // Create a new vector with the constant
            let vec = vector::empty<Constant>();
            vector::push_back(&mut vec, new_constant);
            table::add(&mut db.database, header, vec);
        }
    }

    public fun handle_registration_multi(address: &signer, header: vector<String>, constant_name: vector<String>, value: vector<vector<u8>>, value_type: vector<String>, editable: vector<bool>, permission: &Permission) acquires KeyRegistry, ConstantCounter, ConstantDatabase{
        let len = vector::length(&value_type);
        while(len>0){
            handle_registration(address, *vector::borrow(&header, len-1), *vector::borrow(&constant_name, len-1), *vector::borrow(&value, len-1), *vector::borrow(&value_type, len-1), *vector::borrow(&editable, len-1), permission);
            len=len-1;
        };
    }

    public fun handle_registration(address: &signer, header: String, constant_name: String, value: vector<u8>, value_type: String, editable: bool, permission: &Permission) acquires KeyRegistry, ConstantCounter, ConstantDatabase{
        if(value_type == utf8(b"u8")){
             register_constant<u8>(address, header, constant_name, from_bcs::to_u8(value), editable, permission);
        } else if  (value_type == utf8(b"u16")){
             register_constant<u16>(address, header, constant_name, from_bcs::to_u16(value), editable, permission);
        } else if  (value_type == utf8(b"u32")){
             register_constant<u32>(address, header, constant_name, from_bcs::to_u32(value), editable, permission);
        } else if  (value_type == utf8(b"u64")){
             register_constant<u64>(address, header, constant_name, from_bcs::to_u64(value), editable, permission);
        } else if  (value_type == utf8(b"u128")){
             register_constant<u128>(address, header, constant_name, from_bcs::to_u128(value), editable, permission);
        } else if  (value_type == utf8(b"u256")){
             register_constant<u256>(address, header, constant_name, from_bcs::to_u256(value), editable, permission);
        } else if  (value_type == utf8(b"bool")){
             register_constant<bool>(address, header, constant_name, from_bcs::to_bool(value), editable, permission);
        } else if  (value_type == utf8(b"address")){
             register_constant<address>(address, header, constant_name, from_bcs::to_address(value), editable, permission);
        } else{
            abort ERROR_INVALID_VALUE_TYPE
        }
    }

    fun get_constant(db: &mut ConstantDatabase, header: String, name: String): &mut Constant{

        if (!table::contains(&db.database, header)) {
            abort ERROR_HEADER_DOESNT_EXISTS;
        };

        let constants = table::borrow_mut(&mut db.database, header);

        let i = vector::length(constants);
        while (i > 0) {
            i = i - 1;
            let constant = vector::borrow_mut(constants, i); // copy or move depending on definition
            if (constant.name == name) {
                return constant;
            };
        };
        abort ERROR_HEADER_DOESNT_EXISTS
    }

    public fun change_constant_multi(address: &signer, header: vector<String>, constant_name: vector<String>, value: vector<vector<u8>>, permission: &Permission) acquires ConstantDatabase{
        let len = vector::length(&header);
        while(len>0){
            change_constant(address, *vector::borrow(&header, len-1), *vector::borrow(&constant_name, len-1), *vector::borrow(&value, len-1), permission);
            len=len-1;
        };
    }

    public fun change_constant(address: &signer,header: String,name: String,new_value: vector<u8>, permission: &Permission) acquires ConstantDatabase {
        assert!(signer::address_of(address) == OWNER, ERROR_NOT_ADMIN);
        let db = borrow_global_mut<ConstantDatabase>(OWNER);

        if (!table::contains(&db.database, header)) {
            abort ERROR_CONSTANT_DOES_NOT_EXIST;
        };

        let constant = get_constant(db, header, name);

        if (!constant.editable) {
            abort ERROR_CONSTANT_CANT_BE_EDITED
        };

        let old_constant = make_constant(
            constant.name,
            constant.value,
            constant.editable,
            constant.index
        );

        // Update the constant
        constant.value.data = new_value;

        let new_constant = make_constant(
            constant.name,
            constant.value,
            constant.editable,
            constant.index
        );

        event::emit(ConstantChange {
            address: signer::address_of(address),
            old_constant,
            new_constant
        });
    }


    #[view]
    public fun viewHeaders(): vector<String> acquires KeyRegistry {
        let key_registry = borrow_global<KeyRegistry>(OWNER);
        key_registry.keys
    }

    #[view]
    public fun viewConstants(header: String): vector<Constant> acquires ConstantDatabase {
        let db = borrow_global<ConstantDatabase>(OWNER);

        if (!table::contains(&db.database, header)) {
            abort ERROR_CONSTANT_DOES_NOT_EXIST;
        };

        let constants_ref = table::borrow(&db.database, header);
        *constants_ref // return a copy of the vector
    }

    #[view]
    public fun viewConstant_raw(header: String, constant_name: String): Constant acquires ConstantDatabase {
        let db = borrow_global<ConstantDatabase>(OWNER);

        if (!table::contains(&db.database, header)) {
            abort ERROR_HEADER_DOESNT_EXISTS;
        };

        let constants_ref: &vector<Constant> = table::borrow(&db.database, header);
        let len = vector::length(constants_ref);

        let i = 0;
        while (i < len) {
            let c_ref = vector::borrow(constants_ref, i);
            if (c_ref.name == constant_name) {
                // clone the Constant to return
                return make_constant(c_ref.name, c_ref.value, c_ref.editable, c_ref.index);
            };
            i = i + 1;
        };

        // If not found
        abort ERROR_CONSTANT_DOES_NOT_EXIST
    }

    #[view]
    public fun viewConstant(header: String, constant_name: String): vector<u8> acquires ConstantDatabase {
        let db = borrow_global<ConstantDatabase>(OWNER);

        if (!table::contains(&db.database, header)) {
            abort ERROR_HEADER_DOESNT_EXISTS;
        };

        let constants_ref: &vector<Constant> = table::borrow(&db.database, header);
        let len = vector::length(constants_ref);

        let i = 0;
        while (i < len) {
            let c_ref = vector::borrow(constants_ref, i);
            if (c_ref.name == constant_name) {
                return c_ref.value.data
            };
            i = i + 1;
        };

        // If not found
        abort ERROR_CONSTANT_DOES_NOT_EXIST
    }

    #[view]
        public fun viewAllConstants(): Map<String, vector<Constant>> acquires ConstantDatabase, KeyRegistry {
            let db = borrow_global<ConstantDatabase>(OWNER);
            let key_registry = borrow_global<KeyRegistry>(OWNER);

            let all_constants = map::new<String, vector<Constant>>();
            let headers = key_registry.keys;
            let len = vector::length(&headers);
            let i = 0;
            while (i < len) {
                let header = vector::borrow(&headers, i);
        
                if (table::contains(&db.database, *header)) {
                    let constants_ref = table::borrow(&db.database, *header);
                    map::add(&mut all_constants, *header, *constants_ref);
                };
                i = i + 1;
            };
            all_constants
        }

     #[view]
    public fun expect_u8(data: vector<u8>): u8 {
        from_bcs::to_u8(data)
    }
     #[view]
    public fun expect_u16(data: vector<u8>): u16 {
        from_bcs::to_u16(data)
    }
     #[view]
    public fun expect_u32(data: vector<u8>): u32 {
        from_bcs::to_u32(data)
    }
     #[view]
    public fun expect_u64(data: vector<u8>): u64 {
        from_bcs::to_u64(data)
    }
     #[view]
    public fun expect_u128(data: vector<u8>): u128 {
        from_bcs::to_u128(data)
    }
     #[view]
    public fun expect_u256(data: vector<u8>): u256 {
        from_bcs::to_u256(data)
    }
     #[view]
    public fun expect_bool(data: vector<u8>): bool {
        from_bcs::to_bool(data)
    }
    
     #[view]
    public fun expect_address(data: vector<u8>): address {
        from_bcs::to_address(data)
    }
 #[view] 
    public fun expect_bytes(data: vector<u8>): vector<u8> {
        from_bcs::to_bytes(data)
    }
 #[view]
    public fun expect_string(data: vector<u8>): string::String {
        from_bcs::to_string(data)
    }


}
