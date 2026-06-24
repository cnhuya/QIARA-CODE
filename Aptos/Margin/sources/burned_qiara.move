module dev::QiaraBurnedQiaraV20 {
    use std::signer;
    use std::option;
    use std::vector;
    use std::bcs;
    use std::timestamp;
    use std::type_info::{Self, TypeInfo};
    use aptos_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata, FungibleAsset, FungibleStore};
    use aptos_framework::dispatchable_fungible_asset;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::function_info;
    use aptos_framework::account;
    use aptos_framework::object::{Self, Object, ConstructorRef};
    use aptos_framework::event;
    use std::string::{Self as string, String, utf8};
    use aptos_std::smart_table::{Self, SmartTable};

    use dev::QiaraSharedV8::{Self as Shared};
    use dev::QiaraTokensCoreV23::{Self as TokensCore, Access as TokensCoreAccess};
    use dev::QiaraStorageV11::{Self as storage};
    use dev::QiaraRanksV20::{Self as Ranks};
// === CONSTANTS === //
    const ADMIN: address = @dev;
    const PRECISION: u64 = 1_000_000;  // 6 decimals for reward rate
    const SECONDS_PER_YEAR: u64 = 31_536_000;  // 365 * 24 * 60 * 60

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_NOT_AUTHORIZED_FOR_CLAIMING: u64 = 2;

// === ACCESS === //
    struct Access has store, key, drop {}
    struct Permission has copy, key, drop {}

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @dev, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_permission(access: &Access): Permission {
        Permission {}
    }
    
// === STRUCTS === //
    /// Tracks per-user claim state
    struct UserClaimState has copy, drop, store {
        last_claim_timestamp: u64,
    }

    struct UserBurnSummary has copy, drop {
        burned_amount: u64,
        last_claim_timestamp: u64,
    }

    /// Stores the secure custom fee store and tracks balance updates per shared name
    struct BurnedQiara has key {
        balances: Object<FungibleStore>,
        tracked_amounts: SmartTable<String, u64>,
        user_claims: SmartTable<String, UserClaimState>,  // NEW: track claim history
    }

    struct Permissions has key {
        token_core: TokensCoreAccess,
    }

// === INIT === //

    fun init_module(admin: &signer){
        let deploy_addr = signer::address_of(admin);

        if (!exists<Permissions>(@dev)) {
            move_to(admin, Permissions { token_core: TokensCore::give_access(admin)});
        };
    }

    public entry fun init_burned_qiara(admin: &signer){
        let deploy_addr = signer::address_of(admin);

        if (!exists<BurnedQiara>(@dev)) {
            let constructor_ref = &object::create_sticky_object(signer::address_of(admin));
            let metadata = TokensCore::get_metadata(utf8(b"Qiara"));
            let store = fungible_asset::create_store(constructor_ref, metadata);
            
            move_to(admin, BurnedQiara {
                balances: store,
                tracked_amounts: smart_table::new<String, u64>(),
                user_claims: smart_table::new<String, UserClaimState>(),  // Initialize new table
            });
        };
    }


