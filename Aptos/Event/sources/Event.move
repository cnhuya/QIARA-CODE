module event::QiaraEventV1 {
    use std::vector;
    use std::signer;
    use std::bcs;
    use std::string::{Self as String, String, utf8};
    use std::timestamp;
    use std::hash;
    use aptos_framework::event;


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

// === INIT === //
    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == @event, 1);
    }

  public fun create_identifier(addr: vector<u8>, type: String, nonce: vector<u8>): vector<u8> {
        let vect = vector::empty<u8>();
    
        // 1. Convert vectors to u256 first so your BE function can process them
        // OR: If they are already 32 bytes, just append them directly!
        let addr_u256 = bytes_to_u256(addr);
        let nonce_u256 = bytes_to_u256(nonce);
        
        // 2. Convert to 32-byte Big Endian vectors
        let user_bytes = u256_to_bytes_be(addr_u256);
        let nonce_bytes = u256_to_bytes_be(nonce_u256);
        
        // 3. Concatenate (matches abi.encodePacked)
        vector::append(&mut vect, user_bytes);
        vector::append(&mut vect, bcs::to_bytes(&type));
        vector::append(&mut vect, nonce_bytes);
        vector::append(&mut vect, x"00000000000000000000000000000000000000000000000000000001");
        
        // 4. SHA2-256 hash
        hash::sha2_256(vect)
    }

    // Helper to turn your input vector into the u256 your function expects
    public fun bytes_to_u256(bytes: vector<u8>): u256 {
        let val = 0u256;
        let i = 0;
        let len = vector::length(&bytes);
        while (i < len) {
            val = (val << 8) | (*vector::borrow(&bytes, i) as u256);
            i = i + 1;
        };
        val
    }

    public fun u256_to_bytes_be(val: u256): vector<u8> {
        let res = vector::empty<u8>();
        let i = 0;
        while (i < 32) {
            let shift_bits = (31 - i) * 8;
            // FIX: Added parentheses to ensure bit-shift happens before casting
            let byte = ((val >> (shift_bits as u8)) & 0xFF);
            vector::push_back(&mut res, (byte as u8));
            i = i + 1;
        };
        res
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


}
