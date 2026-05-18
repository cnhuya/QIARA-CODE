module 0x0::QiaraBluefinInterfaceV1 {
    use sui::tx_context::{Self, TxContext};
    use std::string::{Self, String};
    use sui::bcs;
    
    use Qiara::QiaraEventsV1::{Self as Event};

// --- Errors ---

// --- Initialization ---

    fun init(ctx: &mut TxContext) {
    }

// --- Permissionless Asset Listing ---
  
    public entry fun m_create_shared_storage(name: String, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        let data = vector[
            Event::create_data_struct(string::utf8(b"user"), string::utf8(b"address"), bcs::to_bytes(&sender)),
            Event::create_data_struct(string::utf8(b"name"), string::utf8(b"string"), bcs::to_bytes(&name)),
        ];

        Event::emit_withdraw_event(string::utf8(b"Modular Storage Creation"), data);
    }

    public entry fun p_allow_sub_owner(name: String, sub_owner: vector<u8>, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        let data = vector[
            Event::create_data_struct(string::utf8(b"user"), string::utf8(b"address"), bcs::to_bytes(&sender)),
            Event::create_data_struct(string::utf8(b"sub_owner"), string::utf8(b"vector<u8>"), bcs::to_bytes(&sub_owner)),
            Event::create_data_struct(string::utf8(b"name"), string::utf8(b"string"), bcs::to_bytes(&name)),
        ];

        Event::emit_withdraw_event(string::utf8(b"Modular Storage Sub Owner Added"), data);
    }

    public entry fun p_remove_sub_owner(name: String, sub_owner: vector<u8>, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        let data = vector[
            Event::create_data_struct(string::utf8(b"user"), string::utf8(b"address"), bcs::to_bytes(&sender)),
            Event::create_data_struct(string::utf8(b"sub_owner"), string::utf8(b"vector<u8>"), bcs::to_bytes(&sub_owner)),
            Event::create_data_struct(string::utf8(b"name"), string::utf8(b"string"), bcs::to_bytes(&name)),
        ];

        Event::emit_withdraw_event(string::utf8(b"Modular Storage Sub Owner Removed"), data);
    }

}