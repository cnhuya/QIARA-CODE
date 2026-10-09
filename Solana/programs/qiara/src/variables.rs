use anchor_lang::prelude::*;
use crate::error::QiaraError;
use crate::state::*;
use crate::utils::verify_signatures;

pub fn handle_initialize_epoch(
    ctx: Context<InitializeEpoch>,
    genesis_timestamp_sec: u64,
    epoch_duration_sec: u64,
) -> Result<()> {
    let clock = Clock::get()?;
    let now_ms = (clock.unix_timestamp * 1000) as u64;
    let genesis_ms = genesis_timestamp_sec * 1000;

    require!(genesis_ms <= now_ms, QiaraError::GenesisInFuture);
    require!(epoch_duration_sec > 0, QiaraError::DurationIsZero);

    let config = &mut ctx.accounts.config;
    config.genesis_timestamp_ms = genesis_ms;
    config.epoch_duration_ms = epoch_duration_sec * 1000;
    config.authority = ctx.accounts.authority.key();
    Ok(())
}

pub fn handle_initialize_registry(ctx: Context<InitializeRegistry>) -> Result<()> {
    let registry_acc = &mut ctx.accounts.registry;
    registry_acc.is_locked = false;
    registry_acc.headers = Vec::new();
    Ok(())
}

/// Admin direct update matching EVM setActiveVariableDirect()
pub fn handle_admin_add_variable(
    ctx: Context<AdminAddVariable>,
    header: String,
    name: String,
    data: Vec<u8>,
) -> Result<()> {
    let registry_acc = &mut ctx.accounts.registry;
    require!(!registry_acc.is_locked, QiaraError::RegistryLocked);

    if let Some(head) = registry_acc.headers.iter_mut().find(|h| h.header == header) {
        if let Some(var) = head.variables.iter_mut().find(|v| v.name == name) {
            var.active_data = data;
            var.pending_data.clear();
            var.effective_epoch = 0;
            return Ok(());
        }
        head.variables.push(TimedVariable {
            name,
            active_data: data,
            pending_data: Vec::new(),
            effective_epoch: 0,
        });
    } else {
        registry_acc.headers.push(VariableHeaderEntry {
            header,
            variables: vec![TimedVariable {
                name,
                active_data: data,
                pending_data: Vec::new(),
                effective_epoch: 0,
            }],
        });
    }

    Ok(())
}
/// Matches EVM stageVariable(): stages variable update to take effect next epoch using universal BCS payload
pub fn handle_friend_add_variable(
    ctx: Context<FriendAddVariable>,
    message_hash: [u8; 32],
    raw_payload: Vec<u8>,
) -> Result<()> {
    // 1. Assert canonical keccak256 hash
    let computed_hash = anchor_lang::solana_program::keccak::hash(&raw_payload).to_bytes();
    require!(message_hash == computed_hash, QiaraError::InvalidActionHash);

    let current_epoch = ctx.accounts.epoch_config.get_current_epoch()?;
    let registry_acc = &mut ctx.accounts.registry;
    require!(!registry_acc.is_locked, QiaraError::RegistryLocked);

    // 2. Verify validator signatures against current epoch validator set
    let signatures = &ctx.accounts.sig_buffer.signatures;
    verify_signatures(
        &ctx.accounts.validator_state,
        registry_acc,
        signatures,
        &raw_payload,
        current_epoch,
    )?;

    // 3. Deserialize canonical Move-compatible BCS bytes
    // (Ensures 100% byte-for-byte alignment across Sui, Aptos, EVM, and Solana)
    let payload: VariablePayload = bcs::from_bytes(&raw_payload)
        .map_err(|_| error!(QiaraError::InvalidPayloadEncoding))?;

    // 4. Stage variable to activate at effective_epoch (current_epoch + 1)
    let effective_epoch = current_epoch + 1;

    if let Some(head) = registry_acc.headers.iter_mut().find(|h| h.header == payload.header) {
        if let Some(var) = head.variables.iter_mut().find(|v| v.name == payload.name) {
            // Auto-promote matured value before overwriting (exact EVM match)
            if var.effective_epoch != 0 && current_epoch >= var.effective_epoch {
                var.active_data = std::mem::take(&mut var.pending_data);
            }
            var.pending_data = payload.data;
            var.effective_epoch = effective_epoch;
            return Ok(());
        }
        head.variables.push(TimedVariable {
            name: payload.name,
            active_data: Vec::new(),
            pending_data: payload.data,
            effective_epoch,
        });
    } else {
        registry_acc.headers.push(VariableHeaderEntry {
            header: payload.header,
            variables: vec![TimedVariable {
                name: payload.name,
                active_data: Vec::new(),
                pending_data: payload.data,
                effective_epoch,
            }],
        });
    }

    Ok(())
}

pub fn handle_lock_registry(ctx: Context<LockRegistry>) -> Result<()> {
    ctx.accounts.registry.is_locked = true;
    Ok(())
}

// Account Contexts
#[derive(Accounts)]
pub struct InitializeEpoch<'info> {
    #[account(init, payer = authority, space = 8 + 8 + 8 + 32)]
    pub config: Account<'info, EpochConfig>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct InitializeRegistry<'info> {
    #[account(init, payer = admin, space = 8 + 8000)]
    pub registry: Account<'info, Registry>,
    #[account(mut)]
    pub admin: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct AdminAddVariable<'info> {
    #[account(mut)]
    pub registry: Account<'info, Registry>,
    pub admin: Signer<'info>,
}

#[derive(Accounts)]
#[instruction(message_hash: [u8; 32], raw_payload: Vec<u8>)]
pub struct FriendAddVariable<'info> {
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
    pub registry: Account<'info, Registry>,
    pub validator_state: Account<'info, ValidatorState>,
    pub epoch_config: Account<'info, EpochConfig>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct LockRegistry<'info> {
    #[account(mut)]
    pub registry: Account<'info, Registry>,
    pub admin: Signer<'info>,
}