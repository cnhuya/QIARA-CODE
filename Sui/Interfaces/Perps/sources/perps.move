module 0x0::QiaraPerpsInterfaceV1 {
    use sui::tx_context::{Self, TxContext};
    use std::string::{Self, String};
    use sui::bcs;
    use sui::clock::{Self, Clock};
    
    use Qiara::QiaraEventsV1::{Self as Event};

    // --- Errors ---
    const ERROR_SHARED_NAME_CANT_BE_EMPTY: u64 = 0;
    const ERROR_ASSET_CANT_BE_EMPTY: u64 = 3;

    // --- Initialization ---
    fun init(_ctx: &mut TxContext) {
    }

    // --- Perpetuals Interface Functions ---

    public entry fun p_accrue_interest(shared: String, asset: String, clock: &Clock, ctx: &mut TxContext) {
        safety_check(shared, asset);

        let sender = tx_context::sender(ctx);
        let data = vector[
            Event::create_data_struct(string::utf8(b"sender"), string::utf8(b"address"), bcs::to_bytes(&sender)),
            Event::create_data_struct(string::utf8(b"shared_storage"), string::utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(string::utf8(b"asset"), string::utf8(b"string"), bcs::to_bytes(&asset)),
        ];

        Event::emit_event(clock, string::utf8(b"Modular Interest Accrue"), data);
    }

    public entry fun p_trade(shared: String, asset: String, size: u64, leverage: u64, is_long: bool, reserve_chain: String, reserve_provider: String, reserve_token: String, clock: &Clock, ctx: &mut TxContext) {
        safety_check(shared, asset);

        let sender = tx_context::sender(ctx);
        let data = vector[
            Event::create_data_struct(string::utf8(b"sender"), string::utf8(b"address"), bcs::to_bytes(&sender)),
            Event::create_data_struct(string::utf8(b"shared_storage"), string::utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(string::utf8(b"asset"), string::utf8(b"string"), bcs::to_bytes(&asset)),
            Event::create_data_struct(string::utf8(b"size"), string::utf8(b"u64"), bcs::to_bytes(&size)),
            Event::create_data_struct(string::utf8(b"leverage"), string::utf8(b"u64"), bcs::to_bytes(&leverage)),
            Event::create_data_struct(string::utf8(b"is_long"), string::utf8(b"bool"), bcs::to_bytes(&is_long)),
            Event::create_data_struct(string::utf8(b"reserve_chain"), string::utf8(b"string"), bcs::to_bytes(&reserve_chain)),
            Event::create_data_struct(string::utf8(b"reserve_provider"), string::utf8(b"string"), bcs::to_bytes(&reserve_provider)),
            Event::create_data_struct(string::utf8(b"reserve_token"), string::utf8(b"string"), bcs::to_bytes(&reserve_token)),
        ];

        Event::emit_event(clock, string::utf8(b"Modular Trade"), data);
    }

    public entry fun p_update_oracle_and_trade(shared: String, asset: String, size: u64, leverage: u64, is_long: bool, reserve_chain: String, reserve_provider: String, reserve_token: String, price_update_data: vector<vector<u8>>, clock: &Clock, ctx: &mut TxContext) {
        safety_check(shared, asset);

        let sender = tx_context::sender(ctx);
        let data = vector[
            Event::create_data_struct(string::utf8(b"sender"), string::utf8(b"address"), bcs::to_bytes(&sender)),
            Event::create_data_struct(string::utf8(b"shared_storage"), string::utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(string::utf8(b"asset"), string::utf8(b"string"), bcs::to_bytes(&asset)),
            Event::create_data_struct(string::utf8(b"size"), string::utf8(b"u64"), bcs::to_bytes(&size)),
            Event::create_data_struct(string::utf8(b"leverage"), string::utf8(b"u64"), bcs::to_bytes(&leverage)),
            Event::create_data_struct(string::utf8(b"is_long"), string::utf8(b"bool"), bcs::to_bytes(&is_long)),
            Event::create_data_struct(string::utf8(b"reserve_chain"), string::utf8(b"string"), bcs::to_bytes(&reserve_chain)),
            Event::create_data_struct(string::utf8(b"reserve_provider"), string::utf8(b"string"), bcs::to_bytes(&reserve_provider)),
            Event::create_data_struct(string::utf8(b"reserve_token"), string::utf8(b"string"), bcs::to_bytes(&reserve_token)),
            Event::create_data_struct(string::utf8(b"price_update_data"), string::utf8(b"vector<vector<u8>>"), bcs::to_bytes(&price_update_data)),
        ];

        Event::emit_event(clock, string::utf8(b"Modular Oracle Updated and Trade"), data);
    }

    public entry fun p_change_reserve(shared: String, asset: String, new_reserve_chain: String, new_reserve_provider: String, new_reserve_token: String, clock: &Clock, ctx: &mut TxContext) {
        safety_check(shared, asset);

        let sender = tx_context::sender(ctx);
        let data = vector[
            Event::create_data_struct(string::utf8(b"sender"), string::utf8(b"address"), bcs::to_bytes(&sender)),
            Event::create_data_struct(string::utf8(b"shared_storage"), string::utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(string::utf8(b"asset"), string::utf8(b"string"), bcs::to_bytes(&asset)),
            Event::create_data_struct(string::utf8(b"new_reserve_chain"), string::utf8(b"string"), bcs::to_bytes(&new_reserve_chain)),
            Event::create_data_struct(string::utf8(b"new_reserve_provider"), string::utf8(b"string"), bcs::to_bytes(&new_reserve_provider)),
            Event::create_data_struct(string::utf8(b"new_reserve_token"), string::utf8(b"string"), bcs::to_bytes(&new_reserve_token)),
        ];

        Event::emit_event(clock, string::utf8(b"Modular Reserve Change"), data);
    }

    public entry fun p_update_oracle_with_reward(shared: String, asset: String, price_update_data: vector<vector<u8>>, clock: &Clock, ctx: &mut TxContext) {
        safety_check(shared, asset);

        let sender = tx_context::sender(ctx);
        let data = vector[
            Event::create_data_struct(string::utf8(b"sender"), string::utf8(b"address"), bcs::to_bytes(&sender)),
            Event::create_data_struct(string::utf8(b"shared_storage"), string::utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(string::utf8(b"asset"), string::utf8(b"string"), bcs::to_bytes(&asset)),
            Event::create_data_struct(string::utf8(b"price_update_data"), string::utf8(b"vector<vector<u8>>"), bcs::to_bytes(&price_update_data)),
        ];

        Event::emit_event(clock, string::utf8(b"Modular Oracle Updated with Reward"), data);
    }

    public entry fun p_batch_update_oracle_with_reward(shared: String, asset: vector<String>, price_update_data: vector<vector<vector<u8>>>, clock: &Clock, ctx: &mut TxContext) {
        if (shared == string::utf8(b"")) {
            abort ERROR_SHARED_NAME_CANT_BE_EMPTY
        };
        let len = vector::length(&asset);
        let mut i = 0;
        while (i < len) {
            let item = vector::borrow(&asset, i);
            if (*item == string::utf8(b"")) {
                abort ERROR_ASSET_CANT_BE_EMPTY
            };
            i = i + 1;
        };

        let sender = tx_context::sender(ctx);
        let data = vector[
            Event::create_data_struct(string::utf8(b"sender"), string::utf8(b"address"), bcs::to_bytes(&sender)),
            Event::create_data_struct(string::utf8(b"shared_storage"), string::utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(string::utf8(b"asset"), string::utf8(b"vector<string>"), bcs::to_bytes(&asset)),
            Event::create_data_struct(string::utf8(b"price_update_data"), string::utf8(b"vector<vector<vector<u8>>>"), bcs::to_bytes(&price_update_data)),
        ];

        Event::emit_event(clock, string::utf8(b"Modular Batch Oracle Updated with Reward"), data);
    }

    // Helper validation checks
    fun safety_check(shared: String, asset: String) {
        if (shared == string::utf8(b"")) {
            abort ERROR_SHARED_NAME_CANT_BE_EMPTY
        };
        if (asset == string::utf8(b"")) {
            abort ERROR_ASSET_CANT_BE_EMPTY
        };
    }
}