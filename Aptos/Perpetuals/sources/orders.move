module dev::QiaraPerpsOrdersV2 {
    use std::signer;
    use std::string::{Self, String, utf8};
    use aptos_std::table::{Self, Table};
    use std::vector;
    use std::timestamp;

    // === ERRORS === //
    const ERROR_ID_OUT_OF_BOUNDS: u64 = 1;
    const ERROR_REQUEST_WITH_THIS_ID_DOESNT_EXIST: u64 = 2;
    const ERROR_SHARED_MISMATCH: u64 = 3;

    struct OrdersCounter has key {
        counter: u64
    }

    struct Orders has key {
        twap_orders: Table<u64, TwapRequest>,
        limit_orders: Table<u64, LimitRequest>,
    }

    struct LimitRequest has copy, drop, store {
        shared: String,
        user: vector<u8>,
        asset: String,
        size: u64,
        desired_price: u128,
        isLong: bool,
        leverage: u32,
        reserve_chain: String,
        reserve_provider: String,
        reserve_token: String,
    }

    struct TwapRequest has copy, drop, store {
        shared: String,
        user: vector<u8>,
        asset: String,
        periods: vector<u64>,
        sizes: vector<u64>,
        isLong: bool,
        leverage: u32,
        reserve_chain: String,
        reserve_provider: String,
        reserve_token: String,
        created_at: u64
    }

    /// === INIT ===
    fun init_module(admin: &signer) {
        let admin_addr = signer::address_of(admin);

        if (!exists<Orders>(admin_addr)) {
            move_to(admin, Orders { twap_orders: table::new<u64, TwapRequest>() , limit_orders: table::new<u64, LimitRequest>() });
        };

        if (!exists<OrdersCounter>(admin_addr)) {
            move_to(admin, OrdersCounter { counter: 0 });
        };
    }

    public entry fun create_limit_order(_signer: &signer, shared: String, user: vector<u8>, asset: String, size: u64, desired_price: u128, isLong: bool, leverage: u32, reserve_chain: String, reserve_provider: String, reserve_token: String) acquires Orders, OrdersCounter {
        let counter = borrow_global_mut<OrdersCounter>(@dev);
        let orders = borrow_global_mut<Orders>(@dev);

        let order = LimitRequest {
            shared: shared,
            user: user,
            asset: asset,
            size: size,
            desired_price: desired_price,
            isLong: isLong,
            leverage: leverage,
            reserve_chain: reserve_chain,
            reserve_provider: reserve_provider,
            reserve_token: reserve_token,
        };

        table::add(&mut orders.limit_orders, counter.counter, order);

        counter.counter = counter.counter + 1;
    }
    public entry fun create_twap_order(_signer: &signer, shared: String, user: vector<u8>, asset: String, periods: vector<u64>, sizes: vector<u64>, desired_price: u128, isLong: bool, leverage: u32, reserve_chain: String, reserve_provider: String, reserve_token: String) acquires Orders, OrdersCounter {
        let counter = borrow_global_mut<OrdersCounter>(@dev);
        let orders = borrow_global_mut<Orders>(@dev);

        let order = TwapRequest {
            shared: shared,
            user: user,
            asset: asset,
            periods: periods,
            sizes: sizes,
            isLong: isLong,
            leverage: leverage,
            reserve_chain: reserve_chain,
            reserve_provider: reserve_provider,
            reserve_token: reserve_token,
            created_at: timestamp::now_seconds(),
        };

        table::add(&mut orders.twap_orders, counter.counter, order);

        counter.counter = counter.counter + 1;
    }

    public entry fun remove_limit_order(_signer: &signer, shared: String, user: vector<u8>, id: u64) acquires OrdersCounter, Orders {
        let counter = borrow_global_mut<OrdersCounter>(@dev);
        let orders = borrow_global_mut<Orders>(@dev);

        assert!(id < counter.counter, ERROR_ID_OUT_OF_BOUNDS);
        assert!(table::contains(&orders.limit_orders, id), ERROR_REQUEST_WITH_THIS_ID_DOESNT_EXIST);

        // Validate that the request matches the user and shared fields to prevent arbitrary deletion
        let order = table::borrow(&orders.limit_orders, id);
        assert!(order.shared == shared, ERROR_SHARED_MISMATCH);

        table::remove(&mut orders.limit_orders, id);
    }

    public entry fun remove_twap_order(_signer: &signer, shared: String, user: vector<u8>, id: u64) acquires OrdersCounter, Orders {
        let counter = borrow_global_mut<OrdersCounter>(@dev);
        let orders = borrow_global_mut<Orders>(@dev);

        assert!(id < counter.counter, ERROR_ID_OUT_OF_BOUNDS);
        assert!(table::contains(&orders.twap_orders, id), ERROR_REQUEST_WITH_THIS_ID_DOESNT_EXIST);

        // Validate that the request matches the user and shared fields to prevent arbitrary deletion
        let order = table::borrow(&orders.twap_orders, id);
        assert!(order.shared == shared, ERROR_SHARED_MISMATCH);

        table::remove(&mut orders.twap_orders, id);
    }

   // Permissionless Interface
/// === VIEW FUNCTIONS ===
    /// === TWAP VIEW FUNCTIONS ===
        #[view]
        public fun get_twap_order(id: u64): TwapRequest acquires Orders {
            let orders = borrow_global<Orders>(@dev);
            assert!(table::contains(&orders.twap_orders, id), ERROR_REQUEST_WITH_THIS_ID_DOESNT_EXIST);
            *table::borrow(&orders.twap_orders, id)
        }

        #[view]
        public fun get_twap_orders(ids: vector<u64>): vector<TwapRequest> acquires Orders {
            let orders = borrow_global<Orders>(@dev);
            let results = vector::empty<TwapRequest>();
            
            let i = 0;
            let len = vector::length(&ids);
            while (i < len) {
                let id = *vector::borrow(&ids, i);
                assert!(table::contains(&orders.twap_orders, id), ERROR_REQUEST_WITH_THIS_ID_DOESNT_EXIST);
                let order = *table::borrow(&orders.twap_orders, id);
                vector::push_back(&mut results, order);
                i = i + 1;
            };
            
            results
        }

        #[view]
        public fun get_twap_order_deconstructed(id: u64): (String, vector<u8>, String, vector<u64>, vector<u64>, bool, u32, String, String, String, u64) acquires Orders {
            let orders = borrow_global<Orders>(@dev);
            assert!(table::contains(&orders.twap_orders, id), ERROR_REQUEST_WITH_THIS_ID_DOESNT_EXIST);
            
            // Copy the struct from the table (allowed since Request has the `copy` ability)
            let order = *table::borrow(&orders.twap_orders, id);
            
            // Deconstruct the struct into its individual fields
            let TwapRequest {
                shared,
                user,
                asset,
                periods,
                sizes,
                isLong,
                leverage,
                reserve_chain,
                reserve_provider,
                reserve_token,
                created_at
            } = order;

            (shared,user,asset,periods,sizes,isLong,leverage,reserve_chain,reserve_provider,reserve_token, created_at)
        }
    /// === LIMIT VIEW FUNCTIONS ===
        #[view]
        public fun get_limit_order(id: u64): LimitRequest acquires Orders {
            let limit_orders = borrow_global<Orders>(@dev);
            assert!(table::contains(&limit_orders.limit_orders, id), ERROR_REQUEST_WITH_THIS_ID_DOESNT_EXIST);
            *table::borrow(&limit_orders.limit_orders, id)
        }

        #[view]
        public fun get_limit_orders(ids: vector<u64>): vector<LimitRequest> acquires Orders {
            let orders = borrow_global<Orders>(@dev);
            let results = vector::empty<LimitRequest>();
            
            let i = 0;
            let len = vector::length(&ids);
            while (i < len) {
                let id = *vector::borrow(&ids, i);
                assert!(table::contains(&orders.limit_orders, id), ERROR_REQUEST_WITH_THIS_ID_DOESNT_EXIST);
                let order = *table::borrow(&orders.limit_orders, id);
                vector::push_back(&mut results, order);
                i = i + 1;
            };
            
            results
        }

        #[view]
        public fun get_limit_order_deconstructed(id: u64): (String, vector<u8>, String, u64, u128, bool, u32, String, String, String) acquires Orders {
            let orders = borrow_global<Orders>(@dev);
            assert!(table::contains(&orders.limit_orders, id), ERROR_REQUEST_WITH_THIS_ID_DOESNT_EXIST);
            
            // Copy the struct from the table (allowed since Request has the `copy` ability)
            let order = *table::borrow(&orders.limit_orders, id);
            
            // Deconstruct the struct into its individual fields
            let LimitRequest {
                shared,
                user,
                asset,
                size,
                desired_price,
                isLong,
                leverage,
                reserve_chain,
                reserve_provider,
                reserve_token,
            } = order;

            (shared,user,asset,size,desired_price,isLong,leverage,reserve_chain,reserve_provider,reserve_token)
        }
}