module dev::QiaraOracleV11 {
    use std::string::{String, utf8};
    use std::vector;
    use std::bcs;
    use std::signer;
    use aptos_framework::timestamp;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    
    use event::QiaraEventV1::{Self as Event};
    use dev::QiaraStorageV21::{Self as storage};

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 0;
    const E_NOT_INITIALIZED: u64 = 1;
    const E_NOT_IN_COMMITTEE: u64 = 2;
    const E_ALREADY_SUBMITTED: u64 = 3;
    const E_STALE_ROUND: u64 = 4;
    const E_PRICE_DIVERGENCE_TOO_HIGH: u64 = 5;
    const E_ROUND_ALREADY_SETTLED: u64 = 6;

// === CONSTANTS === //
    const ORACLE_DECIMALS: u8 = 8;
    const DRIFT_DENOMINATOR: u128 = 10_000_000;   // 1,000 = 0.01%
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
        submissions: vector<RoundSubmission>,
        settled: bool,
    }

    struct Integer has drop, key, store, copy {
        oracleID: vector<u8>,
        value: u256,
        isPositive: bool,
    }

    struct PriceStore has key, store, drop, copy {
        price:        u128,
        decimals:     u8,
        publish_time: u64,
    }

    struct Prices has key {
        map: Map<String, Integer>,            // Token Symbol -> Impact Integer
        prices: Map<vector<u8>, PriceStore>,  // Oracle ID / Symbol Bytes -> PriceStore
        rounds: Map<u64, RoundData>,          // round_id -> RoundData
        active_validators: vector<String>,    // Local cache synced from QiaraValidators
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
                map: map::new<String, Integer>(),
                prices: map::new<vector<u8>, PriceStore>(),
                rounds: map::new<u64, RoundData>(),
                active_validators: vector::empty<String>(),
            });
        };
    }

// === DYNAMIC STORAGE READERS === //

    inline fun get_required_quorum(): u64 {
        storage::expect_u64(storage::viewConstant(utf8(b"QiaraOracle"), utf8(b"REQUIRED_QUORUM")))
    }

    inline fun get_round_duration_secs(): u64 {
        let ms = storage::expect_u64(storage::viewConstant(utf8(b"QiaraOracle"), utf8(b"ROUND_DURATION_MILISECONDS")));
        ms / 1000
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
        let prices = borrow_global_mut<Prices>(@dev);
        prices.active_validators = new_validators;
    }

    public entry fun admin_sync_active_validators(admin: &signer, new_validators: vector<String>) acquires Prices {
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_ADMIN);
        let prices = borrow_global_mut<Prices>(@dev);
        prices.active_validators = new_validators;
    }

    #[view]
    public fun return_active_validators(): vector<String> acquires Prices {
        if (!exists<Prices>(@dev)) return vector::empty<String>();
        borrow_global<Prices>(@dev).active_validators
    }

