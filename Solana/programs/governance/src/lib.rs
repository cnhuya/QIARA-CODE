use anchor_lang::prelude::*;
use events; // Shared dynamic events library

declare_id!("2rZG6L4StdcgD9a97NgEp1ST5xnQiKjQHscSAXcAw9pF");

#[program]
pub mod governance_interface {
    use super::*;

    /// 1:1 equivalent to `m_propose(ProposeParams calldata params)`
    pub fn m_propose(ctx: Context<MPropose>, params: ProposeParams) -> Result<()> {
        let sender = ctx.accounts.sender.key();

        // Pack proposal parameters into the dynamic event vector structure
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
                "type".to_string(),
                "string[]".to_string(),
                params.type_.try_to_vec()?,
            ),
            events::create_data_struct(
                "isChange".to_string(),
                "bool[]".to_string(),
                params.is_change.try_to_vec()?,
            ),
            events::create_data_struct(
                "isMultichain".to_string(),
                "bool[]".to_string(),
                params.is_multichain.try_to_vec()?,
            ),
            events::create_data_struct(
                "header".to_string(),
                "string[]".to_string(),
                params.header.try_to_vec()?,
            ),
            events::create_data_struct(
                "constant_name".to_string(),
                "string[]".to_string(),
                params.constant_name.try_to_vec()?,
            ),
            events::create_data_struct(
                "new_value".to_string(),
                "bytes[]".to_string(),
                params.new_value.try_to_vec()?,
            ),
            events::create_data_struct(
                "value_type".to_string(),
                "string[]".to_string(),
                params.value_type.try_to_vec()?,
            ),
            events::create_data_struct(
                "duration".to_string(),
                "u64".to_string(),
                params.duration.to_le_bytes().to_vec(),
            ),
            events::create_data_struct(
                "editable".to_string(),
                "bool[]".to_string(),
                params.editable.try_to_vec()?,
            ),
        ];

        // Emit the event via the shared library
        events::emit_event("Modular Governance Proposal".to_string(), data)?;

        Ok(())
    }

    /// 1:1 equivalent to `m_vote(...)`
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

        // Emit the event via the shared library
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
    pub type_: Vec<String>,
    pub is_change: Vec<bool>,
    pub is_multichain: Vec<bool>,
    pub header: Vec<String>,
    pub constant_name: Vec<String>,
    pub new_value: Vec<Vec<u8>>,
    pub value_type: Vec<String>,
    pub duration: u64,
    pub editable: Vec<bool>,
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