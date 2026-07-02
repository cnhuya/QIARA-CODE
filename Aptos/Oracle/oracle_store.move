module dev::QiaraOracleStoreV5 {
    use std::string::{Self as string, String, utf8};
    use std::vector;
    use std::bcs;
    use pyth::pyth;
    use pyth::price;
    use pyth::price::Price;
    use pyth::price_identifier;
    use pyth::i64;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};

    use event::QiaraEventV1::{Self as Event};


// ── Error codes ────────────────────────────────────────────────────────────
    const E_NOT_INITIALIZED:  u64 = 1;
    const E_ALREADY_INIT:     u64 = 2;
    const E_NEGATIVE_PRICE:   u64 = 3;
    const E_STALE_PRICE:      u64 = 4;
    const E_FEED_ID_EMPTY:    u64 = 5;


// ── Max age for "fresh" price: 60 seconds ──────────────────────────────────
    const MAX_AGE_SECS: u64 = 60;

    struct PriceStore has key, store, drop, copy {
        price:        i64::I64,
        expo:         i64::I64,
        publish_time: u64,
    }

    struct Prices has key, store {
        prices: Map<vector<u8>, PriceStore>,
    }

    // ── Init ───────────────────────────────────────────────────────────────────
    fun init_module(admin: &signer) {
        move_to(admin, Prices { prices: map::new<vector<u8>, PriceStore>() });
    }


    // ── Update + cache ─────────────────────────────────────────────────────────
    public entry fun update_price(user: &signer,price_update_data: vector<vector<u8>>,feed_id_bytes: vector<u8>,) acquires Prices {
        assert!(exists<Prices>(@dev), E_NOT_INITIALIZED);
        assert!(std::vector::length(&feed_id_bytes) == 32, std::vector::length(&feed_id_bytes));

        let old_price_store = get_price(feed_id_bytes);  // ← update this call too

        let fee = pyth::get_update_fee(&price_update_data);
        let coins = coin::withdraw<AptosCoin>(user, fee);
        pyth::update_price_feeds(price_update_data, coins);

        let price_id = price_identifier::from_byte_vec(feed_id_bytes);
        let p: Price = pyth::get_price_no_older_than(price_id, MAX_AGE_SECS);

        let raw = price::get_price(&p);
        assert!(!i64::get_is_negative(&raw), E_NEGATIVE_PRICE);

        let prices = borrow_global_mut<Prices>(@dev);
        let new_store = PriceStore {
            price: raw,
            expo: price::get_expo(&p),
            publish_time: price::get_timestamp(&p),
        };

        let old_price = i64::get_magnitude_if_positive(&old_price_store.price);
        let new_price = i64::get_magnitude_if_positive(&new_store.price);

        let data = vector[
            Event::create_data_struct(utf8(b"oracle id"), utf8(b"vector<u8>"), bcs::to_bytes(&feed_id_bytes)),
            Event::create_data_struct(utf8(b"old_price"), utf8(b"u64"), bcs::to_bytes(&old_price)),
            Event::create_data_struct(utf8(b"new_price"), utf8(b"u64"), bcs::to_bytes(&new_price)),
        ];
        Event::emit_oracle_event(utf8(b"Price Update"), data);

        if (map::contains_key(&prices.prices, &feed_id_bytes)) {
            *map::borrow_mut(&mut prices.prices, &feed_id_bytes) = new_store;
        } else {
            map::add(&mut prices.prices, feed_id_bytes, new_store);
        }
    }

    public entry fun batch_update_price(user: &signer,price_update_data: vector<vector<vector<u8>>>,feed_id_bytes: vector<vector<u8>>,) acquires Prices {
        let len = vector::length(&price_update_data);
        while(len > 0){
            update_price(user,price_update_data[len-1],feed_id_bytes[len-1]);
            len = len - 1;
        };
    }

    fun ensure_price(feed_id_str: vector<u8>, price_store: PriceStore) acquires Prices {
        let prices = borrow_global_mut<Prices>(@dev);
        map::upsert(&mut prices.prices, feed_id_str, price_store);
    }

    // ── Read from cache ────────────────────────────────────────────────────────
    #[view]
    public fun get_price(feed_id_bytes: vector<u8>): PriceStore acquires Prices {
        assert!(std::vector::length(&feed_id_bytes) == 32, std::vector::length(&feed_id_bytes));

        let prices = borrow_global<Prices>(@dev);  // No mut needed for view

        if (!map::contains_key(&prices.prices, &feed_id_bytes)) {
            PriceStore { price: i64::new(0, false), expo: i64::new(0, false), publish_time: 0 }
        } else {
            *map::borrow(&prices.prices, &feed_id_bytes)  // borrow (not borrow_mut) in view
        }
    }
    // ── Read raw from cache ────────────────────────────────────────────────────────
    #[view]
    public fun get_raw_price(feed_id_bytes: vector<u8>): (u64, u64) acquires Prices {
        assert!(std::vector::length(&feed_id_bytes) == 32, std::vector::length(&feed_id_bytes));

        let prices = borrow_global<Prices>(@dev);

        if (!map::contains_key(&prices.prices, &feed_id_bytes)) {
            return (0u64, 0u64)
        };

        let cached_price = map::borrow(&prices.prices, &feed_id_bytes);  // fixed typo: catched → cached

        // Explicit type + handle expo sign
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
    // ── Direct read from Pyth (no cache) ───────────────────────────────────────
    #[view]
    public fun get_price_direct(feed_id_bytes: vector<u8>): (i64::I64, i64::I64, u64) {
        assert!(std::vector::length(&feed_id_bytes) == 32, std::vector::length(&feed_id_bytes));

        let price_id = price_identifier::from_byte_vec(feed_id_bytes);
        let p: Price = pyth::get_price_no_older_than(price_id, MAX_AGE_SECS);
        (
            price::get_price(&p),
            price::get_expo(&p),
            price::get_timestamp(&p),
        )
    }
}