module dev::QiaraGovernanceV45 {
    use std::signer;
    use std::string::{String, utf8};
    use std::vector;
    use std::bcs;
    use aptos_framework::timestamp;
    use aptos_framework::transaction_context;
    use aptos_framework::account::{Self, SignerCapability, create_signer_with_capability};

    use dev::QiaraMarginV88 as Margin;
    use event::QiaraEventV1 as Event;

    const OWNER: address = @dev;

    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_PROPOSAL_NOT_FINISHED: u64 = 2;
    const ERROR_PROPOSAL_NOT_PASSED: u64 = 3;
    const ERROR_ALREADY_EXECUTED: u64 = 4;
    const ERROR_INVALID_SCRIPT_HASH: u64 = 5;
    const ERROR_ALREADY_VOTED: u64 = 6;
    const ERROR_PROPOSAL_DOES_NOT_EXIST: u64 = 7;

    struct Proposal has store, copy, drop {
        id: u64,
        name: String,
        desc: String,
        source_code: String,
        sub_owner: vector<u8>,       // 👈 Address/sub_owner bytes (Sui/EVM/Solana/Aptos)
        shared: String,              // 👈 Shared storage name
        duration: u64,
        execution_hash: vector<u8>,  // SHA3-256 of the compiled script bytecode
        yes: u256,
        no: u256,
        voters: vector<String>,
        executed: bool,
    }