// === ENTRY FUNCTIONS === //

    /// Deposits tokens from the user's primary store into our custom store and 
    /// tracks the accumulated amount sent by a specific 'shared_name' (string).
    public entry fun deposit_and_burn_qiara(sender: &signer, shared: String, amount: u64) acquires BurnedQiara, Permissions  {
        Shared::assert_is_sub_owner(shared, bcs::to_bytes(&signer::address_of(sender)));
        let burn_qiara = borrow_global_mut<BurnedQiara>(@dev);
        let to_store = burn_qiara.balances;
        
        // Get the metadata of your token from our custom store
        let metadata = fungible_asset::store_metadata(to_store);
        let sender_addr = signer::address_of(sender);
        let obj = primary_fungible_store::ensure_primary_store_exists(signer::address_of(sender),metadata);
        let fa = TokensCore::withdraw(shared, obj, amount, utf8(b"Aptos"));
        TokensCore::burn_fa(utf8(b"Qiara"), utf8(b"Aptos"), fa, TokensCore::give_permission(&borrow_global<Permissions>(@dev).token_core));
        

        // Record the transferred amount in our tracking table per shared name
        if (smart_table::contains(&burn_qiara.tracked_amounts, shared)) {
            let current_amount = smart_table::borrow_mut(&mut burn_qiara.tracked_amounts, shared);
            *current_amount = *current_amount + amount;
        } else {
            smart_table::add(&mut burn_qiara.tracked_amounts, shared, amount);
        };
        let obj = primary_fungible_store::ensure_primary_store_exists(signer::address_of(sender),TokensCore::get_metadata(utf8(b"Burned Qiara")));
        let new_fa = TokensCore::mint(utf8(b"Burned Qiara"), utf8(b"Aptos"), amount, TokensCore::give_permission(&borrow_global<Permissions>(@dev).token_core));
                claim_rewards(sender, shared);
        TokensCore::deposit(shared, obj, new_fa, utf8(b"Aptos"));
    }
    /// Claims accumulated rewards based on burned amount and time since last claim
    public entry fun claim_rewards(sender: &signer, shared: String) acquires BurnedQiara, Permissions {
        Shared::assert_is_sub_owner(shared, bcs::to_bytes(&signer::address_of(sender)));
        
        let burn_qiara = borrow_global_mut<BurnedQiara>(@dev);
        let current_time = timestamp::now_seconds();
        let sender_addr = signer::address_of(sender);
        
        // Get burned amount for this shared name
        let burned_amount = if (smart_table::contains(&burn_qiara.tracked_amounts, shared)) {
            *smart_table::borrow(&burn_qiara.tracked_amounts, shared)
        } else {
            0
        };
        
        if (burned_amount == 0) {
            return;  // Nothing burned, nothing to reward
        };
        
        // Get or initialize user claim state
        let last_claim = if (smart_table::contains(&burn_qiara.user_claims, shared)) {
            smart_table::borrow(&burn_qiara.user_claims, shared).last_claim_timestamp
        } else {
            // First claim: initialize with current time (no backdated rewards)
            smart_table::add(&mut burn_qiara.user_claims, shared, UserClaimState { last_claim_timestamp: current_time });
            current_time
        };
        
        // Calculate time elapsed and rewards
        let time_elapsed = current_time - last_claim;
        let view_user_rank = Ranks::return_shared_rank(shared);
        let user_increased_reward_rate = Ranks::extract_gas_fee_reduction(view_user_rank);
        let reward_rate = calculate_increased_reward_rate((user_increased_reward_rate as u64));
        let reward = calculate_reward(burned_amount, reward_rate, time_elapsed);
        
        // Update last claim timestamp
        if (smart_table::contains(&burn_qiara.user_claims, shared)) {
            let state = smart_table::borrow_mut(&mut burn_qiara.user_claims, shared);
            state.last_claim_timestamp = current_time;
        };
        
        // Mint and deposit rewards if any
        if (reward > 0) {
            let reward_metadata = TokensCore::get_metadata(utf8(b"Qiara")); // Reward token
            let obj = primary_fungible_store::ensure_primary_store_exists(sender_addr, reward_metadata);
            let reward_fa = TokensCore::mint(
                utf8(b"Qiara"), 
                utf8(b"Aptos"), 
                reward, 
                TokensCore::give_permission(&borrow_global<Permissions>(@dev).token_core)
            );
            TokensCore::deposit(shared, obj, reward_fa, utf8(b"Aptos"));
        };
    }


