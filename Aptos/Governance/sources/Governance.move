module dev::QiaraGovernanceV46 {
    use std::signer;
use std::string::{Self, String, utf8};
    use std::vector;
    use std::bcs;
    use aptos_framework::timestamp;
    use aptos_framework::transaction_context;
    use aptos_framework::account::{Self, SignerCapability, create_signer_with_capability};

    use dev::QiaraMarginV89 as Margin;
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
        sub_owner: vector<u8>,
        shared: String,
        duration: u64,
        execution_hash: vector<u8>,
        yes: u256,
        no: u256,
        voters: vector<String>,
        executed: bool,
    }

    /// Resource holding the DAO's SignerCapability under @dev
    struct DaoCapability has key {
        cap: SignerCapability,
    }

    struct GovernanceStorage has key {
        proposals: vector<Proposal>,
    }

    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == OWNER, ERROR_NOT_ADMIN);

        // 🟢 1. Only create the resource account if it doesn't already exist on @dev!
        if (!exists<DaoCapability>(OWNER)) {
            // Uses seed b"QiaraDAO" to create the permanent DAO resource account
            let (_, signer_cap) = account::create_resource_account(admin, b"QiaraDAO");
            move_to(admin, DaoCapability {
                cap: signer_cap,
            });
        };

        // 🟢 2. Initialize GovernanceStorage if it doesn't exist
        if (!exists<GovernanceStorage>(OWNER)) {
            move_to(admin, GovernanceStorage {
                proposals: vector::empty<Proposal>(),
            });
        };
    }

    /// 1. Propose
    public entry fun propose(
        user: &signer,
        sub_owner: vector<u8>,
        shared: String,
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

        // Emit "Create Proposal" event
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

    /// 2. Vote
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

        // Emit "Vote" event
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

    /// 3. Resolve: Borrows DaoCapability and creates the DAO signer for the script
    public fun resolve(proposal_id: u64): signer acquires GovernanceStorage, DaoCapability {
        let storage = borrow_global_mut<GovernanceStorage>(@dev);
        assert!(proposal_id < vector::length(&storage.proposals), ERROR_PROPOSAL_DOES_NOT_EXIST);

        let proposal = vector::borrow_mut(&mut storage.proposals, proposal_id);

        assert!(!proposal.executed, ERROR_ALREADY_EXECUTED);
        assert!(timestamp::now_seconds() > proposal.duration, ERROR_PROPOSAL_NOT_FINISHED);
        assert!(proposal.yes > proposal.no, ERROR_PROPOSAL_NOT_PASSED);

        // Verify script hash
        let current_script_hash = transaction_context::get_script_hash();
        assert!(current_script_hash == proposal.execution_hash, ERROR_INVALID_SCRIPT_HASH);

        proposal.executed = true;

        let yes_votes = proposal.yes;
        let no_votes = proposal.no;

        // Emit "Proposal Result" event
        let data = vector[
            Event::create_data_struct(utf8(b"proposal_id"), utf8(b"u64"), bcs::to_bytes(&proposal_id)),
            Event::create_data_struct(utf8(b"status"), utf8(b"u8"), bcs::to_bytes(&(1 as u8))),
            Event::create_data_struct(utf8(b"result"), utf8(b"u8"), bcs::to_bytes(&(1 as u8))),
            Event::create_data_struct(utf8(b"yes"), utf8(b"u256"), bcs::to_bytes(&yes_votes)),
            Event::create_data_struct(utf8(b"no"), utf8(b"u256"), bcs::to_bytes(&no_votes)),
        ];
        Event::emit_governance_event(utf8(b"Proposal Result"), data);

        // 🟢 Borrow DaoCapability from @dev to create the DAO signer
        let dao_cap = borrow_global<DaoCapability>(OWNER);
        create_signer_with_capability(&dao_cap.cap)
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