// === AUTONOMOUS COMMITTEE SUBMISSION === //

    public entry fun submit_round_price(
        caller: &signer,
        validator_shared: String,
        symbol: String,
        price: u128,
        round_id: u64,
    ) acquires Prices {
        assert!(exists<Prices>(@dev), E_NOT_INITIALIZED);
        let caller_addr = signer::address_of(caller);

        let round_duration = get_round_duration_secs();
        let committee_size = get_committee_pool_size();
        let required_quorum = get_required_quorum();
        let max_divergence = get_max_divergence();
        let max_clamp_step = get_max_clamp_step();

        // 1. Verify round freshness
        let current_round = timestamp::now_seconds() / round_duration;
        assert!(round_id == current_round || round_id == current_round - 1, E_STALE_ROUND);

        // 2. Local active validator committee check
        let prices = borrow_global_mut<Prices>(@dev);
        let total_val = vector::length(&prices.active_validators);
        assert!(total_val >= committee_size, E_NOT_IN_COMMITTEE);

        let is_in_committee = false;
        let c = 0;
        while (c < committee_size) {
            let assigned_idx = (round_id * 7 + c * 3) % total_val;
            if (*vector::borrow(&prices.active_validators, assigned_idx) == validator_shared) {
                is_in_committee = true;
                break
            };
            c = c + 1;
        };
        assert!(is_in_committee, E_NOT_IN_COMMITTEE);

        // 3. Update round data & isolate borrow scope
        if (!map::contains_key(&prices.rounds, &round_id)) {
            map::upsert(&mut prices.rounds, round_id, RoundData {
                submissions: vector::empty<RoundSubmission>(),
                settled: false,
            });
        };

        let should_settle = false;
        let prices_vec = vector::empty<u128>();

        // 🔒 Scoped block: releases round_data so `prices` can be safely used below
        {
            let round_data = map::borrow_mut(&mut prices.rounds, &round_id);
            assert!(!round_data.settled, E_ROUND_ALREADY_SETTLED);

            // Prevent duplicate submissions from the same validator in this round
            let len = vector::length(&round_data.submissions);
            let i = 0;
            while (i < len) {
                assert!(vector::borrow(&round_data.submissions, i).validator != caller_addr, E_ALREADY_SUBMITTED);
                i = i + 1;
            };

            vector::push_back(&mut round_data.submissions, RoundSubmission { validator: caller_addr, price });

            let sub_count = vector::length(&round_data.submissions);
            if (sub_count >= required_quorum) {
                should_settle = true;
                round_data.settled = true; // Marked settled here

                let k = 0;
                while (k < sub_count) {
                    vector::push_back(&mut prices_vec, vector::borrow(&round_data.submissions, k).price);
                    k = k + 1;
                };
            };
        }; // 👈 round_data reference is completely released here!

        // 4. AUTONOMOUS QUORUM RESOLUTION
        if (should_settle) {
            let sub_count = vector::length(&prices_vec);

            // In-place sort to find median
            sort_prices(&mut prices_vec);
            let median = *vector::borrow(&prices_vec, sub_count / 2);

            // Autonomous Loop: Enforce max 0.01% drift against median across ALL submissions
            let j = 0;
            while (j < sub_count) {
                let p = *vector::borrow(&prices_vec, j);
                assert!(calculate_divergence(p, median) <= max_divergence, E_PRICE_DIVERGENCE_TOO_HIGH);
                j = j + 1;
            };

            // 5. AUTO-RAMP CIRCUIT BREAKER: Clamps large 1-tick jumps without deadlocking
            let symbol_bytes = bcs::to_bytes(&symbol);
            let old_price = get_raw_price_internal(prices, &symbol_bytes);
            let final_settled_price = clamp_price_step(median, old_price, max_clamp_step);

            let now = timestamp::now_seconds();
            let store = PriceStore { price: final_settled_price, decimals: ORACLE_DECIMALS, publish_time: now };

            map::upsert(&mut prices.prices, symbol_bytes, store);
            if (!map::contains_key(&prices.map, &symbol)) {
                map::upsert(&mut prices.map, symbol, Integer { oracleID: symbol_bytes, value: 0, isPositive: true });
            };

            let qiara_impact = *map::borrow(&prices.map, &symbol);
            if (qiara_impact.oracleID != symbol_bytes && vector::length(&qiara_impact.oracleID) > 0) {
                map::upsert(&mut prices.prices, qiara_impact.oracleID, store);
            };

            let data = vector[
                Event::create_data_struct(utf8(b"symbol"), utf8(b"string"), symbol_bytes),
                Event::create_data_struct(utf8(b"price"), utf8(b"u128"), bcs::to_bytes(&final_settled_price)),
                Event::create_data_struct(utf8(b"round_id"), utf8(b"u64"), bcs::to_bytes(&round_id)),
            ];
            Event::emit_oracle_event(utf8(b"Round Settled"), data);
        };
    }

    /// Autonomous in-place sorting for arbitrary quorum sizes (O(K^2), lightweight in VM)
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

    /// Clamps price steps based on MAX_CLAMP_PRICE_STEP from QiaraStorageV21
    fun clamp_price_step(new_price: u128, old_price: u128, max_step_scaled: u128): u128 {
        if (old_price == 0) return new_price;

        let max_delta = (old_price * max_step_scaled) / PERCENT_DENOMINATOR;

        if (new_price > old_price + max_delta) {
            return old_price + max_delta // Clamps pump step without reverting
        };

        if (old_price > max_delta && new_price < old_price - max_delta) {
            return old_price - max_delta // Clamps dump step without reverting
        };

        new_price
    }

    fun calculate_divergence(val: u128, target: u128): u128 {
        let diff = if (val > target) val - target else target - val;
        (diff * DRIFT_DENOMINATOR) / target
    }

    fun get_raw_price_internal(prices: &Prices, symbol_bytes: &vector<u8>): u128 {
        if (map::contains_key(&prices.prices, symbol_bytes)) {
            map::borrow(&prices.prices, symbol_bytes).price
        } else {
            0
        }
    }

    #[view]
    public fun is_round_settled(round_id: u64): bool acquires Prices {
        let prices = borrow_global<Prices>(@dev);
        if (!map::contains_key(&prices.rounds, &round_id)) return false;
        map::borrow(&prices.rounds, &round_id).settled
    }

