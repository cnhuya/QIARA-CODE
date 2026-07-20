module dev::QiaraRanksV47{
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::vector;
    use std::timestamp;
    use std::table::{Self, Table};
    use aptos_std::math128::{Self as math128};
    use dev::QiaraTokenTypesV47::{Self as TokensType};
    use dev::QiaraChainTypesV47::{Self as ChainTypes};
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use dev::QiaraStorageV20::{Self as storage, Access as StorageAccess};

    use dev::QiaraSharedV17::{Self as Shared, OwnershipView as Ownership, RefCodeParams};

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_NOT_REGISTERED: u64 = 2;
    const ERROR_SOME_OF_REWARD_STRUCT_IS_NONE: u64 = 3;
    const ERROR_SOME_OF_INTEREST_STRUCT_IS_NONE: u64 = 4;



// === ACCESS === //
    struct Access has store, key, drop {}
    struct Permission has key, drop {}

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @dev, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_permission(access: &Access): Permission {
        Permission {}
    }
// === STRUCTS === //
    // (shared storage owner) -> points
    struct UsersProfile has key {
        table: Table<String, User>,
    }

    struct User has store, key {
        first_interaction: u64,
        experience: u256,
        custom_rank: String,
    }

    struct ViewUser has copy, drop, store{
        ownership: Ownership,
        ref_code_params: RefCodeParams,
        first_interaction: u64,
        experience: u256,
        experience_to_this_level: u256,
        experience_to_next_level: u256,
        level: u256,
        rank: String,
        custom_rank: String,
        fee_deduction: u256,
        ltv_increase: u256,
        withdraval_over_limit: u256,
        increased_qburned_reward_rate: u256,
        xp_multiplier: u256,
    }

    struct ViewRank has copy, drop, store{
        level_treshold: u256,
        rank: String,
        fee_deduction: u256,
        ltv_increase: u256,
        withdraval_over_limit: u256,
        increased_qburned_reward_rate: u256,
    }

// === INIT === //
    fun init_module(admin: &signer){
        if (!exists<UsersProfile>(@dev)) {
            move_to(admin,UsersProfile {table: table::new<String, User>()});
        };
    }

// === ENTRY FUN === //

    public fun ensure_user(table: &mut UsersProfile, shared: String): &mut User{
        Shared::assert_shared_storage(shared);
        if (!table::contains(&table.table, shared)) {
            table::add(&mut table.table, shared, User {first_interaction: timestamp::now_seconds(), experience: 0, custom_rank: utf8(b"None")});
        };
        return table::borrow_mut(&mut table.table, shared)
    }

    public entry fun set_custom_rank(shared: String, custom_rank: String) acquires UsersProfile{
        let user  = ensure_user(borrow_global_mut<UsersProfile>(@dev),shared);
        let user_struct = table::borrow_mut(&mut borrow_global_mut<UsersProfile>(@dev).table, shared);
        user_struct.custom_rank = custom_rank;
    }

    public entry fun test_add_experience(shared: String, n_points: u256) acquires UsersProfile{
        let user  = ensure_user(borrow_global_mut<UsersProfile>(@dev),shared);
        user.experience = user.experience + n_points;
    }

    public fun add_experience(shared: String, n_points: u256, perm: Permission) acquires UsersProfile{
        let user  = ensure_user(borrow_global_mut<UsersProfile>(@dev),shared);
        user.experience = user.experience + n_points;
    }

    fun tttta(number: u64){
        abort(number);
    }


// === PUBLIC VIEWS === //
    #[view]
    public fun return_shared_rank(shared: String): ViewUser acquires UsersProfile{
        let points_table = borrow_global<UsersProfile>(@dev);
   //             tttta(1);
        let ownership = Shared::return_shared_ownership_new(shared);
                    //    tttta(10);
        let (xp_tax, fee_tax) = Shared::extract_raw_params(ownership);
        //tttta(2);
        let (gas_fee_reduction, xp_increased) = calculate_actual_ref_code_taxes_from_shared(fee_tax, xp_tax);
        if(!table::contains(&points_table.table, shared)){
            return ViewUser {
                ownership: ownership,
                ref_code_params: Shared::extract_used_ref_code_params(ownership),
                first_interaction: 0,
                experience: 0,
                experience_to_this_level: 0,
                experience_to_next_level: return_xp_needed_to_level(1),
                level: 0,
                rank: utf8(b"Iron"),
                custom_rank: utf8(b"None"),
                fee_deduction: 0 + (gas_fee_reduction as u256),
                ltv_increase: 0,
                withdraval_over_limit: 0,
                increased_qburned_reward_rate: 0,
                xp_multiplier: 0 + (xp_increased as u256),

            }
        };

        let user = table::borrow(&points_table.table, shared);
        let level = return_level_from_xp(user.experience);
        let rank = convert_level_to_rank(level);

        if(user.custom_rank != utf8(b"None")){
            rank = user.custom_rank;
        };

        let (xp_multiplier, _, _) = calculate_xp_multiplier(user.first_interaction);
        return ViewUser {
            ownership: ownership,
            ref_code_params: Shared::extract_used_ref_code_params(ownership),
            first_interaction: user.first_interaction,
            experience: user.experience,
            experience_to_this_level: return_xp_needed_to_level(level),
            experience_to_next_level: return_xp_needed_to_level(level+1),
            level: level,
            rank: rank,
            custom_rank: user.custom_rank,
            fee_deduction: calculate_fee_deduction(convert_rank_to_power(rank)) + (gas_fee_reduction as u256),
            ltv_increase: calculate_ltv_increase(convert_rank_to_power(rank)),
            withdraval_over_limit: calculate_withdrawal_over_limit(convert_rank_to_power(rank)),
            increased_qburned_reward_rate: calculate_increased_qburned_reward_rate(convert_rank_to_power(rank)),
            xp_multiplier: xp_multiplier + (xp_increased as u256),
        }
    }

    #[view]
    public fun return_raw_shared_rank(shared: String): (u256, u256, u256) acquires UsersProfile{
        let points_table = borrow_global<UsersProfile>(@dev);
        let ownership = Shared::return_shared_ownership_new(shared);
        if(!table::contains(&points_table.table, shared)){
            return (0, 0, 0);
        };

        let user = table::borrow(&points_table.table, shared);
        let level = return_level_from_xp(user.experience);
        let rank = convert_level_to_rank(level);

        if(user.custom_rank != utf8(b"None")){
            rank = user.custom_rank;
        };

        return (calculate_fee_deduction(convert_rank_to_power(rank)), calculate_ltv_increase(convert_rank_to_power(rank)), calculate_withdrawal_over_limit(convert_rank_to_power(rank)))
    
    }

    #[view]
    public fun view_ranks(rank: vector<String>): vector<ViewRank>{
        let len = vector::length(&rank);
        let vect = vector::empty<ViewRank>();

        while(len>0){
            let rank = *vector::borrow(&rank, len-1);
            let rank_ =  ViewRank {
                level_treshold: ((convert_rank_to_power(rank)*10) as u256),
                rank: rank,
                fee_deduction: calculate_fee_deduction(convert_rank_to_power(rank)),
                ltv_increase: calculate_ltv_increase(convert_rank_to_power(rank)),
                withdraval_over_limit: calculate_withdrawal_over_limit(convert_rank_to_power(rank)),
                increased_qburned_reward_rate: calculate_increased_qburned_reward_rate(convert_rank_to_power(rank)),
            };
            len = len-1;
            vector::push_back(&mut vect, rank_);
        }

        return vect
    }

    #[view]
    public fun return_multiple_shared_rank(shared: vector<String>): Map<String, ViewUser> acquires UsersProfile{
        let points_table = borrow_global<UsersProfile>(@dev);

        let map = map::new<String, ViewUser>();

        let len = vector::length(&shared);
        while(len>0){
            let shared = vector::borrow(&shared, len-1);
            let viewUser = return_shared_rank(*shared);
            map::upsert(&mut map, *shared, viewUser);
            len = len-1
        };
        return map
    }
//5846000000000000000000
//100000000000000000000000000
//100000000000000000000
    #[view]
    public fun return_xp_needed_to_level(level: u256): u256{
       let base_xp = return_base_xp_increase();
       return base_xp*level*level
    }

    #[view]
    public fun return_level_from_xp(total_xp: u256): u256 {
        let base_xp = (return_base_xp_increase() as u256);
        
        if (total_xp == 0) return 0;

        let ratio = total_xp / base_xp;
        
        let level_u128 = math128::sqrt((ratio as u128));
        
        (level_u128 as u256)
    }

    #[view]
    public fun return_base_xp_increase(): u256{
        (storage::expect_u64(storage::viewConstant(utf8(b"QiaraRanks"), utf8(b"BASE_XP"))) as u256)*1000000000000000000/1_000_000
    }
    #[view]
    public fun return_fee_points_conversion(): u256{ // 1$ fee = 1 xp
        (storage::expect_u64(storage::viewConstant(utf8(b"QiaraRanks"), utf8(b"ANY_FEE_CONVERSION"))) as u256)
    }
    #[view]
    public fun return_perp_volume_points_conversion(): u256{ // 1000$ volume = 1 xp
        (storage::expect_u64(storage::viewConstant(utf8(b"QiaraRanks"), utf8(b"PERPS_VOLUME_CONVERSION"))) as u256)
    }
    #[view]
    public fun return_market_liquidity_provision_points_conversion(): u256{
        (storage::expect_u64(storage::viewConstant(utf8(b"QiaraRanks"), utf8(b"MARKET_LIQUIDITY_PROVISION_CONVERSION"))) as u256)
    }
    #[view]
    public fun return_free_daily_claim_points(): u256{ // 10 xp/day free claim
        (storage::expect_u64(storage::viewConstant(utf8(b"QiaraRanks"), utf8(b"DAILY_CLAIM"))) as u256)
    }

    #[view]
    public fun return_fee_deduction_per_power(): u256{ 
        (storage::expect_u64(storage::viewConstant(utf8(b"QiaraRanks"), utf8(b"FEE_DEDUCTION_PER_POWER"))) as u256)
    }
    #[view]
    public fun return_ltv_increase_per_power(): u256{ 
        (storage::expect_u64(storage::viewConstant(utf8(b"QiaraRanks"), utf8(b"LTVP_INCREASE_PER_POWER"))) as u256)
    }
    #[view]
    public fun return_withdrawal_over_limit_per_power(): u256{
        (storage::expect_u64(storage::viewConstant(utf8(b"QiaraRanks"), utf8(b"WITHDRAWAL_OVER_LIMIT_PER_POWER"))) as u256)
    }
    #[view]
    public fun return_increased_qburned_reward_rate_per_power(): u256{
        (storage::expect_u64(storage::viewConstant(utf8(b"QiaraRanks"), utf8(b"INCREASED_QBURNED_REWARD_RATE_PER_POWER"))) as u256)
    }
    #[view]
    public fun return_base_xp_multi_per_day(): u128{
        (storage::expect_u64(storage::viewConstant(utf8(b"QiaraRanks"), utf8(b"BASE_XP_MULTI_PER_DAY"))) as u128)
    }
    #[view]
    public fun return_scaler_xp_multi_per_day(): u128{
        (storage::expect_u64(storage::viewConstant(utf8(b"QiaraRanks"), utf8(b"SCALER_XP_MULTI_PER_DAY"))) as u128)
    }
    #[view]
    public fun return_exponent_xp_multi_per_day(): u128{
        (storage::expect_u64(storage::viewConstant(utf8(b"QiaraRanks"), utf8(b"EXPONENT_XP_MULTI_PER_DAY"))) as u128)
    }


    //deprecated remove in future
    #[view]
    public fun calculate_ref_code_taxes_directly(shared: String): (u64, u64, String) {

        let ownership = Shared::return_shared_ownership_new(shared);
                    //    tttta(10);
        let (xp_tax, fee_tax) = Shared::extract_raw_params(ownership);
        let (gas_fee_reduction, xp_increased) = calculate_actual_ref_code_taxes_from_shared(fee_tax, xp_tax);
        let used_ref_code = Shared::extract_used_ref_code(ownership);

        (gas_fee_reduction, xp_increased, used_ref_code)

    }

//50000000
//50000000
//50000000
//50000000

    #[view]
    public fun calculate_actual_ref_code_taxes_from_shared(ref_code_gas_tax: u64, ref_code_xp_tax: u64): (u64, u64) {
        let base_gas_reduction = storage::expect_u64(storage::viewConstant(utf8(b"QiaraShared"), utf8(b"BASE_SHARED_FEE_REDUCTION")));
        let base_xp_increase = storage::expect_u64(storage::viewConstant(utf8(b"QiaraShared"), utf8(b"BASE_SHARED_XP_INCREASE")));

        let scale = 100_000_000;


        // 10_000_000 * 500_000

        // e.g., (10_000_000 * 1_000_000) / 100_000_000 
        // (500_000_000_000_000 / 100_000_000 )
        // 5_000_000, which equals 5% (correct)
        let actual_gas_reduction_for_ref_code_user = base_gas_reduction - (base_gas_reduction * ref_code_gas_tax) / scale ;
        let actual_xp_increase_for_ref_code_user = base_xp_increase - (base_xp_increase * ref_code_xp_tax) / scale;

        (actual_gas_reduction_for_ref_code_user, actual_xp_increase_for_ref_code_user)

    }

    // returns:
    // arg1 - the amount saved for used (i.e., the discount from the innitial base discount combined with the % tax of ref code from the discount)
    #[view]
    public fun calculate_ref_code_taxes(ref_code_gas_tax: u64, ref_code_xp_tax: u64, gas_fee: u256, xp_earned: u256): (u256, u256, u256, u256) {
        let scale = 100_000_000;
        
        // 1. Query raw base configuration parameters
        let base_gas_reduction = storage::expect_u64(storage::viewConstant(utf8(b"QiaraShared"), utf8(b"BASE_SHARED_FEE_REDUCTION")));
        let base_xp_increase = storage::expect_u64(storage::viewConstant(utf8(b"QiaraShared"), utf8(b"BASE_SHARED_XP_INCREASE")));

        // 2. Fetch the calculated actual user rates
        let (actual_gas_reduction, actual_xp_increase) = calculate_actual_ref_code_taxes_from_shared(ref_code_gas_tax, ref_code_xp_tax);

        // 3. Calculate gross base discount/bonus amounts
        let base_gas_discount_amount = (gas_fee * (base_gas_reduction as u256)) / scale;
        let base_xp_increase_amount = (xp_earned * (base_xp_increase as u256)) / scale;

        // 4. Calculate actual net user savings/bonus amounts
        let user_gas_savings = (gas_fee * (actual_gas_reduction as u256)) / scale;
        let user_xp_bonus = (xp_earned * (actual_xp_increase as u256)) / scale;

        // 5. Referrer's share is the baseline discount minus what the user saved [3]
        let referrer_gas_share = base_gas_discount_amount - user_gas_savings;
        let referrer_xp_share = base_xp_increase_amount - user_xp_bonus;

        (user_gas_savings, user_xp_bonus, referrer_gas_share, referrer_xp_share)
    }

    fun calculate_fee_deduction(power: u8): u256{
        let deduction_percentage = (power as u256) * return_fee_deduction_per_power(); // each rank power gives 5% fee deductionpower as u256 * 5; // each rank power gives 5% fee deduction
        return deduction_percentage
    }
    fun calculate_ltv_increase(power: u8): u256{
    
        if(power<=2){ // minimum rank to have ltv increase is Gold (power 3)
            return 0;
        };
        let deducted = 2 * return_ltv_increase_per_power();
        let deduction_percentage = (power as u256) * return_ltv_increase_per_power(); // each rank power gives 5% fee deduction
        return deduction_percentage-deducted
    }
    fun calculate_withdrawal_over_limit(power: u8): u256{
        if(power<=4){ // minimum rank to have ltv increase is Gold (power 3)
            return 0;
        };
        let deducted = 4 * return_withdrawal_over_limit_per_power();

        let deduction_percentage = (power as u256) * return_withdrawal_over_limit_per_power(); // each rank power gives 5% fee deduction
        return deduction_percentage-deducted
    }
    fun calculate_increased_qburned_reward_rate(power: u8): u256{
        let increased_qburned_reward_rate = (power as u256) * return_increased_qburned_reward_rate_per_power(); // each rank power gives 5% fee deduction
        return increased_qburned_reward_rate
    }

//8100000000000000000000000000
//48400000000000000000000000000
//5220000000000000
//100000000000000000000
//100000000000000000000000000
//100000000000000000000000000
//1000000000000000000

//317999682000000000000000000
//72590400000000000000000000
    #[view]
    public fun calculate_xp_multiplier(first_interaction: u64): (u256, u256, u256) {
        let days = (((timestamp::now_seconds() - first_interaction) / 86400) as u256);
        let base = (return_base_xp_multi_per_day() as u256); // Raw value: 10_000 (0.01% on a 10^8 scale)
        let exponent = (return_exponent_xp_multi_per_day() as u256); // Raw value: 10_000 (0.01% on a 10^8 scale)
        let scaler = (return_scaler_xp_multi_per_day() as u256); // Raw value: 10_000 (0.01% on a 10^8 scale)
        let result: u256 = 0;
        let multiplier_scaled: u256 = 0;
        if (days > 0) {
            // 1. Correctly scale the days up by 1,000,000 and assign to a variable
            let days_scaled = days * 1_000_000; 
            
            // 2. Perform the calculation: Days * (Days_scaled + W45_scaled) / W44
            // W45 = 1,000 -> scaled by 1,000,000 is 1,000,000,000
            // W44 = 25,000
            // 14 * (14,000,000 + 1,000,000,000) / 25,000
            multiplier_scaled = (days * (days_scaled + exponent)) / scaler; 
            
            // 3. Multiply by your base rate
            result = multiplier_scaled * base; 
        };

        return (
            result , 
            days, 
            multiplier_scaled
        )
    }

    fun convert_level_to_rank(level: u256): String {
        if (level < 10) {
            return utf8(b"Iron")
        } else if (level < 20) {
            return utf8(b"Bronze")
        } else if (level < 30) {
            return utf8(b"Silver")
        } else if (level < 40) {
            return utf8(b"Gold")
        } else if (level < 50) {
            return utf8(b"Platinum")
        } else if (level < 60) {
            return utf8(b"Emerald")
        } else if (level < 70) {
            return utf8(b"Diamond")
        } else {
            return utf8(b"Obsidian")
        }
    }
    fun convert_rank_to_power(rank: String): u8{
        if(rank == utf8(b"Iron")){
            return 0
        } else if (rank == utf8(b"Bronze")){
            return 1
        } else if (rank == utf8(b"Silver")){
            return 2
        } else if (rank == utf8(b"Gold")){
            return 3
        } else if (rank == utf8(b"Platinum")){
            return 4
        } else if (rank == utf8(b"Emerald")){
            return 5
        } else if (rank == utf8(b"Diamond")){
            return 6
        } else if (rank == utf8(b"VIP I")){
            return 10
        } else if (rank == utf8(b"VIP II")){
            return 12
        } else if (rank == utf8(b"VIP III")){
            return 14
        } else {
            return 7
        }
        
    }

    public fun extract_gas_fee_reduction(view_user: ViewUser): u256{
        view_user.fee_deduction
    }
    public fun extract_xp_increase(view_user: ViewUser): u256{
        view_user.xp_multiplier
    }
    public fun extract_increased_qburned_reward_rate(view_user: ViewUser): u256{
        view_user.increased_qburned_reward_rate
    }
    public fun extract_withdrawal_over_limit(view_user: ViewUser): u256{
        view_user.withdraval_over_limit
    }

 }