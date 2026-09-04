module dev::QiaraOracleV10 {
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
    const DRIFT_DENOMINATOR: u128 = 10_000_000; // 1,000 = 0.01%

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

    #[view]
    public fun get_oracle_config(): OracleConfig {
        OracleConfig {
            required_quorum: get_required_quorum(),
            round_duration_ms: storage::expect_u64(storage::viewConstant(utf8(b"QiaraOracle"), utf8(b"ROUND_DURATION_MILISECONDS"))),
            max_price_divergence_drift: storage::expect_u64(storage::viewConstant(utf8(b"QiaraOracle"), utf8(b"MAX_PRICE_DIVERGENCE_DRIFT"))),
            min_price_divergence_drift: storage::expect_u64(storage::viewConstant(utf8(b"QiaraOracle"), utf8(b"MIN_PRICE_DIVERGENCE_DRIFT"))),
            committee_pool_size: get_committee_pool_size(),
        }
    }

// === VALIDATOR SYNC METHODS === //

    /// Called by QiaraValidators whenever active validators change
    public fun sync_active_validators(new_validators: vector<String>, _perm: &Permission) acquires Prices {
        let prices = borrow_global_mut<Prices>(@dev);
        prices.active_validators = new_validators;
    }

    /// Admin entry function to initialize or manually update active validators
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

// === COMMITTEE SUBMISSION === //

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

        // 1. Verify round freshness
        let current_round = timestamp::now_seconds() / round_duration;
        assert!(round_id == current_round || round_id == current_round - 1, E_STALE_ROUND);

        // 2. Read active validators locally from Prices (0 cross-module latency!)
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

        // 3. Update round data
        if (!map::contains_key(&prices.rounds, &round_id)) {
            map::upsert(&mut prices.rounds, round_id, RoundData {
                submissions: vector::empty<RoundSubmission>(),
                settled: false,
            });
        };

        let round_data = map::borrow_mut(&mut prices.rounds, &round_id);
        assert!(!round_data.settled, E_ROUND_ALREADY_SETTLED);

        let len = vector::length(&round_data.submissions);
        let i = 0;
        while (i < len) {
            assert!(vector::borrow(&round_data.submissions, i).validator != caller_addr, E_ALREADY_SUBMITTED);
            i = i + 1;
        };

        vector::push_back(&mut round_data.submissions, RoundSubmission { validator: caller_addr, price });

        // 4. Quorum reached: compute median & settle
        if (vector::length(&round_data.submissions) >= required_quorum) {
            let p0 = vector::borrow(&round_data.submissions, 0).price;
            let p1 = vector::borrow(&round_data.submissions, 1).price;
            let p2 = vector::borrow(&round_data.submissions, 2).price;

            let median = find_median_of_three(p0, p1, p2);

            assert!(calculate_divergence(p0, median) <= max_divergence, E_PRICE_DIVERGENCE_TOO_HIGH);
            assert!(calculate_divergence(p1, median) <= max_divergence, E_PRICE_DIVERGENCE_TOO_HIGH);
            assert!(calculate_divergence(p2, median) <= max_divergence, E_PRICE_DIVERGENCE_TOO_HIGH);

            let now = timestamp::now_seconds();
            let symbol_bytes = bcs::to_bytes(&symbol);
            let store = PriceStore { price: median, decimals: ORACLE_DECIMALS, publish_time: now };

            map::upsert(&mut prices.prices, symbol_bytes, store);
            if (!map::contains_key(&prices.map, &symbol)) {
                map::upsert(&mut prices.map, symbol, Integer { oracleID: symbol_bytes, value: 0, isPositive: true });
            };

            let qiara_impact = *map::borrow(&prices.map, &symbol);
            if (qiara_impact.oracleID != symbol_bytes && vector::length(&qiara_impact.oracleID) > 0) {
                map::upsert(&mut prices.prices, qiara_impact.oracleID, store);
            };

            round_data.settled = true;

            let data = vector[
                Event::create_data_struct(utf8(b"symbol"), utf8(b"string"), symbol_bytes),
                Event::create_data_struct(utf8(b"price"), utf8(b"u128"), bcs::to_bytes(&median)),
                Event::create_data_struct(utf8(b"round_id"), utf8(b"u64"), bcs::to_bytes(&round_id)),
            ];
            Event::emit_oracle_event(utf8(b"Round Settled"), data);
        };
    }

    fun find_median_of_three(a: u128, b: u128, c: u128): u128 {
        if ((a >= b && a <= c) || (a <= b && a >= c)) return a;
        if ((b >= a && b <= c) || (b <= a && b >= c)) return b;
        c
    }

    fun calculate_divergence(val: u128, target: u128): u128 {
        let diff = if (val > target) val - target else target - val;
        (diff * DRIFT_DENOMINATOR) / target
    }

    #[view]
    public fun is_round_settled(round_id: u64): bool acquires Prices {
        let prices = borrow_global<Prices>(@dev);
        if (!map::contains_key(&prices.rounds, &round_id)) return false;
        map::borrow(&prices.rounds, &round_id).settled
    }

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
        let price;
        {
            let prices_storage = borrow_global_mut<Prices>(@dev);
            if (!map::contains_key(&prices_storage.map, &name)) {
                map::upsert(&mut prices_storage.map, name, Integer { oracleID, value: 0, isPositive: true });
            };
            price = map::borrow_mut(&mut prices_storage.map, &name);
        };

        let scaled_impact = (impact * 1_000_000) / native_oracle_weight;
        if (scaled_impact == 0) return 0;
        let old_price_state = *price;

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

        let updated_view_price = viewPrice(name);
        let data = vector[
            Event::create_data_struct(utf8(b"name"), utf8(b"string"), bcs::to_bytes(&name)),
            Event::create_data_struct(utf8(b"oracle id"), utf8(b"vector<u8>"), bcs::to_bytes(&oracleID)),
            Event::create_data_struct(utf8(b"old_price_impact"), utf8(b"u64"), bcs::to_bytes(&old_price_state)),
            Event::create_data_struct(utf8(b"new_price_impact"), utf8(b"u64"), bcs::to_bytes(&price)),
            Event::create_data_struct(utf8(b"price"), utf8(b"u256"), bcs::to_bytes(&updated_view_price)),
        ];
        Event::emit_oracle_event(utf8(b"Qiara Oracle Impact Update"), data);

        let a = calculate_impact_percentage((raw_price as u256), price.value, price.isPositive);
        a / 1_000_000
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