// === VIEW METHODS === //

    #[view]
    public fun viewPrice(name: String): u256 acquires Prices {
        if (name == utf8(b"Qiara")) return 0;
        if (!exists<Prices>(@dev)) return 0;

        let prices = borrow_global<Prices>(@dev);
        let raw_price: u256 = 0;
        let symbol_bytes = bcs::to_bytes(&name);

        if (map::contains_key(&prices.prices, &symbol_bytes)) {
            raw_price = (map::borrow(&prices.prices, &symbol_bytes).price as u256);
        };

        if (raw_price == 0 && map::contains_key(&prices.map, &name)) {
            let oracle_id = map::borrow(&prices.map, &name).oracleID;
            if (map::contains_key(&prices.prices, &oracle_id)) {
                raw_price = (map::borrow(&prices.prices, &oracle_id).price as u256);
            };
        };

        if (raw_price == 0) return 0;

        if (map::contains_key(&prices.map, &name)) {
            let impact = map::borrow(&prices.map, &name);
            if (impact.isPositive) {
                raw_price + impact.value
            } else {
                if (impact.value >= raw_price) 1 else raw_price - impact.value
            }
        } else {
            raw_price
        }
    }

    #[view]
    public fun viewPriceWithDecimals(name: String): (u256, u64) acquires Prices {
        (viewPrice(name), (ORACLE_DECIMALS as u64))
    }

    #[view]
    public fun get_price(feed_id_bytes: vector<u8>): PriceStore acquires Prices {
        if (!exists<Prices>(@dev) || vector::is_empty(&feed_id_bytes)) {
            return PriceStore { price: 0, decimals: ORACLE_DECIMALS, publish_time: 0 }
        };
        let prices = borrow_global<Prices>(@dev);
        if (!map::contains_key(&prices.prices, &feed_id_bytes)) {
            PriceStore { price: 0, decimals: ORACLE_DECIMALS, publish_time: 0 }
        } else {
            *map::borrow(&prices.prices, &feed_id_bytes)
        }
    }

    #[view]
    public fun get_raw_price(feed_id_bytes: vector<u8>): (u64, u64) acquires Prices {
        let store = get_price(feed_id_bytes);
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

    public fun impact_price(
        name: String, 
        oracleID: vector<u8>, 
        impact: u256, 
        isPositive: bool, 
        native_oracle_weight: u256, 
        _perm: Permission
    ): u256 acquires Prices {
        let (raw_price, _,) = get_raw_price(oracleID);
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
            Event::create_data_struct(utf8(b"oracle id"), utf8(b"vector<u8>"), bcs::to_bytes(&oracleID)),
            Event::create_data_struct(utf8(b"old_price_impact"), utf8(b"u64"), bcs::to_bytes(&old_price_state)),
            Event::create_data_struct(utf8(b"new_price_impact"), utf8(b"u64"), bcs::to_bytes(&new_price_state)),
            Event::create_data_struct(utf8(b"price"), utf8(b"u256"), bcs::to_bytes(&updated_view_price)),
        ];
        Event::emit_oracle_event(utf8(b"Qiara Oracle Impact Update"), data);

        let a = calculate_impact_percentage((raw_price as u256), final_price_value, final_price_is_positive);
        a / 1_000_000
    }

    #[view]
    public fun existsPrice(name: String): bool acquires Prices {
        if (!exists<Prices>(@dev)) return false;
        let prices = borrow_global<Prices>(@dev);
        map::contains_key(&prices.prices, &bcs::to_bytes(&name)) || map::contains_key(&prices.map, &name)
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