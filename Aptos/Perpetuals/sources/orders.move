module dev::QiaraPerpsOrdersV12 {
    use std::signer;
    use std::string::{Self, String, utf8};
    use aptos_std::table::{Self, Table};
    use std::vector;
    use aptos_std::bcs;
    use std::timestamp;
    use event::QiaraEventV1::{Self as Event};
    use dev::QiaraSharedV7::{Self as Shared, Access as SharedAccess};
    // === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 0;
    const ERROR_ID_OUT_OF_BOUNDS: u64 = 1;
    const ERROR_REQUEST_WITH_THIS_ID_DOESNT_EXIST: u64 = 2;
    const ERROR_SHARED_MISMATCH: u64 = 3;
    const ERROR_SIGNER_DOESNT_MATCH_USER: u64 = 4;

// === ACCESS === //
    struct Access has store, key, drop {}
    struct Permission has key, drop {}

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @dev, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_permission(_access: &Access): Permission {
        Permission {}
    }


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

// Native Interface
    public entry fun create_limit_order(_signer: &signer, shared: String, user: vector<u8>, asset: String, size: u64, desired_price: u128, isLong: bool, leverage: u32, reserve_chain: String, reserve_provider: String, reserve_token: String) acquires Orders, OrdersCounter {
        assert!(bcs::to_bytes(&signer::address_of(_signer)) == user, ERROR_SIGNER_DOESNT_MATCH_USER);
        Shared::assert_is_sub_owner(shared, user);
        
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

        let data = vector[
            Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&utf8(b""))),
            Event::create_data_struct(utf8(b"id"), utf8(b"u256"), bcs::to_bytes(&counter.counter)),
            Event::create_data_struct(utf8(b"user"), utf8(b"string"), bcs::to_bytes(&user)),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(utf8(b"asset"), utf8(b"string"), bcs::to_bytes(&asset)),
            Event::create_data_struct(utf8(b"size"), utf8(b"u256"), bcs::to_bytes(&size)),
            Event::create_data_struct(utf8(b"leverage"), utf8(b"u256"), bcs::to_bytes(&leverage)),
            Event::create_data_struct(utf8(b"isLong"), utf8(b"bool"), bcs::to_bytes(&isLong)),
            Event::create_data_struct(utf8(b"desired_price"), utf8(b"u256"), bcs::to_bytes(&desired_price)),
            Event::create_data_struct(utf8(b"reserve_chain"), utf8(b"string"), bcs::to_bytes(&reserve_chain)),
            Event::create_data_struct(utf8(b"reserve_provider"), utf8(b"string"), bcs::to_bytes(&reserve_provider)),
            Event::create_data_struct(utf8(b"reserve_token"), utf8(b"string"), bcs::to_bytes(&reserve_token)),
        ];
        Event::emit_perps_event(utf8(b"Limit Order Created"), data);

        counter.counter = counter.counter + 1;
    }
    public entry fun create_twap_order(_signer: &signer, shared: String, user: vector<u8>, asset: String, periods: vector<u64>, sizes: vector<u64>, desired_price: u128, isLong: bool, leverage: u32, reserve_chain: String, reserve_provider: String, reserve_token: String) acquires Orders, OrdersCounter {
        assert!(bcs::to_bytes(&signer::address_of(_signer)) == user, ERROR_SIGNER_DOESNT_MATCH_USER);
        Shared::assert_is_sub_owner(shared, user);
       
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

        let data = vector[
            Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&utf8(b""))),
            Event::create_data_struct(utf8(b"id"), utf8(b"u256"), bcs::to_bytes(&counter.counter)),
            Event::create_data_struct(utf8(b"user"), utf8(b"string"), bcs::to_bytes(&user)),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(utf8(b"asset"), utf8(b"string"), bcs::to_bytes(&asset)),
            Event::create_data_struct(utf8(b"leverage"), utf8(b"u256"), bcs::to_bytes(&leverage)),
            Event::create_data_struct(utf8(b"isLong"), utf8(b"bool"), bcs::to_bytes(&isLong)),
            Event::create_data_struct(utf8(b"periods"), utf8(b"vector<u64>"), bcs::to_bytes(&periods)),
            Event::create_data_struct(utf8(b"sizes"), utf8(b"vector<u64>"), bcs::to_bytes(&sizes)),
            Event::create_data_struct(utf8(b"reserve_chain"), utf8(b"string"), bcs::to_bytes(&reserve_chain)),
            Event::create_data_struct(utf8(b"reserve_provider"), utf8(b"string"), bcs::to_bytes(&reserve_provider)),
            Event::create_data_struct(utf8(b"reserve_token"), utf8(b"string"), bcs::to_bytes(&reserve_token)),
        ];
        Event::emit_perps_event(utf8(b"TWAP Order Created"), data);

        counter.counter = counter.counter + 1;
    }
    public entry fun remove_limit_order(_signer: &signer, shared: String, user: vector<u8>, id: u64) acquires OrdersCounter, Orders {
        assert!(bcs::to_bytes(&signer::address_of(_signer)) == user, ERROR_SIGNER_DOESNT_MATCH_USER);
        Shared::assert_is_sub_owner(shared, user);
        
        let counter = borrow_global_mut<OrdersCounter>(@dev);
        let orders = borrow_global_mut<Orders>(@dev);

        assert!(id < counter.counter, ERROR_ID_OUT_OF_BOUNDS);
        assert!(table::contains(&orders.limit_orders, id), ERROR_REQUEST_WITH_THIS_ID_DOESNT_EXIST);

        // Validate that the request matches the user and shared fields to prevent arbitrary deletion
        let order = table::borrow(&orders.limit_orders, id);
        assert!(order.shared == shared, ERROR_SHARED_MISMATCH);

        let data = vector[
            Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&utf8(b""))),
            Event::create_data_struct(utf8(b"id"), utf8(b"u256"), bcs::to_bytes(&id)),
            Event::create_data_struct(utf8(b"user"), utf8(b"string"), bcs::to_bytes(&user)),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
        ];
        Event::emit_perps_event(utf8(b"Limit Order Deleted"), data);

        table::remove(&mut orders.limit_orders, id);
    }
    public entry fun remove_twap_order(_signer: &signer, shared: String, user: vector<u8>, id: u64) acquires OrdersCounter, Orders {
        assert!(bcs::to_bytes(&signer::address_of(_signer)) == user, ERROR_SIGNER_DOESNT_MATCH_USER);
        Shared::assert_is_sub_owner(shared, user);

        let counter = borrow_global_mut<OrdersCounter>(@dev);
        let orders = borrow_global_mut<Orders>(@dev);

        assert!(id < counter.counter, ERROR_ID_OUT_OF_BOUNDS);
        assert!(table::contains(&orders.twap_orders, id), ERROR_REQUEST_WITH_THIS_ID_DOESNT_EXIST);

        // Validate that the request matches the user and shared fields to prevent arbitrary deletion
        let order = table::borrow(&orders.twap_orders, id);
        assert!(order.shared == shared, ERROR_SHARED_MISMATCH);

        let data = vector[
            Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&utf8(b""))),
            Event::create_data_struct(utf8(b"id"), utf8(b"u256"), bcs::to_bytes(&id)),
            Event::create_data_struct(utf8(b"user"), utf8(b"string"), bcs::to_bytes(&user)),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
        ];
        Event::emit_perps_event(utf8(b"TWAP Order Deleted"), data);

        table::remove(&mut orders.twap_orders, id);
    }

