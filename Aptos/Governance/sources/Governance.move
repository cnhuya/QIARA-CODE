module dev::QiaraGovernanceV2 {
    use std::signer;
    use std::string::{Self, String, utf8};
    use std::vector;
    use std::bcs;
    use aptos_std::type_info;
    use aptos_std::timestamp;
    use std::table;
    use aptos_std::from_bcs;

    use event::QiaraEventV1::{Self as Event};
    use dev::QiaraMarginV2::{Self as Margin};

    use dev::QiaraStorageV1::{Self as storage, Access as StorageAccess};
    use dev::QiaraCapabilitiesV1::{Self as capabilities, Access as CapabilitiesAccess};
    use dev::QiaraFunctionsV1::{Self as functions, Access as FunctionAccess};
    use dev::QiaraSharedV1::{Self as TokensShared};
    const OWNER: address = @dev;

    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_CONSTANT_ALREADY_EXISTS: u64 = 2;
    const ERROR_NOT_ENOUGH_TOKENS_TO_PROPOSE: u64 = 3;
    const ERROR_PROPOSAL_NOT_FINISHED_YET: u64 = 4;
    const ERROR_INVALID_PROPOSAL_TYPE: u64 = 5;
    const ERROR_NOT_ENOUGH_VOTES: u64 = 6;
    const ERROR_ALREADY_VOTED: u64 = 7;
    const ERROR_BLACKLISTED: u64 = 8;

    struct ProposalCount has store, key, copy { count: u64 }

    struct Access has key, store, drop {
        storage_access: StorageAccess,
        capabilities_access: CapabilitiesAccess,
        function_access: FunctionAccess
    }

    struct Proposal has copy, store, drop {
        id: u64,
        type: vector<String>,
        proposer: address,
        duration: u64,
        header: vector<String>,
        constant: vector<String>,
        new_value: vector<vector<u8>>,
        value_type: vector<String>,
        isChange: vector<bool>,
        editable: vector<bool>,
        yes: u256,
        no: u256,
        voters: vector<String>,
        result: u8,
    }


    #[event]
    struct ProposeEvent has store, drop {
        id: u64,
        type: vector<String>,
        proposer: address,
        start: u256,
        end: u256,
        header: vector<String>,
        constant: vector<String>,
        isChange: vector<bool>,
        editable: vector<bool>,
        new_value: vector<vector<u8>>,
        value_type: vector<String>,
    }

    #[event]
    struct ProposalResultEvent has store, drop {
        id: u64,
        type: vector<String>,
        proposer: address,
        start: u64,
        end: u64,
        header: vector<String>,
        constant: vector<String>,
        new_value: vector<vector<u8>>,
        value_type: vector<String>,
        isChange: vector<bool>,
        editable: vector<bool>,
        yes: u256,
        no: u256,
        result: u8,
    }

    #[event]
    struct Vote has store, drop {
        proposal_id: u64,
        voter: address,
        isYes: bool,
        amount: u256,
    }

    struct PendingProposals has key {
        proposals: vector<Proposal>
    }

    fun make_proposal(id: u64, type: vector<String>, proposer: address, duration: u64, header: vector<String>, constant: vector<String>, isChange: vector<bool>, editable: vector<bool>, new_value: vector<vector<u8>>, value_type:vector<String>): Proposal {
        Proposal {id, type, proposer, duration, header, constant, new_value, value_type, isChange, editable, yes: 0, no: 0, voters: vector::empty<address>(), result: 0}
    }


    fun init_module(admin: &signer) {
        assert!(signer::address_of(admin) == OWNER, ERROR_NOT_ADMIN);

        if (!exists<PendingProposals>(OWNER)) {
            move_to(admin, PendingProposals { proposals: vector::empty<Proposal>() });
        };

        if (!exists<ProposalCount>(OWNER)) {
            move_to(admin, ProposalCount { count: 0 });
        };

        if (!exists<Access>(OWNER)) {
            move_to(admin, Access {
                storage_access: storage::give_access(admin),
                capabilities_access: capabilities::give_access(admin),
                function_access: functions::give_access(admin)
            });
        };
    }

    public entry fun propose(proposer: &signer, type: vector<String>, isChange: vector<bool>, header: vector<String>, constant_name: vector<String>, new_value: vector<vector<u8>>, value_type: vector<String>, duration: u64, editable: vector<bool>) acquires PendingProposals, ProposalCount {
        let addr = signer::address_of(proposer);
        assert_allowed_type(type);
        assert!(!capabilities::assert_wallet_capability(signer::address_of(proposer), utf8(b"QiaraGovernance"), utf8(b"BLACKLIST")), ERROR_BLACKLISTED);
        let registry = borrow_global_mut<PendingProposals>(OWNER);
        let count_ref = borrow_global_mut<ProposalCount>(OWNER);
        let proposal_id = count_ref.count;

        let proposal = make_proposal(proposal_id, type, addr, duration, header, constant_name, isChange, editable, new_value, value_type);
        vector::push_back(&mut registry.proposals, proposal);

        count_ref.count = count_ref.count + 1;
    }

    // finalize_proposal: remove proposal, destructure into locals, then operate on locals
    public entry fun finalize_proposal(user: &signer, proposal_id: u64) acquires PendingProposals, Access {
        let addr = signer::address_of(user);

        let registry = borrow_global_mut<PendingProposals>(OWNER);
        let len = vector::length(&registry.proposals);

        while (len > 0) {
            let idx = len - 1;
            let prop_ref = vector::borrow(&registry.proposals, idx);
            if (prop_ref.id == proposal_id) {
                // remove and destructure
                let proposal = vector::remove(&mut registry.proposals, idx);

                let Proposal {
                    id,
                    type,
                    proposer,
                    duration,
                    header,
                    constant,
                    new_value,
                    value_type,
                    isChange,
                    editable,
                    yes,
                    no,
                    voters,
                    result,
                } = proposal;

                // 1. Ensure proposal duration expired
                assert!(timestamp::now_seconds() > duration, ERROR_PROPOSAL_NOT_FINISHED_YET);

                // 2. Ensure minimum participation threshold
                let min_votes = storage::expect_u64(
                    storage::viewConstant(utf8(b"QiaraGovernance"), utf8(b"MINIMUM_TOTAL_VOTES_PERCENTAGE_SUPPLY"))
                );
                if(yes >= (min_votes as u256)){
                    // 3. Calculate quorum %
                    let total_votes = yes + no;
                    let  result: u8 = 2; // default fail
                    if (total_votes != 0) {
                        let quorum_required = storage::expect_u64(
                            storage::viewConstant(utf8(b"QiaraGovernance"), utf8(b"MINIMUM_QUARUM_FOR_PROPOSAL_TO_PASS"))
                        );

                        if (((yes * 100) / total_votes) >= (quorum_required as u256)) {
                            result = 1;
                            let x = vector::length(&type);
                            while(x > 0){
                                let _type = vector::borrow(&type, x-1);
                                let _isChange = *vector::borrow(&isChange, x-1);
                                x=x-1;

                                if (*_type == utf8(b"Constant")) {
                                    if (_isChange) {
                                        storage::change_constant_multi(
                                            user,
                                            header,
                                            constant,
                                            new_value,
                                            &storage::give_permission(&borrow_global<Access>(OWNER).storage_access)
                                        );
                                    } else {
                                        storage::handle_registration_multi(
                                            user,
                                            header,
                                            constant,
                                            new_value,
                                            value_type,
                                            editable,
                                            &storage::give_permission(&borrow_global<Access>(OWNER).storage_access)
                                        );
                                    };
                                } else if (*_type == utf8(b"Capability")) {
                                    if (_isChange) {
                                        capabilities::remove_capability_multi(
                                            user,
                                            to_adress_multi(new_value),
                                            header,
                                            constant,
                                            &capabilities::give_permission(&borrow_global<Access>(OWNER).capabilities_access)
                                        );
                                    } else {
                                        capabilities::create_capability_multi(
                                            user,
                                            to_adress_multi(new_value),
                                            header,
                                            constant,
                                            editable,
                                            &capabilities::give_permission(&borrow_global<Access>(OWNER).capabilities_access)
                                        );
                                    };
                                } else if (*_type == utf8(b"Function")) {
                                    if (_isChange) {
                                        functions::consume_function_multi (
                                            user,
                                            header,
                                            constant,
                                            &functions::give_permission(&borrow_global<Access>(OWNER).function_access)
                                        );
                                    } else {
                                        functions::register_function_multi(
                                            user,
                                            header,
                                            constant,
                                            &functions::give_permission(&borrow_global<Access>(OWNER).function_access)
                                        );
                                    };
                                };
                            };
                        };
                    };
                };

            let data = vector[
                Event::create_data_struct(utf8(b"proposal_id"), utf8(b"u64"), bcs::to_bytes(&id)),
                Event::create_data_struct(utf8(b"type"), utf8(b"vector<string>"), bcs::to_bytes(&type)),
                Event::create_data_struct(utf8(b"proposer"), utf8(b"address"), bcs::to_bytes(&proposer)),
                Event::create_data_struct(utf8(b"duration"), utf8(b"u64"), bcs::to_bytes(&duration)),
                Event::create_data_struct(utf8(b"header"), utf8(b"vector<string>"), bcs::to_bytes(&header)),
                Event::create_data_struct(utf8(b"constant"), utf8(b"vector<string>"), bcs::to_bytes(&constant)),
                Event::create_data_struct(utf8(b"new_value"), utf8(b"vector<vector<u8>>"), bcs::to_bytes(&new_value)),
                Event::create_data_struct(utf8(b"value_type"), utf8(b"vector<string>"), bcs::to_bytes(&value_type)),
                Event::create_data_struct(utf8(b"isChange"), utf8(b"vector<bool>"), bcs::to_bytes(&isChange)),
                Event::create_data_struct(utf8(b"editable"), utf8(b"vector<bool>"), bcs::to_bytes(&editable)),
                Event::create_data_struct(utf8(b"yes"), utf8(b"u256"), bcs::to_bytes(&yes)),
                Event::create_data_struct(utf8(b"no"), utf8(b"u256"), bcs::to_bytes(&no)),
                Event::create_data_struct(utf8(b"result"), utf8(b"u8"), bcs::to_bytes(&result)),
            ];

            Event::emit_governance_event(utf8(b"Proposal Result"), data);
            len = idx;
            };
        }
    }
    // --- vote: ensure voter_addr defined, check table, then add ---
    // vote: make len mutable and use voter_addr local
    public entry fun vote(user: &signer, shared_storage_name: String, proposal_id: u64, isYes: bool) acquires PendingProposals {
        TokensShared::assert_is_owner(bcs::to_bytes(&signer::address_of(user)), shared_storage_name);
        let registry = borrow_global_mut<PendingProposals>(OWNER);
        let len = vector::length(&registry.proposals);
        let (_, _, _, _, _, _, _, _, vote_value, _, _) = Margin::get_user_total_usd(shared_storage_name);

        while (len > 0) {
            len = len - 1;
            let proposal = vector::borrow_mut(&mut registry.proposals, len);
            if (proposal.id == proposal_id) {
                let has_voted = vector::contains(&proposal.voters, &shared_storage_name);
                assert!(!has_voted, ERROR_ALREADY_VOTED);

                if (isYes) {
                    proposal.yes = proposal.yes + vote_value;
                } else {
                    proposal.no = proposal.no + vote_value;
                };

                vector::push_back(&mut proposal.voters, shared_storage_name);
            };
        };

            let data = vector[
                // Items from the event top-level fields
                Event::create_data_struct(utf8(b"sender"), utf8(b"vector<u8>"), bcs::to_bytes(&signer::address_of(user))),
                Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared_storage_name)),
                Event::create_data_struct(utf8(b"proposal_id"), utf8(b"u64"), bcs::to_bytes(&proposal_id)),
                Event::create_data_struct(utf8(b"vote_weight"), utf8(b"u64"), bcs::to_bytes(&vote_value)),
                Event::create_data_struct(utf8(b"isYes"), utf8(b"bool"), bcs::to_bytes(&isYes)),
            ];

            Event::emit_governance_event(utf8(b"Vote"), data)

    }

