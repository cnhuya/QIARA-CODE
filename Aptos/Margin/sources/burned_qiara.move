module dev::QiaraBurnedQiaraV85 {
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

    use dev::QiaraSharedV18::{Self as Shared, Access as SharedAccess};
    use dev::QiaraTokensCoreV85::{Self as TokensCore, Access as TokensCoreAccess};
    use dev::QiaraTokensQiaraV85::{Self as TokensQiara, Access as TokensQiaraAccess};
    use dev::QiaraStorageV24::{Self as storage};
    use dev::QiaraRanksV85::{Self as Ranks};

    use event::QiaraEventV1::{Self as Event};

// === CONSTANTS === //
    const ADMIN: address = @dev;
    const PRECISION: u64 = 1_000_000;          // 6 decimals for reward rate
    const SECONDS_PER_YEAR: u64 = 31_536_000;   // 365 * 24 * 60 * 60

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_NOT_AUTHORIZED_FOR_CLAIMING: u64 = 2;
    const ERROR_ZERO_AMOUNT: u64 = 3;

// === ACCESS === //
    struct Access has store, key, drop {}
    struct Permission has copy, key, drop {}

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == ADMIN, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_permission(_access: &Access): Permission {
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
        user_claims: SmartTable<String, UserClaimState>,
    }

    struct Permissions has key {
        tokens_qiara: TokensQiaraAccess,
        token_core: TokensCoreAccess,
        shared: SharedAccess,
    }

// === INIT === //

    fun init_module(admin: &signer) {
        if (!exists<Permissions>(ADMIN)) {
            move_to(admin, Permissions { 
                tokens_qiara: TokensQiara::give_access(admin),
                shared: Shared::give_access(admin), 
                token_core: TokensCore::give_access(admin),
            });
        };

        if (!exists<BurnedQiara>(ADMIN)) {
            move_to(admin, BurnedQiara {
                tracked_amounts: smart_table::new<String, u64>(),
                user_claims: smart_table::new<String, UserClaimState>(),
            });
        };
    }

// === ENTRY FUNCTIONS === //

    /// Burns canonical QIARA directly from the user's primary store, credits their 'shared' identity,
    /// and mints internal 'Burned Qiara' receipt tokens to the shared wallet storage.
    public entry fun deposit_and_burn_qiara(
        sender: &signer, 
        shared: String, 
        amount: u64
    ) acquires BurnedQiara, Permissions {
        assert!(amount > 0, ERROR_ZERO_AMOUNT);
        let sender_addr = signer::address_of(sender);
        Shared::assert_is_sub_owner(shared, bcs::to_bytes(&sender_addr));

        // 1. Settle any pending rewards accrued prior to this new burn
        claim_rewards(sender, shared);

        // 2. Burn canonical QIARA directly from user's primary fungible store
        let perms = borrow_global<Permissions>(ADMIN);
        let qiara_perm = TokensQiara::give_permission(&perms.tokens_qiara);
        TokensQiara::burn_from_user(sender_addr, amount, &qiara_perm);

        // 3. Record the burned amount in our tracking table per shared name
        let burn_qiara = borrow_global_mut<BurnedQiara>(ADMIN);
        if (smart_table::contains(&burn_qiara.tracked_amounts, shared)) {
            let current_amount = smart_table::borrow_mut(&mut burn_qiara.tracked_amounts, shared);
            *current_amount = *current_amount + amount;
        } else {
            smart_table::add(&mut burn_qiara.tracked_amounts, shared, amount);
        };

        // 4. Mint internal 'Burned Qiara' receipt token into shared storage for Ranks / Margin systems
        let shared_perm = Shared::give_permission(&perms.shared);
        let obj = Shared::ensure_shared_fungible_storage(
            shared,
            TokensCore::get_metadata(utf8(b"Burned Qiara")), 
            shared_perm
        );
        
        let core_perm = TokensCore::give_permission(&perms.token_core);
        let new_fa = TokensCore::mint(
            utf8(b"Burned Qiara"), 
            utf8(b"Aptos"), 
            amount, 
            core_perm
        );
        TokensCore::deposit(shared, obj, new_fa, utf8(b"Aptos"));
    }

    /// Claims accumulated rewards based on burned amount and time elapsed,
    /// minting canonical QIARA directly to the user's primary fungible store.
    public entry fun claim_rewards(
        sender: &signer, 
        shared: String
    ) acquires BurnedQiara, Permissions {
        let sender_addr = signer::address_of(sender);
        Shared::assert_is_sub_owner(shared, bcs::to_bytes(&sender_addr));
        
        // Fetch total ratio/burned if needed by ratio logic
        let (_total_burned, _qiara_supply, _) = TokensQiara::get_ratio();
        
        let burn_qiara = borrow_global_mut<BurnedQiara>(ADMIN);
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
        let (user_dedicated_reward_rate, _base_reward_rate) = calculate_increased_reward_rate((user_increased_reward_rate as u64));
        let reward = calculate_reward(burned_amount, user_dedicated_reward_rate, time_elapsed);
        
        // Update last claim timestamp
        if (smart_table::contains(&burn_qiara.user_claims, shared)) {
            let state = smart_table::borrow_mut(&mut burn_qiara.user_claims, shared);
            state.last_claim_timestamp = current_time;
        };
        
        // Mint canonical QIARA rewards directly to user's primary store
        if (reward > 0) {
            let perms = borrow_global<Permissions>(ADMIN);
            let qiara_perm = TokensQiara::give_permission(&perms.tokens_qiara);
            TokensQiara::mint_to_user(sender_addr, reward, &qiara_perm);
        };

        TokensQiara::emit_qiara_events();
    }

// === HELPER & VIEW FUNCTIONS === //
   
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
        let burn_qiara = borrow_global<BurnedQiara>(ADMIN);
        
        let default_amount = 0;
        let burned_amount = *smart_table::borrow_with_default(
            &burn_qiara.tracked_amounts, 
            shared_name, 
            &default_amount
        );
        
        let last_claim_timestamp = if (smart_table::contains(&burn_qiara.user_claims, shared_name)) {
            let claim = smart_table::borrow(&burn_qiara.user_claims, shared_name);
            claim.last_claim_timestamp
        } else {
            0
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
        let scale = 100_000_000;
        let increased_rate = (((reward_rate as u128) * (increase as u128) / (scale as u128)) as u64);
        (increased_rate, reward_rate)
    }

    #[view]
    public fun calculate_required_locked_tokens_u256(shared_name: String, dolars: u256): (u256, u256, bool) {
        let conversion_rate = (get_required_conversion_rate() as u256);
        let user_burned = (get_user_burn_summary(shared_name).burned_amount as u256);

        if (user_burned == 0 || conversion_rate == 0) {
            return (0, user_burned, false);
        };
        
        let actual_user_dedicated_reward_rate = (dolars / 1_000_000_000_000_000_000) / conversion_rate;
        if (user_burned >= actual_user_dedicated_reward_rate) {
            return (actual_user_dedicated_reward_rate, user_burned, true);
        };
        (actual_user_dedicated_reward_rate, user_burned, false)
    }
}