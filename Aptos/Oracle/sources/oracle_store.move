module dev::QiaraOracleV14 {
    use std::string::{String, utf8};
    use std::vector;
    use std::bcs;
    use std::signer;
    use aptos_framework::timestamp;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    
    use event::QiaraEventV1::{Self as Event};
    use dev::QiaraStorageV22::{Self as storage};

    // === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 0;

    // === CONSTANTS === //
    const ORACLE_DECIMALS: u8 = 8;
    const PERCENT_DENOMINATOR: u128 = 100_000_000; // 1,000_000 = 1%

    // === ACCESS & PERMISSIONS === //
    struct Access has store, key, drop {}
    struct Permission has copy, drop, store {}

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @dev, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_permission(_access: &Access): Permission {
        Permission {}
    }

    // === STRUCTS === //
    struct RoundSubmission has store, drop, copy {
        validator: address,
        price: u128,
    }

    struct RoundData has store, drop {
        round_id: u64,
        submissions: vector<RoundSubmission>,
        settled: bool,
    }

    struct Integer has drop, key, store, copy {
        oracleID: String,
        value: u256,
        isPositive: bool,
    }

    struct PriceStore has key, store, drop, copy {
        price: u128,
        publish_time: u64,
        round_id: u64,
        settled: bool,
        submissions: vector<RoundSubmission>,
    }

    struct Prices has key {
        map: Map<String, Integer>,
        prices: Map<String, PriceStore>, // 1 single map for both pending votes and settled prices
        active_validators: vector<String>,
    }


    struct OracleConfig has copy, drop, store {
        required_quorum: u64,
        round_duration_ms: u64,
        max_price_divergence_drift: u64,
        min_price_divergence_drift: u64,
        committee_pool_size: u64,
        max_clamp_price_step: u64,
    }

    // === INIT === //
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_ADMIN);
        if (!exists<Prices>(@dev)) {
            move_to(admin, Prices { 
                map: map::new(),
                prices: map::new(),
                rounds: map::new(),
                active_validators: vector::empty(),
            });
        };
    }

    // === DYNAMIC STORAGE READERS === //

    inline fun get_required_quorum(): u64 {
        storage::expect_u64(storage::viewConstant(utf8(b"QiaraOracle"), utf8(b"REQUIRED_QUORUM")))
    }

    inline fun get_round_duration_secs(): u64 {
        storage::expect_u64(storage::viewConstant(utf8(b"QiaraOracle"), utf8(b"ROUND_DURATION_MILISECONDS"))) / 1000
    }

    inline fun get_max_divergence(): u128 {
        (storage::expect_u64(storage::viewConstant(utf8(b"QiaraOracle"), utf8(b"MAX_PRICE_DIVERGENCE_DRIFT"))) as u128)
    }

    inline fun get_committee_pool_size(): u64 {
        storage::expect_u64(storage::viewConstant(utf8(b"QiaraOracle"), utf8(b"COMMITTEE_POOL_SIZE")))
    }

    inline fun get_max_clamp_step(): u128 {
        (storage::expect_u64(storage::viewConstant(utf8(b"QiaraOracle"), utf8(b"MAX_CLAMP_PRICE_STEP"))) as u128)
    }

    #[view]
    public fun get_oracle_config(): OracleConfig {
        OracleConfig {
            required_quorum: get_required_quorum(),
            round_duration_ms: storage::expect_u64(storage::viewConstant(utf8(b"QiaraOracle"), utf8(b"ROUND_DURATION_MILISECONDS"))),
            max_price_divergence_drift: storage::expect_u64(storage::viewConstant(utf8(b"QiaraOracle"), utf8(b"MAX_PRICE_DIVERGENCE_DRIFT"))),
            min_price_divergence_drift: storage::expect_u64(storage::viewConstant(utf8(b"QiaraOracle"), utf8(b"MIN_PRICE_DIVERGENCE_DRIFT"))),
            committee_pool_size: get_committee_pool_size(),
            max_clamp_price_step: (get_max_clamp_step() as u64),
        }
    }

    // === VALIDATOR SYNC METHODS === //

    public fun sync_active_validators(new_validators: vector<String>, _perm: &Permission) acquires Prices {
        borrow_global_mut<Prices>(@dev).active_validators = new_validators;
    }

    public entry fun admin_sync_active_validators(admin: &signer, new_validators: vector<String>) acquires Prices {
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_ADMIN);
        borrow_global_mut<Prices>(@dev).active_validators = new_validators;
    }

    #[view]
    public fun return_active_validators(): vector<String> acquires Prices {
        if (!exists<Prices>(@dev)) return vector::empty();
        borrow_global<Prices>(@dev).active_validators
    }

    public entry fun batch_submit_round_prices(
        caller: &signer,
        validator_shared: String,
        symbols: vector<String>,
        prices_vec: vector<u128>,
        round_id: u64,
    ) acquires Prices {
        let total = vector::length(&symbols);
        assert!(total == vector::length(&prices_vec), 100);

        let i = 0;
        let settled_count: u64 = 0;
        let error_count: u64 = 0;

        while (i < total) {
            let sym = *vector::borrow(&symbols, i);
            let p = *vector::borrow(&prices_vec, i);
            let (settled, is_error) = submit_round_price_internal(caller, validator_shared, sym, p, round_id);
            if (settled) settled_count = settled_count + 1;
            if (is_error) error_count = error_count + 1;
            i = i + 1;
        };

        emit_round_settled(round_id, settled_count, error_count, total);
    }

    public entry fun submit_round_price(
        caller: &signer,
        validator_shared: String,
        symbol: String,
        price: u128,
        round_id: u64,
    ) acquires Prices {
        let (settled, is_error) = submit_round_price_internal(caller, validator_shared, symbol, price, round_id);
        let s_count = if (settled) 1 else 0;
        let e_count = if (is_error) 1 else 0;
        emit_round_settled(round_id, s_count, e_count, 1);
    }

    fun submit_round_price_internal(
        caller: &signer,
        validator_shared: String,
        symbol: String,
        price: u128,
        round_id: u64,
    ): (bool, bool) acquires Prices {
        if (!exists<Prices>(@dev)) {
            emit_oracle_error(&symbol, round_id, utf8(b"Not Initialized"));
            return (false, true)
        };

        let caller_addr = signer::address_of(caller);
        let round_duration = get_round_duration_secs();
        let committee_size = get_committee_pool_size();
        let required_quorum = get_required_quorum();
        let max_divergence = get_max_divergence();
        let max_clamp_step = get_max_clamp_step();

        // 1. Verify round freshness
        let current_round = timestamp::now_seconds() / round_duration;
        if (round_id != current_round && round_id != current_round - 1) {
            emit_oracle_error(&symbol, round_id, utf8(b"Stale Round"));
            return (false, true)
        };

        // 2. Committee verification
        let prices = borrow_global_mut<Prices>(@dev);
        let total_val = vector::length(&prices.active_validators);
        if (total_val < required_quorum) {
            emit_oracle_error(&symbol, round_id, utf8(b"Insufficient Active Validators"));
            return (false, true)
        };

        let eff_committee = if (total_val < committee_size) total_val else committee_size;
        let is_in_committee = false;
        let c = 0;
        while (c < eff_committee) {
            if (*vector::borrow(&prices.active_validators, (round_id + c) % total_val) == validator_shared) {
                is_in_committee = true;
                break
            };
            c = c + 1;
        };

        if (!is_in_committee) {
            emit_oracle_error(&symbol, round_id, utf8(b"Not In Committee"));
            return (false, true)
        };

        // 3. Register submission in bounded map (Keyed by symbol only)
        if (!map::contains_key(&prices.rounds, &symbol)) {
            map::upsert(&mut prices.rounds, symbol, RoundData {
                round_id,
                submissions: vector::empty(),
                settled: false,
            });
        };

        let round_data = map::borrow_mut(&mut prices.rounds, &symbol);

        // Rotate round in-place when round advances
        if (round_data.round_id < round_id) {
            round_data.round_id = round_id;
            round_data.settled = false;
            round_data.submissions = vector::empty();
        };

        if (round_data.settled) {
            emit_oracle_error(&symbol, round_id, utf8(b"Round Already Settled"));
            return (false, false)
        };

        let sub_len = vector::length(&round_data.submissions);
        let i = 0;
        while (i < sub_len) {
            if (vector::borrow(&round_data.submissions, i).validator == caller_addr) {
                emit_oracle_error(&symbol, round_id, utf8(b"Already Submitted"));
                return (false, true)
            };
            i = i + 1;
        };

        vector::push_back(&mut round_data.submissions, RoundSubmission { validator: caller_addr, price });
        sub_len = sub_len + 1;

        // 4. Quorum resolution
        if (sub_len >= required_quorum) {
            let prices_vec = vector::empty<u128>();
            let k = 0;
            while (k < sub_len) {
                vector::push_back(&mut prices_vec, vector::borrow(&round_data.submissions, k).price);
                k = k + 1;
            };

            sort_prices(&mut prices_vec);
            let median = *vector::borrow(&prices_vec, sub_len / 2);

            let j = 0;
            while (j < sub_len) {
                if (calculate_divergence(*vector::borrow(&prices_vec, j), median) > max_divergence) {
                    emit_oracle_error(&symbol, round_id, utf8(b"Price Divergence Too High"));
                    return (false, true)
                };
                j = j + 1;
            };

            round_data.settled = true;
            round_data.submissions = vector::empty(); // Free submission memory immediately

            let old_price = get_raw_price_internal(prices, &symbol);
            let final_settled_price = clamp_price_step(median, old_price, max_clamp_step);
            let now = timestamp::now_seconds();
            let store = PriceStore { price: final_settled_price, decimals: ORACLE_DECIMALS, publish_time: now };

            map::upsert(&mut prices.prices, symbol, store);
            if (!map::contains_key(&prices.map, &symbol)) {
                map::upsert(&mut prices.map, symbol, Integer { oracleID: symbol, value: 0, isPositive: true });
            };

            let qiara_impact = *map::borrow(&prices.map, &symbol);
            if (qiara_impact.oracleID != symbol && qiara_impact.oracleID != utf8(b"")) {
                map::upsert(&mut prices.prices, qiara_impact.oracleID, store);
            };

            let full_price = apply_impact((final_settled_price as u256), &qiara_impact);

            emit_price_change(&symbol, old_price, median, final_settled_price, full_price);
            return (true, false)
        };

        (false, false)
    }

    // === EVENT EMITTERS === //

    fun emit_round_settled(round_id: u64, settled_oracles: u64, error_count: u64, total_submitted: u64) {
        let data = vector[
            Event::create_data_struct(utf8(b"round_id"), utf8(b"u64"), bcs::to_bytes(&round_id)),
            Event::create_data_struct(utf8(b"settled_oracles"), utf8(b"u64"), bcs::to_bytes(&settled_oracles)),
            Event::create_data_struct(utf8(b"error_count"), utf8(b"u64"), bcs::to_bytes(&error_count)),
            Event::create_data_struct(utf8(b"total_submitted"), utf8(b"u64"), bcs::to_bytes(&total_submitted)),
        ];
        Event::emit_oracle_event(utf8(b"Round Settled"), data);
    }

    fun emit_price_change(
        symbol: &String, 
        previous_price: u128, 
        raw_input_price: u128, 
        settled_price: u128, 
        price: u256
    ) {
        let data = vector[
            Event::create_data_struct(utf8(b"symbol"), utf8(b"string"), bcs::to_bytes(symbol)),
            Event::create_data_struct(utf8(b"previous_price"), utf8(b"u128"), bcs::to_bytes(&previous_price)),
            Event::create_data_struct(utf8(b"raw_input_price"), utf8(b"u128"), bcs::to_bytes(&raw_input_price)),
            Event::create_data_struct(utf8(b"settled_price"), utf8(b"u128"), bcs::to_bytes(&settled_price)),
            Event::create_data_struct(utf8(b"price"), utf8(b"u256"), bcs::to_bytes(&price)),
        ];
        Event::emit_oracle_event(utf8(b"Price Change"), data);
    }

    fun emit_oracle_error(symbol: &String, round_id: u64, reason: String) {
        let data = vector[
            Event::create_data_struct(utf8(b"symbol"), utf8(b"string"), bcs::to_bytes(symbol)),
            Event::create_data_struct(utf8(b"round_id"), utf8(b"u64"), bcs::to_bytes(&round_id)),
            Event::create_data_struct(utf8(b"reason"), utf8(b"string"), bcs::to_bytes(&reason)),
        ];
        Event::emit_oracle_event(utf8(b"Oracle Error"), data);
    }

    fun apply_impact(raw_price: u256, impact: &Integer): u256 {
        if (impact.isPositive) {
            raw_price + impact.value
        } else {
            if (impact.value >= raw_price) 1 else raw_price - impact.value
        }
    }

    fun sort_prices(prices: &mut vector<u128>) {
        let len = vector::length(prices);
        let i = 0;
        while (i < len) {
            let j = i + 1;
            while (j < len) {
                if (*vector::borrow(prices, i) > *vector::borrow(prices, j)) {
                    vector::swap(prices, i, j);
                };
                j = j + 1;
            };
            i = i + 1;
        };
    }

    fun clamp_price_step(new_price: u128, old_price: u128, max_step_scaled: u128): u128 {
        if (old_price == 0) return new_price;
        let max_delta = (old_price * max_step_scaled) / PERCENT_DENOMINATOR;
        if (new_price > old_price + max_delta) return old_price + max_delta;
        if (old_price > max_delta && new_price < old_price - max_delta) return old_price - max_delta;
        new_price
    }

    fun calculate_divergence(val: u128, target: u128): u128 {
        let diff = if (val > target) val - target else target - val;
        (diff * PERCENT_DENOMINATOR) / target
    }

    fun get_raw_price_internal(prices: &Prices, symbol: &String): u128 {
        if (map::contains_key(&prices.prices, symbol)) {
            map::borrow(&prices.prices, symbol).price
        } else {
            0
        }
    }

    #[view]
    public fun is_round_settled(round_id: u64, symbol: String): bool acquires Prices {
        if (!exists<Prices>(@dev)) return false;
        let prices = borrow_global<Prices>(@dev);
        if (!map::contains_key(&prices.rounds, &symbol)) return false;
        let r = map::borrow(&prices.rounds, &symbol);
        (r.round_id > round_id) || (r.round_id == round_id && r.settled)
    }

    // === VIEW METHODS === //

    #[view]
    public fun viewPrice(name: String): u256 acquires Prices {
        if (!exists<Prices>(@dev)) return 0;
        let prices = borrow_global<Prices>(@dev);
        let raw_price: u256 = 0;

        if (map::contains_key(&prices.prices, &name)) {
            raw_price = (map::borrow(&prices.prices, &name).price as u256);
        };
        if (raw_price == 0 && map::contains_key(&prices.map, &name)) {
            let oracle_id = map::borrow(&prices.map, &name).oracleID;
            if (map::contains_key(&prices.prices, &oracle_id)) {
                raw_price = (map::borrow(&prices.prices, &oracle_id).price as u256);
            };
        };
        if (raw_price == 0) return 0;

        if (map::contains_key(&prices.map, &name)) {
            apply_impact(raw_price, map::borrow(&prices.map, &name))
        } else {
            raw_price
        }
    }

    #[view]
    public fun viewPrices(names: vector<String>): vector<u256> acquires Prices {
        let len = vector::length(&names);
        let results = vector::empty<u256>();
        if (!exists<Prices>(@dev)) {
            let i = 0;
            while (i < len) {
                vector::push_back(&mut results, 0);
                i = i + 1;
            };
            return results
        };

        let prices = borrow_global<Prices>(@dev);
        let i = 0;
        while (i < len) {
            vector::push_back(&mut results, get_price_internal(prices, vector::borrow(&names, i)));
            i = i + 1;
        };
        results
    }

    fun get_price_internal(prices: &Prices, name: &String): u256 {
        let raw_price: u256 = 0;
        if (map::contains_key(&prices.prices, name)) {
            raw_price = (map::borrow(&prices.prices, name).price as u256);
        };
        if (raw_price == 0 && map::contains_key(&prices.map, name)) {
            let oracle_id = &map::borrow(&prices.map, name).oracleID;
            if (map::contains_key(&prices.prices, oracle_id)) {
                raw_price = (map::borrow(&prices.prices, oracle_id).price as u256);
            };
        };

        if (raw_price == 0) {
            0
        } else if (map::contains_key(&prices.map, name)) {
            apply_impact(raw_price, map::borrow(&prices.map, name))
        } else {
            raw_price
        }
    }

    #[view]
    public fun viewPriceWithDecimals(name: String): (u256, u64) acquires Prices {
        (viewPrice(name), (ORACLE_DECIMALS as u64))
    }

    #[view]
    public fun get_price(symbol: String): PriceStore acquires Prices {
        if (!exists<Prices>(@dev) || symbol == utf8(b"")) {
            return PriceStore { price: 0, decimals: ORACLE_DECIMALS, publish_time: 0 }
        };
        let prices = borrow_global<Prices>(@dev);
        if (!map::contains_key(&prices.prices, &symbol)) {
            PriceStore { price: 0, decimals: ORACLE_DECIMALS, publish_time: 0 }
        } else {
            *map::borrow(&prices.prices, &symbol)
        }
    }

    #[view]
    public fun get_raw_price(symbol: String): (u64, u64) acquires Prices {
        let store = get_price(symbol);
        ((store.price as u64), (store.decimals as u64))
    }

    #[view]
    public fun convert_to_usd(name: String, size: u256): u256 acquires Prices {
        (viewPrice(name) * size) / 1000000000000000000
    }

    #[view]
    public fun convert_to_token(name: String, usd: u256): u256 acquires Prices {
        let price = viewPrice(name);
        if (price == 0) return 0;
        (usd * 1000000000000000000) / price
    }

    // === PRICE IMPACT === //

    public fun impact_price(
        name: String, 
        oracleID: String, 
        impact: u256, 
        isPositive: bool, 
        native_oracle_weight: u256, 
        _perm: Permission
    ): u256 acquires Prices {
        let (raw_price, _) = get_raw_price(oracleID);
        let scaled_impact = (impact * 1_000_000) / native_oracle_weight;
        if (scaled_impact == 0) return 0;

        let old_price_state;
        let new_price_state;
        let final_price_value;
        let final_price_is_positive;

        {
            let prices_storage = borrow_global_mut<Prices>(@dev);
            if (!map::contains_key(&prices_storage.map, &name)) {
                map::upsert(&mut prices_storage.map, name, Integer { oracleID, value: 0, isPositive: true });
            };
            let price = map::borrow_mut(&mut prices_storage.map, &name);
            old_price_state = *price;

            if (isPositive) {
                if (price.isPositive) {
                    price.value = price.value + scaled_impact;
                } else {
                    if (scaled_impact >= price.value) {
                        price.value = scaled_impact - price.value;
                        price.isPositive = true;
                    } else {
                        price.value = price.value - scaled_impact;
                    };
                }
            } else {
                if (price.isPositive) {
                    if (scaled_impact >= price.value) {
                        price.value = scaled_impact - price.value;
                        price.isPositive = false;
                    } else {
                        price.value = price.value - scaled_impact;
                    };
                } else {
                    price.value = price.value + scaled_impact;
                }
            };

            new_price_state = *price;
            final_price_value = price.value;
            final_price_is_positive = price.isPositive;
        };

        let updated_view_price = viewPrice(name);

        let data = vector[
            Event::create_data_struct(utf8(b"name"), utf8(b"string"), bcs::to_bytes(&name)),
            Event::create_data_struct(utf8(b"oracle id"), utf8(b"string"), bcs::to_bytes(&oracleID)),
            Event::create_data_struct(utf8(b"old_price_impact"), utf8(b"u64"), bcs::to_bytes(&old_price_state)),
            Event::create_data_struct(utf8(b"new_price_impact"), utf8(b"u64"), bcs::to_bytes(&new_price_state)),
        ];
        Event::emit_oracle_event(utf8(b"Qiara Oracle Impact Update"), data);

        let old_p = (raw_price as u128);
        emit_price_change(&name, old_p, old_p, old_p, updated_view_price);

        let a = calculate_impact_percentage((raw_price as u256), final_price_value, final_price_is_positive);
        a / 1_000_000
    }

    #[view]
    public fun existsPrice(name: String): bool acquires Prices {
        if (!exists<Prices>(@dev)) return false;
        let prices = borrow_global<Prices>(@dev);
        map::contains_key(&prices.prices, &name) || map::contains_key(&prices.map, &name)
    }

    #[view]
    public fun calculate_impact_percentage(supra_price: u256, impact: u256, isPositive: bool): u256 {
        if (supra_price == 0) return 0;
        if (isPositive) {
            ((supra_price + impact) * 1_000_000_000_000_000_000) / supra_price
        } else {
            if (impact >= supra_price) return 0;
            ((supra_price - impact) * 1_000_000_000_000_000_000) / supra_price
        }
    }
}