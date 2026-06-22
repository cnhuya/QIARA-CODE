module 0x0::QiaraPerpOrdersInterfaceV1 {
    use sui::tx_context::{Self, TxContext};
    use std::string::{Self, String};
    use sui::bcs;
    use sui::clock::{Self, Clock};
    
    use Qiara::QiaraEventsV1::{Self as Event};

    // --- Errors ---
    const ERROR_SHARED_NAME_CANT_BE_EMPTY: u64 = 0;

    // --- Initialization ---
    fun init(_ctx: &mut TxContext) {}

    // --- Order Interface Functions ---

    public entry fun create_limit_order(
        shared: String, 
        user: vector<u8>, 
        asset: String, 
        size: u64, 
        desired_price: u128, 
        is_long: bool, 
        leverage: u32, 
        reserve_chain: String, 
        reserve_provider: String, 
        reserve_token: String, 
        order_id: u64, 
        clock: &Clock, 
        _ctx: &mut TxContext
    ) {
        if (shared == string::utf8(b"")) {
            abort ERROR_SHARED_NAME_CANT_BE_EMPTY
        };

        // Explicitly cast parameters to matching event type lengths (u256)
        let id_u256 = (order_id as u256);
        let size_u256 = (size as u256);
        let leverage_u256 = (leverage as u256);
        let desired_price_u256 = (desired_price as u256);

        let data = vector[
            Event::create_data_struct(string::utf8(b"validator"), string::utf8(b"string"), bcs::to_bytes(&string::utf8(b""))),
            Event::create_data_struct(string::utf8(b"id"), string::utf8(b"u256"), bcs::to_bytes(&id_u256)),
            Event::create_data_struct(string::utf8(b"user"), string::utf8(b"string"), bcs::to_bytes(&user)),
            Event::create_data_struct(string::utf8(b"shared"), string::utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(string::utf8(b"asset"), string::utf8(b"string"), bcs::to_bytes(&asset)),
            Event::create_data_struct(string::utf8(b"size"), string::utf8(b"u256"), bcs::to_bytes(&size_u256)),
            Event::create_data_struct(string::utf8(b"leverage"), string::utf8(b"u256"), bcs::to_bytes(&leverage_u256)),
            Event::create_data_struct(string::utf8(b"isLong"), string::utf8(b"bool"), bcs::to_bytes(&is_long)),
            Event::create_data_struct(string::utf8(b"desired_price"), string::utf8(b"u256"), bcs::to_bytes(&desired_price_u256)),
            Event::create_data_struct(string::utf8(b"reserve_chain"), string::utf8(b"string"), bcs::to_bytes(&reserve_chain)),
            Event::create_data_struct(string::utf8(b"reserve_provider"), string::utf8(b"string"), bcs::to_bytes(&reserve_provider)),
            Event::create_data_struct(string::utf8(b"reserve_token"), string::utf8(b"string"), bcs::to_bytes(&reserve_token)),
        ];

        Event::emit_event(clock, string::utf8(b"Limit Order Created"), data);
    }

    public entry fun create_twap_order(
        shared: String, 
        user: vector<u8>, 
        asset: String, 
        periods: vector<u64>, 
        sizes: vector<u64>, 
        is_long: bool, 
        leverage: u32, 
        reserve_chain: String, 
        reserve_provider: String, 
        reserve_token: String, 
        order_id: u64, 
        clock: &Clock, 
        _ctx: &mut TxContext
    ) {
        if (shared == string::utf8(b"")) {
            abort ERROR_SHARED_NAME_CANT_BE_EMPTY
        };

        let id_u256 = (order_id as u256);
        let leverage_u256 = (leverage as u256);

        let data = vector[
            Event::create_data_struct(string::utf8(b"validator"), string::utf8(b"string"), bcs::to_bytes(&string::utf8(b""))),
            Event::create_data_struct(string::utf8(b"id"), string::utf8(b"u256"), bcs::to_bytes(&id_u256)),
            Event::create_data_struct(string::utf8(b"user"), string::utf8(b"string"), bcs::to_bytes(&user)),
            Event::create_data_struct(string::utf8(b"shared"), string::utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(string::utf8(b"asset"), string::utf8(b"string"), bcs::to_bytes(&asset)),
            Event::create_data_struct(string::utf8(b"leverage"), string::utf8(b"u256"), bcs::to_bytes(&leverage_u256)),
            Event::create_data_struct(string::utf8(b"isLong"), string::utf8(b"bool"), bcs::to_bytes(&is_long)),
            Event::create_data_struct(string::utf8(b"periods"), string::utf8(b"vector<u64>"), bcs::to_bytes(&periods)),
            Event::create_data_struct(string::utf8(b"sizes"), string::utf8(b"vector<u64>"), bcs::to_bytes(&sizes)),
            Event::create_data_struct(string::utf8(b"reserve_chain"), string::utf8(b"string"), bcs::to_bytes(&reserve_chain)),
            Event::create_data_struct(string::utf8(b"reserve_provider"), string::utf8(b"string"), bcs::to_bytes(&reserve_provider)),
            Event::create_data_struct(string::utf8(b"reserve_token"), string::utf8(b"string"), bcs::to_bytes(&reserve_token)),
        ];

        Event::emit_event(clock, string::utf8(b"TWAP Order Created"), data);
    }

    public entry fun remove_limit_order(
        shared: String, 
        user: vector<u8>, 
        id: u64, 
        clock: &Clock, 
        _ctx: &mut TxContext
    ) {
        if (shared == string::utf8(b"")) {
            abort ERROR_SHARED_NAME_CANT_BE_EMPTY
        };

        let id_u256 = (id as u256);

        let data = vector[
            Event::create_data_struct(string::utf8(b"validator"), string::utf8(b"string"), bcs::to_bytes(&string::utf8(b""))),
            Event::create_data_struct(string::utf8(b"id"), string::utf8(b"u256"), bcs::to_bytes(&id_u256)),
            Event::create_data_struct(string::utf8(b"user"), string::utf8(b"string"), bcs::to_bytes(&user)),
            Event::create_data_struct(string::utf8(b"shared"), string::utf8(b"string"), bcs::to_bytes(&shared)),
        ];

        Event::emit_event(clock, string::utf8(b"Limit Order Deleted"), data);
    }

    public entry fun remove_twap_order(
        shared: String, 
        user: vector<u8>, 
        id: u64, 
        clock: &Clock, 
        _ctx: &mut TxContext
    ) {
        if (shared == string::utf8(b"")) {
            abort ERROR_SHARED_NAME_CANT_BE_EMPTY
        };

        let id_u256 = (id as u256);

        let data = vector[
            Event::create_data_struct(string::utf8(b"validator"), string::utf8(b"string"), bcs::to_bytes(&string::utf8(b""))),
            Event::create_data_struct(string::utf8(b"id"), string::utf8(b"u256"), bcs::to_bytes(&id_u256)),
            Event::create_data_struct(string::utf8(b"user"), string::utf8(b"string"), bcs::to_bytes(&user)),
            Event::create_data_struct(string::utf8(b"shared"), string::utf8(b"string"), bcs::to_bytes(&shared)),
        ];

        Event::emit_event(clock, string::utf8(b"TWAP Order Deleted"), data);
    }
}