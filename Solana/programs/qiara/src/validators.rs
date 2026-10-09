use anchor_lang::prelude::*;
use crate::error::QiaraError;
use crate::state::*;
use crate::utils::verify_signatures;

pub fn handle_initialize_validator_state(ctx: Context<InitializeValidatorState>) -> Result<()> {
    let state = &mut ctx.accounts.validator_state;
    state.validators = Vec::new();
    Ok(())
}

pub fn handle_stage_signatures(
    ctx: Context<StageSignatures>,
    message_hash: [u8; 32],
    signatures: Vec<[u8; 65]>,
) -> Result<()> {
    let buf = &mut ctx.accounts.sig_buffer;
    buf.message_hash = message_hash;
    buf.signatures = signatures;
    Ok(())
}
/// Matches EVM stageValidator(): stages validator status for effective_epoch (current_epoch + 1) using universal BCS payload
pub fn handle_add_pending_pubkey(
    ctx: Context<AddPendingPubkey>,
    message_hash: [u8; 32],
    raw_payload: Vec<u8>,
) -> Result<()> {
    // 1. Assert canonical keccak256 hash
    let computed_hash = anchor_lang::solana_program::keccak::hash(&raw_payload).to_bytes();
    require!(message_hash == computed_hash, QiaraError::InvalidActionHash);

    let current_epoch = ctx.accounts.epoch_config.get_current_epoch()?;

    // 2. Verify validator signatures against current epoch validator set
    let signatures = &ctx.accounts.sig_buffer.signatures;
    verify_signatures(
        &ctx.accounts.validator_state,
        &ctx.accounts.registry,
        signatures,
        &raw_payload,
        current_epoch,
    )?;

    // 3. Unpack canonical Move-compatible BCS payload
    let payload: ValidatorRotationPayload = bcs::from_bytes(&raw_payload)
        .map_err(|_| error!(QiaraError::InvalidPayloadEncoding))?;

    // 4. Stage validator to take effect next epoch (effective_epoch = current_epoch + 1)
    let effective_epoch = current_epoch + 1;
    let val_state = &mut ctx.accounts.validator_state;

    if let Some(val) = val_state.validators.iter_mut().find(|v| v.pubkey == payload.pubkey) {
        // Auto-promote previous status if already matured (exact EVM match)
        if val.effective_epoch != 0 && current_epoch >= val.effective_epoch {
            val.is_active = val.target_status;
        }
        val.target_status = !payload.is_removal;
        val.effective_epoch = effective_epoch;
    } else {
        val_state.validators.push(TimedValidator {
            pubkey: payload.pubkey,
            is_active: false,
            target_status: !payload.is_removal,
            effective_epoch,
        });
    }

    Ok(())
}

/// Admin fallback matching EVM setActiveValidatorDirect()
pub fn handle_add_active_pubkey_direct(
    ctx: Context<AddActivePubkeyDirect>,
    pubkey: Vec<u8>,
    is_active: bool,
) -> Result<()> {
    let val_state = &mut ctx.accounts.validator_state;
    if let Some(val) = val_state.validators.iter_mut().find(|v| v.pubkey == pubkey) {
        val.is_active = is_active;
        val.effective_epoch = 0;
        val.target_status = false;
    } else {
        val_state.validators.push(TimedValidator {
            pubkey,
            is_active,
            target_status: false,
            effective_epoch: 0,
        });
    }
    Ok(())
}

// Account Contexts
#[derive(Accounts)]
pub struct InitializeValidatorState<'info> {
    #[account(init, payer = admin, space = 8 + 4000)]
    pub validator_state: Account<'info, ValidatorState>,
    #[account(mut)]
    pub admin: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(message_hash: [u8; 32], signatures: Vec<[u8; 65]>)]
pub struct StageSignatures<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    #[account(
        init,
        payer = payer,
        space = 8 + 32 + 4 + (signatures.len() * 65),
        seeds = [b"sig_buffer", message_hash.as_ref()],
        bump
    )]
    pub sig_buffer: Account<'info, SignatureBuffer>,

    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(message_hash: [u8; 32], raw_payload: Vec<u8>)]
pub struct AddPendingPubkey<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    #[account(
        mut,
        close = payer,
        seeds = [b"sig_buffer", message_hash.as_ref()],
        bump,
        constraint = sig_buffer.message_hash == message_hash @ QiaraError::InvalidActionHash
    )]
    pub sig_buffer: Account<'info, SignatureBuffer>,

    #[account(mut)]
    pub validator_state: Account<'info, ValidatorState>,
    pub registry: Account<'info, Registry>,
    pub epoch_config: Account<'info, EpochConfig>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct AddActivePubkeyDirect<'info> {
    #[account(mut)]
    pub validator_state: Account<'info, ValidatorState>,
    pub admin: Signer<'info>,
}