use anchor_lang::prelude::*;

pub mod error;
pub mod state;
pub mod utils;
pub mod variables;
pub mod validators;
pub mod registry;
pub mod token;

pub use error::*;
pub use state::*;
pub use variables::*;
pub use validators::*;
pub use registry::*;
pub use token::*;

declare_id!("4DBj1qh8KTC7TNgEenyxSmNc7YK3ceyaMzhYASm159Uo");

#[program]
pub mod qiara {
    use super::*;

    // --- Epoch & Registry Instructions ---
    pub fn initialize_epoch(
        ctx: Context<InitializeEpoch>,
        genesis_timestamp_sec: u64,
        epoch_duration_sec: u64,
    ) -> Result<()> {
        variables::handle_initialize_epoch(ctx, genesis_timestamp_sec, epoch_duration_sec)
    }

    pub fn initialize_registry(ctx: Context<InitializeRegistry>) -> Result<()> {
        variables::handle_initialize_registry(ctx)
    }

    pub fn admin_add_variable(
        ctx: Context<AdminAddVariable>,
        header: String,
        name: String,
        data: Vec<u8>,
    ) -> Result<()> {
        variables::handle_admin_add_variable(ctx, header, name, data)
    }

pub fn friend_add_variable(
        ctx: Context<FriendAddVariable>,
        message_hash: [u8; 32],
        raw_payload: Vec<u8>,
    ) -> Result<()> {
        variables::handle_friend_add_variable(ctx, message_hash, raw_payload)
    }

    pub fn lock_registry(ctx: Context<LockRegistry>) -> Result<()> {
        variables::handle_lock_registry(ctx)
    }

    // --- Validator Management ---
    pub fn initialize_validator_state(ctx: Context<InitializeValidatorState>) -> Result<()> {
        validators::handle_initialize_validator_state(ctx)
    }

    pub fn stage_signatures(
        ctx: Context<StageSignatures>,
        message_hash: [u8; 32],
        signatures: Vec<[u8; 65]>,
    ) -> Result<()> {
        validators::handle_stage_signatures(ctx, message_hash, signatures)
    }

pub fn add_pending_pubkey(
        ctx: Context<AddPendingPubkey>,
        message_hash: [u8; 32],
        raw_payload: Vec<u8>,
    ) -> Result<()> {
        validators::handle_add_pending_pubkey(ctx, message_hash, raw_payload)
    }

pub fn add_active_pubkey_direct(
        ctx: Context<AddActivePubkeyDirect>,
        pubkey: Vec<u8>,
        is_active: bool,
    ) -> Result<()> {
        validators::handle_add_active_pubkey_direct(ctx, pubkey, is_active)
    }

    // --- Provider Registry ---
    pub fn initialize_provider_registry(
        ctx: Context<InitializeProviderRegistry>,
        chain: String,
    ) -> Result<()> {
        registry::handle_initialize(ctx, chain)
    }

    pub fn dev_add_tokens(
        ctx: Context<DevAction>,
        provider: String,
        tokens: Vec<String>,
    ) -> Result<()> {
        registry::handle_dev_add_tokens(ctx, provider, tokens)
    }

    pub fn dev_set_token_address(
        ctx: Context<DevAction>,
        token: String,
        token_address: String,
    ) -> Result<()> {
        registry::handle_dev_set_token_address(ctx, token, token_address)
    }

    pub fn revoke_dev_access(ctx: Context<DevAction>) -> Result<()> {
        registry::handle_revoke_dev_access(ctx)
    }

    pub fn set_chain(ctx: Context<DevAction>, chain: String) -> Result<()> {
        registry::handle_set_chain(ctx, chain)
    }
pub fn update_tokens(
        ctx: Context<UpdateTokensAction>,
        message_hash: [u8; 32],
        raw_payload: Vec<u8>,
    ) -> Result<()> {
        registry::handle_update_tokens(ctx, message_hash, raw_payload)
    }

    pub fn update_token_address(
        ctx: Context<UpdateTokenAddressAction>,
        message_hash: [u8; 32],
        raw_payload: Vec<u8>,
    ) -> Result<()> {
        registry::handle_update_token_address(ctx, message_hash, raw_payload)
    }

    // --- Qiara Token ---
    pub fn initialize_token(
        ctx: Context<InitializeToken>,
        variable_header: String,
        chain: String,
        chain_id: u32,
        name: String,
        symbol: String,
        uri: String,
    ) -> Result<()> {
        token::handle_initialize_token(ctx, variable_header, chain, chain_id, name, symbol, uri)
    }

    pub fn request_bridge(
        ctx: Context<RequestBridge>,
        shared: String,
        destination_chain: String,
        amount: u64,
    ) -> Result<()> {
        token::handle_request_bridge(ctx, shared, destination_chain, amount)
    }

    pub fn consensus_mint(
        ctx: Context<ConsensusMint>,
        nullifier: [u8; 32],
        raw_payload: Vec<u8>,
    ) -> Result<()> {
        token::handle_consensus_mint(ctx, nullifier, raw_payload)
    }

    pub fn transfer_with_fee(ctx: Context<TransferWithFee>, amount: u64) -> Result<()> {
        token::handle_transfer_with_fee(ctx, amount)
    }

    pub fn set_fee_exempt(ctx: Context<SetFeeExempt>, exempt: bool) -> Result<()> {
        token::handle_set_fee_exempt(ctx, exempt)
    }

    pub fn set_fee_recipient(ctx: Context<SetFeeRecipient>, new_recipient: Pubkey) -> Result<()> {
        token::handle_set_fee_recipient(ctx, new_recipient)
    }
}