module event::QiaraEventV1 {
    use std::vector;
    use std::signer;
    use std::bcs;
    use std::string::{Self as String, String, utf8};
    use std::timestamp;
    use std::hash;
    use aptos_framework::event;
    use aptos_std::aptos_hash;

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 0;
    const ERROR_TOKEN_PRICE_COULDNT_BE_FOUND: u64 = 1;
    const ERROR_INVALID_CONSENSUS_TYPE: u64 = 2;
    
// === ACCESS === //
    struct Access has store, key, drop {}
    struct Permission has copy, key, drop {}

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @event, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_permission(access: &Access): Permission {
        Permission {}
    }

// === STRUCTS === //
    struct Data has key, copy, drop, store{
        name: String,
        type: String,
        value: vector<u8>,
    }

// === EVENTS === //
    #[event]
    struct MarketEvent has copy, drop, store {
        name: String,
        aux: vector<Data>,
    }
    #[event]
    struct PerpsEvent has copy, drop, store {
        name: String,
        aux: vector<Data>,
    }
    #[event]
    struct GovernanceEvent has copy, drop, store {
        name: String,
        aux: vector<Data>,
    }
    #[event]
    struct PointsEvent has copy, drop, store {
        name: String,
        aux: vector<Data>,
    }
    #[event]
    struct StakingEvent has copy, drop, store {
        name: String,
        aux: vector<Data>,
    }
    #[event]
    struct BridgeEvent has copy, drop, store {
        name: String,
        aux: vector<Data>,
    }
    #[event]
    struct ConsensusEvent has copy, drop, store {
        name: String,
        aux: vector<Data>,
    }
    #[event]
    struct TypesEvent has copy, drop, store {
        name: String,
        aux: vector<Data>,
    }
    #[event]
    struct CrosschainEvent has copy, drop, store {
        name: String,
        aux: vector<Data>,
    }
    #[event]
    struct ValidationEvent has copy, drop, store {
        name: String,
        aux: vector<Data>,
    }
    #[event]
    struct ConsensusVoteEvent has copy, drop, store {
        aux: vector<Data>,
    }
    #[event]
    struct QiaraBurnEvent has copy, drop, store {
        aux: vector<Data>,
    }
    #[event]
    struct QiaraRefCodeStats has copy, drop, store {
        aux: vector<Data>,
    }
    #[event]
    struct QiaraSharedStats has copy, drop, store {
        aux: vector<Data>,
    }
    #[event]
    struct QiaraSupplyEvent has copy, drop, store {
        aux: vector<Data>,
    }
    #[event]
    struct ProofEvent has copy, drop, store {
        aux: vector<Data>,
    }
    #[event]
    struct SharedStorageEvent has copy, drop, store {
        name: String,
        aux: vector<Data>,
    }
    #[event]
    struct HistoricalEvent has copy, drop, store {
        name: String,
        aux: vector<Data>,
    }
    #[event]
    struct AutomatedEvent has copy, drop, store {
        name: String,
        aux: vector<Data>,
    }
    #[event]
    struct OracleEvent has copy, drop, store {
        name: String,
        aux: vector<Data>,
    }
    #[event]
    struct ValidatorsEvent has copy, drop, store {
        name: String,
        aux: vector<Data>,
    }
    #[event]
    struct OmniProofEvent has copy, drop, store {
        aux: vector<Data>,
    }
// === INIT === //
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @event, 1);
    }
public fun safe_create_identifier(type_names: vector<String>, payload: vector<vector<u8>>): vector<u8> {
    let raw = vector::empty<u8>();
    let len = vector::length(&payload);
    let i = 0;

    while (i < len) {
        let name = vector::borrow(&type_names, i);
        // Skip the signature field when computing the message identifier!
        if (name != &utf8(b"signature")) {
            // Append the raw BCS bytes of the field value
            vector::append(&mut raw, *vector::borrow(&payload, i));
        };
        i = i + 1;
    };

    // Exactly 32-byte domain separator (0x00...0012) to match Go: DomainSeparator
    vector::append(&mut raw, x"0000000000000000000000000000000000000000000000000000000000000012");

    // Use KECCAK256 so the identifier is identical on Aptos, Go, Solana, and EVM!
    aptos_hash::keccak256(raw)
}

