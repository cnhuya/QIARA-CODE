module 0x0::QiaraGovernanceInterfaceV1 {
    use sui::tx_context::{Self, TxContext};
    use std::string::{Self, String};
    use sui::bcs;
    use sui::clock::{Self, Clock}; // Added Clock
    
    use Qiara::QiaraEventsV1::{Self as Event};

// --- Errors ---

// --- Initialization ---

    fun init(ctx: &mut TxContext) {
    }

// --- Permissionless Asset Listing ---
  
   // --- Assumptions for this translation ---
    // 1. TokensShared and Event modules are ported to Sui.
    // 2. PendingProposals and ProposalCount are Sui Objects (they must have the `key` ability and an `id: UID` field).
    // 3. propose_internal and vote_internal have been updated to accept object references.

    public entry fun m_propose(
        sub_owner: vector<u8>,
        shared_storage_name: String,
        name: String,
        desc: String,
        type_: vector<String>, // Renamed from 'type' to avoid reserved keyword conflicts in modern Move
        isChange: vector<bool>,
        header: vector<String>,
        constant_name: vector<String>,
        new_value: vector<vector<u8>>,
        value_type: vector<String>,
        duration: u64,
        editable: vector<bool>,
        clock: &sui::clock::Clock,
        ctx: &mut TxContext
    ) {
        // In Sui, the sender address is retrieved from the TxContext
        let sender = tx_context::sender(ctx);

        // Emit custom event (Direct translation of your event struct)
        let data = vector[
            Event::create_data_struct(string::utf8(b"sender"), string::utf8(b"address"), bcs::to_bytes(&sender)),
            Event::create_data_struct(string::utf8(b"sub_owner"), string::utf8(b"vector<u8>"), bcs::to_bytes(&sub_owner)),
            Event::create_data_struct(string::utf8(b"shared"), string::utf8(b"string"), bcs::to_bytes(&shared_storage_name)),
            Event::create_data_struct(string::utf8(b"name"), string::utf8(b"string"), bcs::to_bytes(&name)),
            Event::create_data_struct(string::utf8(b"desc"), string::utf8(b"string"), bcs::to_bytes(&desc)),
            Event::create_data_struct(string::utf8(b"type"), string::utf8(b"vector<string>"), bcs::to_bytes(&type_)),
            Event::create_data_struct(string::utf8(b"isChange"), string::utf8(b"vector<bool>"), bcs::to_bytes(&isChange)),
            Event::create_data_struct(string::utf8(b"header"), string::utf8(b"vector<string>"), bcs::to_bytes(&header)),
            Event::create_data_struct(string::utf8(b"constant_name"), string::utf8(b"vector<string>"), bcs::to_bytes(&constant_name)),
            Event::create_data_struct(string::utf8(b"new_value"), string::utf8(b"vector<vector<u8>>"), bcs::to_bytes(&new_value)),
            Event::create_data_struct(string::utf8(b"value_type"), string::utf8(b"vector<string>"), bcs::to_bytes(&value_type)),
            Event::create_data_struct(string::utf8(b"duration"), string::utf8(b"u64"), bcs::to_bytes(&duration)),
            Event::create_data_struct(string::utf8(b"editable"), string::utf8(b"vector<bool>"), bcs::to_bytes(&editable)),
        ];
        Event::emit_event(clock, string::utf8(b"Modular Governance Proposal"), data);
    }

    public entry fun m_vote(sub_owner: vector<u8>, shared_storage_name: String, proposal_id: u64, isYes: bool,clock: &sui::clock::Clock,ctx: &mut TxContext) {

        let sender = tx_context::sender(ctx);

        // Emit custom event (Direct translation of your event struct)
        let data = vector[
            Event::create_data_struct(string::utf8(b"sender"), string::utf8(b"address"), bcs::to_bytes(&sender)),
            Event::create_data_struct(string::utf8(b"sub_owner"), string::utf8(b"vector<u8>"), bcs::to_bytes(&sub_owner)),
            Event::create_data_struct(string::utf8(b"shared"), string::utf8(b"string"), bcs::to_bytes(&shared_storage_name)),
            Event::create_data_struct(string::utf8(b"proposal_id"), string::utf8(b"u64"), bcs::to_bytes(&proposal_id)),
            Event::create_data_struct(string::utf8(b"isYes"), string::utf8(b"bool"), bcs::to_bytes(&isYes)),
        ];
        Event::emit_event(clock, string::utf8(b"Modular Governance Vote"), data);
    }
}