// === HELPER FUNCTIONS === //
   
    /// Calculates reward: (burned * rate * elapsed) / (PRECISION * SECONDS_PER_YEAR)
    /// Uses u128 intermediates to prevent overflow
    #[view]
    public fun calculate_reward(burned_amount: u64, reward_rate: u64, time_elapsed: u64): u64 {
        if (burned_amount == 0 || time_elapsed == 0 || reward_rate == 0) {
            return 0;
        };
        
        let numerator = (burned_amount as u128) * (reward_rate as u128) * (time_elapsed as u128);
        let denominator = (PRECISION as u128) * (SECONDS_PER_YEAR as u128);
        
        (numerator / denominator) as u64
    }

    /// View: Returns both burned amount and last claim timestamp for a shared name
    #[view]
    public fun get_user_burn_summary(shared_name: String): UserBurnSummary acquires BurnedQiara {
        let burn_qiara = borrow_global<BurnedQiara>(@dev);
        
        // Get burned amount
        let burned_amount = if (smart_table::contains(&burn_qiara.tracked_amounts, shared_name)) {
            *smart_table::borrow(&burn_qiara.tracked_amounts, shared_name)
        } else {
            0
        };
        
        // Get last claim timestamp
        let last_claim = if (smart_table::contains(&burn_qiara.user_claims, shared_name)) {
            smart_table::borrow(&burn_qiara.user_claims, shared_name).last_claim_timestamp
        } else {
            0  // Never claimed
        };
        
        UserBurnSummary {
            burned_amount,
            last_claim_timestamp: last_claim,
        }
    }

    /// View function to query the total tracked deposited amount for a specific shared name.
    #[view]
    public fun get_tracked_burned_amount(shared_name: String): u64 acquires BurnedQiara {
        let burn_qiara = borrow_global<BurnedQiara>(@dev);
        if (smart_table::contains(&burn_qiara.tracked_amounts, shared_name)) {
            *smart_table::borrow(&burn_qiara.tracked_amounts, shared_name)
        } else {
            0
        }
    }

    /// View function to query the metadata of the token that this store tracks.
    #[view]
    public fun get_tracked_token_metadata(): Object<Metadata> acquires BurnedQiara {
        let burn_qiara = borrow_global<BurnedQiara>(@dev);
        fungible_asset::store_metadata(burn_qiara.balances)
    }

    #[view]
    public fun get_reward_rate(): u64 {
        storage::expect_u64(storage::viewConstant(utf8(b"QiaraToken"), utf8(b"LOCKED_QIARA_REWARD_RATE")))
    }

    #[view]
    public fun get_required_conversion_rate(): u64 {
        storage::expect_u64(storage::viewConstant(utf8(b"QiaraToken"), utf8(b"REQUIRED_BURNED_TOKENS_FOR_REWARDS")))
    }

    #[view]
    public fun calculate_increased_reward_rate(increase: u64): (u64) {
        let base_reward_rate = get_reward_rate();
        let scale = 1_000_000;
        // e.g., (10_000_000 * 50_000_000) / 100_000_000 / 100
        // (500_000_000_000_000 / 100_000_000 )/ 100
        // (500_000_000 / 100)
        // 5_000_000, which equals 5% (correct)
        let actual_user_dedicated_reward_rate = (base_reward_rate * increase) / scale / 100;

        actual_user_dedicated_reward_rate

    }

    #[view]
    public fun calculate_required_locked_tokens(shared_name: String, dolars: u64): (u64, u64, bool) {
        let conversion_rate = get_required_conversion_rate();
        let scale = 1_000_000;
        let user_burn_summary = get_user_burn_summary(shared_name);
        if(user_burn_summary.burned_amount == 0){
            return (0, 0, true);
        };
        // e.g., (10_000_000 / 1_000
        let actual_user_dedicated_reward_rate = (dolars/1000000000000000000) / conversion_rate;
        if ( user_burn_summary.burned_amount >= actual_user_dedicated_reward_rate) {
            return (actual_user_dedicated_reward_rate, user_burn_summary.burned_amount, true);
        };
        (actual_user_dedicated_reward_rate, user_burn_summary.burned_amount, false)

    }

    #[view]
    public fun calculate_required_locked_tokens_u256(shared_name: String, dolars: u256): (u256, u256, bool) {
        let conversion_rate = (get_required_conversion_rate() as u256);
        let scale = 1_000_000;
        let user_burned = (get_user_burn_summary(shared_name).burned_amount as u256);

        if(user_burned == 0){
            return (0, 0, true);
        };
        // e.g., (10_000_000 / 1_000
        let actual_user_dedicated_reward_rate = (dolars/1000000000000000000) / conversion_rate;
        if ( user_burned >= actual_user_dedicated_reward_rate) {
            return (actual_user_dedicated_reward_rate, user_burned, true);
        };
        (actual_user_dedicated_reward_rate, user_burned, false)

    }

}