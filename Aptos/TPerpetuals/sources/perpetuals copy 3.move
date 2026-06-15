module perp::non_liquidative_perp {
    use aptos_framework::timestamp;
    use aptos_std::smart_table::{Self, SmartTable};
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_coin::AptosCoin;

    const E_NOT_AUTHORIZED: u64 = 1;
    const E_POSITION_NOT_FOUND: u64 = 2;
    const E_INSUFFICIENT_COLLATERAL: u64 = 3;
    const E_ZERO_AMOUNT: u64 = 4;
    const E_PRICE_NOT_UPDATED: u64 = 5;

    const BASE_INTEREST_RATE: u64 = 4; // 4% annualized (scaled by 100)
    const EXPONENTIAL_SCALE: u64 = 10000; // For precision
    const INTEREST_SCALE: u64 = 1000000;
    const UPDATE_INTERVAL_SECONDS: u64 = 30;

    struct Position has store {
        collateral: u64,
        initial_price: u64,
        last_interest_time: u64,
        accrued_interest: u64,
    }

    struct Market has key {
        cumulative_price: u64,
        last_update_time: u64,
        current_twap: u64,
        positions: SmartTable<address, Position>,
        keeper_reward: u64,
    }

    public fun initialize_market(admin: &signer, keeper_reward: u64) {
        let market = Market {
            cumulative_price: 0,
            last_update_time: timestamp::now_seconds(),
            current_twap: 0,
            positions: smart_table::new(),
            keeper_reward,
        };
        move_to(admin, market);
    }

    public fun update_twap(market_addr: address, current_price: u64) acquires Market {
        let market = borrow_global_mut<Market>(market_addr);
        let now = timestamp::now_seconds();
        let time_delta = now - market.last_update_time;
        
        if (time_delta >= UPDATE_INTERVAL_SECONDS) {
            let new_cumulative = market.cumulative_price + (market.current_twap * time_delta);
            market.cumulative_price = new_cumulative;
            market.last_update_time = now;
            market.current_twap = new_cumulative / (now - market.last_update_time);
        } else {
            // Still update with current price for continuous accumulation
            market.cumulative_price = market.cumulative_price + (current_price * time_delta);
            market.last_update_time = now;
            market.current_twap = market.cumulative_price / (now - market.last_update_time);
        };

        // Pay keeper reward
        if (market.keeper_reward > 0) {
            let keeper = signer::address_of(&timestamp::now_seconds()); // Simplified - pass actual keeper
            // In production: transfer reward from fee pool to keeper
        };
    }

    public fun open_position(
        user: &signer,
        market_addr: address,
        collateral: u64,
        price: u64,
    ) acquires Market {
        assert!(collateral > 0, E_ZERO_AMOUNT);
        
        let market = borrow_global_mut<Market>(market_addr);
        let user_addr = signer::address_of(user);
        
        // Ensure TWAP is up to date
        if (timestamp::now_seconds() - market.last_update_time >= UPDATE_INTERVAL_SECONDS) {
            update_twap(market_addr, price);
        };
        
        let position = Position {
            collateral,
            initial_price: market.current_twap,
            last_interest_time: timestamp::now_seconds(),
            accrued_interest: 0,
        };
        
        smart_table::add(&mut market.positions, user_addr, position);
        
        // Transfer collateral from user to pool
        // coin::transfer<AptosCoin>(user, market_addr, collateral);
    }

    public fun calculate_interest_rate(
        market_addr: address,
        user_addr: address,
        current_price: u64,
    ): u64 acquires Market {
        let market = borrow_global<Market>(market_addr);
        let position = smart_table::borrow(&market.positions, user_addr);
        
        let price_ratio = if (position.initial_price > current_price) {
            (position.initial_price - current_price) * EXPONENTIAL_SCALE / position.initial_price
        } else {
            0
        };
        
        // Exponential multiplier: e^(x) approximated as (1 + x + x^2/2 + x^3/6)
        let x = price_ratio as u128;
        let exp_multiplier = (EXPONENTIAL_SCALE as u128 
            + x 
            + (x * x / (2 * EXPONENTIAL_SCALE as u128))
            + (x * x * x / (6 * EXPONENTIAL_SCALE as u128 * EXPONENTIAL_SCALE as u128))) as u64;
        
        BASE_INTEREST_RATE * exp_multiplier / EXPONENTIAL_SCALE
    }

    public fun accrue_interest(
        user_addr: address,
        market_addr: address,
        current_price: u64,
    ) acquires Market {
        let market = borrow_global_mut<Market>(market_addr);
        let position = smart_table::borrow_mut(&mut market.positions, user_addr);
        
        let now = timestamp::now_seconds();
        let time_delta = now - position.last_interest_time;
        
        if (time_delta == 0) return;
        
        let interest_rate = calculate_interest_rate(market_addr, user_addr, current_price);
        let interest = (position.collateral as u128) 
            * (interest_rate as u128) 
            * (time_delta as u128) 
            / (INTEREST_SCALE as u128 * 365 * 24 * 3600 as u128);
        
        position.accrued_interest = position.accrued_interest + (interest as u64);
        position.last_interest_time = now;
        
        // Note: No forced payment - positions are non-liquidative
    }

    public fun add_collateral(
        user: &signer,
        market_addr: address,
        amount: u64,
        current_price: u64,
    ) acquires Market {
        assert!(amount > 0, E_ZERO_AMOUNT);
        
        let user_addr = signer::address_of(user);
        accrue_interest(user_addr, market_addr, current_price);
        
        let market = borrow_global_mut<Market>(market_addr);
        let position = smart_table::borrow_mut(&mut market.positions, user_addr);
        
        position.collateral = position.collateral + amount;
        // Transfer additional collateral
        // coin::transfer<AptosCoin>(user, market_addr, amount);
    }

    public fun close_position(
        user: &signer,
        market_addr: address,
        current_price: u64,
    ) acquires Market {
        let user_addr = signer::address_of(user);
        accrue_interest(user_addr, market_addr, current_price);
        
        let market = borrow_global_mut<Market>(market_addr);
        let position = smart_table::remove(&mut market.positions, user_addr);
        
        let price_diff = if (current_price > position.initial_price) {
            (current_price - position.initial_price) as u128
        } else {
            0
        };
        
        // Calculate PnL
        let pnl = (position.collateral as u128) * price_diff / (position.initial_price as u128);
        let total_return = (position.collateral as u128) + pnl;
        
        assert!(total_return > position.accrued_interest as u128, E_INSUFFICIENT_COLLATERAL);
        
        let final_payout = total_return - (position.accrued_interest as u128);
        
        // Return collateral + PnL - interest to user
        // coin::transfer<AptosCoin>(&market_addr, user_addr, final_payout as u64);
        
        // 5% keeper reward logic - handle separately in fee pool
    }

    #[view]
    public fun get_user_debt(market_addr: address, user_addr: address, current_price: u64): u64 acquires Market {
        let market = borrow_global<Market>(market_addr);
        let position = smart_table::borrow(&market.positions, user_addr);
        
        let interest_rate = calculate_interest_rate(market_addr, user_addr, current_price);
        let time_since = timestamp::now_seconds() - position.last_interest_time;
        
        (position.collateral as u128) 
            * (interest_rate as u128) 
            * (time_since as u128) 
            / (INTEREST_SCALE as u128 * 365 * 24 * 3600 as u128) as u64
            + position.accrued_interest
    }

    #[test_only]
    fun setup_market(): address {
        let admin = &@0x123;
        initialize_market(admin, 1000);
        @0x123
    }

    #[test(admin = @0x123, user = @0x456)]
    fun test_open_and_close_position(admin: signer, user: signer) {
        let market_addr = setup_market();
        
        timestamp::set_time_has_started_for_testing(&admin);
        timestamp::update_global_time_for_test_secs(1000);
        
        open_position(&user, market_addr, 10000, 100);
        
        timestamp::update_global_time_for_test_secs(1100);
        
        close_position(&user, market_addr, 105);
        // Assertions would go here
    }
}