module dev::QiaraGasV5{
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
        usd_perps_volume: u256,
        usd_deposits: u256,
        usd_withdrawals: u256,
        usd_borrows: u256,
        gas: u256,               // Instantaneous fee rate
        global_gas_index: u256,  // Cumulative global interest index
        last_update: u64,
    }

/// === INIT ===
    fun init_module(admin: &signer){
        if (!exists<Gas>(@dev)) {
            move_to(admin, Gas {
                usd_perps_volume: 0, 
                avg_leverage: 0, 
                usd_deposits: 0, 
                usd_withdrawals: 0, 
                usd_borrows: 0, 
                gas: 0, 
                global_gas_index: 0, // Starts at 0
                last_update: timestamp::now_seconds() 
            });
        };
    }

    public fun add_leverage(_token: String, leverage: u64, volume: u256, _cap: Permission): u256 acquires Gas {
        let gas = borrow_global_mut<Gas>(@dev);
        
        if (volume == 0) {
            let (gas_rate, _, _, _, _, _) = calculateGas(gas, 0, 0);
            return gas_rate
        };

        let old_volume = gas.usd_perps_volume;
        let new_volume = old_volume + volume;

        // Calculate running weighted leverage sum (scaled to u256 to prevent overflows)
        let old_weighted_leverage = (gas.avg_leverage as u256) * old_volume;
        let new_weighted_leverage = (leverage as u256) * volume;

        // Calculate new weighted average leverage
        let new_avg_leverage = (old_weighted_leverage + new_weighted_leverage) / new_volume;

        // Update Gas state variables
        gas.avg_leverage = (new_avg_leverage as u64);
        gas.usd_perps_volume = new_volume;

        let (gas_rate, _, _, _, _, _) = calculateGas(gas, 0, 0);
        return gas_rate
    }

    public fun add_deposit(token: String, deposit: u256, _cap: Permission): u256 acquires Gas {
        let gas = borrow_global_mut<Gas>(@dev);
        gas.usd_deposits = gas.usd_deposits + Oracle::convert_to_usd(token, deposit);
        let (gas_rate, _, _, _, _, _) = calculateGas(gas, deposit, 0);
        gas.gas = gas_rate;
        return gas_rate
    }

    public fun add_withdraw(token: String, withdraw: u256, _cap: Permission): u256 acquires Gas {
        let gas = borrow_global_mut<Gas>(@dev);
        gas.usd_withdrawals = gas.usd_withdrawals + Oracle::convert_to_usd(token, withdraw);
        let (gas_rate, _, _, _, _, _) = calculateGas(gas, 0, withdraw);
        gas.gas = gas_rate;
        return gas_rate
    }

    public fun add_borrow(token: String, borrow: u256, _cap: Permission): u256 acquires Gas {
        let gas = borrow_global_mut<Gas>(@dev);
        gas.usd_borrows = gas.usd_borrows + Oracle::convert_to_usd(token, borrow);
        let (gas_rate, _, _, _, _, _) = calculateGas(gas, 0, 0);
        gas.gas = gas_rate;
        return gas_rate
    }

    // Accrues the global state and returns the newly updated global_gas_index.
    // The calling contract should store this returned value on the user's position as their snapshot index.
    public fun accrue(token: String, borrow: u256, _user_last_interacted: u64, _cap: Permission): u256 acquires Gas {
        let gas = borrow_global_mut<Gas>(@dev);
        gas.usd_borrows = gas.usd_borrows + Oracle::convert_to_usd(token, borrow);
        
        // calculateGas automatically updates global_gas_index, gas.gas, and gas.last_update
        calculateGas(gas, 0, 0);
        
        return gas.global_gas_index
    }

    public entry fun dev_reset_gas(admin: &signer) acquires Gas {
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_ADMIN);
        let gas = borrow_global_mut<Gas>(@dev);
        gas.usd_deposits = 0;
        gas.usd_withdrawals = 0;
        gas.usd_borrows = 0;
        gas.usd_perps_volume = 0;
        gas.avg_leverage = 0;
        gas.global_gas_index = 0; // Reset index back to 0
        gas.last_update = timestamp::now_seconds();
    }

    #[view]
    public fun calculateGas_test(deposits: u256, withdrawals: u256, new_deposit: u256, new_withdrawal: u256, leverage: u256, last_update_sec: u256): (u256, u256, u256, u256, u256, u256) {
        let base = 1_000_000;
        let withdrawal_weight = 5_000_000;
        let e6 = 1_000_000;
        
        let e8 = 100_000_000u256;
        let percentage_decay = 1_000u256; 
        let max_decay = 25_000_000u256;   

        let decay_pct = if (percentage_decay * last_update_sec > max_decay) {
            max_decay
        } else {
            percentage_decay * last_update_sec
        };

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

        let new_deposits = new_deposit + previous_deposit_impact;
        let new_withdrawals = new_withdrawal + previous_withdrawal_impact;

        let ratio = (new_withdrawals * withdrawal_weight) / (new_deposits + 1);

        let total_fee = (base * ((ratio * ratio) / e6) / e6) + leverage + base;

        let data = vector[
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

    public fun calculateGas(gas_ref: &mut Gas, deposit: u256, withdrawal: u256): (u256, u256, u256, u256, u256, u256) {
        let base = 1_000_000u256;
        let withdrawal_weight = 5_000_000u256; 
        let e6 = 1_000_000u256;
        
        let e8 = 100_000_000u256; 
        let percentage_decay = 1_000u256; 
        let max_decay = 25_000_000u256;   

        let last_update_sec = ((timestamp::now_seconds() - gas_ref.last_update) as u256);

        // 1. UPDATE THE CUMULATIVE GLOBAL INDEX FIRST
        // We accumulate using the rate that was active DURING this elapsed period (gas_ref.gas)
        gas_ref.global_gas_index = gas_ref.global_gas_index + (gas_ref.gas * last_update_sec);

        // 2. Standard decay logic with 100% scale division
        let decay_pct = if (percentage_decay * last_update_sec > max_decay) {
            max_decay
        } else {
            percentage_decay * last_update_sec
        };

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
            Event::create_data_struct(utf8(b"gas"), utf8(b"u256"), bcs::to_bytes(&total_fee)),
            Event::create_data_struct(utf8(b"previous_deposit_impact"), utf8(b"u256"), bcs::to_bytes(&previous_deposit_impact)),
            Event::create_data_struct(utf8(b"previous_withdrawal_impact"), utf8(b"u256"), bcs::to_bytes(&previous_withdrawal_impact)),
        ];

        Event::emit_historical_event(utf8(b"Gas"), data);
        
        // 3. Save the new fee rate and update the timestamp reference for the NEXT period
        gas_ref.gas = total_fee;
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
        let total_fee = (amount * gas_fee * time_u256) / 1_000_000 / 100; 
        return total_fee
    }

    #[view]
    public fun calculate_gas_fee_from_index(user_last_index: u256, current_index: u256, amount: u256): u256 {
        if (current_index <= user_last_index) {
            return 0
        };
        let index_diff = current_index - user_last_index;
        // Replicates your percentage conversion logic with the integrated index difference
        let total_fee = (amount * index_diff) / 1_000_000 / 100;
        return total_fee
    }

    #[view]
    public fun return_gas(): Gas acquires Gas{
        return *borrow_global<Gas>(@dev)
    }
}