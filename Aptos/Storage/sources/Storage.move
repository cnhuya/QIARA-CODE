module dev::QiaraStorageV25 {
    use std::string::{Self, String, utf8, bytes as b};
    use std::signer;
    use std::vector;
    use aptos_framework::event;
    use std::table::{Self, Table};
    use aptos_std::type_info;
    use aptos_std::from_bcs;
    use std::bcs::{Self as bc};
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use aptos_framework::account; // 👈 Add this import

    // Helper: allows either your developer wallet OR the DAO to modify storage
    fun is_admin(caller: address): bool {
        let dao_address = account::create_resource_address(&@dev, x"01");
        caller == OWNER || caller == dao_address
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
        index: u64,
        isCrossChain: bool
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
    const ERROR_INVALID_ADDRESS_LENGTH: u64 = 9;

    fun make_constant(name: String, value: Any, editable: bool, index: u64, isCrossChain: bool): Constant {
        Constant { name, value, editable, index, isCrossChain }
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

        register_constant<u64>(admin, utf8(b"QiaraToken"), utf8(b"BRIDGE_TAX_FEE"), 100_000, true, true, ); // 0,1%
        register_constant<u64>(admin, utf8(b"QiaraToken"), utf8(b"MINIMAL_INFLATION"), 1_000_000, true, false, ); // 1%
        register_constant<u64>(admin, utf8(b"QiaraToken"), utf8(b"INFLATION"), 25_000_000, true,  false, ); // 25%
        register_constant<u64>(admin, utf8(b"QiaraToken"), utf8(b"INFLATION_DEBT"), 25_000, false,  false, ); 
        register_constant<u64>(admin, utf8(b"QiaraToken"), utf8(b"BURN_FEE"), 500, false,true, ); // 0,001%
        register_constant<u64>(admin, utf8(b"QiaraToken"), utf8(b"BURN_FEE_MINIMAL"), 100, false,true, ); //  0,0001 Qiara token
        register_constant<u64>(admin, utf8(b"QiaraToken"), utf8(b"BURN_INCREASE"), 250, false, true, ); // 0,00025% a month
        register_constant<u64>(admin, utf8(b"QiaraToken"), utf8(b"REQUIRED_BURNED_TOKENS_FOR_REWARDS"), 1_000, false,  false, ); // 0,001 burned tokens per 1$
        register_constant<u64>(admin, utf8(b"QiaraToken"), utf8(b"LOCKED_QIARA_REWARD_RATE"), 25_000_000, true,  false, ); // 25%  
        register_constant<u64>(admin, utf8(b"QiaraToken"), utf8(b"EMISSIONS_VALIDATORS"), 2_000_000, true,  false, ); // 25%  


        register_constant<u16>(admin, utf8(b"QiaraTiers"), utf8(b"T0_X"), 100, true,  false,);
        register_constant<u16>(admin, utf8(b"QiaraTiers"), utf8(b"T00_X"), 200, true, false, );
        register_constant<u16>(admin, utf8(b"QiaraTiers"), utf8(b"T1_X"), 200, true, false, );
        register_constant<u16>(admin, utf8(b"QiaraTiers"), utf8(b"T2_X"), 300, true, false, );
        register_constant<u16>(admin, utf8(b"QiaraTiers"), utf8(b"T3_X"), 500, true,  false,);
        register_constant<u16>(admin, utf8(b"QiaraTiers"), utf8(b"T4_X"), 1000, true,  false,);
        register_constant<u16>(admin, utf8(b"QiaraTiers"), utf8(b"T5_X"), 1500, true,  false,);
        register_constant<u16>(admin, utf8(b"QiaraTiers"), utf8(b"T6_X"), 2500, true,  false,);
        register_constant<u16>(admin, utf8(b"QiaraTiers"), utf8(b"T7_X"), 5000, true, false, );

        register_constant<u16>(admin, utf8(b"QiaraTiers"), utf8(b"T0_EFF"), 8500, true,  false,);
        register_constant<u16>(admin, utf8(b"QiaraTiers"), utf8(b"T00_EFF"), 7500, true ,false, );
        register_constant<u16>(admin, utf8(b"QiaraTiers"), utf8(b"T1_EFF"), 8000, true,  false,);
        register_constant<u16>(admin, utf8(b"QiaraTiers"), utf8(b"T2_EFF"), 7500, true,  false,);
        register_constant<u16>(admin, utf8(b"QiaraTiers"), utf8(b"T3_EFF"), 6250, true,  false,);
        register_constant<u16>(admin, utf8(b"QiaraTiers"), utf8(b"T4_EFF"), 5000, true, false, );
        register_constant<u16>(admin, utf8(b"QiaraTiers"), utf8(b"T5_EFF"), 3500, true, false, );
        register_constant<u16>(admin, utf8(b"QiaraTiers"), utf8(b"T6_EFF"), 2000, true, false, );
        register_constant<u16>(admin, utf8(b"QiaraTiers"), utf8(b"T7_EFF"), 1000, true,  false,);

        register_constant<u64>(admin, utf8(b"QiaraMarket"), utf8(b"DEPOSIT_LIMIT"), 1_000_000, true,  false, );
        register_constant<u64>(admin, utf8(b"QiaraMarket"), utf8(b"BORROW_LIMIT"), 500_000, true,  false,);
        register_constant<u64>(admin, utf8(b"QiaraMarket"), utf8(b"W_FEE"), 2_500, true,  false, ); // 0.001%
        //register_constant<u64>(admin, utf8(b"QiaraMarket"), utf8(b"W_CAP"), 500, true, );
        //register_constant<u64>(admin, utf8(b"QiaraMarket"), utf8(b"MARKET_PERCENTAGE_SCALE"), 5000, true, );
        register_constant<u64>(admin, utf8(b"QiaraMarket"), utf8(b"MIN_LEND_APR_FACTOR"), 100_000, true,  false, ); // 0.5%
        register_constant<u64>(admin, utf8(b"QiaraMarket"), utf8(b"APR_SCAILING_FACTOR"), 10_00_000, true,  false, ); // 10x
        register_constant<u64>(admin, utf8(b"QiaraMarket"), utf8(b"WITHDRAW_LIMIT"), 5_000_000, true, false,  ); // 0.1x
        register_constant<u64>(admin, utf8(b"QiaraMarket"), utf8(b"STAKE_FEE_PER_EPOCH"), 100_000, true, false, ); // 0.0025%
        register_constant<u64>(admin, utf8(b"QiaraMarket"), utf8(b"STAKE_FEE_REFUND"), 50_000_000, true,  false,); // 50%
        register_constant<u64>(admin, utf8(b"QiaraMarket"), utf8(b"MAX_STAKE_EPOCH"), 52, true,  false,); // 50%

        register_constant<u64>(admin, utf8(b"QiaraMarket"), utf8(b"NEW_MULTIPLIER_HANDICAP"), 10_000_000, true,  false,);
        //register_constant<u64>(admin, utf8(b"QiaraMarket"), utf8(b"NEW_EFFICIENCY_HANDICAP"), 200, true, );
        //register_constant<u64>(admin, utf8(b"QiaraMarket"), utf8(b"NEW_PENALTY_TIME"), 604_800, true, );

        //register_constant<u64>(admin, utf8(b"QiaraPerps"), utf8(b"LEVERAGE"), 1000, true, );
        register_constant<u64>(admin, utf8(b"QiaraPerps"), utf8(b"MAX_POSITION"), 1_000_000, true, false,  );
        register_constant<u64>(admin, utf8(b"QiaraPerps"), utf8(b"PROFIT_FEE"), 30_000, true,  false, ); // 0.03%
        //register_constant<u64>(admin, utf8(b"QiaraPerps"), utf8(b"PERPS_PERCENTAGE_SCALE"), 75000, true, );
        register_constant<u64>(admin, utf8(b"QiaraPerps"), utf8(b"MIN_USD_SIZE_PER_TRADE"), 1_000_000, true,  false, );
        register_constant<u64>(admin, utf8(b"QiaraPerps"), utf8(b"MIN_TOKEN_SIZE_PER_TRADE"), 1, true,  false, );


        //register_constant<u64>(admin, utf8(b"QiaraMargin"), utf8(b"BASE_UTIL_FEE"), 1_000_000, true, ); // 1%
        //register_constant<u64>(admin, utf8(b"QiaraMargin"), utf8(b"EXP_SCALE"), 50_000_000, true, );
        //register_constant<u64>(admin, utf8(b"QiaraMargin"), utf8(b"EXP_AGGRESION"), 10, true, );
        register_constant<u64>(admin, utf8(b"QiaraMargin"), utf8(b"STAKED_LTV_INCREASE"), 250_000, true,  false, ); // 10%
        register_constant<u64>(admin, utf8(b"QiaraMargin"), utf8(b"STAKED_LTV_INCREASE_MISSING"), 250_000, true,  false, ); // 10%
        register_constant<u64>(admin, utf8(b"QiaraMargin"), utf8(b"MAX_LTV_RATE"), 99_900_000, true, false,  ); // 99%
        register_constant<u64>(admin, utf8(b"QiaraMargin"), utf8(b"CREDIT_SWAP_FEE"), 1_000_000, true, false,  ); // 99%
        register_constant<u64>(admin, utf8(b"QiaraMargin"), utf8(b"DEFLATIONARY_LTV_INCREASE"), 2_500_000, true, false,  ); // 2,5%
        //register_constant<u64>(admin, utf8(b"QiaraMargin"), utf8(b"DEFLATIONARY_MISSING_LTV_INCREASE"), 2_500_000, true, false, ); // 5%

        register_constant<u64>(admin, utf8(b"QiaraGovernance"), utf8(b"MINIMUM_TOKENS_TO_PROPOSE"), 100_000_000, true, false, ); // 100 Qiara Tokens
        register_constant<u64>(admin, utf8(b"QiaraGovernance"), utf8(b"BURN_TAX"), 1_000_000, true, false, ); // 1 Qiara Token
        register_constant<u64>(admin, utf8(b"QiaraGovernance"), utf8(b"MINIMUM_TOTAL_VOTES_PERCENTAGE_SUPPLY"), 1_000_000, true, false, ); // 1%
        register_constant<u64>(admin, utf8(b"QiaraGovernance"), utf8(b"MINIMUM_QUARUM_FOR_PROPOSAL_TO_PASS"), 500, true, false, ); // 50.0%
        
        //register_constant<u64>(admin, utf8(b"QiaraAuto"), utf8(b"MAX_DURATION"), 604_800, true, );
        //register_constant<u64>(admin, utf8(b"QiaraStaking"), utf8(b"UNLOCK_PERIOD"), 604_800, true, );
        //register_constant<u64>(admin, utf8(b"QiaraStaking"), utf8(b"STAKING_FEE"), 1_000_000, true, ); // 1%
    }
    public entry fun more2(admin: &signer) acquires ConstantDatabase, KeyRegistry, ConstantCounter{
        assert!(signer::address_of(admin) == OWNER, ERROR_NOT_ADMIN);
        //register_constant<u64>(admin, utf8(b"QiaraBridge"), utf8(b"FEE"), 100_000, true, ); // 0.001%  
        register_constant<u8>(admin, utf8(b"QiaraBridge"), utf8(b"MINIMUM_UNIQUE_VALIDATORS"), 3, true,  true, ); // 3
        register_constant<u64>(admin, utf8(b"QiaraBridge"), utf8(b"MINIMUM_REQUIRED_VOTED_WEIGHT"), 10_000, true, false, ); // 10000$
        register_constant<u64>(admin, utf8(b"QiaraBridge"), utf8(b"MINIMUM_REQUIRED_VOTING_POWER"), 100_000_000, true, false, ); // 100$
        register_constant<u64>(admin, utf8(b"QiaraBridge"), utf8(b"FLAT_USD_FEE"), 10_000, true, false, ); // 0.01$  

        register_constant<u64>(admin, utf8(b"QiaraOracle"), utf8(b"NATIVE_ORACLE_WEIGHT"), 1_000_000, true, false, ); // 1x
        register_constant<u64>(admin, utf8(b"QiaraOracle"), utf8(b"NATIVE_ORACLE_WEIGHT_SLASHING"), 10_000_000, true, false, ); // 10
        register_constant<u64>(admin, utf8(b"QiaraOracle"), utf8(b"REQUIRED_QUORUM"), 2, true, false, ); // 2 VALIDATORS SIGNATURES
        register_constant<u64>(admin, utf8(b"QiaraOracle"), utf8(b"ROUND_DURATION_MILISECONDS"), 30000, true, false, ); // 30 SECONDS?
        register_constant<u64>(admin, utf8(b"QiaraOracle"), utf8(b"MAX_PRICE_DIVERGENCE_DRIFT"), 100_000, true, false, ); // 0.1% 
        register_constant<u64>(admin, utf8(b"QiaraOracle"), utf8(b"MIN_PRICE_DIVERGENCE_DRIFT"), 100, true, false, ); // 0.0001% 
        register_constant<u64>(admin, utf8(b"QiaraOracle"), utf8(b"COMMITTEE_POOL_SIZE"), 3, true, false, ); // 3
        register_constant<u64>(admin, utf8(b"QiaraOracle"), utf8(b"MAX_CLAMP_PRICE_STEP"), 1_000_000, true, false, ); // 1%

        register_constant<u64>(admin, utf8(b"QiaraPerps"), utf8(b"MAX_LEVERAGE"), 5_000_000, true, false, ); // 1x
        //register_constant<u64>(admin, utf8(b"QiaraPerps"), utf8(b"MAX_LEVERAGE_SLASHING"), 2_000_000, true, false, ); // 25x
        //register_constant<u64>(admin, utf8(b"QiaraValidator"), utf8(b"VALIDATOR_COMPUTATION_FEE"), 1_000, true, false, ); // 0.001%
        register_constant<u64>(admin, utf8(b"QiaraPoints"), utf8(b"ANY_FEE_CONVERSION"), 1_000_000, true, false, ); // 1x
        register_constant<u64>(admin, utf8(b"QiaraPoints"), utf8(b"PERPS_VOLUME_CONVERSION"), 100_000, true, false, ); // 0.1x
        register_constant<u64>(admin, utf8(b"QiaraPoints"), utf8(b"MARKET_LIQUIDITY_PROVISION_CONVERSION"), 10_000, true, false, ); // 0.05/s/$
        register_constant<u64>(admin, utf8(b"QiaraPoints"), utf8(b"DAILY_CLAIM"), 100_000_000, true, false, ); // 100*level
        register_constant<u64>(admin, utf8(b"QiaraPoints"), utf8(b"XP_PER_0001_PRICE_SHIFT"), 100_000_000, true, false, ); // 100 XP PER 0,0001%

        register_constant<u64>(admin, utf8(b"QiaraRanks"), utf8(b"EXPONENT_XP_MULTI_PER_DAY"), 1_000_000_000, true, false, ); // 1,25X   
        register_constant<u64>(admin, utf8(b"QiaraRanks"), utf8(b"BASE_XP_MULTI_PER_DAY"), 1_000_000, true, false, ); // 0.1%
        register_constant<u64>(admin, utf8(b"QiaraRanks"), utf8(b"INCREASED_QBURNED_REWARD_RATE_PER_POWER"), 5_000_000, true, false, ); // 5%
        register_constant<u64>(admin, utf8(b"QiaraRanks"), utf8(b"FEE_DEDUCTION_PER_POWER"), 5_000_000, true, false, ); // 5%
        register_constant<u64>(admin, utf8(b"QiaraRanks"), utf8(b"LTVP_INCREASE_PER_POWER"), 2_500_000, true, false, ); // 2,5%
        register_constant<u64>(admin, utf8(b"QiaraRanks"), utf8(b"WITHDRAWAL_OVER_LIMIT_PER_POWER"), 2_500_000, true, false, ); // 2,5%
        register_constant<u64>(admin, utf8(b"QiaraRanks"), utf8(b"BASE_XP"), 100_000_000, true, false, ); // 100
        //register_constant<u64>(admin, utf8(b"QiaraRanks"), utf8(b"ANY_FEE_CONVERSION"), 1_000_000, true, false, ); // 1x
        //register_constant<u64>(admin, utf8(b"QiaraRanks"), utf8(b"PERPS_VOLUME_CONVERSION"), 100_000, true, false, ); // 0.1x
        //register_constant<u64>(admin, utf8(b"QiaraRanks"), utf8(b"MARKET_LIQUIDITY_PROVISION_CONVERSION"), 10_000, true, false, ); // 0.05/s/$
        //register_constant<u64>(admin, utf8(b"QiaraRanks"), utf8(b"DAILY_CLAIM"), 100_000_000, true, false, ); // 100*level
        register_constant<u64>(admin, utf8(b"QiaraRanks"), utf8(b"SCALER_XP_MULTI_PER_DAY"), 25_000, true, false, ); // 25%  
        register_constant<u64>(admin, utf8(b"QiaraRanks"), utf8(b"POINTS_PER_PERP_ACTION"), 100, true, false, ); // 0.001%  
        register_constant<u64>(admin, utf8(b"QiaraFaucet"), utf8(b"TIME_PERIOD"), 86400, true, false, ); // 1x
        register_constant<u64>(admin, utf8(b"QiaraFaucet"), utf8(b"USD_VALUE"), 100_000_000, true, false, ); // 0.1x
      
        register_constant<u64>(admin, utf8(b"QiaraShared"), utf8(b"BASE_SHARED_XP_INCREASE"), 25_000_000, true, false, ); // 25%  
        register_constant<u64>(admin, utf8(b"QiaraShared"), utf8(b"BASE_SHARED_FEE_REDUCTION"), 10_000_000, true, false, ); // 10%  
   
        register_constant<u64>(admin, utf8(b"QiaraGas"), utf8(b"GAS_TO_FEE_INCREASE"), 1_000_000, true, false, ); // 1x
        register_constant<u64>(admin, utf8(b"QiaraGas"), utf8(b"WITHDRAWAL_WEIGHT"), 1_000_000, true, false, ); // 1x
        register_constant<u64>(admin, utf8(b"QiaraGas"), utf8(b"BASE_GAS_FEE"), 500_000, true, false, ); // 1x
        register_constant<u64>(admin, utf8(b"QiaraGas"), utf8(b"DECAY_WEIGHT"), 2_500, true, false, ); // 1x
        register_constant<u64>(admin, utf8(b"QiaraGas"), utf8(b"MAX_DECAY"), 25_000_000, true, false, ); // 1x

    }
    public entry fun more4(admin: &signer) acquires ConstantDatabase, KeyRegistry, ConstantCounter{
        assert!(signer::address_of(admin) == OWNER, ERROR_NOT_ADMIN);
        register_constant<u64>(admin, utf8(b"QiaraOracle"), utf8(b"REQUIRED_QUORUM"), 2, true, false, ); // 2 VALIDATORS SIGNATURES
        register_constant<u64>(admin, utf8(b"QiaraOracle"), utf8(b"ROUND_DURATION_MILISECONDS"), 30000, true, false, ); // 30 SECONDS?
        register_constant<u64>(admin, utf8(b"QiaraOracle"), utf8(b"MAX_PRICE_DIVERGENCE_DRIFT"), 100_000, true, false, ); // 0.1% 
        register_constant<u64>(admin, utf8(b"QiaraOracle"), utf8(b"MIN_PRICE_DIVERGENCE_DRIFT"), 100, true, false, ); // 0.0001% 
        register_constant<u64>(admin, utf8(b"QiaraOracle"), utf8(b"COMMITTEE_POOL_SIZE"), 3, true, false, ); // 3
        register_constant<u64>(admin, utf8(b"QiaraOracle"), utf8(b"MAX_CLAMP_PRICE_STEP"), 1_000_000, true, false, ); // 1%

    }

    public entry fun more3(admin: &signer) acquires ConstantDatabase {
        assert!(signer::address_of(admin) == OWNER, ERROR_NOT_ADMIN);
//register_constant<u64>(admin, utf8(b"QiaraBridge"), utf8(b"FLAT_USD_FEE"), 10_000, true, false, ); // 0.01$  
        change_constant(admin, utf8(b"QiaraOracle"), utf8(b"ROUND_DURATION_MILISECONDS"), bc::to_bytes(&30_000), ); // 0.1%  
     //  change_constant(admin, utf8(b"QiaraMarket"), utf8(b"NEW_MULTIPLIER_HANDICAP"), bc::to_bytes(&10_000_000), ); // 0.0001%  
      //  change_constant(admin, utf8(b"QiaraOracle"), utf8(b"REQUIRED_QUORUM"), bc::to_bytes(&2), ); // 0.001%  



    }



    public entry fun more5(admin: &signer)  acquires ConstantDatabase, KeyRegistry, ConstantCounter{
        assert!(signer::address_of(admin) == OWNER, ERROR_NOT_ADMIN);
        register_constant<vector<u8>>(admin, utf8(b"QiaraToken"), utf8(b"BASE_BRIDGE_TAX_FEE_RECEIVER"), x"92AafAC1636Fd7d7abEDA9297f05724eCBA21193", true, true, ); // 0,1%
        register_constant<vector<u8>>(admin, utf8(b"QiaraToken"), utf8(b"MONAD_BRIDGE_TAX_FEE_RECEIVER"), x"92AafAC1636Fd7d7abEDA9297f05724eCBA21193", true, true, ); // 0,1%
        register_constant<vector<u8>>(admin, utf8(b"QiaraToken"), utf8(b"APTOS_BRIDGE_TAX_FEE_RECEIVER"), x"92AafAC1636Fd7d7abEDA9297f05724eCBA21193", true, true, ); // 0,1%
        register_constant<vector<u8>>(admin, utf8(b"QiaraToken"), utf8(b"SUI_BRIDGE_TAX_FEE_RECEIVER"), x"a58fa2a3a4c292205292139e5d71771517a61ced2643b14fe8882264622f07b5", true, true, ); // 0,1%
        register_constant<vector<u8>>(admin, utf8(b"QiaraToken"), utf8(b"SOLANA_BRIDGE_TAX_FEE_RECEIVER"), x"b1734bbef4c28beb5d08c73b2c39f56efdb217382de02b9637d981a589d5e7e0", true, true, ); // 0,1%
        register_constant<vector<u8>>(admin, utf8(b"QiaraToken"), utf8(b"ETHEREUM_BRIDGE_TAX_FEE_RECEIVER"),x"92AafAC1636Fd7d7abEDA9297f05724eCBA21193", true, true, ); // 0,1%
        register_constant<vector<u8>>(admin, utf8(b"QiaraToken"), utf8(b"ROBINHOOD_BRIDGE_TAX_FEE_RECEIVER"), x"92AafAC1636Fd7d7abEDA9297f05724eCBA21193", true, true, ); // 0,1%

        register_constant<vector<u8>>(admin, utf8(b"QiaraToken"), utf8(b"BASE_WHITELIST_ADMIN"), x"92AafAC1636Fd7d7abEDA9297f05724eCBA21193", true, true, ); // 0,1%
        register_constant<vector<u8>>(admin, utf8(b"QiaraToken"), utf8(b"MONAD_WHITELIST_ADMIN"), x"92AafAC1636Fd7d7abEDA9297f05724eCBA21193", true, true, ); // 0,1%
        register_constant<vector<u8>>(admin, utf8(b"QiaraToken"), utf8(b"APTOS_WHITELIST_ADMIN"), x"92AafAC1636Fd7d7abEDA9297f05724eCBA21193", true, true, ); // 0,1%
        register_constant<vector<u8>>(admin, utf8(b"QiaraToken"), utf8(b"SUI_WHITELIST_ADMIN"), x"a58fa2a3a4c292205292139e5d71771517a61ced2643b14fe8882264622f07b5", true, true, ); // 0,1%
        register_constant<vector<u8>>(admin, utf8(b"QiaraToken"), utf8(b"SOLANA_WHITELIST_ADMIN"), x"b1734bbef4c28beb5d08c73b2c39f56efdb217382de02b9637d981a589d5e7e0", true, true, ); // 0,1%
        register_constant<vector<u8>>(admin, utf8(b"QiaraToken"), utf8(b"ETHEREUM_WHITELIST_ADMIN"),x"92AafAC1636Fd7d7abEDA9297f05724eCBA21193", true, true, ); // 0,1%
        register_constant<vector<u8>>(admin, utf8(b"QiaraToken"), utf8(b"ROBINHOOD_WHITELIST_ADMIN"), x"92AafAC1636Fd7d7abEDA9297f05724eCBA21193", true, true, ); // 0,1%

    }


// Make this public fun so scripts can also register new constants if needed!
public fun register_constant<T: drop>(
    address: &signer, 
    header: String, 
    constant_name: String, 
    value: T, 
    editable: bool, 
    isCrossChain: bool
) acquires ConstantCounter, ConstantDatabase, KeyRegistry {
    assert!(is_admin(signer::address_of(address)), ERROR_NOT_ADMIN); // 👈 Updated check
    let db = borrow_global_mut<ConstantDatabase>(OWNER);
    let counter = borrow_global_mut<ConstantCounter>(OWNER);
    let key_registry = borrow_global_mut<KeyRegistry>(OWNER);
    let any = make_any<T>(bc::to_bytes(&value));
    let new_constant = make_constant(constant_name, any, editable, counter.count, isCrossChain);
    counter.count = counter.count + 1;
    if(!vector::contains(&key_registry.keys, &header)){
        vector::push_back(&mut key_registry.keys, header);
    };
    if (table::contains(&db.database, header)) {
        let constants = table::borrow_mut(&mut db.database, header);
        let len = vector::length(constants);
        let i = 0;
        while (i < len) {
            let c_ref = vector::borrow(constants, i);
            if (c_ref.name == constant_name) {
                abort ERROR_CONSTANT_ALREADY_EXISTS
            };
            i = i + 1;
        };
        vector::push_back(constants, new_constant);
    } else {
        let vec = vector::empty<Constant>();
        vector::push_back(&mut vec, new_constant);
        table::add(&mut db.database, header, vec);
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


public fun change_constant(
    address: &signer,
    header: String,
    name: String,
    new_value: vector<u8>
    // 👈 Removed permission: &Permission
) acquires ConstantDatabase {
    assert!(is_admin(signer::address_of(address)), ERROR_NOT_ADMIN); // 👈 Updated check
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
        constant.index,
        constant.isCrossChain
    );

    constant.value.data = new_value;

    let new_constant = make_constant(
        constant.name,
        constant.value,
        constant.editable,
        constant.index,
        constant.isCrossChain
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
                return make_constant(c_ref.name, c_ref.value, c_ref.editable, c_ref.index, c_ref.isCrossChain);
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
public fun expect_address_padded(data: vector<u8>): address {
    let bytes = from_bcs::to_bytes(data);          // strip BCS length prefix
    let len = vector::length(&bytes);
    assert!(len <= 32, ERROR_INVALID_ADDRESS_LENGTH);

    let padded = vector::empty<u8>();
    let i = len;
    while (i < 32) {
        vector::push_back(&mut padded, 0);
        i = i + 1;
    };
    vector::append(&mut padded, bytes);            // zeros first, then the bytes
    from_bcs::to_address(padded)
}
 #[view]
    public fun expect_string(data: vector<u8>): string::String {
        from_bcs::to_string(data)
    }


}
