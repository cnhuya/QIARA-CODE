module dev::QiaraOracleV5 {
    use std::string::{Self, String, utf8, bytes as b};
    use std::vector;
    use std::bcs;
    use std::signer;
    use std::timestamp;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use event::QiaraEventV1::{Self as Event};
    use dev::QiaraOracleStoreV5::{Self as oracle_store};
// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 0;
    const ERROR_TOKEN_PRICE_COULDNT_BE_FOUND: u64 = 1;
    
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
    struct Prices has copy, key{
        map: Map<String, Integer>,
    }

    struct Integer has drop, key, store, copy {
        oracleID: vector<u8>,
        value: u256,
        isPositive: bool,
    }

    fun tttta(x: u64){
        abort(x);
    }

// === INIT === //
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @dev, 1);

        if (!exists<Prices>(@dev)) {
            move_to(admin, Prices { map: map::new<String, Integer>() });
        };
    }

public fun impact_price(name: String, oracleID: vector<u8>, impact: u256, isPositive: bool, native_oracle_weight: u256, perm: Permission): u256 acquires Prices {

        let (supra_oracle_price, _,) = oracle_store::get_raw_price(oracleID);
        
        // Scaling impact
        let scaled_impact = (impact * 1_000_000) / native_oracle_weight;
        if (scaled_impact == 0) { return 0 };

        // Declare variables to hold values extracted from the borrow scope
        let old_price_state;
        let new_price_state;
        let final_price_value;
        let final_price_is_positive;

        // Isolate the mutable borrow scope
        {
            let prices_storage = borrow_global_mut<Prices>(@dev);
            let price = ensure_price(prices_storage, name, oracleID);
            
            // Capture old state for the event
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
                // Handle Negative Impact
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

            // Copy out data and dereference price before releasing the borrow
            new_price_state = *price;
            final_price_value = price.value;
            final_price_is_positive = price.isPositive;
        }; // <-- The mutable borrow of `Prices` is completely released here

        // Now you can safely call viewPrice because Prices is no longer borrowed
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
            map::upsert(&mut prices.map, name, Integer {  oracleID: oracleID, value: 0, isPositive: true });
        };
        return map::borrow_mut(&mut prices.map, &name)
    }

    public entry fun test_ensure_price(name: String, oracleID: vector<u8>) acquires Prices
    {
        ensure_price(borrow_global_mut<Prices>(@dev), name, oracleID);

    }

    #[view]
    public fun convert_to_usd(name: String, size: u256): u256 acquires Prices{
        let price = viewPrice(name);

        //1000000000000000000*1000000000000000000/1000000000000000000

        return(price*size)/1000000000000000000
    }

    #[view]
    public fun convert_to_token(name: String, usd: u256): u256 acquires Prices{
        let price = viewPrice(name);
        return (usd*1000000000000000000)/price
    }


    #[view]
    public fun convert_to_usd_safe(name: String, oracleID: vector<u8>, size: u256): u256 acquires Prices{
        let price = viewPrice_safe(name, oracleID);

        //1000000000000000000*1000000000000000000/1000000000000000000

        return(price*size)/1000000000000000000
    }

    #[view]
    public fun convert_to_token_safe(name: String, oracleID: vector<u8>, usd: u256): u256 acquires Prices{
        let price = viewPrice_safe(name, oracleID);
        return (usd*1000000000000000000)/price
    }

    #[view]
    public fun viewAllPrices(name: String): Map<String, Integer> acquires Prices{

        borrow_global_mut<Prices>(@dev).map

    }
    #[view]
    public fun viewPrice_safe(name: String, oracleID: vector<u8>): u256 acquires Prices {
        if (name == utf8(b"Qiara")) { return 0 };
        assert!(exists<Prices>(@dev), 404);

        let prices = borrow_global<Prices>(@dev);

        // If the token isn't in our "Impact Map" yet, return the raw Supra price
        if (!map::contains_key(&prices.map, &name)) {
            // We need an oracleID to fetch the price. 
            // If we don't have it in the map, we can't look up Supra.
            // Therefore, we return a 0 or abort with a clearer message.
            let (supra_oracle_price, _,) = oracle_store::get_raw_price(oracleID);
            return (supra_oracle_price as u256)
        };

        let qiara_impact = map::borrow(&prices.map, &name);
        let (supra_oracle_price, _,) = oracle_store::get_raw_price(qiara_impact.oracleID);

        if (qiara_impact.isPositive) {
            return (supra_oracle_price as u256) + qiara_impact.value
        } else {
            // Prevent underflow if impact > price
            let s_price = (supra_oracle_price as u256);
            if (qiara_impact.value >= s_price) { return 1 }; // Return 1 cent/unit min price
            return s_price - qiara_impact.value
        }
    }

    #[view]
    public fun viewPrice(name: String): u256 acquires Prices {
        if (name == utf8(b"Qiara")) { return 0 };
        assert!(exists<Prices>(@dev), 404);

        let prices = borrow_global<Prices>(@dev);

        // If the token isn't in our "Impact Map" yet, return the raw Supra price
        if (!map::contains_key(&prices.map, &name)) {
            // We need an oracleID to fetch the price. 
            // If we don't have it in the map, we can't look up Supra.
            // Therefore, we return a 0 or abort with a clearer message.
            return 0
        };

        let qiara_impact = map::borrow(&prices.map, &name);
        let (supra_oracle_price, _, ) = oracle_store::get_raw_price(qiara_impact.oracleID);

        if (qiara_impact.isPositive) {
            return (supra_oracle_price as u256) + qiara_impact.value
        } else {
            // Prevent underflow if impact > price
            let s_price = (supra_oracle_price as u256);
            if (qiara_impact.value >= s_price) { return 1 }; // Return 1 cent/unit min price
            return s_price - qiara_impact.value
        }
    }

    #[view]
    public fun viewPriceMulti(name: vector<String>): Map<String, u256> acquires Prices{

        let map = map::new<String, u256>();
        let len = vector::length(&name);
        while(len>0){
            map::upsert(&mut map, *vector::borrow(&name, len-1), viewPrice(*vector::borrow(&name, len-1)));
            len=len-1;
        };
        return map

    }

    #[view]
    public fun existsPrice(name: String): bool acquires Prices{

        let prices = borrow_global_mut<Prices>(@dev);

        if (!map::contains_key(&prices.map, &name)) {
            return false
        };

        return true

    }

    #[view]
    public fun calculate_impact_percentage(supra_oracle_price: u256, impact: u256,  isPositive: bool): u256 {
        // Avoid division by zero
        if (supra_oracle_price == 0) { return 0 };
        if (isPositive) {
            // Returns the price multiplier (e.g., 1.05 * 1e18)
            return ((supra_oracle_price + impact) * 1_000_000_000_000_000_000) / supra_oracle_price
        } else {
            // Prevent underflow if impact is greater than price
            if (impact >= supra_oracle_price) {
                return 0 // Price cannot be less than zero
            };
            return ((supra_oracle_price - impact) * 1_000_000_000_000_000_000) / supra_oracle_price
        }
    }

}