module dev::QiaraGasV2{
    use std::signer;
    use std::string::{Self as String, String, utf8};
    use std::vector;
    use std::table;
    use std::timestamp;
    use std::bcs;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use aptos_std::math128 ::{Self as math128};

    use event::QiaraEventV1::{Self as Event};
    use dev::QiaraOracleV5::{Self as Oracle};


// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_MARKET_ALREADY_EXISTS: u64 = 2;
    const ERROR_LEVERAGE_TOO_LOW: u64 = 3;
    const ERROR_SENDER_DOESNT_MATCH_SIGNER: u64 = 4;
    const ERROR_UNKNOWN_PERP_TYPE: u64 = 5;

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

/// === STRUCTS ===

    struct Gas has copy, key, store {
        avg_leverage: u64,
        usd_deposits: u256,
        usd_withdrawals: u256,
        usd_borrows: u256,
        gas: u256,
        last_update: u64,
    }


/// === INIT ===
    fun init_module(admin: &signer){

        if (!exists<Gas>(@dev)) {
            move_to(admin, Gas { avg_leverage: 0, usd_deposits: 0, usd_withdrawals: 0, usd_borrows: 0, gas: 0, last_update: timestamp::now_seconds() });
        };
    }

    public fun add_leverage(token: String,leverage: u64): u256 acquires Gas {
        let gas = borrow_global_mut<Gas>(@dev);
        gas.avg_leverage = gas.avg_leverage + leverage;
        let (gas_rate, _, _, _, _, _) = calculateGas(gas, 0, 0);
        return gas_rate
    }


    public fun add_deposit(token: String, deposit: u256): u256 acquires Gas {
        let gas = borrow_global_mut<Gas>(@dev);
        gas.usd_deposits = gas.usd_deposits + Oracle::convert_to_usd(token, deposit);
        let (gas_rate, _, _, _, _, _) = calculateGas(gas, deposit, 0);
        gas.gas = gas_rate;
        return gas_rate
    }


    public fun add_withdraw(token: String,withdraw: u256): u256 acquires Gas {
        let gas = borrow_global_mut<Gas>(@dev);
        gas.usd_withdrawals = gas.usd_withdrawals + Oracle::convert_to_usd(token, withdraw);
        let (gas_rate, _, _, _, _, _) = calculateGas(gas, 0, withdraw);
        gas.gas = gas_rate;
        return gas_rate
    }


    public fun add_borrow(token: String,borrow: u256): u256 acquires Gas {
        let gas = borrow_global_mut<Gas>(@dev);
        gas.usd_borrows = gas.usd_borrows + Oracle::convert_to_usd(token, borrow);
        let (gas_rate, _, _, _, _, _) = calculateGas(gas, 0, 0);
        gas.gas = gas_rate;
        return gas_rate
    }




    public entry fun dev_reset_gas(admin: &signer) acquires Gas {
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_ADMIN);
        let gas = borrow_global_mut<Gas>(@dev);
        gas.usd_deposits = 0;
        gas.usd_withdrawals = 0;
        gas.usd_borrows = 0;
        gas.last_update = timestamp::now_seconds();
    }

    //supra move tool view --function-id 0xc536f11396d0510d90b021cbae973ab1f71155e8ff32c9d544bfb48212b11ac9::QiaraGasV1::calculateFunding --args u256:50 u256:1250000 u256:2500000 u256:1250000 u256:1522143811 u256:408101064 u256:784666762 u256:3481215007  u256:275
    #[view]
    public fun calculateFunding(skewer: u256, avg_leverage: u256, base: u256,withdrawal_weight: u256, prev_deposits: u256, deposits: u256, prev_withdrawals: u256, withdrawals: u256, last_update_sec: u256,): (u256,u256,u256,u256,u256,u256) {
        // let base = 2_500_000 2_500_000
        // let avg_leverage = 1_250_000 1_250_000 1_250_000
        // let skewer = 500 (0,000050)
        // let withdrawal_weight = 1_250_000
        //7_760_369633536
        //1_940_092.40838
        // 7_760_369 * 2_500_000
        let e18 = 1000000000000000000;
        let e6 = 1_000_000;
        let previous_deposit_impact = prev_deposits-((prev_deposits*skewer*last_update_sec)/1_000_000);
        let previous_withdrawal_impact = prev_withdrawals-((prev_withdrawals*skewer*last_update_sec)/1_000_000);

        let new_deposits = deposits + previous_deposit_impact;
        let new_withdrawals = withdrawals + previous_withdrawal_impact;

        let ratio = ((new_withdrawals*withdrawal_weight))/new_deposits;

        let total_fee = (base * ((ratio*ratio)/e6)/e6) + avg_leverage + base;
        return (total_fee, previous_deposit_impact, previous_withdrawal_impact, new_deposits, new_withdrawals, ((ratio*ratio)/e6))
    }

