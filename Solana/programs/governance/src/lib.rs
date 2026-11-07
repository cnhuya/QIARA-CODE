use anchor_lang::prelude::*;
use events; // Shared dynamic events library

declare_id!("2rZG6L4StdcgD9a97NgEp1ST5xnQiKjQHscSAXcAw9pF");

#[program]
pub mod governance_interface {
    use super::*;

    pub fn m_propose(ctx: Context<MPropose>, params: ProposeParams) -> Result<()> {
        let sender = ctx.accounts.sender.key();

        let data = vec![
            events::create_data_struct(
                "sender".to_string(),
                "address".to_string(),
                sender.to_bytes().to_vec(),
            ),
            events::create_data_struct(
                "sub_owner".to_string(),
                "bytes".to_string(),
                params.sub_owner,
            ),
            events::create_data_struct(
                "shared".to_string(),
                "string".to_string(),
                params.shared_storage_name.as_bytes().to_vec(),
            ),
            events::create_data_struct(
                "name".to_string(),
                "string".to_string(),
                params.name.as_bytes().to_vec(),
            ),
            events::create_data_struct(
                "desc".to_string(),
                "string".to_string(),
                params.desc.as_bytes().to_vec(),
            ),
            events::create_data_struct(
                "source_code".to_string(),
                "string".to_string(),
                params.source_code.as_bytes().to_vec(),
            ),
            events::create_data_struct(
                "duration".to_string(),
                "u64".to_string(),
                params.duration.to_le_bytes().to_vec(),
            ),
            events::create_data_struct(
                "execution_hash".to_string(),
                "bytes".to_string(),
                params.execution_hash,
            ),
        ];

        events::emit_event("Modular Governance Proposal".to_string(), data)?;
        Ok(())
    }

    pub fn m_vote(
        ctx: Context<MVote>,
        sub_owner: Vec<u8>,
        shared_storage_name: String,
        proposal_id: u64,
        is_yes: bool,
    ) -> Result<()> {
        let sender = ctx.accounts.sender.key();

        let data = vec![
            events::create_data_struct(
                "sender".to_string(),
                "address".to_string(),
                sender.to_bytes().to_vec(),
            ),
            events::create_data_struct(
                "sub_owner".to_string(),
                "bytes".to_string(),
                sub_owner,
            ),
            events::create_data_struct(
                "shared".to_string(),
                "string".to_string(),
                shared_storage_name.as_bytes().to_vec(),
            ),
            events::create_data_struct(
                "proposal_id".to_string(),
                "u64".to_string(),
                proposal_id.to_le_bytes().to_vec(),
            ),
            events::create_data_struct(
                "is_yes".to_string(),
                "bool".to_string(),
                vec![if is_yes { 1 } else { 0 }],
            ),
        ];

        events::emit_event("Modular Governance Vote".to_string(), data)?;
        Ok(())
    }
}

// ---------------------------------------------------------
// Instruction Parameter Structs
// ---------------------------------------------------------

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Debug)]
pub struct ProposeParams {
    pub sub_owner: Vec<u8>,
    pub shared_storage_name: String,
    pub name: String,
    pub desc: String,
    pub source_code: String,
    pub duration: u64,
    pub execution_hash: Vec<u8>,
}

// ---------------------------------------------------------
// Accounts Contexts
// ---------------------------------------------------------

#[derive(Accounts)]
pub struct MPropose<'info> {
    #[account(mut)]
    pub sender: Signer<'info>,
}

#[derive(Accounts)]
pub struct MVote<'info> {
    #[account(mut)]
    pub sender: Signer<'info>,
}