    struct GovernanceStorage has key {
        dao_signer_cap: SignerCapability,
        proposals: vector<Proposal>,
    }

    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == OWNER, ERROR_NOT_ADMIN);

        // Resource account representing the DAO's on-chain authority
        let (_, signer_cap) = account::create_resource_account(admin, x"01");

        move_to(admin, GovernanceStorage {
            dao_signer_cap: signer_cap,
            proposals: vector::empty<Proposal>(),
        });
    }

    /// 1. Propose: Accepts sub_owner and shared, stores them, and emits event for Go indexer
    public entry fun propose(
        user: &signer,
        sub_owner: vector<u8>,       // 👈 Added sub_owner
        shared: String,              // 👈 Added shared
        name: String,
        desc: String,
        source_code: String,
        duration_seconds: u64,
        execution_hash: vector<u8>
    ) acquires GovernanceStorage {
        let storage = borrow_global_mut<GovernanceStorage>(@dev);
        let id = vector::length(&storage.proposals);
        let created_at = timestamp::now_seconds();
        let end_duration = created_at + duration_seconds;

        vector::push_back(&mut storage.proposals, Proposal {
            id,
            name,
            desc,
            source_code,
            sub_owner,
            shared,
            duration: end_duration,
            execution_hash,
            yes: 0,
            no: 0,
            voters: vector::empty<String>(),
            executed: false,
        });

        // 🟢 Emit "Create Proposal" event with sub_owner and shared for Supabase/Go API
        let validator_bytes = bcs::to_bytes(&signer::address_of(user));
        let data = vector[
            Event::create_data_struct(utf8(b"proposal_id"), utf8(b"u64"), bcs::to_bytes(&id)),
            Event::create_data_struct(utf8(b"name"), utf8(b"string"), bcs::to_bytes(&name)),
            Event::create_data_struct(utf8(b"desc"), utf8(b"string"), bcs::to_bytes(&desc)),
            Event::create_data_struct(utf8(b"source_code"), utf8(b"string"), bcs::to_bytes(&source_code)),
            Event::create_data_struct(utf8(b"execution_hash"), utf8(b"vector<u8>"), bcs::to_bytes(&execution_hash)),
            Event::create_data_struct(utf8(b"sub_owner"), utf8(b"vector<u8>"), bcs::to_bytes(&sub_owner)),
            Event::create_data_struct(utf8(b"proposer"), utf8(b"vector<u8>"), bcs::to_bytes(&sub_owner)),
            Event::create_data_struct(utf8(b"sender"), utf8(b"vector<u8>"), bcs::to_bytes(&sub_owner)),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(utf8(b"validator"), utf8(b"vector<u8>"), validator_bytes),
            Event::create_data_struct(utf8(b"duration"), utf8(b"u64"), bcs::to_bytes(&end_duration)),
            Event::create_data_struct(utf8(b"created"), utf8(b"u64"), bcs::to_bytes(&created_at)),
            Event::create_data_struct(utf8(b"status"), utf8(b"u8"), bcs::to_bytes(&(0 as u8))),
            Event::create_data_struct(utf8(b"result"), utf8(b"u8"), bcs::to_bytes(&(0 as u8))),
        ];
        Event::emit_governance_event(utf8(b"Create Proposal"), data);
    }

    /// 2. Vote: Records user's staked weight and emits "Vote" event
    public entry fun vote(
        user: &signer, 
        shared_storage_name: String, 
        proposal_id: u64, 
        is_yes: bool
    ) acquires GovernanceStorage {
        let storage = borrow_global_mut<GovernanceStorage>(@dev);
        assert!(proposal_id < vector::length(&storage.proposals), ERROR_PROPOSAL_DOES_NOT_EXIST);

        let proposal = vector::borrow_mut(&mut storage.proposals, proposal_id);

        assert!(!vector::contains(&proposal.voters, &shared_storage_name), ERROR_ALREADY_VOTED);
        assert!(timestamp::now_seconds() <= proposal.duration, ERROR_PROPOSAL_NOT_FINISHED);

        let vote_weight = Margin::get_user_total_staked_qiara(shared_storage_name);
        if (is_yes) {
            proposal.yes = proposal.yes + vote_weight;
        } else {
            proposal.no = proposal.no + vote_weight;
        };

        vector::push_back(&mut proposal.voters, shared_storage_name);

        // 🟢 Emit "Vote" event
        let sender_bytes = bcs::to_bytes(&signer::address_of(user));
        let data = vector[
            Event::create_data_struct(utf8(b"proposal_id"), utf8(b"u64"), bcs::to_bytes(&proposal_id)),
            Event::create_data_struct(utf8(b"sender"), utf8(b"vector<u8>"), sender_bytes),
            Event::create_data_struct(utf8(b"sub_owner"), utf8(b"vector<u8>"), sender_bytes),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared_storage_name)),
            Event::create_data_struct(utf8(b"vote_weight"), utf8(b"u256"), bcs::to_bytes(&vote_weight)),
            Event::create_data_struct(utf8(b"isYes"), utf8(b"bool"), bcs::to_bytes(&is_yes)),
        ];
        Event::emit_governance_event(utf8(b"Vote"), data);
    }

    /// 3. Resolve: Called by the approved script at execution time
    public fun resolve(proposal_id: u64): signer acquires GovernanceStorage {
        let storage = borrow_global_mut<GovernanceStorage>(@dev);
        assert!(proposal_id < vector::length(&storage.proposals), ERROR_PROPOSAL_DOES_NOT_EXIST);

        let proposal = vector::borrow_mut(&mut storage.proposals, proposal_id);

        assert!(!proposal.executed, ERROR_ALREADY_EXECUTED);
        assert!(timestamp::now_seconds() > proposal.duration, ERROR_PROPOSAL_NOT_FINISHED);
        assert!(proposal.yes > proposal.no, ERROR_PROPOSAL_NOT_PASSED);

        // Verify the running script bytecode matches what was proposed
        let current_script_hash = transaction_context::get_script_hash();
        assert!(current_script_hash == proposal.execution_hash, ERROR_INVALID_SCRIPT_HASH);

        proposal.executed = true;

        let yes_votes = proposal.yes;
        let no_votes = proposal.no;

        // 🟢 Emit "Proposal Result" event
        let data = vector[
            Event::create_data_struct(utf8(b"proposal_id"), utf8(b"u64"), bcs::to_bytes(&proposal_id)),
            Event::create_data_struct(utf8(b"status"), utf8(b"u8"), bcs::to_bytes(&(1 as u8))),
            Event::create_data_struct(utf8(b"result"), utf8(b"u8"), bcs::to_bytes(&(1 as u8))),
            Event::create_data_struct(utf8(b"yes"), utf8(b"u256"), bcs::to_bytes(&yes_votes)),
            Event::create_data_struct(utf8(b"no"), utf8(b"u256"), bcs::to_bytes(&no_votes)),
        ];
        Event::emit_governance_event(utf8(b"Proposal Result"), data);

        // Return the DAO's authority to the script
        account::create_signer_with_capability(&storage.dao_signer_cap)
    }

    // ==========================================
    // VIEW FUNCTIONS
    // ==========================================

    #[view]
    public fun view_proposal_source_code(proposal_id: u64): String acquires GovernanceStorage {
        let storage = borrow_global<GovernanceStorage>(@dev);
        assert!(proposal_id < vector::length(&storage.proposals), ERROR_PROPOSAL_DOES_NOT_EXIST);
        let proposal = vector::borrow(&storage.proposals, proposal_id);
        proposal.source_code
    }

    #[view]
    public fun view_proposals(): vector<Proposal> acquires GovernanceStorage {
        borrow_global<GovernanceStorage>(@dev).proposals
    }
}