// Permissionless Interface
    public fun p_create_limit_order(validator: &signer, shared: String, user: vector<u8>, asset: String, size: u64, desired_price: u128, isLong: bool, leverage: u32, reserve_chain: String, reserve_provider: String, reserve_token: String, perm: Permission) acquires Orders, OrdersCounter {
        Shared::assert_is_sub_owner(shared, user);
        
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

        let data = vector[
            Event::create_data_struct(utf8(b"validator"), utf8(b"vector<u8>"), bcs::to_bytes(&signer::address_of(validator))),
            Event::create_data_struct(utf8(b"id"), utf8(b"u256"), bcs::to_bytes(&counter.counter)),
            Event::create_data_struct(utf8(b"user"), utf8(b"string"), bcs::to_bytes(&user)),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(utf8(b"asset"), utf8(b"string"), bcs::to_bytes(&asset)),
            Event::create_data_struct(utf8(b"size"), utf8(b"u256"), bcs::to_bytes(&size)),
            Event::create_data_struct(utf8(b"leverage"), utf8(b"u256"), bcs::to_bytes(&leverage)),
            Event::create_data_struct(utf8(b"isLong"), utf8(b"bool"), bcs::to_bytes(&isLong)),
            Event::create_data_struct(utf8(b"desired_price"), utf8(b"u256"), bcs::to_bytes(&desired_price)),
            Event::create_data_struct(utf8(b"reserve_chain"), utf8(b"string"), bcs::to_bytes(&reserve_chain)),
            Event::create_data_struct(utf8(b"reserve_provider"), utf8(b"string"), bcs::to_bytes(&reserve_provider)),
            Event::create_data_struct(utf8(b"reserve_token"), utf8(b"string"), bcs::to_bytes(&reserve_token)),
        ];
        Event::emit_perps_event(utf8(b"Limit Order Created"), data);

        counter.counter = counter.counter + 1;
    }
    public fun p_create_twap_order(validator: &signer, shared: String, user: vector<u8>, asset: String, periods: vector<u64>, sizes: vector<u64>, isLong: bool, leverage: u32, reserve_chain: String, reserve_provider: String, reserve_token: String, perm: Permission) acquires Orders, OrdersCounter {
        Shared::assert_is_sub_owner(shared, user);
        
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

        let data = vector[
            Event::create_data_struct(utf8(b"validator"), utf8(b"vector<u8>"), bcs::to_bytes(&signer::address_of(validator))),
            Event::create_data_struct(utf8(b"id"), utf8(b"u256"), bcs::to_bytes(&counter.counter)),
            Event::create_data_struct(utf8(b"user"), utf8(b"string"), bcs::to_bytes(&user)),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(utf8(b"asset"), utf8(b"string"), bcs::to_bytes(&asset)),
            Event::create_data_struct(utf8(b"leverage"), utf8(b"u256"), bcs::to_bytes(&leverage)),
            Event::create_data_struct(utf8(b"isLong"), utf8(b"bool"), bcs::to_bytes(&isLong)),
            Event::create_data_struct(utf8(b"periods"), utf8(b"vector<u64>"), bcs::to_bytes(&periods)),
            Event::create_data_struct(utf8(b"sizes"), utf8(b"vector<u64>"), bcs::to_bytes(&sizes)),
            Event::create_data_struct(utf8(b"reserve_chain"), utf8(b"string"), bcs::to_bytes(&reserve_chain)),
            Event::create_data_struct(utf8(b"reserve_provider"), utf8(b"string"), bcs::to_bytes(&reserve_provider)),
            Event::create_data_struct(utf8(b"reserve_token"), utf8(b"string"), bcs::to_bytes(&reserve_token)),
        ];
        Event::emit_perps_event(utf8(b"TWAP Order Created"), data);

        counter.counter = counter.counter + 1;
    }

    public fun p_remove_limit_order(validator: &signer, shared: String, user: vector<u8>, id: u64, perm: Permission) acquires OrdersCounter, Orders {
        Shared::assert_is_sub_owner(shared, user);
        
        let counter = borrow_global_mut<OrdersCounter>(@dev);
        let orders = borrow_global_mut<Orders>(@dev);

        assert!(id < counter.counter, ERROR_ID_OUT_OF_BOUNDS);
        assert!(table::contains(&orders.limit_orders, id), ERROR_REQUEST_WITH_THIS_ID_DOESNT_EXIST);

        // Validate that the request matches the user and shared fields to prevent arbitrary deletion
        let order = table::borrow(&orders.limit_orders, id);
        assert!(order.shared == shared, ERROR_SHARED_MISMATCH);

        let data = vector[
            Event::create_data_struct(utf8(b"validator"), utf8(b"vector<u8>"), bcs::to_bytes(&signer::address_of(validator))),
            Event::create_data_struct(utf8(b"id"), utf8(b"u256"), bcs::to_bytes(&id)),
            Event::create_data_struct(utf8(b"user"), utf8(b"string"), bcs::to_bytes(&user)),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
        ];
        Event::emit_perps_event(utf8(b"Limit Order Deleted"), data);

        table::remove(&mut orders.limit_orders, id);
    }

    public fun p_remove_twap_order(validator: &signer, shared: String, user: vector<u8>, id: u64, perm: Permission) acquires OrdersCounter, Orders {
        Shared::assert_is_sub_owner(shared, user);

        let counter = borrow_global_mut<OrdersCounter>(@dev);
        let orders = borrow_global_mut<Orders>(@dev);

        assert!(id < counter.counter, ERROR_ID_OUT_OF_BOUNDS);
        assert!(table::contains(&orders.twap_orders, id), ERROR_REQUEST_WITH_THIS_ID_DOESNT_EXIST);

        // Validate that the request matches the user and shared fields to prevent arbitrary deletion
        let order = table::borrow(&orders.twap_orders, id);
        assert!(order.shared == shared, ERROR_SHARED_MISMATCH);

        let data = vector[
            Event::create_data_struct(utf8(b"validator"), utf8(b"vector<u8>"), bcs::to_bytes(&signer::address_of(validator))),
            Event::create_data_struct(utf8(b"id"), utf8(b"u256"), bcs::to_bytes(&id)),
            Event::create_data_struct(utf8(b"user"), utf8(b"string"), bcs::to_bytes(&user)),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
        ];
        Event::emit_perps_event(utf8(b"TWAP Order Deleted"), data);

        table::remove(&mut orders.twap_orders, id);
    }



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