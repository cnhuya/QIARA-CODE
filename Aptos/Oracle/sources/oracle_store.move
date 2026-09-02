module dev::QiaraOracleV10 {
    use std::string::{String, utf8};
    use std::vector;
    use std::bcs;
    use std::signer;
    use aptos_std::from_bcs;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    
    use aptos_framework::object::{Self, Object};
    use aptos_framework::aptos_coin::AptosCoin;

    use switchboard::aggregator::{Self, Aggregator, CurrentResult};
    use switchboard::decimal::{Self, Decimal};
    use switchboard::update_action;

    use event::QiaraEventV1::{Self as Event};

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 0;
    const ERROR_TOKEN_PRICE_COULDNT_BE_FOUND: u64 = 1;
    const E_NOT_INITIALIZED: u64 = 2;
    const E_ALREADY_INIT: u64 = 3;
    const E_NEGATIVE_PRICE: u64 = 4;
    const E_STALE_PRICE: u64 = 5;
    const E_FEED_ID_EMPTY: u64 = 6;

// === CONSTANTS === //
    const SWITCHBOARD_DECIMALS: u8 = 18;
    
// === ACCESS === //
    struct Access has store, key, drop {}
    struct Permission has copy, key, drop {}

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @dev, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_permission(_access: &Access): Permission {
        Permission {}
    }

// === STRUCTS === //
    struct Prices has key {
        map: Map<String, Integer>,            // Token Symbol -> Impact Integer
        prices: Map<vector<u8>, PriceStore>,  // Switchboard Feed ID -> PriceStore
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

// === INIT === //
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @dev, ERROR_NOT_ADMIN);

        if (!exists<Prices>(@dev)) {
            move_to(admin, Prices { 
                map: map::new<String, Integer>(),
                prices: map::new<vector<u8>, PriceStore>(),
            });
        };
    }

// === HELPER METHODS === //

    fun bytes_to_address(feed_id_bytes: &vector<u8>): address {
        assert!(vector::length(feed_id_bytes) == 32, E_FEED_ID_EMPTY);
        from_bcs::to_address(*feed_id_bytes)
    }

    fun find_token_name_by_oracle_id(prices: &Prices, oracleID: &vector<u8>): (bool, String) {
        let keys = map::keys(&prices.map);
        let len = vector::length(&keys);
        let i = 0;
        while (i < len) {
            let name = vector::borrow(&keys, i);
            let val = map::borrow(&prices.map, name);
            if (&val.oracleID == oracleID) {
                return (true, *name)
            };
            i = i + 1;
        };
        (false, utf8(b""))
    }

