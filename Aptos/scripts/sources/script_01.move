script {
    use dev::QiaraGovernanceV45;
    use dev::QiaraStorageV26as storage;
    use std::string::utf8;
    use std::bcs;

    fun main(proposal_id: u64) {
        // 1. Resolve governance to obtain the DAO signer
        let dao_signer = QiaraGovernanceV45::resolve(proposal_id);

        // 2. Execute desired actions with the DAO authority
        storage::change_constant(
            &dao_signer,
            utf8(b"QiaraToken"),
            utf8(b"BRIDGE_TAX_FEE"),
            bcs::to_bytes(&250_000) // e.g. new fee value
        );
    }
}