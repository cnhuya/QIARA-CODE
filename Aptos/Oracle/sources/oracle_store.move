module dev::QiaraOracleV6 {
    use std::string::{Self, String, utf8};
    use std::vector;
    use std::bcs;
    use std::signer;
    use std::timestamp;
    use pyth::pyth;
    use pyth::price;
    use pyth::price::Price;
    use pyth::price_identifier;
    use pyth::i64;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
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
    const MAX_AGE_SECS: u64 = 60;
    
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
    struct Prices has key {
        map: Map<String, Integer>,            // Token Symbol -> Impact Integer
        prices: Map<vector<u8>, PriceStore>,  // Pyth Feed ID -> PriceStore
    }

    struct Integer has drop, key, store, copy {
        oracleID: vector<u8>,
        value: u256,
        isPositive: bool,
    }

    struct PriceStore has key, store, drop, copy {
        price:        i64::I64,
        expo:         i64::I64,
        publish_time: u64,
    }

// === INIT === //
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @dev, 1);

        if (!exists<Prices>(@dev)) {
            move_to(admin, Prices { 
                map: map::new<String, Integer>(),
                prices: map::new<vector<u8>, PriceStore>(),
            });
        };
    }

// === HELPER METHODS === //

    // Scans the active impact map to resolve which token symbol is tied to a Pyth feed ID
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

    // Updates the Pyth price cache and emits the old and new full combined prices (taking impact into account)
    public entry fun update_price(user: &signer,price_update_data: vector<vector<u8>>,feed_id_bytes: vector<u8>,) acquires Prices {
        assert!(exists<Prices>(@dev), E_NOT_INITIALIZED);
        assert!(vector::length(&feed_id_bytes) == 32, E_FEED_ID_EMPTY);

        let old_price_store = get_price(feed_id_bytes);

        let fee = pyth::get_update_fee(&price_update_data);
        let coins = coin::withdraw<AptosCoin>(user, fee);
        pyth::update_price_feeds(price_update_data, coins);

        let price_id = price_identifier::from_byte_vec(feed_id_bytes);
        let p: Price = pyth::get_price_no_older_than(price_id, MAX_AGE_SECS);

        let raw = price::get_price(&p);
        assert!(!i64::get_is_negative(&raw), E_NEGATIVE_PRICE);

        let new_store = PriceStore {
            price: raw,
            expo: price::get_expo(&p),
            publish_time: price::get_timestamp(&p),
        };

        let token_name;
        let found;
        let old_raw_price;
        let new_raw_price;
        let qiara_impact = Integer { oracleID: vector::empty<u8>(), value: 0, isPositive: true };

        // Isolate the mutable borrow of Prices to prevent any acquires conflicts
        {
            let prices = borrow_global_mut<Prices>(@dev);
            
            old_raw_price = i64::get_magnitude_if_positive(&old_price_store.price);
            new_raw_price = i64::get_magnitude_if_positive(&new_store.price);

            // Update the cached Pyth price inside our unified prices map
            if (map::contains_key(&prices.prices, &feed_id_bytes)) {
                *map::borrow_mut(&mut prices.prices, &feed_id_bytes) = new_store;
            } else {
                map::add(&mut prices.prices, feed_id_bytes, new_store);
            };

            // Determine if this feed is associated with any token to calculate the combined price
            let (f, name) = find_token_name_by_oracle_id(prices, &feed_id_bytes);
            found = f;
            token_name = name;

            if (f) {
                // Copy the Integer struct out of global storage using the dereference operator (*)
                qiara_impact = *map::borrow(&prices.map, &token_name);
            };
        }; // <-- The borrow on `Prices` is completely released here

        // Initialize old and new combined prices with their raw Pyth values
        let old_combined_price: u256 = (old_raw_price as u256);
        let new_combined_price: u256 = (new_raw_price as u256);

        // If the oracle feed is bound to an active token symbol, integrate the stored impact [2]
        if (found) {
            if (token_name != utf8(b"Qiara")) {
                // Calculate old combined price
                if (qiara_impact.isPositive) {
                    old_combined_price = (old_raw_price as u256) + qiara_impact.value;
                } else {
                    if (qiara_impact.value >= (old_raw_price as u256)) {
                        old_combined_price = 1;
                    } else {
                        old_combined_price = (old_raw_price as u256) - qiara_impact.value;
                    }
                };

                // Calculate new combined price
                if (qiara_impact.isPositive) {
                    new_combined_price = (new_raw_price as u256) + qiara_impact.value;
                } else {
                    if (qiara_impact.value >= (new_raw_price as u256)) {
                        new_combined_price = 1;
                    } else {
                        new_combined_price = (new_raw_price as u256) - qiara_impact.value;
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

    public entry fun batch_update_price(user: &signer,price_update_data: vector<vector<vector<u8>>>,feed_id_bytes: vector<vector<u8>>,) acquires Prices {
        let len = vector::length(&price_update_data);
        while(len > 0){
            update_price(user, price_update_data[len-1], feed_id_bytes[len-1]);
            len = len - 1;
        };
    }

    fun tttta(id: u64){
        abort(id);
    }

    public fun impact_price(name: String, oracleID: vector<u8>, impact: u256, isPositive: bool, native_oracle_weight: u256, perm: Permission): u256 acquires Prices {
   // tttta(0);
        let (supra_oracle_price, _,) = get_raw_price(oracleID);
        let price;
        {
            let prices_storage = borrow_global_mut<Prices>(@dev);
            price = ensure_price(prices_storage, name, oracleID);
        }

        // Scaling impact
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

        return a / 1_000_000
    }

    fun ensure_price(prices: &mut Prices, name: String, oracleID: vector<u8>): &mut Integer{
        if (!map::contains_key(&prices.map, &name)) {
            map::upsert(&mut prices.map, name, Integer { oracleID: oracleID, value: 0, isPositive: true });
        };
        return map::borrow_mut(&mut prices.map, &name)
    }

    public entry fun test_ensure_price(name: String, oracleID: vector<u8>) acquires Prices {
        ensure_price(borrow_global_mut<Prices>(@dev), name, oracleID);
    }

// === VIEW METHODS === //

    #[view]
    public fun convert_to_usd(name: String, size: u256): u256 acquires Prices{
        let price = viewPrice(name);
        return (price * size) / 1000000000000000000
    }

    #[view]
    public fun convert_to_token(name: String, usd: u256): u256 acquires Prices{
        let price = viewPrice(name);
        return (usd * 1000000000000000000) / price
    }

    #[view]
    public fun convert_to_usd_safe(name: String, oracleID: vector<u8>, size: u256): u256 acquires Prices{
        let price = viewPrice_safe(name, oracleID);
        return (price * size) / 1000000000000000000
    }

    #[view]
    public fun convert_to_token_safe(name: String, oracleID: vector<u8>, usd: u256): u256 acquires Prices{
        let price = viewPrice_safe(name, oracleID);
        return (usd * 1000000000000000000) / price
    }

    #[view]
    public fun viewAllPrices(name: String): Map<String, Integer> acquires Prices{
        *&borrow_global<Prices>(@dev).map
    }

    #[view]
    public fun get_price(feed_id_bytes: vector<u8>): PriceStore acquires Prices {
        assert!(vector::length(&feed_id_bytes) == 32, E_FEED_ID_EMPTY);
        let prices = borrow_global<Prices>(@dev);

        if (!map::contains_key(&prices.prices, &feed_id_bytes)) {
            PriceStore { price: i64::new(0, false), expo: i64::new(0, false), publish_time: 0 }
        } else {
            *map::borrow(&prices.prices, &feed_id_bytes)
        }
    }

    #[view]
    public fun get_raw_price(feed_id_bytes: vector<u8>): (u64, u64) acquires Prices {
        assert!(vector::length(&feed_id_bytes) == 32, E_FEED_ID_EMPTY);
        let prices = borrow_global<Prices>(@dev);

        if (!map::contains_key(&prices.prices, &feed_id_bytes)) {
            return (0u64, 0u64)
        };

        let cached_price = map::borrow(&prices.prices, &feed_id_bytes);

        let expo_mag: u64 = if (i64::get_is_negative(&cached_price.expo)) {
            i64::get_magnitude_if_negative(&cached_price.expo)
        } else {
            i64::get_magnitude_if_positive(&cached_price.expo)
        };

        let price_mag: u64 = if (i64::get_is_negative(&cached_price.price)) {
            i64::get_magnitude_if_negative(&cached_price.price)
        } else {
            i64::get_magnitude_if_positive(&cached_price.price)
        };

        (price_mag, expo_mag)
    }

    #[view]
    public fun get_price_direct(feed_id_bytes: vector<u8>): (i64::I64, i64::I64, u64) {
        assert!(vector::length(&feed_id_bytes) == 32, E_FEED_ID_EMPTY);

        let price_id = price_identifier::from_byte_vec(feed_id_bytes);
        let p: Price = pyth::get_price_no_older_than(price_id, MAX_AGE_SECS);
        (
            price::get_price(&p),
            price::get_expo(&p),
            price::get_timestamp(&p),
        )
    }

    #[view]
    public fun viewPrice_safe(name: String, oracleID: vector<u8>): u256 acquires Prices {
        if (name == utf8(b"Qiara")) { return 0 };
        assert!(exists<Prices>(@dev), 404);

        let has_key;
        let qiara_impact;

        // Isolate the immutable borrow scope of Prices
        {
            let prices = borrow_global<Prices>(@dev);
            has_key = map::contains_key(&prices.map, &name);
            if (has_key) {
                // Copy the Integer struct out of global storage using the dereference operator (*)
                qiara_impact = *map::borrow(&prices.map, &name);
            } else {
                qiara_impact = Integer { oracleID: oracleID, value: 0, isPositive: true };
            };
        }; // <-- The borrow on `Prices` is completely released here

        // Now we can safely call get_raw_price()
        let (supra_oracle_price, _) = get_raw_price(qiara_impact.oracleID);

        if (!has_key) {
            return (supra_oracle_price as u256)
        };

        if (qiara_impact.isPositive) {
            return (supra_oracle_price as u256) + qiara_impact.value
        } else {
            let s_price = (supra_oracle_price as u256);
            if (qiara_impact.value >= s_price) { return 1 };
            return s_price - qiara_impact.value
        }
    }

    #[view]
    public fun viewPrice(name: String): u256 acquires Prices {
        if (name == utf8(b"Qiara")) { return 0 };
        assert!(exists<Prices>(@dev), 404);

        let has_key;
        let qiara_impact;

        // Isolate the immutable borrow scope of Prices
        {
            let prices = borrow_global<Prices>(@dev);
            has_key = map::contains_key(&prices.map, &name);
            if (has_key) {
                // Copy the Integer struct out of global storage using the dereference operator (*)
                qiara_impact = *map::borrow(&prices.map, &name);
            } else {
                qiara_impact = Integer { oracleID: vector::empty<u8>(), value: 0, isPositive: true };
            };
        }; // <-- The borrow on `Prices` is completely released here

        if (!has_key) {
            return 0
        };

        // Now we can safely call get_raw_price()
        let (supra_oracle_price, _) = get_raw_price(qiara_impact.oracleID);

        if (qiara_impact.isPositive) {
            return (supra_oracle_price as u256) + qiara_impact.value
        } else {
            let s_price = (supra_oracle_price as u256);
            if (qiara_impact.value >= s_price) { return 1 };
            return s_price - qiara_impact.value
        }
    }

    #[view]
    public fun viewPriceMulti(name: vector<String>): Map<String, u256> acquires Prices {
        let map = map::new<String, u256>();
        let len = vector::length(&name);
        while(len > 0){
            map::upsert(&mut map, *vector::borrow(&name, len-1), viewPrice(*vector::borrow(&name, len-1)));
            len = len - 1;
        };
        return map
    }

    #[view]
    public fun existsPrice(name: String): bool acquires Prices {
        let prices = borrow_global<Prices>(@dev);

        if (!map::contains_key(&prices.map, &name)) {
            return false
        };

        return true
    }

    #[view]
    public fun calculate_impact_percentage(supra_oracle_price: u256, impact: u256, isPositive: bool): u256 {
        if (supra_oracle_price == 0) { return 0 };
        if (isPositive) {
            return ((supra_oracle_price + impact) * 1_000_000_000_000_000_000) / supra_oracle_price
        } else {
            if (impact >= supra_oracle_price) {
                return 0
            };
            return ((supra_oracle_price - impact) * 1_000_000_000_000_000_000) / supra_oracle_price
        }
    }
}