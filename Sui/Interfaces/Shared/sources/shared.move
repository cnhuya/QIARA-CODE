module 0x0::QiaraBluefinInterfaceV1 {
    use sui::tx_context::{Self, TxContext};
    use std::string::{Self, String};
    use sui::bcs;
    use sui::clock::{Self, Clock};
    
    use Qiara::QiaraEventsV1::{Self as Event};

// --- Errors ---

// --- Initialization ---

    fun init(_ctx: &mut TxContext) {
    }

// --- Permissionless Asset Listing ---
  
    public entry fun m_create_shared_storage(name: String, clock: &sui::clock::Clock, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        let data = vector[
            Event::create_data_struct(string::utf8(b"sender"), string::utf8(b"address"), bcs::to_bytes(&sender)),
            Event::create_data_struct(string::utf8(b"name"), string::utf8(b"string"), bcs::to_bytes(&name)),
        ];

        Event::emit_event(clock, string::utf8(b"Modular Storage Creation"), data);
    }

    public entry fun p_allow_sub_owner(name: String, sub_owner: vector<u8>, clock: &sui::clock::Clock, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        let data = vector[
            Event::create_data_struct(string::utf8(b"sender"), string::utf8(b"address"), bcs::to_bytes(&sender)),
            Event::create_data_struct(string::utf8(b"sub_owner"), string::utf8(b"vector<u8>"), bcs::to_bytes(&sub_owner)),
            Event::create_data_struct(string::utf8(b"name"), string::utf8(b"string"), bcs::to_bytes(&name)),
        ];

        Event::emit_event(clock, string::utf8(b"Modular Storage Sub Owner Added"), data);
    }

    public entry fun p_remove_sub_owner(name: String, sub_owner: vector<u8>, clock: &sui::clock::Clock, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        let data = vector[
            Event::create_data_struct(string::utf8(b"sender"), string::utf8(b"address"), bcs::to_bytes(&sender)),
            Event::create_data_struct(string::utf8(b"sub_owner"), string::utf8(b"vector<u8>"), bcs::to_bytes(&sub_owner)),
            Event::create_data_struct(string::utf8(b"name"), string::utf8(b"string"), bcs::to_bytes(&name)),
        ];

        Event::emit_event(clock, string::utf8(b"Modular Storage Sub Owner Removed"), data);
    }

    // Updates the designated referral code for a specific shared storage
    public entry fun p_change_used_ref_code(name: String, sub_owner: vector<u8>, new_used_ref_code: String, clock: &sui::clock::Clock, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        let data = vector[
            Event::create_data_struct(string::utf8(b"sender"), string::utf8(b"address"), bcs::to_bytes(&sender)),
            Event::create_data_struct(string::utf8(b"sub_owner"), string::utf8(b"vector<u8>"), bcs::to_bytes(&sub_owner)),
            Event::create_data_struct(string::utf8(b"name"), string::utf8(b"string"), bcs::to_bytes(&name)),
            Event::create_data_struct(string::utf8(b"new_used_ref_code"), string::utf8(b"string"), bcs::to_bytes(&new_used_ref_code)),
        ];

        Event::emit_event(clock, string::utf8(b"Modular Storage Used Ref Code Updated"), data);
    }
}