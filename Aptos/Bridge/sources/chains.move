module dev::QiaraBridgeV1{
    use std::signer;
    use aptos_framework::account::{Self as address};
    use std::string::{Self as string, String, utf8};
    use std::vector;
    use std::type_info;
    use std::table:: {Self as table, Table};
    use std::timestamp;
    use std::bcs;
    use std::hash;
    use std::debug::print;
    use aptos_std::from_bcs;
    use aptos_std::bcs_stream::{Self};
    use aptos_std::ed25519::{Self as Crypto, Signature, UnvalidatedPublicKey};
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};
    use aptos_framework::fungible_asset::{Self, Metadata, FungibleAsset};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;
    use event::QiaraEventV1::{Self as Event};
    use dev::QiaraStorageV1::{Self as storage};

    use dev::QiaraTokensCoreV2::{Self as TokensCore, Access as TokensCoreAccess};
    use dev::QiaraTokensOmnichainV2::{Self as TokensOmnichain, Access as TokensOmnichainAccess};
    use dev::QiaraTokensValidatorsV2::{Self as TokensValidators};
    
    use dev::QiaraVaultsV1::{Self as Market, Access as MarketAccess};

    use dev::QiaraMarginV1::{Self as Margin};

    use dev::QiaraPayloadV1::{Self as Payload};
    use dev::QiaraValidatorsV1::{Self as Validators, Access as ValidatorsAccess};
    /// Admin address constant
    const STORAGE: address = @dev;

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_INVALID_CHAIN_ID: u64 = 2;
    const ERROR_VALIDATOR_IS_ALREADY_ALLOWED: u64 = 3;
    const ERROR_INVALID_CHAIN_TYPE_ARGUMENT: u64 = 4;
    const ERROR_CHAIN_ALREADY_REGISTERED: u64 = 5;
    const ERROR_NOT_VALIDATOR: u64 = 6;
    const ERROR_DUPLICATE_EVENT: u64 = 7;
    const ERROR_INVALID_BATCH_REGISTER_EVENT_ARG_EQUALS: u64 = 8;
    const ERROR_INVALID_SIGNATURE: u64 = 9;
    const ERROR_INVALID_MESSAGE: u64 = 10;
    const ERROR_NOT_FOUND: u64 = 11;
    const ERROR_CAPS_NOT_PUBLISHED: u64 = 11;
    const ERROR_NOT_ENOUGH_VOTING_POWER: u64 = 12;
    const ERROR_INVALID_VOTING_POWER: u64 = 13;
    const ERROR_INVALID_TYPE: u64 = 14;
    const ERROR_NULLIFIER_USED: u64 = 15;
    const ERROR_PROOF_NOT_FOUND: u64 = 16;


// === ACCESS === //
    struct Access has store, key, drop {}
    struct Permission has store, key, drop, copy {}

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @dev, ERROR_NOT_ADMIN);
        //capabilities::assert_wallet_capability(utf8(b"QiaraVault"), utf8(b"PERMISSION_TO_INITIALIZE_VAULTS"));
        Access {}
    }

    public fun give_permission(access: &Access): Permission {
        Permission {}
    }

    // Permissions 
    struct Permissions has key, store, drop {
        market: MarketAccess,
        tokens_core: TokensCoreAccess,
        tokens_omnichain: TokensOmnichainAccess,
        validators: ValidatorsAccess,
    }

// === STRUCTS === //
   // [DEPRECATED]
   // struct DepositEvent has store, key {}
   // struct RequestUnlockEvent has store, key {}
   // struct UnlockEvent has store, key {}

    /// In the future implement a more complext structure for storage,
    /// Making it generic for epoch (1 day for example) and adding epoch key to events, to make it
    /// so that event from epoch (ex. 14797) cant be stored/registered/validated in epoch (ex. 14798)
    /// This way we can avoid double spending attacks on other chains and also reduce storage space 
    /// which would mean more efficiency and lower gas fees by around 30-40%.

   /// counting how many times the message was "validated"
   /// If lets say it was "validated" total of 5 times succesfully, the 6th times will mote if from here
   /// to chain storage
   /// 
   /// <message> <vector<Aux>>
   /// <message> <validators, weight>
   /// <message> <validator adress, validator weight, <weight>>
   