// === UPDATE METHODS === //

    public entry fun ensure_switchboard_feed_new(token: String, feed_id_bytes: vector<u8>) acquires Prices {
        let prices = borrow_global_mut<Prices>(@dev);
        assert!(vector::length(&feed_id_bytes) == 32, E_FEED_ID_EMPTY);
        if (!map::contains_key(&prices.map, &token)) {
            map::upsert(&mut prices.map, token, Integer { oracleID: feed_id_bytes, value: 0, isPositive: true });
        };
    }

    public entry fun ensure_switchboard_feed(feed_id_bytes: vector<u8>) acquires Prices {
        let prices = borrow_global_mut<Prices>(@dev);
        assert!(vector::length(&feed_id_bytes) == 32, E_FEED_ID_EMPTY);
        if (!map::contains_key(&prices.prices, &feed_id_bytes)) {
            map::upsert(&mut prices.prices, feed_id_bytes, PriceStore { price: 0, decimals: 0, publish_time: 0 });
        };
    }

    public entry fun update_price(
        user: &signer,
        switchboard_update_data: vector<vector<u8>>,
        feed_id_bytes: vector<u8>,
    ) acquires Prices {
        assert!(exists<Prices>(@dev), E_NOT_INITIALIZED);
        assert!(vector::length(&feed_id_bytes) == 32, E_FEED_ID_EMPTY);

        // 1. Submit on-chain Switchboard update action if update data is provided
        if (vector::length(&switchboard_update_data) > 0) {
            update_action::run<AptosCoin>(user, switchboard_update_data);
        };

        // 2. Read the latest aggregated value from the Switchboard aggregator object
        let feed_addr = bytes_to_address(&feed_id_bytes);
        let agg_obj: Object<Aggregator> = object::address_to_object<Aggregator>(feed_addr);
        let current_result: CurrentResult = aggregator::current_result(agg_obj);
        let result_decimal: Decimal = aggregator::result(&current_result);
        
        let (raw_val, _neg) = decimal::unpack(result_decimal);
        let timestamp = aggregator::timestamp(&current_result);

        let old_price_store = get_price(feed_id_bytes);

        let new_store = PriceStore {
            price: raw_val,
            decimals: SWITCHBOARD_DECIMALS,
            publish_time: timestamp,
        };

        let token_name;
        let found;
        let old_raw_price = (old_price_store.price as u256);
        let new_raw_price = (new_store.price as u256);
        let qiara_impact = Integer { oracleID: vector::empty<u8>(), value: 0, isPositive: true };

        // 3. Update local cache table
        {
            let prices = borrow_global_mut<Prices>(@dev);

            if (map::contains_key(&prices.prices, &feed_id_bytes)) {
                *map::borrow_mut(&mut prices.prices, &feed_id_bytes) = new_store;
            } else {
                map::add(&mut prices.prices, feed_id_bytes, new_store);
            };

            let (f, name) = find_token_name_by_oracle_id(prices, &feed_id_bytes);
            found = f;
            token_name = name;

            if (f) {
                qiara_impact = *map::borrow(&prices.map, &token_name);
            };
        };

        // 4. Calculate impact-combined prices
        let old_combined_price: u256 = old_raw_price;
        let new_combined_price: u256 = new_raw_price;

        if (found) {
            if (token_name != utf8(b"Qiara")) {
                if (qiara_impact.isPositive) {
                    old_combined_price = old_raw_price + qiara_impact.value;
                } else {
                    if (qiara_impact.value >= old_raw_price) {
                        old_combined_price = 1;
                    } else {
                        old_combined_price = old_raw_price - qiara_impact.value;
                    }
                };

                if (qiara_impact.isPositive) {
                    new_combined_price = new_raw_price + qiara_impact.value;
                } else {
                    if (qiara_impact.value >= new_raw_price) {
                        new_combined_price = 1;
                    } else {
                        new_combined_price = new_raw_price - qiara_impact.value;
                    }
                };
            }
        };

        let data = vector[
            Event::create_data_struct(utf8(b"oracle id"), utf8(b"vector<u8>"), bcs::to_bytes(&feed_id_bytes)),
            Event::create_data_struct(utf8(b"old_price"), utf8(b"u256"), bcs::to_bytes(&old_combined_price)),
            Event::create_data_struct(utf8(b"new_price"), utf8(b"u256"), bcs::to_bytes(&new_combined_price)),
        ];
        Event::emit_oracle_event(utf8(b"Price Update"), data);
    }