#[view]
    public fun calculateGas_test(
        deposits: u256, 
        withdrawals: u256, 
        new_deposit: u256, 
        new_withdrawal: u256, 
        leverage: u256, 
        last_update_sec: u256
    ): (u256, u256, u256, u256, u256, u256) {
        let base = 1_000_000;
        let withdrawal_weight = 5_000_000;
        let e6 = 1_000_000;
        
        // Fixed-point scaling where 100% is 100_000_000
        let e8 = 100_000_000u256;
        let percentage_decay = 1_000u256; // 0.001% decay per second
        let max_decay = 25_000_000u256;   // Max 25% decay

        // Calculate the elapsed decay percentage and cap it at max_decay (25%)
        let decay_pct = if (percentage_decay * last_update_sec > max_decay) {
            max_decay
        } else {
            percentage_decay * last_update_sec
        };

        // Standard decay logic using input base deposits and withdrawals
        let deposit_decay = (deposits * decay_pct) / e8;
        let previous_deposit_impact = if (deposit_decay >= deposits) {
            0
        } else {
            deposits - deposit_decay
        };

        let withdrawal_decay = (withdrawals * decay_pct) / e8;
        let previous_withdrawal_impact = if (withdrawal_decay >= withdrawals) {
            0
        } else {
            withdrawals - withdrawal_decay
        };

        // Calculate active values after decay with new inputs
        let new_deposits = new_deposit + previous_deposit_impact;
        let new_withdrawals = new_withdrawal + previous_withdrawal_impact;

        // Corrected logic: Ensure the denominator is at least 1
        let ratio = (new_withdrawals * withdrawal_weight) / (new_deposits + 1);

        // Updated avg_leverage usage to match the 'leverage' input parameter
        let total_fee = (base * ((ratio * ratio) / e6) / e6) + leverage + base;

        let data = vector[
            // Items from the event top-level fields
            Event::create_data_struct(utf8(b"gas"), utf8(b"u256"), bcs::to_bytes(&total_fee)),
            Event::create_data_struct(utf8(b"previous_deposit_impact"), utf8(b"u256"), bcs::to_bytes(&previous_deposit_impact)),
            Event::create_data_struct(utf8(b"previous_withdrawal_impact"), utf8(b"u256"), bcs::to_bytes(&previous_withdrawal_impact)),
        ];

        Event::emit_historical_event(utf8(b"Gas"), data);
        
        return (
            total_fee, 
            previous_deposit_impact, 
            previous_withdrawal_impact, 
            new_deposits, 
            new_withdrawals, 
            ((ratio * ratio) / e6)
        )
    }
public fun calculateGas(
        gas_ref: &mut Gas, 
        deposit: u256, 
        withdrawal: u256
    ): (u256, u256, u256, u256, u256, u256) {
        let base = 1_000_000u256;
        let withdrawal_weight = 5_000_000u256; // 5x
        let e6 = 1_000_000u256;
        
        // Fixed-point scaling where 100% is 100_000_000
        let e8 = 100_000_000u256; 
        let percentage_decay = 1_000u256; // 0.001% decay per second
        let max_decay = 25_000_000u256;   // Max 25% decay

        let last_update_sec = ((timestamp::now_seconds() - gas_ref.last_update) as u256);

        // Calculate the elapsed decay percentage and cap it at max_decay (25%)
        let decay_pct = if (percentage_decay * last_update_sec > max_decay) {
            max_decay
        } else {
            percentage_decay * last_update_sec
        };

        // Standard decay logic with 100% scale division
        let deposit_decay = (gas_ref.usd_deposits * decay_pct) / e8;
        let previous_deposit_impact = if (deposit_decay >= gas_ref.usd_deposits) {
            0
        } else {
            gas_ref.usd_deposits - deposit_decay
        };

        let withdrawal_decay = (gas_ref.usd_withdrawals * decay_pct) / e8;
        let previous_withdrawal_impact = if (withdrawal_decay >= gas_ref.usd_withdrawals) {
            0
        } else {
            gas_ref.usd_withdrawals - withdrawal_decay
        };
        
        let new_deposits = deposit + previous_deposit_impact;
        let new_withdrawals = withdrawal + previous_withdrawal_impact;

        // Corrected logic: Ensure the denominator is at least 1
        let ratio = (new_withdrawals * withdrawal_weight) / (new_deposits + 1);

        let total_fee = (base * ((ratio * ratio) / e6) / e6) + (gas_ref.avg_leverage as u256) + base;

        let data = vector[
            // Items from the event top-level fields
            Event::create_data_struct(utf8(b"gas"), utf8(b"u256"), bcs::to_bytes(&total_fee)),
            Event::create_data_struct(utf8(b"previous_deposit_impact"), utf8(b"u256"), bcs::to_bytes(&previous_deposit_impact)),
            Event::create_data_struct(utf8(b"previous_withdrawal_impact"), utf8(b"u256"), bcs::to_bytes(&previous_withdrawal_impact)),
        ];

        Event::emit_historical_event(utf8(b"Gas"), data);
        
        gas_ref.last_update = timestamp::now_seconds();
        return (
            total_fee, 
            previous_deposit_impact, 
            previous_withdrawal_impact, 
            new_deposits, 
            new_withdrawals, 
            ((ratio * ratio) / e6)
        )
    }

        #[view]
        public fun calculate_gas_fee(time: u64, gas_fee: u256, amount: u256): u256 {
            let time_u256 = (time as u256);
            let total_fee = (amount * gas_fee * time_u256) / 1_000_000 / 100; // the 100 is for percentage conversion
            return total_fee
        }

       #[view]
       public fun return_gas(): Gas acquires Gas{
           return *borrow_global<Gas>(@dev)
       }

}