// === Pending Struct Methology === //
    struct Pending has key {
        main: Table<vector<u8>, MainVotes>,
        zk: Table<vector<u8>, ZkVotes>,
        proof: Table<vector<u8>, ProofVotes>,
    }

    struct Validated has key {
        main: Table<vector<u8>, MainVotes>,
        zk: Table<vector<u8>, ZkVotes>,
        proof: Table<vector<u8>, ProofVotes>,
    }

    struct Vote has key, copy, store, drop {
        weight: u128,
        signature: vector<u8>,
    }


    struct ZkVote has key, copy, store, drop {
        weight: u128,
        s_r8x: String,
        s_r8y: String,
        s: String,
        pub_key_x: String,
        pub_key_y: String,
    }
    struct ProofVotes has key, copy, store, drop {
        votes: Map<String, u128>,
        rv: vector<String>, // rewarded validators
        proof: vector<u256>,
        inputs: vector<u256>,
        total_weight: u128,
        time: u64,   
    }
    struct MainVotes has key, copy, store, drop {
        votes: Map<String, Vote>,
        rv: vector<String>, // rewarded validators
        data_types: vector<String>,
        data: vector<vector<u8>>,
        total_weight: u128,
        time: u64,   
    }
    struct ZkVotes has key, copy, store, drop {
        votes: Map<String, ZkVote>,
        rv: vector<String>, // rewarded validators
        data_types: vector<String>,
        data: vector<vector<u8>>,
        total_weight: u128,
        time: u64,   
    }


// === INIT === //
    fun init_module(admin: &signer) {
        if (!exists<Permissions>(@dev)) {
            move_to(admin, Permissions {market: Market::give_access(admin), tokens_core: TokensCore::give_access(admin), tokens_omnichain: TokensOmnichain::give_access(admin), validators: Validators::give_access(admin)});
        };
        if (!exists<Pending>(@dev)) {
            move_to(admin, Pending {main: table::new<vector<u8>, MainVotes>(), zk: table::new<vector<u8>, ZkVotes>(), proof: table::new<vector<u8>, ProofVotes>()});
        };
        if (!exists<Validated>(@dev)) {
            move_to(admin, Validated {main: table::new<vector<u8>, MainVotes>(), zk: table::new<vector<u8>, ZkVotes>(), proof: table::new<vector<u8>, ProofVotes>()});
        };
    }

    fun tttta(error: u64){
        abort error
    }

    fun unpack_payload(payload: vector<vector<u8>>): vector<u8> {
        let len = vector::length(&payload);
        let xv = vector::empty<u8>();
        while(len>0){
            let _v = vector::borrow(&payload, len-1);
            len=len-1;
            vector::append(&mut xv, *_v);
        };
        return xv
    }

// === FUNCTIONS === //


    public entry fun register_proof_event(signer: &signer, validator: String, identifier: vector<u8>, proof: vector<u256>, inputs: vector<u256>) acquires Pending, Validated {
        let pending = borrow_global_mut<Pending>(STORAGE);
        let validated = borrow_global_mut<Validated>(STORAGE);
        Validators::take_snapshot(signer, validator);
        assert!(table::contains(&validated.zk, identifier), ERROR_PROOF_NOT_FOUND);

            handle_proof_event(
                signer,
                validator,
                &mut pending.proof,
                &mut validated.proof,
                identifier,
                proof,
                inputs,

            );


    }