// Pubic
    public fun create_data_struct(name: String, type: String, value: vector<u8>): Data {
        Data {name: name,type: type,value: value}
    }

    public fun emit_market_event(type: String, data: vector<Data>) { 
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});
       // let identifier = create_identifier(data);
       // vector::push_back(&mut data, create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier));
        event::emit(MarketEvent {
            name: type,
            aux: data,
        });

    }
    public fun emit_points_event(type: String, data: vector<Data>) {
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});
       // let identifier = create_identifier(data);
       // vector::push_back(&mut data, create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier));
         event::emit(PointsEvent {
            name: type,
            aux: data,
        });
    }
    public fun emit_governance_event(type: String, data: vector<Data>) {
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});  
       // let identifier = create_identifier(data);
       // vector::push_back(&mut data, create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier)); 
         event::emit(GovernanceEvent {
            name: type,
            aux: data,
        });
    }
    public fun emit_perps_event(type: String, data: vector<Data>) {
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});   
       // let identifier = create_identifier(data);
        //vector::push_back(&mut data, create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier));
         event::emit(PerpsEvent {
            name: type,
            aux: data,
        });
    }
    public fun emit_staking_event(type: String, data: vector<Data>) {
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});   
      //  let identifier = create_identifier(data);
       // vector::push_back(&mut data, create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier));
         event::emit(StakingEvent {
            name: type,
            aux: data,
        });
    }
    public fun emit_bridge_event(type: String, data: vector<Data>) {
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});   
       // let identifier = create_identifier(data);
       // vector::push_back(&mut data, create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier));
         event::emit(BridgeEvent {
            name: type,
            aux: data,
        });
    }
    public fun emit_consensus_event(type: String, data: vector<Data>) {
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});   
      //  let identifier = create_identifier(data);
        //vector::push_back(&mut data, create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier));
         event::emit(ConsensusEvent {
            name: type,
            aux: data,
        });
    }
    public fun emit_crosschain_event(type: String, data: vector<Data>) {
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});
       // let identifier = create_identifier(data);
       // vector::push_back(&mut data, create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier));
         event::emit(CrosschainEvent {
            name: type,
            aux: data,
        });
    }
    public fun emit_types_event(type: String, data: vector<Data>) {
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});
       // let identifier = create_identifier(data);
       // vector::push_back(&mut data, create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier));
         event::emit(TypesEvent {
            name: type,
            aux: data,
        });
    }
    public fun emit_validation_event(type: String, data: vector<Data>) {
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});   
         event::emit(ValidationEvent {
            name: type,
            aux: data,
        });
    }
    public fun emit_consensus_vote_event(data: vector<Data>) {
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});   
         event::emit(ConsensusVoteEvent {
            aux: data,
        });
    }
    public fun emit_qiara_event(type: String, data: vector<Data>) {
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});   
         event::emit(ValidationEvent {
            name: type,
            aux: data,
        });
    }

    public fun emit_qiara_burn_event(data: vector<Data>) {
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});   
         event::emit(QiaraBurnEvent {
            aux: data,
        });
    }
    public fun emit_qiara_ref_code_stats(data: vector<Data>) {
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});   
         event::emit(QiaraRefCodeStats {
            aux: data,
        });
    }
    public fun emit_qiara_shared_stats(data: vector<Data>) {
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});   
         event::emit(QiaraSharedStats {
            aux: data,
        });
    }
    public fun emit_qiara_supply_event(data: vector<Data>) {
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});   
         event::emit(QiaraSupplyEvent {
            aux: data,
        });
    }
    public fun emit_consensus_register_event(data: vector<Data>) {
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});   
         event::emit(ConsensusVoteEvent {
            aux: data,
        });
    }
    public fun emit_proof_event(data: vector<Data>) {
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});   
         event::emit(ProofEvent {
            aux: data,
        });
    }
    public fun emit_omnichain_proof_event(data: vector<Data>) {
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});   
         event::emit(OmniProofEvent {
            aux: data,
        });
    }
    public fun emit_shared_storage_event(type: String, data: vector<Data>) {
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});   
         event::emit(SharedStorageEvent {
            name: type,
            aux: data,
        });
    }
    public fun emit_historical_event(type: String, data: vector<Data>) {
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});   
         event::emit(HistoricalEvent {
            name: type,
            aux: data,
        });
    }
    public fun emit_automated_event(type: String, data: vector<Data>) {
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});   
         event::emit(AutomatedEvent {
            name: type,
            aux: data,
        });
    }
    public fun emit_oracle_event(type: String, data: vector<Data>) {
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});   
         event::emit(OracleEvent {
            name: type,
            aux: data,
        });
    }
    public fun emit_validators_event(type: String, data: vector<Data>) {
        vector::push_back(&mut data, Data {name: utf8(b"timestamp"), type: utf8(b"u64"), value: bcs::to_bytes(&timestamp::now_seconds())});   
         event::emit(ValidatorsEvent {
            name: type,
            aux: data,
        });
    }


}