// Modular Interface

    public entry fun m_propose(validator: &signer, sub_owner: vector<u8>, type: vector<String>, isChange: vector<bool>, header: vector<String>, constant_name: vector<String>, new_value: vector<vector<u8>>, value_type: vector<String>, duration: u64, editable: vector<bool>) acquires PendingProposals, ProposalCount {
        TokensShared::assert_is_owner(sub_owner, shared_storage_name);
        assert_allowed_type(type);
        assert!(!capabilities::assert_wallet_capability(signer::address_of(proposer), utf8(b"QiaraGovernance"), utf8(b"BLACKLIST")), ERROR_BLACKLISTED);
        let registry = borrow_global_mut<PendingProposals>(OWNER);
        let count_ref = borrow_global_mut<ProposalCount>(OWNER);
        let proposal_id = count_ref.count;

        let proposal = make_proposal(proposal_id, type, sub_owner, duration, header, constant_name, isChange, editable, new_value, value_type);
        vector::push_back(&mut registry.proposals, proposal);

        count_ref.count = count_ref.count + 1;
    }

    public entry fun m_vote(validator: &signer, sub_owner: vector<u8>, shared_storage_name: String, proposal_id: u64, isYes: bool) acquires PendingProposals {
        TokensShared::assert_is_owner(sub_owner, shared_storage_name);
        let registry = borrow_global_mut<PendingProposals>(OWNER);
        let len = vector::length(&registry.proposals);
        let (_, _, _, _, _, _, _, _, vote_value, _, _) = Margin::get_user_total_usd(shared_storage_name);

        while (len > 0) {
            len = len - 1;
            let proposal = vector::borrow_mut(&mut registry.proposals, len);
            if (proposal.id == proposal_id) {
                let has_voted = vector::contains(&proposal.voters, &shared_storage_name);
                assert!(!has_voted, ERROR_ALREADY_VOTED);

                if (isYes) {
                    proposal.yes = proposal.yes + vote_value;
                } else {
                    proposal.no = proposal.no + vote_value;
                };

                vector::push_back(&mut proposal.voters, shared_storage_name);
            };
        };

            let data = vector[
                // Items from the event top-level fields
                Event::create_data_struct(utf8(b"validator"), utf8(b"vector<u8>"), bcs::to_bytes(&signer::address_of(validator))),
                Event::create_data_struct(utf8(b"sender"), utf8(b"vector<u8>"), bcs::to_bytes(&sub_owner)),
                Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared_storage_name)),
                Event::create_data_struct(utf8(b"proposal_id"), utf8(b"u64"), bcs::to_bytes(&proposal_id)),
                Event::create_data_struct(utf8(b"vote_weight"), utf8(b"u64"), bcs::to_bytes(&vote_value)),
                Event::create_data_struct(utf8(b"isYes"), utf8(b"bool"), bcs::to_bytes(&isYes)),
            ];

            Event::emit_governance_event(utf8(b"Vote"), data)

    }


    fun to_adress_multi(addresses: vector<vector<u8>>): vector<address>{
        let len = vector::length(&addresses);
        let vect = vector::empty<address>();
        while (len > 0) {
            let address = from_bcs::to_address(*vector::borrow(&addresses, len-1));
            len = len - 1;
            vector::push_back(&mut vect, address);
        };
        vect
    }

    fun assert_allowed_type(types: vector<String>){
        let len = vector::length(&types);
        let i = 0;
        while (i < len) {
            let type = vector::borrow(&types, i);
            assert!(*type == utf8(b"Constant") || *type == utf8(b"Capability") || *type == utf8(b"Function"), ERROR_INVALID_PROPOSAL_TYPE);
            i = i + 1;
        }
    }

    #[view]
    public fun view_pending_proposals(): vector<Proposal> acquires PendingProposals{
        let db = borrow_global<PendingProposals>(OWNER);
        return db.proposals
    }
}