//0x1a00000000000000000000000000000000000000000000000000000000000000
//0x1a00000000000000000000000000000000000000000000000000000000000000

    public entry fun register_event(signer: &signer, validator: String, type_names: vector<String>, payload: vector<vector<u8>>) acquires Pending, Validated, Permissions {

    Payload::ensure_valid_payload(type_names, payload);

    let identifier = Payload::create_identifier(type_names, payload);
    
    // 1. Strings MUST use bcs_stream
    let (_, type_raw) = Payload::find_payload_value(utf8(b"consensus_type"), type_names, payload);
    let consensus_type = bcs_stream::deserialize_string(&mut bcs_stream::new(type_raw));
    let (_, event_type_raw) = Payload::find_payload_value(utf8(b"event_type"), type_names, payload);
    let event_type = bcs_stream::deserialize_string(&mut bcs_stream::new(event_type_raw));
    let (pub_key_x, pub_key_y, pubkey, _, _) = Validators::return_validator_raw(validator);

    let pending = borrow_global_mut<Pending>(STORAGE);
    let validated = borrow_global_mut<Validated>(STORAGE);
    Validators::take_snapshot(signer, validator);
    
    // 2. Logic based on the Clean String
    if (consensus_type == utf8(b"native")) {
        let (_, message) = Payload::find_payload_value(utf8(b"message"), type_names, payload);
        let (_, _sig_bytes) = Payload::find_payload_value(utf8(b"signature"), type_names, payload);
        
        // NOTE: message and signature are usually raw bytes, NOT BCS strings.
        // We do NOT use bcs_stream for them if they were passed as raw bytes.
        let pubkey_struct = Crypto::new_unvalidated_public_key_from_bytes(pubkey);
        let signature = Crypto::new_signature_from_bytes(_sig_bytes);
        
        let verified = Crypto::signature_verify_strict(&signature, &pubkey_struct, message);
        assert!(verified, ERROR_INVALID_SIGNATURE);

        handle_main_event(
            signer,
            validator,
            &mut pending.main,
            &mut validated.main,
            identifier,
            type_names,
            payload,
            _sig_bytes,
            event_type // Use the string we decoded earlier
        );
    } else if (consensus_type == utf8(b"zk")) {
        handle_zk_event(
            signer,
            validator,
            &mut pending.zk,
            &mut validated.zk,
            identifier,
            type_names,
            payload,
            build_zkVote_from_payload(pub_key_x, pub_key_y, type_names, payload),
            event_type // Use the string we decoded earlier
        );
    } else if (consensus_type == utf8(b"none")) {
        return
    } else {
        abort(ERROR_INVALID_TYPE);
    };
}
    fun build_zkVote_from_payload(pubkwey_x: String, pubkey_y: String, type_names: vector<String>, payload: vector<vector<u8>>): ZkVote {
        let (_, s_r8x) = Payload::find_payload_value(utf8(b"s_r8x"), type_names, payload);
        let (_, s_r8y) = Payload::find_payload_value(utf8(b"s_r8y"), type_names, payload);
        let (_, s) = Payload::find_payload_value(utf8(b"s"), type_names, payload);
        //let (_, index) = Payload::find_payload_value(utf8(b"index"), type_names, payload);
        //tttta(0);
        return ZkVote {
            weight: 0,
            s_r8x: bcs_stream::deserialize_string(&mut bcs_stream::new(s_r8x)), //s_r8x,
            s_r8y: bcs_stream::deserialize_string(&mut bcs_stream::new(s_r8y)), //s_r8y,
            s:  bcs_stream::deserialize_string(&mut bcs_stream::new(s)), //s_r8y,
            pub_key_x: pubkwey_x,
            pub_key_y: pubkey_y,
            //index:  from_bcs::to_u16(s), //s_r8y,
        }
    }

    fun check_validator_validation(validator: String, map: Map<String, Vote>): (bool, u128){
        if(map::contains_key(&map, &validator)){
            let v = map::borrow(&map, &validator);
            return (true, v.weight)
        };
        return (false, 0)
    }


    fun check_validator_validation_zk(validator: String, map: Map<String, ZkVote>): (bool, u128){
        if(map::contains_key(&map, &validator)){
            let v = map::borrow(&map, &validator);
            return (true, v.weight)
        };
        return (false, 0)
    }
    fun check_validator_validation_proof(validator: String, map: Map<String, u128>): (bool, u128){
        if(map::contains_key(&map, &validator)){
            let v = map::borrow(&map, &validator);
            return (true, *v)
        };
        return (false, 0)
    }


    fun handle_proof_event(signer: &signer, validator: String, pending_table: &mut table::Table<vector<u8>, ProofVotes>, validated_table: &mut table::Table<vector<u8>, ProofVotes>, identifier: vector<u8>,proof: vector<u256>, inputs: vector<u256>) {
        // 1. Load configuration constants

        let quorum = (storage::expect_u64(storage::viewConstant(utf8(b"QiaraBridge"), utf8(b"MINIMUM_REQUIRED_VOTED_WEIGHT"))) as u128);
        let min_unique = (storage::expect_u8(storage::viewConstant(utf8(b"QiaraBridge"), utf8(b"MINIMUM_UNIQUE_VALIDATORS"))) as u64);
        let max_rewarded = (storage::expect_u8(storage::viewConstant(utf8(b"QiaraBridge"), utf8(b"MAXIMUM_REWARDED_VALIDATORS"))) as u64);

        // 2. Already validated?
        if (table::contains(validated_table, identifier)) {
            abort(ERROR_DUPLICATE_EVENT);
        };

        // Calculate voting power (Weight)
        let (_, _, _, _, _, _, _, _, vote_weight_u256, _, _) = Margin::get_user_total_usd(validator);
        let vote_weight = (vote_weight_u256 as u128);

        // 3. Update or Create the Pending state
        if (table::contains(pending_table, identifier)) {
            let votes = table::borrow_mut(pending_table, identifier);
            let (did_validate, _) = check_validator_validation_proof(validator, votes.votes);

            if (!did_validate) {
                // Update mapping and total weight
                map::add(&mut votes.votes, validator, vote_weight);
                votes.total_weight = votes.total_weight + vote_weight;
                
                // Manage Reward Pool (Fastest validators get the spots)
                if (vector::length(&votes.rv) < max_rewarded) {
                    if (!vector::contains(&votes.rv, &validator)) {
                        vector::push_back(&mut votes.rv, validator);
                    };
                };

                // Emit Vote Event
                let data = vector[
                    Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&validator)),
                    Event::create_data_struct(utf8(b"event_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"Proofs"))),
                    Event::create_data_struct(utf8(b"vote_weight"), utf8(b"u128"), bcs::to_bytes(&vote_weight)),
                    Event::create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier),
                ];
                Event::emit_consensus_vote_event(data);
            };
        } else {
            // First vote for this message
            let vect = vector[validator];
            let vote_map = map::new<String, u128>();
            map::add(&mut vote_map, validator, vote_weight);
            
            let new_votes = ProofVotes {
                votes: vote_map, 
                rv: vect, 
                proof: proof,
                inputs: inputs,
                total_weight: vote_weight, 
                time: timestamp::now_seconds()
            };
            table::add(pending_table, identifier, new_votes);

            // Emit Register Event
            let data = vector[
                Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&validator)),
                Event::create_data_struct(utf8(b"event_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"Proofs"))),
                Event::create_data_struct(utf8(b"vote_weight"), utf8(b"u128"), bcs::to_bytes(&vote_weight)),
                Event::create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier),
            ];
            Event::emit_consensus_register_event(data);
        };

        // 4. Consensus Check & Promotion
        let ready_to_finalize = {
            let votes_ref = table::borrow(pending_table, identifier);
            let unique_count = (vector::length(&map::keys(&votes_ref.votes)) as u64);
            (votes_ref.total_weight >= quorum && unique_count >= min_unique)
        };

        if (ready_to_finalize) {
            // Atomic Move from Pending to Validated
            let votes_from_pending = table::remove(pending_table, identifier);
            table::add(validated_table, identifier, votes_from_pending);

    
            // Emit Validated Event
            let data = vector[
                Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&validator)),
                Event::create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier),
                Event::create_data_struct(utf8(b"proofs"), utf8(b"vector<u256>"), bcs::to_bytes(&proof)),
                Event::create_data_struct(utf8(b"inputs"), utf8(b"vector<u256>"), bcs::to_bytes(&inputs)),
                Event::create_data_struct(utf8(b"total_weight"), utf8(b"u128"), bcs::to_bytes(&quorum)),
            ];
            Event::emit_proof_event(data);

            // Emit Validated Event
            let data = vector[
                Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&validator)),
                Event::create_data_struct(utf8(b"event_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"Proofs"))),
                Event::create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier),
                Event::create_data_struct(utf8(b"total_weight"), utf8(b"u128"), bcs::to_bytes(&quorum)),
            ];
            Event::emit_validation_event(utf8(b"Validated Event"), data);
        };
    }
    fun handle_main_event(signer: &signer, validator: String, pending_table: &mut table::Table<vector<u8>, MainVotes>, validated_table: &mut table::Table<vector<u8>, MainVotes>, identifier: vector<u8>, type_names: vector<String>, payload: vector<vector<u8>>,signature: vector<u8>,  event_type: String ) acquires Permissions {
        // 1. Load configuration constants
        let quorum = (storage::expect_u64(storage::viewConstant(utf8(b"QiaraBridge"), utf8(b"MINIMUM_REQUIRED_VOTED_WEIGHT"))) as u128);
        let min_unique = (storage::expect_u8(storage::viewConstant(utf8(b"QiaraBridge"), utf8(b"MINIMUM_UNIQUE_VALIDATORS"))) as u64);
        let max_rewarded = (storage::expect_u8(storage::viewConstant(utf8(b"QiaraBridge"), utf8(b"MAXIMUM_REWARDED_VALIDATORS"))) as u64);

        // 2. Already validated?
        if (table::contains(validated_table, identifier)) {
            abort(ERROR_DUPLICATE_EVENT);
        };

        // Calculate voting power (Weight)
        let (_, _, _, _, _, _, _, _, vote_weight_u256, _, _) = Margin::get_user_total_usd(validator);
        let vote_weight = (vote_weight_u256 as u128);

        // 3. Update or Create the Pending state
        if (table::contains(pending_table, identifier)) {
            let votes = table::borrow_mut(pending_table, identifier);
            let (did_validate, _) = check_validator_validation(validator, votes.votes);

            if (!did_validate) {
                // Update mapping and total weight
                let vote = Vote { signature: signature, weight: vote_weight };
                map::add(&mut votes.votes, validator, vote);
                votes.total_weight = votes.total_weight + vote_weight;
                
                // Manage Reward Pool (Fastest validators get the spots)
                if (vector::length(&votes.rv) < max_rewarded) {
                    if (!vector::contains(&votes.rv, &validator)) {
                        vector::push_back(&mut votes.rv, validator);
                    };
                };

                // Emit Vote Event
                let data = vector[
                    Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&validator)),
                    Event::create_data_struct(utf8(b"event_type"), utf8(b"string"), bcs::to_bytes(&event_type)),
                    Event::create_data_struct(utf8(b"vote_weight"), utf8(b"u128"), bcs::to_bytes(&vote_weight)),
                    Event::create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier),
                    Event::create_data_struct(utf8(b"type_names"), utf8(b"vector<String>"), bcs::to_bytes(&type_names)),
                    Event::create_data_struct(utf8(b"payload"), utf8(b"vector<vector<u8>>"), bcs::to_bytes(&payload)),
                ];
                Event::emit_consensus_vote_event(data);
            };
        } else {
            // First vote for this message
            let validator_vote = Vote { signature: signature, weight: vote_weight };
            let vect = vector[validator];
            let vote_map = map::new<String, Vote>();
            map::add(&mut vote_map, validator, validator_vote);
            
            let new_votes = MainVotes {
                votes: vote_map, 
                rv: vect, 
                data_types: type_names,
                data: payload,
                total_weight: vote_weight, 
                time: timestamp::now_seconds()
            };
            table::add(pending_table, identifier, new_votes);

            // Emit Register Event
            let data = vector[
                Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&validator)),
                Event::create_data_struct(utf8(b"event_type"), utf8(b"string"), bcs::to_bytes(&event_type)),
                Event::create_data_struct(utf8(b"vote_weight"), utf8(b"u128"), bcs::to_bytes(&vote_weight)),
                Event::create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier),
                Event::create_data_struct(utf8(b"type_names"), utf8(b"vector<String>"), bcs::to_bytes(&type_names)),
                Event::create_data_struct(utf8(b"payload"), utf8(b"vector<vector<u8>>"), bcs::to_bytes(&payload)),
            ];
            Event::emit_consensus_register_event(data);
        };

        // 4. Consensus Check & Promotion
        let ready_to_finalize = {
            let votes_ref = table::borrow(pending_table, identifier);
            let unique_count = (vector::length(&map::keys(&votes_ref.votes)) as u64);
            (votes_ref.total_weight >= quorum && unique_count >= min_unique)
        };

        if (ready_to_finalize) {
            // Atomic Move from Pending to Validated
            let votes_from_pending = table::remove(pending_table, identifier);
            table::add(validated_table, identifier, votes_from_pending);

            // Fetch permissions for cross-module calls
            assert!(exists<Permissions>(@dev), ERROR_CAPS_NOT_PUBLISHED);
            let cap = borrow_global<Permissions>(@dev);

            // 5. Execute Bridging Logic (Main Event Specific)
            if (event_type == utf8(b"Bridge Deposit")) {
                // Handle Deposit specific logic here
                let (receiver, x, shared, symbol, chain, provider, amount, hash) = Payload::prepare_bridge_deposit(type_names, payload);
                //tttta(0);
                TokensCore::c_bridge_to_supra(signer, shared, receiver, symbol, chain, amount, TokensCore::give_permission(&cap.tokens_core));

                if(provider != utf8(b"none")) {
                    Market::c_bridge_deposit(signer, shared, receiver, symbol, chain, provider, amount, 0, Market::give_permission(&cap.market));
                }

            } else if (event_type == utf8(b"Request Unlock")) {
                // Handle Request Unlock here
            } else if (event_type == utf8(b"Unlock")) {
                // Handle Unlock here
            } else {
                abort(ERROR_INVALID_MESSAGE);
            };

            // Emit Validated Event
            let data = vector[
                Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&validator)),
                Event::create_data_struct(utf8(b"event_type"), utf8(b"string"), bcs::to_bytes(&event_type)),
                Event::create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier),
                Event::create_data_struct(utf8(b"total_weight"), utf8(b"u128"), bcs::to_bytes(&quorum)),
                Event::create_data_struct(utf8(b"type_names"), utf8(b"vector<String>"), bcs::to_bytes(&type_names)),
                Event::create_data_struct(utf8(b"payload"), utf8(b"vector<vector<u8>>"), bcs::to_bytes(&payload)),
            ];
            Event::emit_validation_event(utf8(b"Validated Event"), data);
        };
    }
    fun handle_zk_event(signer: &signer, validator: String, pending_table: &mut table::Table<vector<u8>, ZkVotes>, validated_table: &mut table::Table<vector<u8>, ZkVotes>, identifier: vector<u8>, type_names: vector<String>, payload: vector<vector<u8>>, zk_vote: ZkVote, event_type: String ) acquires Permissions {
        // 1. Load configuration constants
        let quorum = (storage::expect_u64(storage::viewConstant(utf8(b"QiaraBridge"), utf8(b"MINIMUM_REQUIRED_VOTED_WEIGHT"))) as u128);
        let min_unique = (storage::expect_u8(storage::viewConstant(utf8(b"QiaraBridge"), utf8(b"MINIMUM_UNIQUE_VALIDATORS"))) as u64);
        let max_rewarded = (storage::expect_u8(storage::viewConstant(utf8(b"QiaraBridge"), utf8(b"MAXIMUM_REWARDED_VALIDATORS"))) as u64);
        //tttta(100);
        // 2. Already validated?
        if (table::contains(validated_table, identifier)) {
            abort(ERROR_DUPLICATE_EVENT);
        };
        // Calculate voting power (Weight)
        let (_, _, _, _, _, _, _, _, vote_weight_u256, _, _) = Margin::get_user_total_usd(validator);
        let vote_weight = (vote_weight_u256 as u128);
        // 3. Update or Create the Pending state
        if (table::contains(pending_table, identifier)) {
            let votes = table::borrow_mut(pending_table, identifier);
            let (did_validate, _) = check_validator_validation_zk(validator, votes.votes);

            if (!did_validate) {
                // Update mapping and total weight
                zk_vote.weight = vote_weight;
                map::add(&mut votes.votes, validator, zk_vote);
                votes.total_weight = votes.total_weight + vote_weight;
                
                // Manage Reward Pool (Fastest validators get the spots)
                if (vector::length(&votes.rv) < max_rewarded) {
                    if (!vector::contains(&votes.rv, &validator)) {
                        vector::push_back(&mut votes.rv, validator);
                    };
                };
                // Emit Vote Event
                let data = vector[
                    Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&validator)),
                    Event::create_data_struct(utf8(b"event_type"), utf8(b"string"), bcs::to_bytes(&event_type)),
                    Event::create_data_struct(utf8(b"vote_weight"), utf8(b"u128"), bcs::to_bytes(&vote_weight)),
                    Event::create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier),
                    Event::create_data_struct(utf8(b"type_names"), utf8(b"vector<String>"), bcs::to_bytes(&type_names)),
                    Event::create_data_struct(utf8(b"payload"), utf8(b"vector<vector<u8>>"), bcs::to_bytes(&payload)),
                ];
                Event::emit_consensus_vote_event(data);
            };
        } else {
            // First vote for this message
            zk_vote.weight = vote_weight;
            let vect = vector[validator];
            let vote_map = map::new<String, ZkVote>();
            map::add(&mut vote_map, validator, zk_vote);
            
            let new_votes = ZkVotes {
                votes: vote_map, 
                rv: vect, 
                data_types: type_names,
                data: payload,
                total_weight: vote_weight, 
                time: timestamp::now_seconds()
            };
            table::add(pending_table, identifier, new_votes);

            // Emit Register Event
            let data = vector[
                Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&validator)),
                Event::create_data_struct(utf8(b"event_type"), utf8(b"string"), bcs::to_bytes(&event_type)),
                Event::create_data_struct(utf8(b"vote_weight"), utf8(b"u128"), bcs::to_bytes(&vote_weight)),
                Event::create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier),
                Event::create_data_struct(utf8(b"type_names"), utf8(b"vector<String>"), bcs::to_bytes(&type_names)),
                Event::create_data_struct(utf8(b"payload"), utf8(b"vector<vector<u8>>"), bcs::to_bytes(&payload)),
            ];
            Event::emit_consensus_register_event(data);
        };

        // 4. Consensus Check & Promotion
        // We check weight AND unique validator count
        let ready_to_finalize = {
            let votes_ref = table::borrow(pending_table, identifier);
            let unique_count = vector::length(&map::keys(&votes_ref.votes));
            (votes_ref.total_weight >= quorum && unique_count >= min_unique)
        };

        if (ready_to_finalize) {
            // Atomic Move from Pending to Validated
            let votes_from_pending = table::remove(pending_table, identifier);
            table::add(validated_table, identifier, votes_from_pending);

            // Fetch permissions for cross-module calls
            assert!(exists<Permissions>(@dev), ERROR_CAPS_NOT_PUBLISHED);
            
            // 5. Execute Bridging Logic
            if (event_type == utf8(b"Register Validator")) {
                let (validator, shared, pub_key_x, pub_key_y, pub_key) = Payload::prepare_register_validator(type_names, payload);
                Validators::c_register_validator(signer, shared, validator, pub_key_x, pub_key_y, pub_key, Validators::give_permission(&borrow_global<Permissions>(@dev).validators));
            } else if (event_type == utf8(b"Request Bridge")) {
                  //             tttta(100);
                let (receiver, shared, validator_root, old_root, new_root, symbol, chain, provider, amount, total_outflow, nonce) = Payload::prepare_finalize_bridge(type_names, payload);
                //tttta(45454);
                TokensCore::c_finalize_bridge(signer, symbol, chain, amount, TokensCore::give_permission(&borrow_global<Permissions>(@dev).tokens_core));
                TokensOmnichain::increment_UserOutflow(symbol, chain, shared, receiver, amount, true, TokensOmnichain::give_permission(&borrow_global<Permissions>(@dev).tokens_omnichain)); 
                let data = vector[
                    Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"proof"))),
                    Event::create_data_struct(utf8(b"event_type"), utf8(b"string"), bcs::to_bytes(&event_type)),
                    Event::create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier),
                    Event::create_data_struct(utf8(b"addr"), utf8(b"vector<u8>"), receiver),
                    Event::create_data_struct(utf8(b"token"), utf8(b"string"), bcs::to_bytes(&symbol)),
                    Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
                    Event::create_data_struct(utf8(b"provider"), utf8(b"string"), bcs::to_bytes(&provider)),
                    Event::create_data_struct(utf8(b"total_outflow"), utf8(b"u256"), bcs::to_bytes(&total_outflow)),
                    Event::create_data_struct(utf8(b"additional_outflow"), utf8(b"u256"), bcs::to_bytes(&(amount as u256))),
                    Event::create_data_struct(utf8(b"validator_root"), utf8(b"string"), bcs::to_bytes(&validator_root)),
                    Event::create_data_struct(utf8(b"old_root"), utf8(b"string"), bcs::to_bytes(&old_root)),
                    Event::create_data_struct(utf8(b"new_root"), utf8(b"string"), bcs::to_bytes(&new_root)),
                    Event::create_data_struct(utf8(b"nonce"), utf8(b"u256"), bcs::to_bytes(&nonce)),
                ];
                Event::emit_crosschain_event(utf8(b"Crosschain Event"), data); 

            } else {
                abort(ERROR_INVALID_MESSAGE);
            };


            // Emit Validated Event
            let data = vector[
                Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&validator)),
                Event::create_data_struct(utf8(b"event_type"), utf8(b"string"), bcs::to_bytes(&event_type)),
                Event::create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier),
                Event::create_data_struct(utf8(b"total_weight"), utf8(b"u128"), bcs::to_bytes(&quorum)),
                Event::create_data_struct(utf8(b"type_names"), utf8(b"vector<String>"), bcs::to_bytes(&type_names)),
                Event::create_data_struct(utf8(b"payload"), utf8(b"vector<vector<u8>>"), bcs::to_bytes(&payload)),
            ];
            Event::emit_validation_event(utf8(b"Validated Event"), data);
   

        };
    }

    #[view]
    public fun return_native_pending_tx(identifier: vector<u8>): MainVotes acquires Pending {
        let main = borrow_global<Pending>(@dev);
        assert!(table::contains(&main.main, identifier), ERROR_NOT_FOUND);
        return *table::borrow(&main.main, identifier)
    }
    #[view]
    public fun return_zk_pending_tx(identifier: vector<u8>): ZkVotes acquires Pending {
        let zk = borrow_global<Pending>(@dev);
        assert!(table::contains(&zk.zk, identifier), ERROR_NOT_FOUND);
        return *table::borrow(&zk.zk, identifier)
    }

    #[view]
    public fun return_native_validated_tx(identifier: vector<u8>): MainVotes acquires Validated {
        let main = borrow_global<Validated>(@dev);
        assert!(table::contains(&main.main, identifier), ERROR_NOT_FOUND);
        return *table::borrow(&main.main, identifier)
    }
    #[view]
    public fun return_zk_validated_tx(identifier: vector<u8>): ZkVotes acquires Validated {
        let zk = borrow_global<Validated>(@dev);
        assert!(table::contains(&zk.zk, identifier), ERROR_NOT_FOUND);
        return *table::borrow(&zk.zk, identifier)
    }




    fun convert_eventID_to_string(eventID: u8): String{
        if(eventID == 1 ){
            return utf8(b"Deposit")
        } else if(eventID == 2 ){
            return utf8(b"Request Unlock")
        } else if(eventID == 3 ){
            return utf8(b"Unlock")
        } else{
            return utf8(b"Unknown")
        }
    }



    #[test(account = @0x1, owner = @0xf286f429deaf08050a5ec8fc8a031b8b36e3d4e9d2486ef374e50ef487dd5bbd, owner2 = @0x281d0fce12a353b1f6e8bb6d1ae040a6deba248484cf8e9173a5b428a6fb74e7)]
    public entry fun test(account: signer, owner: signer, owner2: signer) acquires  Chain, Pending, Validated, Caps{
        // Initialize the CurrentTimeMicroseconds resource
        supra_framework::timestamp::set_time_has_started_for_testing(&account);
        supra_framework::timestamp::update_global_time_for_test(50000);
        let t1 =  supra_framework::timestamp::now_seconds();
        print(&t1);
        // Initialize the module
        init_module(&owner);
        // Change config
        let addr = signer::address_of(&owner);
        let addr2 = signer::address_of(&owner2);
        // Register a new chain
       // register_chain<Sui>(&owner, 1, utf8(b"Sui"), utf8(b"SUI"));
       // register_chain<Base>(&owner, 2, utf8(b"Base"), utf8(b"BASE"));
       // register_chain<Supra>(&owner, 3, utf8(b"Supra"), utf8(b"SUPRA"));           

        // Allow a validator


        let pubkey: vector<u8> = vector[
            0xbe, 0x4e, 0x29, 0x0a, 0x50, 0x82, 0xe6, 0xeb,
            0x0d, 0x01, 0x64, 0x1c, 0x4d, 0x35, 0x39, 0xf7,
            0x42, 0x33, 0x05, 0xac, 0xd9, 0x47, 0x42, 0xa0,
            0xe6, 0x23, 0x88, 0x2c, 0xae, 0x3d, 0x1d, 0xfd
        ];

        let pubkey2: vector<u8> = vector[
            0xd2, 0xf4, 0x24, 0x47, 0x42, 0xc8, 0x17, 0x76,
            0x50, 0x3b, 0x8e, 0x45, 0xc4, 0xba, 0x6f, 0x7e,
            0x87, 0x8d, 0x96, 0xe0, 0xd9, 0x74, 0xef, 0x51,
            0x6b, 0x99, 0x25, 0x09, 0xeb, 0x08, 0x5b, 0xcd
        ];

    let serialized_signature: vector<u8> = vector[
        0xfc, 0x3c, 0xa9, 0x97, 0x1c, 0x22, 0x62, 0x60,
        0x4c, 0xd4, 0xe0, 0xda, 0x9d, 0xa2, 0xa7, 0x87,
        0x5b, 0x3a, 0x15, 0x61, 0xd6, 0x32, 0x9b, 0x68,
        0xbf, 0xc1, 0x47, 0xb6, 0x75, 0xbc, 0xc5, 0x2d,
        0xa6, 0xe7, 0x9b, 0x40, 0x9e, 0xa9, 0x50, 0x90,
        0xfc, 0x36, 0x97, 0xd6, 0xdf, 0xcd, 0x22, 0x2f,
        0x36, 0xec, 0x71, 0x9d, 0xd7, 0xdd, 0x09, 0xf8,
        0x1f, 0x4f, 0x5e, 0xa5, 0xb1, 0x69, 0x3b, 0x02
    ];

    let serialized_payload: vector<u8> = vector[
        0x01, 0x51, 0x5b, 0xbf, 0xb8, 0x77, 0x80, 0x44,
        0xab, 0x8f, 0xa5, 0x39, 0x3f, 0x89, 0x84, 0x4e,
        0x5e, 0x27, 0x45, 0x44, 0x45, 0xc7, 0xc6, 0x5a,
        0x91, 0x5e, 0x60, 0x28, 0xdf, 0x40, 0x2d, 0x50,
        0x82, 0x65, 0xad, 0x96, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0xcd, 0xde, 0x99, 0x47, 0x1a, 0x73,
        0x41, 0xc7, 0x3d, 0x3c, 0x78, 0xa2, 0x12, 0x8f,
        0x16, 0xff, 0x82, 0x74, 0x12, 0x52, 0xbb, 0xb7,
        0x89, 0xe9, 0x36, 0x8d, 0x98, 0x37, 0x9e, 0x2b,
        0x8c, 0xdd
    ];


        allow_validator<Base>(&owner, addr, pubkey);
        allow_validator<Supra>(&owner, addr, pubkey);
        allow_validator<Sui>(&owner, addr, pubkey);

        allow_validator<Base>(&owner, addr2, pubkey2);
        allow_validator<Supra>(&owner, addr2, pubkey2);
        allow_validator<Sui>(&owner, addr2, pubkey2);


        let validators = get_chain_validators<Sui>();  

        print(&utf8(b" VALIDATORS "));
        print(&validators);
       // print(&vector::length(&serialized_signature));

      //  struct eth has drop, store {}

        register_event<Sui,Sui>(&owner, serialized_signature , serialized_payload); 

        register_event<Sui,Sui>(&owner2, serialized_signature , serialized_payload);           
 //       print(&deserialize_message(&serialized_payload));

    }
}

