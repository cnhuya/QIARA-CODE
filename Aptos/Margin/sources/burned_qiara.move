module dev::QiaraBurnedQiaraV48 {
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

    use dev::QiaraSharedV17::{Self as Shared, Access as SharedAccess};
    use dev::QiaraTokensCoreV47::{Self as TokensCore, Access as TokensCoreAccess};
    use dev::QiaraTokensQiaraV47::{Self as TokensQiara};
    use dev::QiaraStorageV20::{Self as storage};
    use dev::QiaraRanksV48::{Self as Ranks};

    use event::QiaraEventV1::{Self as Event};
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
        tracked_amounts: SmartTable<String, u64>,
        user_claims: SmartTable<String, UserClaimState>,  // NEW: track claim history
    }

    struct Permissions has key {
        token_core: TokensCoreAccess,
        shared: SharedAccess
    }

// === INIT === //

    fun init_module(admin: &signer){
        let deploy_addr = signer::address_of(admin);

        if (!exists<Permissions>(@dev)) {
            move_to(admin, Permissions { shared: Shared::give_access(admin), token_core: TokensCore::give_access(admin)});
        };

        if (!exists<BurnedQiara>(@dev)) {
            move_to(admin, BurnedQiara {
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

        let obj = Shared::ensure_shared_fungible_storage(shared,TokensCore::get_metadata(utf8(b"Qiara")), Shared::give_permission(&borrow_global<Permissions>(@dev).shared));
        let fa = TokensCore::withdraw(shared, obj, amount, utf8(b"Aptos"));
        
        // 1. Read the actual amount from the FungibleAsset resource BEFORE burning/consuming it
        let actual_amount = fungible_asset::amount(&fa);
        
        // 2. Burn the FungibleAsset (this consumes 'fa')
        TokensCore::burn_fa(utf8(b"Qiara"), utf8(b"Aptos"), fa, TokensCore::give_permission(&borrow_global<Permissions>(@dev).token_core));
        
        // Record the actual burned amount in our tracking table per shared name
        if (smart_table::contains(&burn_qiara.tracked_amounts, shared)) {
            let current_amount = smart_table::borrow_mut(&mut burn_qiara.tracked_amounts, shared);
            *current_amount = *current_amount + actual_amount;
        } else {
            smart_table::add(&mut burn_qiara.tracked_amounts, shared, actual_amount);
        };

        let obj = Shared::ensure_shared_fungible_storage(shared,TokensCore::get_metadata(utf8(b"Burned Qiara")), Shared::give_permission(&borrow_global<Permissions>(@dev).shared));
        
        // 3. Mint the exact post-fee 'actual_amount' that was burned
        let new_fa = TokensCore::mint(utf8(b"Burned Qiara"), utf8(b"Aptos"), actual_amount, TokensCore::give_permission(&borrow_global<Permissions>(@dev).token_core));
        
        claim_rewards(sender, shared);
        TokensCore::deposit(shared, obj, new_fa, utf8(b"Aptos"));
    }
    /// Claims accumulated rewards based on burned amount and time since last claim
    public entry fun claim_rewards(sender: &signer, shared: String) acquires BurnedQiara, Permissions {
        Shared::assert_is_sub_owner(shared, bcs::to_bytes(&signer::address_of(sender)));
        
        // 1. Fetch total_burned FIRST while global resource is not mutably borrowed
        let (total_burned, qiara_supply, _) = TokensQiara::get_ratio();
        
        // 2. Now mutably borrow BurnedQiara safely
        let burn_qiara = borrow_global_mut<BurnedQiara>(@dev);
        let current_time = timestamp::now_seconds();
        
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
        let (user_dedicated_reward_rate, base_reward_rate) = calculate_increased_reward_rate((user_increased_reward_rate as u64));
        let reward = calculate_reward(burned_amount, user_dedicated_reward_rate, time_elapsed);
        
        // Update last claim timestamp
        if (smart_table::contains(&burn_qiara.user_claims, shared)) {
            let state = smart_table::borrow_mut(&mut burn_qiara.user_claims, shared);
            state.last_claim_timestamp = current_time;
        };
        
        // Mint and deposit rewards if any
        if (reward > 0) {
            let obj = Shared::ensure_shared_fungible_storage(shared,TokensCore::get_metadata(utf8(b"Qiara")), Shared::give_permission(&borrow_global<Permissions>(@dev).shared));
            let reward_fa = TokensCore::mint(utf8(b"Qiara"), utf8(b"Aptos"), reward, TokensCore::give_permission(&borrow_global<Permissions>(@dev).token_core));
            TokensCore::deposit(shared, obj, reward_fa, utf8(b"Aptos"));
        };

        TokensQiara::emit_qiara_events();

    
    }


// === HELPER FUNCTIONS === //
   
    /// Calculates reward: (burned * rate * elapsed) / (PRECISION * SECONDS_PER_YEAR)
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
        
        // 1. Optimize tracked_amounts to a single lookup using borrow_with_default
        let default_amount = 0;
        let burned_amount = *smart_table::borrow_with_default(
            &burn_qiara.tracked_amounts, 
            shared_name, 
            &default_amount
        );
        
        // 2. Optimize user_claims lookup from 4 operations down to 1-2, and fix the copy-paste bug
        let (last_claim_timestamp) = if (smart_table::contains(&burn_qiara.user_claims, shared_name)) {
            let claim = smart_table::borrow(&burn_qiara.user_claims, shared_name);
            (claim.last_claim_timestamp)
        } else {
            (0) // Never claimed
        };
        
        UserBurnSummary {
            burned_amount,
            last_claim_timestamp,
        }
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
    public fun calculate_increased_reward_rate(increase: u64): (u64, u64) {
        let reward_rate = TokensQiara::get_burned_qiara_rate();
        let (_,_, ratio) = TokensQiara::get_ratio();
        let scale = 100_000_000;
        // 25_000_000 + 554 092 = 25 554 092
        // e.g., (25 554 092 * 50_000_000) / 100_000_000
        // (1 277 704 600 000 000 / 100_000_000 )
        // 12 777 046, which equals 12,77% (correct)
       ((reward_rate * increase) / scale, reward_rate)


    }

    #[view]
    public fun calculate_required_locked_tokens_u256(shared_name: String, dolars: u256): (u256, u256, bool) {
        let conversion_rate = (get_required_conversion_rate() as u256);
        let scale = 1_000_000;
        let user_burned = (get_user_burn_summary(shared_name).burned_amount as u256);

        if(user_burned == 0){
            return (0, 0, false);
        };
        // e.g., (10_000_000 / 1_000
        let actual_user_dedicated_reward_rate = (dolars/1000000000000000000) / conversion_rate;
        if ( user_burned >= actual_user_dedicated_reward_rate) {
            return (actual_user_dedicated_reward_rate, user_burned, true);
        };
        (actual_user_dedicated_reward_rate, user_burned, false)

    }

}