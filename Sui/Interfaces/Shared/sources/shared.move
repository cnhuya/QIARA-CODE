module 0x0::QiaraBluefinInterfaceV1 {
    use sui::tx_context::{Self, TxContext};
    use std::string::{Self, String};
    use sui::bcs;
    use sui::clock::{Self, Clock};
    
    use Qiara::QiaraEventsV1::{Self as Event};

// --- Errors ---

    const ERROR_SHARED_NAME_CANT_BE_EMPTY: u64 = 0;
    const ERROR_REF_CODE_CANT_BE_EMPTY: u64 = 1;
    const ERROR_SUB_OWNER_CANT_BE_EMPTY: u64 = 2;
// --- Initialization ---


    fun init(_ctx: &mut TxContext) {
    }

// --- Permissionless Asset Listing ---
    public entry fun m_create_shared_storage(name: String,ref_code: String, used_ref_code: String, selected_validator: String, xp_tax: u64, fee_tax: u64, clock: &sui::clock::Clock, ctx: &mut TxContext) {
        if (name == string::utf8(b"")) {
            abort ERROR_SHARED_NAME_CANT_BE_EMPTY
        };
        if (ref_code == string::utf8(b"")) {
            abort ERROR_REF_CODE_CANT_BE_EMPTY
        };
        if (ref_code == string::utf8(b"")) {
            abort ERROR_REF_CODE_CANT_BE_EMPTY
        };
        
        let sender = tx_context::sender(ctx);
        let data = vector[
            Event::create_data_struct(string::utf8(b"sender"), string::utf8(b"address"), bcs::to_bytes(&sender)),
            Event::create_data_struct(string::utf8(b"name"), string::utf8(b"string"), bcs::to_bytes(&name)),
            Event::create_data_struct(string::utf8(b"ref_code"), string::utf8(b"string"), bcs::to_bytes(&ref_code)),
            Event::create_data_struct(string::utf8(b"used_ref_code"), string::utf8(b"string"), bcs::to_bytes(&used_ref_code)),
            Event::create_data_struct(string::utf8(b"selected_validator"), string::utf8(b"string"), bcs::to_bytes(&selected_validator)),
            Event::create_data_struct(string::utf8(b"xp_tax"), string::utf8(b"u64"), bcs::to_bytes(&xp_tax)),
            Event::create_data_struct(string::utf8(b"fee_tax"), string::utf8(b"u64"), bcs::to_bytes(&fee_tax)),
        ];

        Event::emit_event(clock, string::utf8(b"Modular Storage Creation"), data);
    }

    public entry fun p_allow_sub_owner(name: String, sub_owner: vector<u8>, clock: &sui::clock::Clock, ctx: &mut TxContext) {
        safety_check(name, sub_owner, ctx);
        let sender = tx_context::sender(ctx);
        let data = vector[
            Event::create_data_struct(string::utf8(b"sender"), string::utf8(b"address"), bcs::to_bytes(&sender)),
            Event::create_data_struct(string::utf8(b"sub_owner"), string::utf8(b"vector<u8>"), bcs::to_bytes(&sub_owner)),
            Event::create_data_struct(string::utf8(b"name"), string::utf8(b"string"), bcs::to_bytes(&name)),
        ];

        Event::emit_event(clock, string::utf8(b"Modular Storage Sub Owner Added"), data);
    }

    public entry fun p_remove_sub_owner(name: String, sub_owner: vector<u8>, clock: &sui::clock::Clock, ctx: &mut TxContext) {
        safety_check(name, sub_owner, ctx);
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
        safety_check(name, sub_owner, ctx);
        let sender = tx_context::sender(ctx);
        let data = vector[
            Event::create_data_struct(string::utf8(b"sender"), string::utf8(b"address"), bcs::to_bytes(&sender)),
            Event::create_data_struct(string::utf8(b"sub_owner"), string::utf8(b"vector<u8>"), bcs::to_bytes(&sub_owner)),
            Event::create_data_struct(string::utf8(b"name"), string::utf8(b"string"), bcs::to_bytes(&name)),
            Event::create_data_struct(string::utf8(b"new_used_ref_code"), string::utf8(b"string"), bcs::to_bytes(&new_used_ref_code)),
        ];

        Event::emit_event(clock, string::utf8(b"Modular Storage Used Ref Code Updated"), data);
    }

    fun safety_check(name: String, sub_owner: vector<u8>, _ctx: &mut TxContext) {
        if (name == string::utf8(b"")) {
            abort ERROR_SHARED_NAME_CANT_BE_EMPTY
        };
        if (sub_owner == vector::empty<u8>()) {
            abort ERROR_SUB_OWNER_CANT_BE_EMPTY
        };
    }
}