public entry fun batch_update_price(
        user: &signer,
        names: vector<String>,
        price_update_data: vector<vector<u8>>,
        feed_id_bytes: vector<vector<u8>>,
    ) acquires Prices {
        if (vector::length(&price_update_data) > 0) {
            update_action::run<AptosCoin>(user, price_update_data);
        };

        let len = vector::length(&feed_id_bytes);
        let names_len = vector::length(&names);

        while (len > 0) {
            let feed_bytes = *vector::borrow(&feed_id_bytes, len - 1);
            
            // Auto-register token name in prices.map if provided
            if (len <= names_len) {
                let token_name = *vector::borrow(&names, len - 1);
                let prices = borrow_global_mut<Prices>(@dev);
                if (!map::contains_key(&prices.map, &token_name)) {
                    map::upsert(&mut prices.map, token_name, Integer { 
                        oracleID: feed_bytes, 
                        value: 0, 
                        isPositive: true 
                    });
                };
            };

            if (vector::length(&feed_bytes) == 32) {
                update_price(user, vector::empty<vector<u8>>(), feed_bytes);
            };
            len = len - 1;
        };
    }

    public fun impact_price(
        name: String, 
        oracleID: vector<u8>, 
        impact: u256, 
        isPositive: bool, 
        native_oracle_weight: u256, 
        _perm: Permission
    ): u256 acquires Prices {
        let (supra_oracle_price, _,) = get_raw_price(oracleID);
        let price;
        {
            let prices_storage = borrow_global_mut<Prices>(@dev);
            price = ensure_price(prices_storage, name, oracleID);
        }

        let scaled_impact = (impact * 1_000_000) / native_oracle_weight;
        if (scaled_impact == 0) { return 0 };
        let old_price_state;
        let new_price_state;
        let final_price_value;
        let final_price_is_positive;

        {
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

        let a = calculate_impact_percentage((supra_oracle_price as u256), final_price_value, final_price_is_positive);

        a / 1_000_000
    }

    fun ensure_price(prices: &mut Prices, name: String, oracleID: vector<u8>): &mut Integer {
        if (!map::contains_key(&prices.map, &name)) {
            map::upsert(&mut prices.map, name, Integer { oracleID, value: 0, isPositive: true });
        };
        map::borrow_mut(&mut prices.map, &name)
    }

    public entry fun test_ensure_price(name: String, oracleID: vector<u8>) acquires Prices {
        ensure_price(borrow_global_mut<Prices>(@dev), name, oracleID);
    }

// === VIEW METHODS === //

    #[view]
    public fun convert_to_usd(name: String, size: u256): u256 acquires Prices {
        let price = viewPrice(name);
        (price * size) / 1000000000000000000
    }

    #[view]
    public fun convert_to_token(name: String, usd: u256): u256 acquires Prices {
        let price = viewPrice(name);
        if (price == 0) return 0;
        (usd * 1000000000000000000) / price
    }

    #[view]
    public fun convert_to_usd_safe(name: String, oracleID: vector<u8>, size: u256): u256 acquires Prices {
        let price = viewPrice_safe(name, oracleID);
        (price * size) / 1000000000000000000
    }

    #[view]
    public fun convert_to_token_safe(name: String, oracleID: vector<u8>, usd: u256): u256 acquires Prices {
        let price = viewPrice_safe(name, oracleID);
        if (price == 0) return 0;
        (usd * 1000000000000000000) / price
    }

    #[view]
    public fun viewAllPrices(): Map<String, Integer> acquires Prices {
        *&borrow_global<Prices>(@dev).map
    }

    #[view]
    public fun viewAllAllPrices(): Map<vector<u8>, PriceStore> acquires Prices {
        *&borrow_global<Prices>(@dev).prices
    }

    #[view]
    public fun get_price(feed_id_bytes: vector<u8>): PriceStore acquires Prices {
        if (vector::length(&feed_id_bytes) != 32) {
            return PriceStore { price: 0, decimals: 0, publish_time: 0 }
        };
        let prices = borrow_global<Prices>(@dev);

        if (!map::contains_key(&prices.prices, &feed_id_bytes)) {
            PriceStore { price: 0, decimals: 0, publish_time: 0 }
        } else {
            *map::borrow(&prices.prices, &feed_id_bytes)
        }
    }

    #[view]
    public fun get_raw_price(feed_id_bytes: vector<u8>): (u64, u64) acquires Prices {
        if (vector::length(&feed_id_bytes) != 32) {
            return (0u64, 0u64)
        };
        let prices = borrow_global<Prices>(@dev);

        if (!map::contains_key(&prices.prices, &feed_id_bytes)) {
            return (0u64, 0u64)
        };

        let cached_price = map::borrow(&prices.prices, &feed_id_bytes);
        ((cached_price.price as u64), (cached_price.decimals as u64))
    }

    #[view]
    public fun get_price_direct(feed_id_bytes: vector<u8>): (u128, u8, u64) {
        if (vector::length(&feed_id_bytes) != 32) {
            return (0, SWITCHBOARD_DECIMALS, 0)
        };
        let feed_addr = bytes_to_address(&feed_id_bytes);
        let agg_obj = object::address_to_object<Aggregator>(feed_addr);
        let current_result = aggregator::current_result(agg_obj);
        let result_decimal = aggregator::result(&current_result);
        let (raw_val, _neg) = decimal::unpack(result_decimal);
        let timestamp = aggregator::timestamp(&current_result);
        (raw_val, SWITCHBOARD_DECIMALS, timestamp)
    }

    #[view]
    public fun viewPrice_safe(name: String, oracleID: vector<u8>): u256 acquires Prices {
        if (name == utf8(b"Qiara")) { return 0 };
        if (!exists<Prices>(@dev)) return 0;

        let prices = borrow_global<Prices>(@dev);
        let has_key = map::contains_key(&prices.map, &name);
        let qiara_impact = if (has_key) {
            *map::borrow(&prices.map, &name)
        } else {
            Integer { oracleID, value: 0, isPositive: true }
        };

        let (supra_oracle_price, _) = get_raw_price(qiara_impact.oracleID);

        if (!has_key) {
            return (supra_oracle_price as u256)
        };

        if (qiara_impact.isPositive) {
            (supra_oracle_price as u256) + qiara_impact.value
        } else {
            let s_price = (supra_oracle_price as u256);
            if (qiara_impact.value >= s_price) { return 1 };
            s_price - qiara_impact.value
        }
    }

    #[view]
    public fun viewPrice(name: String): u256 acquires Prices {
        if (name == utf8(b"Qiara")) { return 0 };
        if (!exists<Prices>(@dev)) return 0;

        let prices = borrow_global<Prices>(@dev);
        
        // 1. If mapped with an impact offset, compute with impact
        if (map::contains_key(&prices.map, &name)) {
            let qiara_impact = *map::borrow(&prices.map, &name);
            let (supra_oracle_price, _) = get_raw_price(qiara_impact.oracleID);

            if (qiara_impact.isPositive) {
                return (supra_oracle_price as u256) + qiara_impact.value
            } else {
                let s_price = (supra_oracle_price as u256);
                if (qiara_impact.value >= s_price) { return 1 };
                return s_price - qiara_impact.value
            };
        };

        // 2. Fallback: Search prices.prices directly if token name was not yet registered
        let (found, token_name) = (false, utf8(b""));
        let keys = map::keys(&prices.prices);
        let len = vector::length(&keys);
        let i = 0;
        while (i < len) {
            let feed_id = vector::borrow(&keys, i);
            let (f, matched_name) = find_token_name_by_oracle_id(prices, feed_id);
            if (f && matched_name == name) {
                let store = map::borrow(&prices.prices, feed_id);
                return (store.price as u256)
            };
            i = i + 1;
        };

        0
    }

    #[view]
    public fun viewPriceWithDecimals(name: String): (u256, u64) acquires Prices {
        if (name == utf8(b"Qiara")) { return (0, 0) };
        if (!exists<Prices>(@dev)) return (0, 0);

        let prices = borrow_global<Prices>(@dev);
        if (!map::contains_key(&prices.map, &name)) {
            return (0, 0)
        };

        let qiara_impact = *map::borrow(&prices.map, &name);
        let (supra_oracle_price, decimals) = get_raw_price(qiara_impact.oracleID);
        if (qiara_impact.isPositive) {
            ((supra_oracle_price as u256) + qiara_impact.value, decimals)
        } else {
            let s_price = (supra_oracle_price as u256);
            if (qiara_impact.value >= s_price) { return (1, decimals) };
            (s_price - qiara_impact.value, decimals)
        }
    }

    #[view]
    public fun viewPriceMulti(name: vector<String>): Map<String, u256> acquires Prices {
        let map = map::new<String, u256>();
        let len = vector::length(&name);
        while (len > 0) {
            map::upsert(&mut map, *vector::borrow(&name, len - 1), viewPrice(*vector::borrow(&name, len - 1)));
            len = len - 1;
        };
        map
    }

    #[view]
    public fun existsPrice(name: String): bool acquires Prices {
        if (!exists<Prices>(@dev)) return false;
        let prices = borrow_global<Prices>(@dev);
        map::contains_key(&prices.map, &name)
    }

    #[view]
    public fun calculate_impact_percentage(supra_oracle_price: u256, impact: u256, isPositive: bool): u256 {
        if (supra_oracle_price == 0) { return 0 };
        if (isPositive) {
            ((supra_oracle_price + impact) * 1_000_000_000_000_000_000) / supra_oracle_price
        } else {
            if (impact >= supra_oracle_price) {
                return 0
            };
            ((supra_oracle_price - impact) * 1_000_000_000_000_000_000) / supra_oracle_price
        }
    }
}