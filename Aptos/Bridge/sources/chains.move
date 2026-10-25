module dev::QiaraBridgeV99 {
    use std::signer;
    use std::string::{String, utf8};
    use std::vector;
    use std::table::{Self as table, Table};
    use std::timestamp;
    use std::bcs;
    use aptos_std::bcs_stream;
    use aptos_std::ed25519 as Crypto;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};

use aptos_std::secp256k1;
use aptos_std::aptos_hash::keccak256;
use std::option;

    use event::QiaraEventV1 as Event;
    use dev::QiaraStorageV24 as storage;
    use dev::QiaraSharedV18::{Self as Shared, Access as SharedAccess};
    use dev::QiaraTokensCoreV87::{Self as TokensCore, Access as TokensCoreAccess};
    use dev::QiaraTokensQiaraV87::{Self as TokensQiara, Access as TokensQiaraAccess};
    use dev::QiaraTokensOmnichainV87::{Self as TokensOmnichain, Access as TokensOmnichainAccess};
    use dev::QiaraVaultsV109::{Self as Market, Access as MarketAccess};
    use dev::QiaraGovernanceV42::{Self as Governance, Access as GovernanceAccess};
    use dev::QiaraPayloadV99 as Payload;
    use dev::QiaraValidatorsV99::{Self as Validators, Access as ValidatorsAccess};
    use dev::QiaraPerpsOrdersV77::{Self as PerpOrders, Access as PerpOrdersAccess};
    use dev::QiaraPerpsV77::{Self as Perps, Access as PerpAccess};

    const STORAGE: address = @dev;

    // === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_DUPLICATE_EVENT: u64 = 7;
    const ERROR_INVALID_SIGNATURE: u64 = 9;
    const ERROR_INVALID_MESSAGE: u64 = 10;
    const ERROR_NOT_FOUND: u64 = 11;
    const ERROR_CAPS_NOT_PUBLISHED: u64 = 12;
    const ERROR_INVALID_VOTING_POWER: u64 = 13;
    const ERROR_INVALID_TYPE: u64 = 14;
    const ERROR_VALIDATOR_NOT_ACTIVE: u64 = 17;
    const ERROR_HASH_MISMATCH: u64 = 18;

    // === ACCESS & PERMISSIONS === //
    struct Access has store, key, drop {}
    struct Permission has store, key, drop, copy {}

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @dev, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_permission(_access: &Access): Permission {
        Permission {}
    }

    struct Permissions has key, store, drop {
        market: MarketAccess,
        tokens_core: TokensCoreAccess,
        qiara:  TokensQiaraAccess,
        tokens_omnichain: TokensOmnichainAccess,
        validators: ValidatorsAccess,
        perps: PerpAccess,
        perps_orders: PerpOrdersAccess,
        shared: SharedAccess,
        governance: GovernanceAccess
    }

    // === VOTE STRUCTS === //
    struct Vote has key, copy, store, drop {
        weight: u128,
        signature: vector<u8>,
    }

    // === UNIFIED EVENT STATE STRUCTS === //
    struct MainVotes has key, copy, store, drop {
        votes: Map<String, Vote>,
        data_types: vector<String>,
        data: vector<vector<u8>>,
        raw_payload: vector<u8>,
        total_weight: u128,
        time: u64,
        is_validated: bool,
    }

    // Single storage resource replaces dual Pending/Validated tables
    struct EventsStore has key {
        main: Table<vector<u8>, MainVotes>,
    }

    // === INIT === //
    fun init_module(admin: &signer) {
        if (!exists<Permissions>(@dev)) {
            move_to(admin, Permissions {qiara: TokensQiara::give_access(admin), governance: Governance::give_access(admin),shared: Shared::give_access(admin),perps: Perps::give_access(admin),perps_orders: PerpOrders::give_access(admin),market: Market::give_access(admin),tokens_core: TokensCore::give_access(admin),tokens_omnichain: TokensOmnichain::give_access(admin),validators: Validators::give_access(admin)});
        };
        if (!exists<EventsStore>(@dev)) {
            move_to(admin, EventsStore {main: table::new()});
        };
    }

    // === ENTRY FUNCTIONS === //

  public entry fun register_event(
        signer: &signer,
        validator: String,
        type_names: vector<String>,
        payload: vector<vector<u8>>,
        nullifier: vector<u8>,
        raw_payload: vector<u8>,
        signature: vector<u8>,
    ) acquires EventsStore, Permissions {
        // 1. Verify that nullifier is cryptographically bound to raw_payload
        let computed_nullifier = keccak256(raw_payload);
        assert!(nullifier == computed_nullifier, ERROR_HASH_MISMATCH);
        // 2. Validate consensus type
        let (_, type_raw) = Payload::find_payload_value(utf8(b"consensus_type"), type_names, payload);
        let consensus_type = bcs_stream::deserialize_string(&mut bcs_stream::new(type_raw));
        if (consensus_type == utf8(b"none")) return;

        // 3. Validate validator permissions and active status
        let (_, secp256k1_pub_key, isActive, vote_weight, _) = Validators::return_validator_raw(validator);
        assert!(isActive, ERROR_VALIDATOR_NOT_ACTIVE);

        // 4. Verify Secp256k1 Signature over nullifier
        assert!(vector::length(&signature) == 65, ERROR_INVALID_SIGNATURE);
        let eth_prefix = b"\x19Ethereum Signed Message:\n32";
        vector::append(&mut eth_prefix, nullifier);
        let eth_signed_hash = keccak256(eth_prefix);

        let sig_64 = vector::empty<u8>();
        let i = 0;
        while (i < 64) {
            vector::push_back(&mut sig_64, *vector::borrow(&signature, i));
            i = i + 1;
        };

        let v = *vector::borrow(&signature, 64);
        let recovery_id = if (v >= 27) { v - 27 } else { v };

        let ecdsa_sig = secp256k1::ecdsa_signature_from_bytes(sig_64);
        let recovered_key = secp256k1::ecdsa_recover(eth_signed_hash, recovery_id, &ecdsa_sig);
        assert!(option::is_some(&recovered_key), 101);

        let pubkey_bytes = secp256k1::ecdsa_raw_public_key_to_bytes(option::borrow(&recovered_key));
        assert!(&pubkey_bytes == &secp256k1_pub_key, 102);

        // 5. Extract event type
        let (_, event_type_raw) = Payload::find_payload_value(utf8(b"event_type"), type_names, payload);
        let event_type = bcs_stream::deserialize_string(&mut bcs_stream::new(event_type_raw));

        let store = borrow_global_mut<EventsStore>(STORAGE);

        handle_main_event(
            signer,
            validator,
            &mut store.main,
            nullifier,
            raw_payload,
            type_names,
            payload,
            signature,
            event_type,
            consensus_type,
            (vote_weight as u128)
        );
    }

    // === INTERNAL HANDLER === //

    fun handle_main_event(
        signer: &signer,
        validator: String,
        table: &mut Table<vector<u8>, MainVotes>,
        nullifier: vector<u8>,
        raw_payload: vector<u8>,
        type_names: vector<String>,
        payload: vector<vector<u8>>,
        signature: vector<u8>,
        event_type: String,
        consensus_type: String,
        vote_weight: u128
    ) acquires Permissions {
        assert!(vote_weight > 0, ERROR_INVALID_VOTING_POWER);
        let vote = Vote { signature, weight: vote_weight };

        if (table::contains(table, nullifier)) {
            let votes = table::borrow_mut(table, nullifier);
            assert!(!votes.is_validated, ERROR_DUPLICATE_EVENT);

            if (!map::contains_key(&votes.votes, &validator)) {
                map::add(&mut votes.votes, validator, vote);
                votes.total_weight = votes.total_weight + vote_weight;
                Validators::acrue_vote(validator, (vote_weight as u256));

                Event::emit_consensus_vote_event(vector[
                    Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&validator)),
                    Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&consensus_type)),
                    Event::create_data_struct(utf8(b"event_type"), utf8(b"string"), bcs::to_bytes(&event_type)),
                    Event::create_data_struct(utf8(b"vote_weight"), utf8(b"u128"), bcs::to_bytes(&vote_weight)),
                    Event::create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), nullifier),
                ]);
            };
        } else {
            let vote_map = map::new();
            map::add(&mut vote_map, validator, vote);
            table::add(table, nullifier, MainVotes {
                votes: vote_map,
                data_types: type_names,
                data: payload,
                raw_payload,
                total_weight: vote_weight,
                time: timestamp::now_seconds(),
                is_validated: false,
            });

            Event::emit_consensus_register_event(vector[
                Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&validator)),
                Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&consensus_type)),
                Event::create_data_struct(utf8(b"event_type"), utf8(b"string"), bcs::to_bytes(&event_type)),
                Event::create_data_struct(utf8(b"vote_weight"), utf8(b"u128"), bcs::to_bytes(&vote_weight)),
                Event::create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), nullifier),
                Event::create_data_struct(utf8(b"type_names"), utf8(b"vector<String>"), bcs::to_bytes(&type_names)),
                Event::create_data_struct(utf8(b"payload"), utf8(b"vector<vector<u8>>"), bcs::to_bytes(&payload)),
                Event::create_data_struct(utf8(b"raw_payload"), utf8(b"vector<u8>"), raw_payload),
            ]);
        };

        let quorum = (storage::expect_u64(storage::viewConstant(utf8(b"QiaraBridge"), utf8(b"MINIMUM_REQUIRED_VOTED_WEIGHT"))) as u128);
        let min_unique = (storage::expect_u8(storage::viewConstant(utf8(b"QiaraBridge"), utf8(b"MINIMUM_UNIQUE_VALIDATORS"))) as u64);

        let votes = table::borrow_mut(table, nullifier);
        if (!votes.is_validated && votes.total_weight >= quorum && (vector::length(&map::keys(&votes.votes)) as u64) >= min_unique) {
            votes.is_validated = true;
            let cap = borrow_global<Permissions>(@dev);

            // =================================================================
            // FULL DISPATCH BLOCK FOR ALL SUPPORTED INTERNAL SETTLEMENT FUNCTIONS
            // =================================================================
            if (event_type == utf8(b"Bridge Deposit")) {
                let (name, _, shared, symbol, chain, provider, amount, rate, rewards, _) = Payload::prepare_bridge_deposit(type_names, payload);
                Validators::acrue_modularity_fee(shared, name);
                TokensCore::c_bridge_to_supra(signer, shared, name, symbol, chain, provider, amount, 0, TokensCore::give_permission(&cap.tokens_core));
                Market::c_bridge_deposit(signer, shared, name, symbol, chain, provider, amount, rate, rewards, Market::give_permission(&cap.market));
            } else if (event_type == utf8(b"Bridge Stake")) {
                let (name, _, shared, symbol, chain, provider, amount, epoch, _) = Payload::prepare_bridge_stake(type_names, payload);
                Validators::acrue_modularity_fee(shared, name);
                TokensCore::c_bridge_to_supra(signer, shared, name, symbol, chain, provider, amount, 0, TokensCore::give_permission(&cap.tokens_core));
                Market::c_bridge_stake(signer, shared, name, symbol, chain, provider, amount, epoch, Market::give_permission(&cap.market));
            } else if (event_type == utf8(b"Bridge Unstake")) {
                let (shared, user, symbol, chain, provider, amount, _) = Payload::prepare_modular_unstake(type_names, payload);
                Validators::acrue_modularity_fee(shared, user);
                Market::c_bridge_unstake(signer, shared, user, symbol, chain, provider, amount, Market::give_permission(&cap.market));
            } else if (event_type == utf8(b"Bridge Borrow")) {
                let (name, _, shared, symbol, chain, provider, amount, _) = Payload::prepare_bridge_borrow(type_names, payload);
                Validators::acrue_modularity_fee(shared, name);
                Market::c_bridge_borrow(signer, shared, name, symbol, chain, provider, amount, Market::give_permission(&cap.market));
            } else if (event_type == utf8(b"Modular Qiara Bridge")) {
                //let (recepient, user, chain, amount, _) = Payload::prepare_request_qiara_bridge(type_names, payload);
                //TokensQiara::p_request_qiara_bridge(signer, user, chain, amount, recepient, TokensQiara::give_permission(&cap.qiara));
            } else if (event_type == utf8(b"Modular Withdraw")) {
                let (shared, user, symbol, chain, provider, amount, _) = Payload::prepare_modular_withdraw(type_names, payload);
                Validators::acrue_modularity_fee(shared, user);
                Market::c_bridge_withdraw(signer, shared, user, symbol, chain, provider, amount, Market::give_permission(&cap.market));
            } else if (event_type == utf8(b"Modular Storage Creation")) {
                let (name, user, ref_code, used_ref_code, xp_tax, fee_tax) = Payload::prepare_modular_storage_creation(type_names, payload);
                Shared::p_create_shared_storage(signer, user, name, ref_code, used_ref_code, xp_tax, fee_tax, Shared::give_permission(&cap.shared));
                Validators::acrue_modularity_fee(name, user);
            } else if (event_type == utf8(b"Modular Storage Sub Owner Added")) {
                let (name, user, sub_owner) = Payload::prepare_p_allow_sub_owner(type_names, payload);
                Validators::acrue_modularity_fee(name, user);
                Shared::p_allow_sub_owner(signer, user, name, sub_owner, Shared::give_permission(&cap.shared));
            } else if (event_type == utf8(b"Modular Storage Sub Owner Removed")) {
                let (name, user, sub_owner) = Payload::prepare_p_remove_sub_owner(type_names, payload);
                Validators::acrue_modularity_fee(name, user);
                Shared::p_remove_sub_owner(signer, user, name, sub_owner, Shared::give_permission(&cap.shared));
            } else if (event_type == utf8(b"Modular Storage Used Ref Code Updated")) {
                let (name, user, new_used_ref_code) = Payload::prepare_p_change_used_ref_code(type_names, payload);
                Validators::acrue_modularity_fee(name, user);
                Shared::p_change_used_ref_code(signer, user, name, x"", new_used_ref_code, Shared::give_permission(&cap.shared));
            } else if (event_type == utf8(b"Modular Interest Accrue")) {
                let (name, user, asset) = Payload::prepare_p_accrue_interest(type_names, payload);
                Validators::acrue_modularity_fee(user, name);
                Perps::p_accrue_interest(signer, name, user, asset, Perps::give_permission(&cap.perps));
            } else if (event_type == utf8(b"Modular Trade")) {
                let (name, user, asset, size, leverage, is_long, reserve_chain, reserve_provider, reserve_token) = Payload::prepare_p_trade(type_names, payload);
                Validators::acrue_modularity_fee(user, name);
                Perps::p_trade(signer, name, user, asset, (size as u256), leverage, is_long, reserve_chain, reserve_provider, reserve_token, Perps::give_permission(&cap.perps));
            } else if (event_type == utf8(b"Modular Reserve Change")) {
                let (name, user, asset, new_reserve_chain, new_reserve_provider, new_reserve_token) = Payload::prepare_p_change_reserve(type_names, payload);
                Validators::acrue_modularity_fee(user, name);
                Perps::p_change_reserve(signer, name, user, asset, new_reserve_chain, new_reserve_provider, new_reserve_token, Perps::give_permission(&cap.perps));
            } else if (event_type == utf8(b"Modular Limit Order Created")) {
                let (name, user, asset, size, desired_price, is_long, leverage, reserve_chain, reserve_provider, reserve_token) = Payload::prepare_p_create_limit_order(type_names, payload);
                Validators::acrue_modularity_fee(user, name);
                PerpOrders::p_create_limit_order(signer, user, name, asset, size, desired_price, is_long, leverage, reserve_chain, reserve_provider, reserve_token, PerpOrders::give_permission(&cap.perps_orders));
            } else if (event_type == utf8(b"Modular TWAP Order Created")) {
                let (name, user, asset, periods, sizes, is_long, leverage, reserve_chain, reserve_provider, reserve_token) = Payload::prepare_p_create_twap_order(type_names, payload);
                Validators::acrue_modularity_fee(user, name);
                PerpOrders::p_create_twap_order(signer, user, name, asset, periods, sizes, is_long, leverage, reserve_chain, reserve_provider, reserve_token, PerpOrders::give_permission(&cap.perps_orders));
            } else if (event_type == utf8(b"Modular Limit Order Deleted")) {
                let (name, user, id) = Payload::prepare_p_remove_limit_order(type_names, payload);
                Validators::acrue_modularity_fee(user, name);
                PerpOrders::p_remove_limit_order(signer, user, name, id, PerpOrders::give_permission(&cap.perps_orders));
            } else if (event_type == utf8(b"Modular TWAP Order Deleted")) {
                let (name, user, id) = Payload::prepare_p_remove_twap_order(type_names, payload);
                Validators::acrue_modularity_fee(user, name);
                PerpOrders::p_remove_twap_order(signer, user, name, id, PerpOrders::give_permission(&cap.perps_orders));
            } else if (event_type == utf8(b"Modular Governance Proposal")) {
                let (user, shared, name, desc, types, is_change, headers, constant_names, new_values, value_types, duration, editables, is_multichain) = Payload::prepare_modular_governance_proposal(type_names, payload);
                Validators::acrue_modularity_fee(shared, user);
                Governance::m_propose(signer, user, shared, name, desc, types, is_change, is_multichain, headers, constant_names, new_values, value_types, duration, editables, Governance::give_permission(&cap.governance));
            } else if (event_type == utf8(b"Modular Governance Vote")) {
                let (user, shared, proposal_id, is_yes) = Payload::prepare_modular_governance_vote(type_names, payload);
                Validators::acrue_modularity_fee(shared, user);
                Governance::m_vote(signer, user, shared, proposal_id, is_yes, Governance::give_permission(&cap.governance));
            } else {
                abort ERROR_INVALID_MESSAGE
            };

            // 6. Gather all validator signatures for external relaying
            let collected_sigs = vector::empty<vector<u8>>();
            let sig_keys = map::keys(&votes.votes);
            let k_idx = 0;
            while (k_idx < vector::length(&sig_keys)) {
                let k = vector::borrow(&sig_keys, k_idx);
                let v = map::borrow(&votes.votes, k);
                vector::push_back(&mut collected_sigs, v.signature);
                k_idx = k_idx + 1;
            };

            let (_, chain_raw) = Payload::find_payload_value(utf8(b"chain"), type_names, payload);
            let chain = bcs_stream::deserialize_string(&mut bcs_stream::new(chain_raw));

            // 7. Emit Validated Event with the identical raw_payload & signatures
            Event::emit_validation_event(utf8(b"Validated Event"), vector[
                Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&validator)),
                Event::create_data_struct(utf8(b"event_type"), utf8(b"string"), bcs::to_bytes(&event_type)),
                Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&consensus_type)),
                Event::create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), nullifier),
                Event::create_data_struct(utf8(b"total_weight"), utf8(b"u128"), bcs::to_bytes(&quorum)),
                Event::create_data_struct(utf8(b"type_names"), utf8(b"vector<String>"), bcs::to_bytes(&type_names)),
                Event::create_data_struct(utf8(b"payload"), utf8(b"vector<vector<u8>>"), bcs::to_bytes(&payload)),
                Event::create_data_struct(utf8(b"raw_payload"), utf8(b"vector<u8>"), raw_payload),
                Event::create_data_struct(utf8(b"signatures"), utf8(b"vector<vector<u8>>"), bcs::to_bytes(&collected_sigs)),
                Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
            ]);
        };
    }
    // === UNIFIED VIEW FUNCTIONS === //

    #[view]
    public fun get_native_event(identifier: vector<u8>): MainVotes acquires EventsStore {
        let store = borrow_global<EventsStore>(@dev);
        assert!(table::contains(&store.main, identifier), ERROR_NOT_FOUND);
        *table::borrow(&store.main, identifier)
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

