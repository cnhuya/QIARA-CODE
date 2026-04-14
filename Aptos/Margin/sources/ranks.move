module dev::QiaraRanksV2{
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::vector;
    use std::table::{Self, Table};
    use aptos_std::math128::{Self as math128};
    use dev::QiaraTokenTypesV4::{Self as TokensType};
    use dev::QiaraChainTypesV4::{Self as ChainTypes};
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};

    use dev::QiaraStorageV1::{Self as storage, Access as StorageAccess};

    use dev::QiaraSharedV1::{Self as Shared, Ownership};

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
        experience: u256,
        custom_rank: String,
    }

    struct ViewUser has copy, drop, store{
        ownership: Ownership,
        experience: u256,
        experience_to_this_level: u256,
        experience_to_next_level: u256,
        level: u256,
        rank: String,
        custom_rank: String,
        fee_deduction: u256,
        ltv_increase: u256,
        withdraval_over_limit: u256,
    }

    struct ViewRank has copy, drop, store{
        level_treshold: u256,
        rank: String,
        fee_deduction: u256,
        ltv_increase: u256,
        withdraval_over_limit: u256,
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
            table::add(&mut table.table, shared, User {experience: 0, custom_rank: utf8(b"None")});
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


// === PUBLIC VIEWS === //
    #[view]
    public fun return_shared_rank(shared: String): ViewUser acquires UsersProfile{
        let points_table = borrow_global<UsersProfile>(@dev);
        let ownership = Shared::return_shared_ownership_new(shared);
        if(!table::contains(&points_table.table, shared)){
            return ViewUser {
                ownership: ownership,
                experience: 0,
                experience_to_this_level: 0,
                experience_to_next_level: 0,
                level: 0,
                rank: utf8(b"Iron"),
                custom_rank: utf8(b"None"),
                fee_deduction: 0,
                ltv_increase: 0,
                withdraval_over_limit: 0,
            }
        };

        let user = table::borrow(&points_table.table, shared);
        let level = return_level_from_xp(user.experience);
        let rank = convert_level_to_rank(level);

        if(user.custom_rank != utf8(b"None")){
            rank = user.custom_rank;
        };

        return ViewUser {
            ownership: ownership,
            experience: user.experience,
            experience_to_this_level: return_xp_needed_to_level(level),
            experience_to_next_level: return_xp_needed_to_level(level+1),
            level: level,
            rank: rank,
            custom_rank: user.custom_rank,
            fee_deduction: calculate_fee_deduction(convert_rank_to_power(rank)),
            ltv_increase: calculate_ltv_increase(convert_rank_to_power(rank)),
            withdraval_over_limit: calculate_withdrawal_over_limit(convert_rank_to_power(rank)),
        }
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
        (storage::expect_u64(storage::viewConstant(utf8(b"QiaraRanks"), utf8(b"BASE_XP"))) as u256)*1000000000000000000
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


    fun calculate_fee_deduction(power: u8): u256{
        let deduction_percentage = (power as u256) * return_fee_deduction_per_power(); // each rank power gives 5% fee deductionpower as u256 * 5; // each rank power gives 5% fee deduction
        return deduction_percentage
    }
    fun calculate_ltv_increase(power: u8): u256{
        if(power>=2){ // minimum rank to have ltv increase is Gold (power 3)
            return 0
        };
        let deduction_percentage = (power as u256) * return_ltv_increase_per_power(); // each rank power gives 5% fee deduction
        return deduction_percentage
    }
    fun calculate_withdrawal_over_limit(power: u8): u256{

        if(power>=4){ // minimum rank to have ltv increase is Emerald (power 5)
            return 0
        };

        let deduction_percentage = (power as u256) * return_withdrawal_over_limit_per_power(); // each rank power gives 5% fee deduction
        return deduction_percentage
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
        } else {
            return 7
        }
    }
 }