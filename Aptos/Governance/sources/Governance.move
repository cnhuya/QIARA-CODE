module dev::QiaraGovernanceV44 {
    use std::signer;
    use std::string::String;
    use std::vector;
    use aptos_framework::timestamp;
    use aptos_framework::transaction_context;
    use aptos_framework::account::{Self, SignerCapability, create_signer_with_capability};

    use dev::QiaraMarginV88 as Margin;

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
        /// The exact Move script code stored directly on-chain for 100% transparency!
        source_code: String,
        proposer: address,
        duration: u64,
        execution_hash: vector<u8>, // SHA3-256 of the compiled script bytecode
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

    /// 1. Propose: Stores the source code and the execution hash on-chain
    public entry fun propose(
        user: &signer,
        name: String,
        desc: String,
        source_code: String,        // 👈 Passed here!
        duration_seconds: u64,
        execution_hash: vector<u8>
    ) acquires GovernanceStorage {
        let storage = borrow_global_mut<GovernanceStorage>(@dev);
        let id = vector::length(&storage.proposals);

        vector::push_back(&mut storage.proposals, Proposal {
            id,
            name,
            desc,
            source_code,
            proposer: signer::address_of(user),
            duration: timestamp::now_seconds() + duration_seconds,
            execution_hash,
            yes: 0,
            no: 0,
            voters: vector::empty<String>(),
            executed: false,
        });
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

        // Return the DAO's authority to the script
        account::create_signer_with_capability(&storage.dao_signer_cap)
    }

    // ==========================================
    // VIEW FUNCTIONS (For Web Frontend & API)
    // ==========================================

    /// View the exact source code for a specific proposal
    #[view]
    public fun view_proposal_source_code(proposal_id: u64): String acquires GovernanceStorage {
        let storage = borrow_global<GovernanceStorage>(@dev);
        assert!(proposal_id < vector::length(&storage.proposals), ERROR_PROPOSAL_DOES_NOT_EXIST);
        let proposal = vector::borrow(&storage.proposals, proposal_id);
        proposal.source_code
    }

    /// View all proposals with their details
    #[view]
    public fun view_proposals(): vector<Proposal> acquires GovernanceStorage {
        borrow_global<GovernanceStorage>(@dev).proposals
    }
}