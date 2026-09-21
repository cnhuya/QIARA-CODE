module dev::QiaraBridgeV78 {
    use std::signer;
    use std::string::{String, utf8};
    use std::vector;
    use std::table::{Self as table, Table};
    use std::timestamp;
    use std::bcs;
    use aptos_std::bcs_stream;
    use aptos_std::ed25519 as Crypto;
    use aptos_std::simple_map::{Self as map, SimpleMap as Map};

    use event::QiaraEventV1 as Event;
    use dev::QiaraStorageV22 as storage;
    use dev::QiaraSharedV17::{Self as Shared, Access as SharedAccess};
    use dev::QiaraTokensCoreV72::{Self as TokensCore, Access as TokensCoreAccess};
    use dev::QiaraTokensOmnichainV72::{Self as TokensOmnichain, Access as TokensOmnichainAccess};
    use dev::QiaraVaultsV93::{Self as Market, Access as MarketAccess};
    use dev::QiaraGovernanceV28::{Self as Governance, Access as GovernanceAccess};
    use dev::QiaraPayloadV78 as Payload;
    use dev::QiaraValidatorsV78::{Self as Validators, Access as ValidatorsAccess};
    use dev::QiaraPerpsOrdersV61::{Self as PerpOrders, Access as PerpOrdersAccess};
    use dev::QiaraPerpsV61::{Self as Perps, Access as PerpAccess};

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

    struct OmniVote has key, copy, store, drop {
        weight: u128,
        signatures: Map<String, vector<u8>>,
        secp256k1_pub_key: vector<u8>,
    }

    struct ProofVote has key, copy, store, drop {
        weight: u128,
        signature: vector<u8>,
        secp256k1_pub_key: vector<u8>,
    }

    struct ZkVote has key, copy, store, drop {
        weight: u128,
        s_r8x: String,
        s_r8y: String,
        s: String,
        pub_key_y: String,
    }

    // === UNIFIED EVENT STATE STRUCTS === //
    struct MainVotes has key, copy, store, drop {
        votes: Map<String, Vote>,
        data_types: vector<String>,
        data: vector<vector<u8>>,
        total_weight: u128,
        time: u64,
        is_validated: bool,
    }

    struct ZkVotes has key, copy, store, drop {
        votes: Map<String, ZkVote>,
        data_types: vector<String>,
        data: vector<vector<u8>>,
        total_weight: u128,
        time: u64,
        is_validated: bool,
    }

    struct ProofVotes has key, copy, store, drop {
        votes: Map<String, ProofVote>,
        data_types: vector<String>,
        data: vector<vector<u8>>,
        proof: vector<u256>,
        inputs: vector<u256>,
        type: String,
        chain: String,
        total_weight: u128,
        time: u64,
        is_validated: bool,
    }

    struct OmniVotes has key, copy, store, drop {
        votes: Map<String, OmniVote>,
        data_types: vector<String>,
        data: vector<vector<u8>>,
        proof: vector<u256>,
        inputs: vector<u256>,
        type: String,
        total_weight: u128,
        time: u64,
        is_validated: bool,
    }

    struct NonZkVotes has key, copy, store, drop {
        votes: Map<String, Vote>,
        data_types: vector<String>,
        data: vector<vector<u8>>,
        type: String,
        total_weight: u128,
        time: u64,
        is_validated: bool,
    }

    // Single storage resource replaces dual Pending/Validated tables
    struct EventsStore has key {
        main: Table<vector<u8>, MainVotes>,
        zk: Table<vector<u8>, ZkVotes>,
        proof: Table<vector<u8>, ProofVotes>,
        omnichain: Table<vector<u8>, OmniVotes>,
        non_zk: Table<vector<u8>, NonZkVotes>,
    }

    // === INIT === //
    fun init_module(admin: &signer) {
        if (!exists<Permissions>(@dev)) {
            move_to(admin, Permissions {governance: Governance::give_access(admin),shared: Shared::give_access(admin),perps: Perps::give_access(admin),perps_orders: PerpOrders::give_access(admin),market: Market::give_access(admin),tokens_core: TokensCore::give_access(admin),tokens_omnichain: TokensOmnichain::give_access(admin),validators: Validators::give_access(admin)});
        };
        if (!exists<EventsStore>(@dev)) {
            move_to(admin, EventsStore {main: table::new(),zk: table::new(),proof: table::new(),omnichain: table::new(),non_zk: table::new(),});
        };
    }

    // === ENTRY FUNCTIONS === //

    public entry fun register_event(signer: &signer,validator: String,type_names: vector<String>,payload: vector<vector<u8>>) acquires EventsStore, Permissions {
        Payload::ensure_valid_payload(type_names, payload);
        let identifier = Event::safe_create_identifier(type_names, payload);

        let (_, type_raw) = Payload::find_payload_value(utf8(b"consensus_type"), type_names, payload);
        let consensus_type = bcs_stream::deserialize_string(&mut bcs_stream::new(type_raw));
        if (consensus_type == utf8(b"none")) return;

        let (_, secp256k1_pub_key, isActive, _, _, vote_weight, _) = Validators::return_validator_raw(validator);
        assert!(isActive, ERROR_VALIDATOR_NOT_ACTIVE);
        //Validators::take_snapshot(signer, validator);

        let (_, event_type_raw) = Payload::find_payload_value(utf8(b"event_type"), type_names, payload);
        let event_type = bcs_stream::deserialize_string(&mut bcs_stream::new(event_type_raw));
        let store = borrow_global_mut<EventsStore>(STORAGE);

        if (consensus_type == utf8(b"native")) {
            let (_, sig_bytes) = Payload::find_payload_value(utf8(b"signature"), type_names, payload);
            
            // Cryptographic bind of validator identity to full event identifier
            let pubkey_struct = Crypto::new_unvalidated_public_key_from_bytes(secp256k1_pub_key);
            let signature = Crypto::new_signature_from_bytes(sig_bytes);
            assert!(Crypto::signature_verify_strict(&signature, &pubkey_struct, identifier), ERROR_INVALID_SIGNATURE);

            handle_main_event(
                signer,
                validator,
                &mut store.main,
                identifier,
                type_names,
                payload,
                sig_bytes,
                event_type,
                (vote_weight as u128)
            );
        } else if (consensus_type == utf8(b"zk")) {
            handle_zk_event(
                signer,
                validator,
                &mut store.zk,
                identifier,
                type_names,
                payload,
                build_zkVote_from_payload(utf8(b"pub_key_y"), type_names, payload),
                event_type,
                (vote_weight as u128)
            );
        } else {
            abort ERROR_INVALID_TYPE
        };
    }

    public entry fun register_non_zk_event(signer: &signer,validator: String,type_names: vector<String>,payload: vector<vector<u8>>,signature: vector<u8>) acquires EventsStore {
        Validators::take_snapshot(signer, validator);
        let (_, secp256k1_pub_key, isActive, _, _, total_power, _) = Validators::return_validator_raw(validator);
        assert!(isActive, ERROR_VALIDATOR_NOT_ACTIVE);

        let (_, zk_type_raw) = Payload::find_payload_value(utf8(b"zk_type"), type_names, payload);
        let zk_type = bcs_stream::deserialize_string(&mut bcs_stream::new(zk_type_raw));

        let (_, type_raw) = Payload::find_payload_value(utf8(b"fun_type"), type_names, payload);
        let type = bcs_stream::deserialize_string(&mut bcs_stream::new(type_raw));

        let (_, identifier) = Payload::find_payload_value(utf8(b"hash"), type_names, payload);

        let pubkey_struct = Crypto::new_unvalidated_public_key_from_bytes(secp256k1_pub_key);
        let sig = Crypto::new_signature_from_bytes(signature);
        assert!(Crypto::signature_verify_strict(&sig, &pubkey_struct, identifier), ERROR_INVALID_SIGNATURE);

        let store = borrow_global_mut<EventsStore>(STORAGE);
        handle_non_zk_event(
            validator,
            type,
            &mut store.non_zk,
            type_names,
            payload,
            signature,
            zk_type,
            identifier,
            (total_power as u128)
        );
    }

    public entry fun register_omnichain_event(signer: &signer,validator: String,type_names: vector<String>,payload: vector<vector<u8>>,proof: vector<u256>,inputs: vector<u256>,chains: vector<String>,signatures: vector<vector<u8>>) acquires EventsStore {
        Validators::take_snapshot(signer, validator);
        let (_, secp256k1_pub_key, isActive, _, _, total_power, _) = Validators::return_validator_raw(validator);
        assert!(isActive, ERROR_VALIDATOR_NOT_ACTIVE);

        let (_, zk_type_raw) = Payload::find_payload_value(utf8(b"zk_type"), type_names, payload);
        let zk_type = bcs_stream::deserialize_string(&mut bcs_stream::new(zk_type_raw));

        let (_, type_raw) = Payload::find_payload_value(utf8(b"fun_type"), type_names, payload);
        let type = bcs_stream::deserialize_string(&mut bcs_stream::new(type_raw));
        
        let identifier = if (type == utf8(b"Validators")) {
            Payload::create_omnichain_identifier(type_names, payload)
        } else if (type == utf8(b"Variables")) {
            Payload::create_omnichain_identifier_variables(type_names, payload)
        } else {
            abort ERROR_INVALID_TYPE
        };

        let store = borrow_global_mut<EventsStore>(STORAGE);
        handle_omnichain_event(
            validator,
            type,
            &mut store.omnichain,
            type_names,
            payload,
            proof,
            inputs,
            chains,
            signatures,
            secp256k1_pub_key,
            zk_type,
            identifier,
            (total_power as u128)
        );
    }

    public entry fun register_proof_event(signer: &signer,validator: String,type_names: vector<String>,payload: vector<vector<u8>>,proof: vector<u256>,inputs: vector<u256>,signature: vector<u8>) acquires EventsStore, Permissions {
        Payload::ensure_valid_payload(type_names, payload);
        let identifier = Event::safe_create_identifier(type_names, payload);

        let store = borrow_global_mut<EventsStore>(STORAGE);
        if (table::contains(&store.proof, identifier)) {
            let entry = table::borrow(&store.proof, identifier);
            assert!(!entry.is_validated, ERROR_DUPLICATE_EVENT);
        };

        Validators::take_snapshot(signer, validator);
        let (_, secp256k1_pub_key, isActive, _, _, vote_weight_raw, _) = Validators::return_validator_raw(validator);
        assert!(isActive, ERROR_VALIDATOR_NOT_ACTIVE);

        let vote_weight = (vote_weight_raw as u128);
        assert!(vote_weight > 0, ERROR_INVALID_VOTING_POWER);

        let pubkey_struct = Crypto::new_unvalidated_public_key_from_bytes(secp256k1_pub_key);
        let sig = Crypto::new_signature_from_bytes(signature);
        assert!(Crypto::signature_verify_strict(&sig, &pubkey_struct, identifier), ERROR_INVALID_SIGNATURE);

        let vote = ProofVote { signature, weight: vote_weight, secp256k1_pub_key };

        if (!table::contains(&store.proof, identifier)) {
            let (_, zk_type_raw) = Payload::find_payload_value(utf8(b"zk_type"), type_names, payload);
            let zk_type = bcs_stream::deserialize_string(&mut bcs_stream::new(zk_type_raw));

            let (_, chain_raw) = Payload::find_payload_value(utf8(b"chain"), type_names, payload);
            let chain = bcs_stream::deserialize_string(&mut bcs_stream::new(chain_raw));

            let vote_map = map::new();
            map::add(&mut vote_map, validator, vote);

            table::add(&mut store.proof, identifier, ProofVotes {
                votes: vote_map,
                data_types: type_names,
                data: payload,
                proof,
                inputs,
                type: zk_type,
                chain,
                total_weight: vote_weight,
                time: timestamp::now_seconds(),
                is_validated: false,
            });

            Event::emit_proof_event(vector[
                Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&validator)),
                Event::create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier),
                Event::create_data_struct(utf8(b"proofs"), utf8(b"vector<u256>"), bcs::to_bytes(&proof)),
                Event::create_data_struct(utf8(b"inputs"), utf8(b"vector<u256>"), bcs::to_bytes(&inputs)),
            ]);

            Event::emit_consensus_register_event(vector[
                Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&validator)),
                Event::create_data_struct(utf8(b"event_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"Proofs"))),
                Event::create_data_struct(utf8(b"vote_weight"), utf8(b"u128"), bcs::to_bytes(&vote_weight)),
                Event::create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier),
            ]);
        } else {
            let votes = table::borrow_mut(&mut store.proof, identifier);
            if (!map::contains_key(&votes.votes, &validator)) {
                map::add(&mut votes.votes, validator, vote);
                votes.total_weight = votes.total_weight + vote_weight;
                Validators::acrue_vote(validator,(vote_weight as u256));

                Event::emit_consensus_vote_event(vector[
                    Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&validator)),
                    Event::create_data_struct(utf8(b"event_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"Proofs"))),
                    Event::create_data_struct(utf8(b"vote_weight"), utf8(b"u128"), bcs::to_bytes(&vote_weight)),
                    Event::create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier),
                ]);
            };
        };

        // In-place mutation promotion check
        let quorum = (storage::expect_u64(storage::viewConstant(utf8(b"QiaraBridge"), utf8(b"MINIMUM_REQUIRED_VOTED_WEIGHT"))) as u128);
        let min_unique = (storage::expect_u8(storage::viewConstant(utf8(b"QiaraBridge"), utf8(b"MINIMUM_UNIQUE_VALIDATORS"))) as u64);

        let votes = table::borrow_mut(&mut store.proof, identifier);
        if (!votes.is_validated && votes.total_weight >= quorum && (vector::length(&map::keys(&votes.votes)) as u64) >= min_unique) {
            votes.is_validated = true;

            let (_, event_type_raw) = Payload::find_payload_value(utf8(b"zk_type"), votes.data_types, votes.data);
            let event_type = bcs_stream::deserialize_string(&mut bcs_stream::new(event_type_raw));

            if (event_type == utf8(b"Balances")) {
                let (receiver, shared, validator_root, old_root, new_root, symbol, chain, provider, amount, total_outflow, nonce) = Payload::prepare_finalize_bridge(votes.data_types, votes.data);
                let cap = borrow_global<Permissions>(@dev);
                Market::c_bridge_withdraw(signer, shared, receiver, symbol, chain, provider, amount, Market::give_permission(&cap.market));
                TokensOmnichain::increment_UserOutflow(symbol, chain, shared, receiver, amount, true, TokensOmnichain::give_permission(&cap.tokens_omnichain));

                Event::emit_crosschain_event(utf8(b"Zk Balance"), vector[
                    Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"proof"))),
                    Event::create_data_struct(utf8(b"zk_type"), utf8(b"string"), bcs::to_bytes(&event_type)),
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
                ]);
            } else {
                abort ERROR_INVALID_MESSAGE
            };

            Event::emit_validation_event(utf8(b"Validated Proof Event"), vector[
                Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&validator)),
                Event::create_data_struct(utf8(b"event_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"Proofs"))),
                Event::create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier),
                Event::create_data_struct(utf8(b"total_weight"), utf8(b"u128"), bcs::to_bytes(&quorum)),
            ]);
        };
    }

    // === INTERNAL HANDLERS === //

    fun handle_main_event(
        signer: &signer,
        validator: String,
        table: &mut Table<vector<u8>, MainVotes>,
        identifier: vector<u8>,
        type_names: vector<String>,
        payload: vector<vector<u8>>,
        signature: vector<u8>,
        event_type: String,
        vote_weight: u128
    ) acquires Permissions {
        assert!(vote_weight > 0, ERROR_INVALID_VOTING_POWER);
        let vote = Vote { signature, weight: vote_weight };

        if (table::contains(table, identifier)) {
            let votes = table::borrow_mut(table, identifier);
            assert!(!votes.is_validated, ERROR_DUPLICATE_EVENT);

            if (!map::contains_key(&votes.votes, &validator)) {
                map::add(&mut votes.votes, validator, vote);
                votes.total_weight = votes.total_weight + vote_weight;
                Validators::acrue_vote(validator, (vote_weight as u256));

                Event::emit_consensus_vote_event(vector[
                    Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&validator)),
                    Event::create_data_struct(utf8(b"event_type"), utf8(b"string"), bcs::to_bytes(&event_type)),
                    Event::create_data_struct(utf8(b"vote_weight"), utf8(b"u128"), bcs::to_bytes(&vote_weight)),
                    Event::create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier),
                   // Event::create_data_struct(utf8(b"type_names"), utf8(b"vector<String>"), bcs::to_bytes(&type_names)),
                    //Event::create_data_struct(utf8(b"payload"), utf8(b"vector<vector<u8>>"), bcs::to_bytes(&payload)),
                ]);
            };
        } else {
            let vote_map = map::new();
            map::add(&mut vote_map, validator, vote);
            table::add(table, identifier, MainVotes {
                votes: vote_map,
                data_types: type_names,
                data: payload,
                total_weight: vote_weight,
                time: timestamp::now_seconds(),
                is_validated: false,
            });

            Event::emit_consensus_register_event(vector[
                Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&validator)),
                Event::create_data_struct(utf8(b"event_type"), utf8(b"string"), bcs::to_bytes(&event_type)),
                Event::create_data_struct(utf8(b"vote_weight"), utf8(b"u128"), bcs::to_bytes(&vote_weight)),
                Event::create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier),
                Event::create_data_struct(utf8(b"type_names"), utf8(b"vector<String>"), bcs::to_bytes(&type_names)),
                Event::create_data_struct(utf8(b"payload"), utf8(b"vector<vector<u8>>"), bcs::to_bytes(&payload)),
            ]);
        };

        let quorum = (storage::expect_u64(storage::viewConstant(utf8(b"QiaraBridge"), utf8(b"MINIMUM_REQUIRED_VOTED_WEIGHT"))) as u128);
        let min_unique = (storage::expect_u8(storage::viewConstant(utf8(b"QiaraBridge"), utf8(b"MINIMUM_UNIQUE_VALIDATORS"))) as u64);

        let votes = table::borrow_mut(table, identifier);
        if (!votes.is_validated && votes.total_weight >= quorum && (vector::length(&map::keys(&votes.votes)) as u64) >= min_unique) {
            votes.is_validated = true;
            let cap = borrow_global<Permissions>(@dev);

            if (event_type == utf8(b"Bridge Deposit")) {
                let (name, _, shared, symbol, chain, provider, amount, rate, rewards, _) = Payload::prepare_bridge_deposit(type_names, payload);
                Validators::acrue_modularity_fee(shared, name);
                TokensCore::c_bridge_to_supra(signer, shared, name, symbol, chain, provider, amount, 0, TokensCore::give_permission(&cap.tokens_core));
                Market::c_bridge_deposit(signer, shared, name, symbol, chain, provider, amount, rate, rewards, Market::give_permission(&cap.market));
            } else if (event_type == utf8(b"Bridge Stake")) {
                let (name, _, shared, symbol, chain, provider, amount, epoch, _) = Payload::prepare_bridge_stake(type_names, payload);
                Validators::acrue_modularity_fee(shared, name);
                Market::c_bridge_stake(signer, shared, name, symbol, chain, provider, amount, epoch, Market::give_permission(&cap.market));
            } else if (event_type == utf8(b"Bridge Unstake")) {
                let (shared, user, symbol, chain, provider, amount, _) = Payload::prepare_modular_unstake(type_names, payload);
                Validators::acrue_modularity_fee(shared, user);
                Market::c_bridge_unstake(signer, shared, user, symbol, chain, provider, amount, Market::give_permission(&cap.market));
            } else if (event_type == utf8(b"Bridge Borrow")) {
                let (name, _, shared, symbol, chain, provider, amount, _) = Payload::prepare_bridge_borrow(type_names, payload);
                Validators::acrue_modularity_fee(shared, name);
                Market::c_bridge_borrow(signer, shared, name, symbol, chain, provider, amount, Market::give_permission(&cap.market));
            } else if (event_type == utf8(b"Modular Withdraw")) {
                let (shared, user, symbol, chain, provider, amount, _) = Payload::prepare_modular_withdraw(type_names, payload);
                Validators::acrue_modularity_fee(shared, user);
                TokensCore::p_request_bridge(signer, shared, user, symbol, chain, provider, amount, user, TokensCore::give_permission(&cap.tokens_core));
            } else if (event_type == utf8(b"Modular Storage Creation")) {
                let (name, user, ref_code, used_ref_code, selected_validator, xp_tax, fee_tax) = Payload::prepare_modular_storage_creation(type_names, payload);
                Shared::p_create_shared_storage(signer, user, name, ref_code, used_ref_code, selected_validator, xp_tax, fee_tax, Shared::give_permission(&cap.shared));
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

            Event::emit_validation_event(utf8(b"Validated Event"), vector[
                Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&validator)),
                Event::create_data_struct(utf8(b"event_type"), utf8(b"string"), bcs::to_bytes(&event_type)),
                Event::create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier),
                Event::create_data_struct(utf8(b"total_weight"), utf8(b"u128"), bcs::to_bytes(&quorum)),
                Event::create_data_struct(utf8(b"type_names"), utf8(b"vector<String>"), bcs::to_bytes(&type_names)),
                Event::create_data_struct(utf8(b"payload"), utf8(b"vector<vector<u8>>"), bcs::to_bytes(&payload)),
            ]);
        };
    }

    fun handle_zk_event(
        signer: &signer,
        validator: String,
        table: &mut Table<vector<u8>, ZkVotes>,
        identifier: vector<u8>,
        type_names: vector<String>,
        payload: vector<vector<u8>>,
        zk_vote: ZkVote,
        event_type: String,
        vote_weight: u128
    ) acquires Permissions {
        assert!(vote_weight > 0, ERROR_INVALID_VOTING_POWER);
        zk_vote.weight = vote_weight;

        if (table::contains(table, identifier)) {
            let votes = table::borrow_mut(table, identifier);
            assert!(!votes.is_validated, ERROR_DUPLICATE_EVENT);

            if (!map::contains_key(&votes.votes, &validator)) {
                map::add(&mut votes.votes, validator, zk_vote);
                votes.total_weight = votes.total_weight + vote_weight;
                Validators::acrue_vote(validator,(vote_weight as u256));

                Event::emit_consensus_vote_event(vector[
                    Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&validator)),
                    Event::create_data_struct(utf8(b"event_type"), utf8(b"string"), bcs::to_bytes(&event_type)),
                    Event::create_data_struct(utf8(b"vote_weight"), utf8(b"u128"), bcs::to_bytes(&vote_weight)),
                    Event::create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier),
                    //Event::create_data_struct(utf8(b"type_names"), utf8(b"vector<String>"), bcs::to_bytes(&type_names)),
                    //Event::create_data_struct(utf8(b"payload"), utf8(b"vector<vector<u8>>"), bcs::to_bytes(&payload)),
                ]);
            };
        } else {
            let vote_map = map::new();
            map::add(&mut vote_map, validator, zk_vote);
            table::add(table, identifier, ZkVotes {
                votes: vote_map,
                data_types: type_names,
                data: payload,
                total_weight: vote_weight,
                time: timestamp::now_seconds(),
                is_validated: false,
            });

            Event::emit_consensus_register_event(vector[
                Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&validator)),
                Event::create_data_struct(utf8(b"event_type"), utf8(b"string"), bcs::to_bytes(&event_type)),
                Event::create_data_struct(utf8(b"vote_weight"), utf8(b"u128"), bcs::to_bytes(&vote_weight)),
                Event::create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier),
                Event::create_data_struct(utf8(b"type_names"), utf8(b"vector<String>"), bcs::to_bytes(&type_names)),
                Event::create_data_struct(utf8(b"payload"), utf8(b"vector<vector<u8>>"), bcs::to_bytes(&payload)),
            ]);
        };

        let quorum = (storage::expect_u64(storage::viewConstant(utf8(b"QiaraBridge"), utf8(b"MINIMUM_REQUIRED_VOTED_WEIGHT"))) as u128);
        let min_unique = (storage::expect_u8(storage::viewConstant(utf8(b"QiaraBridge"), utf8(b"MINIMUM_UNIQUE_VALIDATORS"))) as u64);

        let votes = table::borrow_mut(table, identifier);
        if (!votes.is_validated && votes.total_weight >= quorum && (vector::length(&map::keys(&votes.votes)) as u64) >= min_unique) {
            votes.is_validated = true;
            let cap = borrow_global<Permissions>(@dev);

            if (event_type == utf8(b"Request Bridge")) {
                let (receiver, shared, validator_root, old_root, new_root, symbol, chain, provider, amount, total_outflow, nonce) = Payload::prepare_finalize_bridge(type_names, payload);
                Validators::acrue_modularity_fee(shared, Shared::return_shared_owner(shared));
                TokensCore::c_finalize_bridge(signer, symbol, chain, amount, TokensCore::give_permission(&cap.tokens_core));
                TokensOmnichain::increment_UserOutflow(symbol, chain, shared, receiver, amount, true, TokensOmnichain::give_permission(&cap.tokens_omnichain));

                Event::emit_crosschain_event(utf8(b"Crosschain Event"), vector[
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
                ]);
            } else if (event_type == utf8(b"Request Unstake")) {
                let (sender, shared, validator_root, old_root, new_root, symbol, chain, provider, amount, total_outflow, nonce) = Payload::prepare_c_unstake(type_names, payload);
                Validators::acrue_modularity_fee(shared, Shared::return_shared_owner(shared));
                Market::c_bridge_withdraw(signer, shared, sender, symbol, chain, provider, amount, Market::give_permission(&cap.market));
                TokensOmnichain::increment_UserOutflow(symbol, chain, shared, sender, amount, true, TokensOmnichain::give_permission(&cap.tokens_omnichain));

                Event::emit_crosschain_event(utf8(b"Crosschain Event"), vector[
                    Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"proof"))),
                    Event::create_data_struct(utf8(b"event_type"), utf8(b"string"), bcs::to_bytes(&event_type)),
                    Event::create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier),
                    Event::create_data_struct(utf8(b"addr"), utf8(b"vector<u8>"), sender),
                    Event::create_data_struct(utf8(b"token"), utf8(b"string"), bcs::to_bytes(&symbol)),
                    Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
                    Event::create_data_struct(utf8(b"provider"), utf8(b"string"), bcs::to_bytes(&provider)),
                    Event::create_data_struct(utf8(b"total_outflow"), utf8(b"u256"), bcs::to_bytes(&total_outflow)),
                    Event::create_data_struct(utf8(b"additional_outflow"), utf8(b"u256"), bcs::to_bytes(&(amount as u256))),
                    Event::create_data_struct(utf8(b"validator_root"), utf8(b"string"), bcs::to_bytes(&validator_root)),
                    Event::create_data_struct(utf8(b"old_root"), utf8(b"string"), bcs::to_bytes(&old_root)),
                    Event::create_data_struct(utf8(b"new_root"), utf8(b"string"), bcs::to_bytes(&new_root)),
                    Event::create_data_struct(utf8(b"nonce"), utf8(b"u256"), bcs::to_bytes(&nonce)),
                ]);
            } else {
                abort ERROR_INVALID_MESSAGE
            };

            Event::emit_validation_event(utf8(b"Validated Event"), vector[
                Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&validator)),
                Event::create_data_struct(utf8(b"event_type"), utf8(b"string"), bcs::to_bytes(&event_type)),
                Event::create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier),
                Event::create_data_struct(utf8(b"total_weight"), utf8(b"u128"), bcs::to_bytes(&quorum)),
                Event::create_data_struct(utf8(b"type_names"), utf8(b"vector<String>"), bcs::to_bytes(&type_names)),
                Event::create_data_struct(utf8(b"payload"), utf8(b"vector<vector<u8>>"), bcs::to_bytes(&payload)),
            ]);
        };
    }

    fun handle_omnichain_event(
        validator: String,
        type: String,
        table: &mut Table<vector<u8>, OmniVotes>,
        type_names: vector<String>,
        payload: vector<vector<u8>>,
        proof: vector<u256>,
        inputs: vector<u256>,
        chains: vector<String>,
        signatures: vector<vector<u8>>,
        secp256k1_pub_key: vector<u8>,
        consensus_type: String,
        identifier: vector<u8>,
        vote_weight: u128
    ){
        assert!(vote_weight > 0, ERROR_INVALID_VOTING_POWER);

        let signature_map = map::new();
        let len = vector::length(&chains);
        let i = 0;
        while (i < len) {
            map::add(&mut signature_map, *vector::borrow(&chains, i), *vector::borrow(&signatures, i));
            i = i + 1;
        };
        let vote = OmniVote { signatures: signature_map, weight: vote_weight, secp256k1_pub_key };

        if (table::contains(table, identifier)) {
            let votes = table::borrow_mut(table, identifier);
            assert!(!votes.is_validated, ERROR_DUPLICATE_EVENT);

            if (!map::contains_key(&votes.votes, &validator)) {
                map::add(&mut votes.votes, validator, vote);
                votes.total_weight = votes.total_weight + vote_weight;

                Event::emit_consensus_vote_event(vector[
                    Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&validator)),
                    Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&consensus_type)),
                    Event::create_data_struct(utf8(b"event_type"), utf8(b"string"), bcs::to_bytes(&type)),
                    Event::create_data_struct(utf8(b"vote_weight"), utf8(b"u128"), bcs::to_bytes(&vote_weight)),
                    Event::create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier),
                    //Event::create_data_struct(utf8(b"type_names"), utf8(b"vector<String>"), bcs::to_bytes(&type_names)),
                    //Event::create_data_struct(utf8(b"payload"), utf8(b"vector<vector<u8>>"), bcs::to_bytes(&payload)),
                ]);
            };
        } else {
            let vote_map = map::new();
            map::add(&mut vote_map, validator, vote);

            table::add(table, identifier, OmniVotes {
                votes: vote_map,
                data_types: type_names,
                data: payload,
                proof,
                inputs,
                type,
                total_weight: vote_weight,
                time: timestamp::now_seconds(),
                is_validated: false,
            });

            Event::emit_consensus_register_event(vector[
                Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&validator)),
                Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&consensus_type)),
                Event::create_data_struct(utf8(b"type"), utf8(b"string"), bcs::to_bytes(&type)),
                Event::create_data_struct(utf8(b"vote_weight"), utf8(b"u128"), bcs::to_bytes(&vote_weight)),
                Event::create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier),
                Event::create_data_struct(utf8(b"type_names"), utf8(b"vector<String>"), bcs::to_bytes(&type_names)),
                Event::create_data_struct(utf8(b"payload"), utf8(b"vector<vector<u8>>"), bcs::to_bytes(&payload)),
            ]);
        };

        let quorum = (storage::expect_u64(storage::viewConstant(utf8(b"QiaraBridge"), utf8(b"MINIMUM_REQUIRED_VOTED_WEIGHT"))) as u128);
        let min_unique = (storage::expect_u8(storage::viewConstant(utf8(b"QiaraBridge"), utf8(b"MINIMUM_UNIQUE_VALIDATORS"))) as u64);

        let votes = table::borrow_mut(table, identifier);
        if (!votes.is_validated && votes.total_weight >= quorum && (vector::length(&map::keys(&votes.votes)) as u64) >= min_unique) {
            votes.is_validated = true;
            Payload::prepare_omnichain_event(type_names, payload);

            Event::emit_validation_event(utf8(b"Validated Omnichain Event"), vector[
                Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&validator)),
                Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&consensus_type)),
                Event::create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier),
                Event::create_data_struct(utf8(b"total_weight"), utf8(b"u128"), bcs::to_bytes(&quorum)),
                Event::create_data_struct(utf8(b"type_names"), utf8(b"vector<String>"), bcs::to_bytes(&type_names)),
                Event::create_data_struct(utf8(b"payload"), utf8(b"vector<vector<u8>>"), bcs::to_bytes(&payload)),
            ]);
        };
    }

    fun handle_non_zk_event(
        validator: String,
        type: String,
        table: &mut Table<vector<u8>, NonZkVotes>,
        type_names: vector<String>,
        payload: vector<vector<u8>>,
        signature: vector<u8>,
        consensus_type: String,
        identifier: vector<u8>,
        vote_weight: u128
    )  {
        assert!(vote_weight > 0, ERROR_INVALID_VOTING_POWER);
        let vote = Vote { weight: vote_weight, signature };

        if (table::contains(table, identifier)) {
            let votes = table::borrow_mut(table, identifier);
            assert!(!votes.is_validated, ERROR_DUPLICATE_EVENT);

            if (!map::contains_key(&votes.votes, &validator)) {
                map::add(&mut votes.votes, validator, vote);
                votes.total_weight = votes.total_weight + vote_weight;

                Event::emit_consensus_vote_event(vector[
                    Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&validator)),
                    Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&consensus_type)),
                    Event::create_data_struct(utf8(b"event_type"), utf8(b"string"), bcs::to_bytes(&type)),
                    Event::create_data_struct(utf8(b"vote_weight"), utf8(b"u128"), bcs::to_bytes(&vote_weight)),
                    Event::create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier),
                    //Event::create_data_struct(utf8(b"type_names"), utf8(b"vector<String>"), bcs::to_bytes(&type_names)),
                    //Event::create_data_struct(utf8(b"payload"), utf8(b"vector<vector<u8>>"), bcs::to_bytes(&payload)),
                ]);
            };
        } else {
            let vote_map = map::new();
            map::add(&mut vote_map, validator, vote);

            table::add(table, identifier, NonZkVotes {
                votes: vote_map,
                data_types: type_names,
                data: payload,
                type,
                total_weight: vote_weight,
                time: timestamp::now_seconds(),
                is_validated: false,
            });

            Event::emit_consensus_register_event(vector[
                Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&validator)),
                Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&consensus_type)),
                Event::create_data_struct(utf8(b"type"), utf8(b"string"), bcs::to_bytes(&type)),
                Event::create_data_struct(utf8(b"vote_weight"), utf8(b"u128"), bcs::to_bytes(&vote_weight)),
                Event::create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier),
                Event::create_data_struct(utf8(b"type_names"), utf8(b"vector<String>"), bcs::to_bytes(&type_names)),
                Event::create_data_struct(utf8(b"payload"), utf8(b"vector<vector<u8>>"), bcs::to_bytes(&payload)),
            ]);
        };

        let quorum = (storage::expect_u64(storage::viewConstant(utf8(b"QiaraBridge"), utf8(b"MINIMUM_REQUIRED_VOTED_WEIGHT"))) as u128);
        let min_unique = (storage::expect_u8(storage::viewConstant(utf8(b"QiaraBridge"), utf8(b"MINIMUM_UNIQUE_VALIDATORS"))) as u64);

        let votes = table::borrow_mut(table, identifier);
        if (!votes.is_validated && votes.total_weight >= quorum && (map::length(&votes.votes) as u64) >= min_unique) {
            votes.is_validated = true;
            Payload::prepare_non_zk_event(type_names, payload);

            Event::emit_validation_event(utf8(b"Validated Non-Zk Event"), vector[
                Event::create_data_struct(utf8(b"validator"), utf8(b"string"), bcs::to_bytes(&validator)),
                Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&consensus_type)),
                Event::create_data_struct(utf8(b"identifier"), utf8(b"vector<u8>"), identifier),
                Event::create_data_struct(utf8(b"type"), utf8(b"string"), bcs::to_bytes(&type)),
                Event::create_data_struct(utf8(b"total_weight"), utf8(b"u128"), bcs::to_bytes(&quorum)),
                Event::create_data_struct(utf8(b"type_names"), utf8(b"vector<String>"), bcs::to_bytes(&type_names)),
                Event::create_data_struct(utf8(b"payload"), utf8(b"vector<vector<u8>>"), bcs::to_bytes(&payload)),
            ]);
        };
    }

    fun build_zkVote_from_payload(pubkey_y: String, type_names: vector<String>, payload: vector<vector<u8>>): ZkVote {
        let (_, s_r8x) = Payload::find_payload_value(utf8(b"s_r8x"), type_names, payload);
        let (_, s_r8y) = Payload::find_payload_value(utf8(b"s_r8y"), type_names, payload);
        let (_, s) = Payload::find_payload_value(utf8(b"s"), type_names, payload);

        ZkVote {
            weight: 0,
            s_r8x: bcs_stream::deserialize_string(&mut bcs_stream::new(s_r8x)),
            s_r8y: bcs_stream::deserialize_string(&mut bcs_stream::new(s_r8y)),
            s: bcs_stream::deserialize_string(&mut bcs_stream::new(s)),
            pub_key_y: pubkey_y,
        }
    }

    // === UNIFIED VIEW FUNCTIONS === //

    #[view]
    public fun get_native_event(identifier: vector<u8>): MainVotes acquires EventsStore {
        let store = borrow_global<EventsStore>(@dev);
        assert!(table::contains(&store.main, identifier), ERROR_NOT_FOUND);
        *table::borrow(&store.main, identifier)
    }

    #[view]
    public fun get_zk_event(identifier: vector<u8>): ZkVotes acquires EventsStore {
        let store = borrow_global<EventsStore>(@dev);
        assert!(table::contains(&store.zk, identifier), ERROR_NOT_FOUND);
        *table::borrow(&store.zk, identifier)
    }

    #[view]
    public fun get_proof_event(identifier: vector<u8>): ProofVotes acquires EventsStore {
        let store = borrow_global<EventsStore>(@dev);
        assert!(table::contains(&store.proof, identifier), ERROR_NOT_FOUND);
        *table::borrow(&store.proof, identifier)
    }

    #[view]
    public fun get_omnichain_event(identifier: vector<u8>): OmniVotes acquires EventsStore {
        let store = borrow_global<EventsStore>(@dev);
        assert!(table::contains(&store.omnichain, identifier), ERROR_NOT_FOUND);
        *table::borrow(&store.omnichain, identifier)
    }

    #[view]
    public fun get_non_zk_event(identifier: vector<u8>): NonZkVotes acquires EventsStore {
        let store = borrow_global<EventsStore>(@dev);
        assert!(table::contains(&store.non_zk, identifier), ERROR_NOT_FOUND);
        *table::borrow(&store.non_zk, identifier)
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

