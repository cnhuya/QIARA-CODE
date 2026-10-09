use anchor_lang::prelude::*;
use anchor_lang::solana_program::keccak;
use crate::error::QiaraError;
use crate::state::*;
use crate::utils::verify_signatures;

// --- Admin & Dev Handlers ---

pub fn handle_initialize(ctx: Context<InitializeProviderRegistry>, chain: String) -> Result<()> {
    let reg = &mut ctx.accounts.provider_registry;
    reg.admin = ctx.accounts.admin.key();
    reg.chain = if chain.is_empty() { "Solana".to_string() } else { chain };
    reg.dev_access_revoked = false;
    reg.providers = Vec::new();
    reg.provider_tokens = Vec::new();
    reg.token_addresses = Vec::new();
    reg.bump = ctx.bumps.provider_registry;
    Ok(())
}

pub fn handle_dev_add_tokens(
    ctx: Context<DevAction>,
    provider: String,
    tokens: Vec<String>,
) -> Result<()> {
    let reg = &mut ctx.accounts.provider_registry;
    require!(!reg.dev_access_revoked, QiaraError::DevAccessRevoked);
    internal_insert_tokens(reg, &provider, &tokens);

    emit!(VaultEvent {
        action: "TokensUpdated".to_string(),
        data: vec![
            create_data("provider", "string", provider.as_bytes().to_vec()),
            create_data("tokens", "string", tokens.join(",").as_bytes().to_vec()),
            create_data("is_add", "bool", vec![1]),
        ],
    });

    Ok(())
}

pub fn handle_dev_set_token_address(
    ctx: Context<DevAction>,
    token: String,
    token_address: String,
) -> Result<()> {
    let reg = &mut ctx.accounts.provider_registry;
    require!(!reg.dev_access_revoked, QiaraError::DevAccessRevoked);
    internal_set_token_address(reg, &token, &token_address);

    emit!(VaultEvent {
        action: "TokenAddressUpdated".to_string(),
        data: vec![
            create_data("token", "string", token.as_bytes().to_vec()),
            create_data("token_address", "string", token_address.as_bytes().to_vec()),
        ],
    });

    Ok(())
}

pub fn handle_revoke_dev_access(ctx: Context<DevAction>) -> Result<()> {
    let reg = &mut ctx.accounts.provider_registry;
    require!(!reg.dev_access_revoked, QiaraError::DevAccessRevoked);
    reg.dev_access_revoked = true;

    emit!(VaultEvent {
        action: "DevAccessPermanentlyRevoked".to_string(),
        data: vec![],
    });

    Ok(())
}

pub fn handle_set_chain(ctx: Context<DevAction>, chain: String) -> Result<()> {
    ctx.accounts.provider_registry.chain = chain;
    Ok(())
}

// --- Cross-Chain Consensus Handlers (Uniform Style) ---

pub fn handle_update_tokens(
    ctx: Context<UpdateTokensAction>,
    message_hash: [u8; 32],
    raw_payload: Vec<u8>,
) -> Result<()> {
    // 1. Verify that message_hash matches raw_payload
    let computed_hash = keccak::hash(&raw_payload).to_bytes();
    require!(message_hash == computed_hash, QiaraError::InvalidActionHash);

    // 2. Verify signatures from sig_buffer
    let current_epoch = ctx.accounts.epoch_config.get_current_epoch()?;
    let signatures = &ctx.accounts.sig_buffer.signatures;
    verify_signatures(
        &ctx.accounts.validator_state,
        &ctx.accounts.var_reg,
        signatures,
        &raw_payload,
        current_epoch,
    )?;

    // 3. Unpack typed payload struct
    let mut slice: &[u8] = &raw_payload[..];
    let payload = UpdateTokensPayload::deserialize(&mut slice)
        .map_err(|_| error!(QiaraError::InvalidPayloadEncoding))?;
    require!(slice.is_empty(), QiaraError::TrailingDataInPayload);

    // 4. Mark action hash as consumed (replay protection)
    ctx.accounts.action_record.action_hash = message_hash;

    // 5. Update state
    let reg = &mut ctx.accounts.provider_registry;
    if payload.is_add {
        internal_insert_tokens(reg, &payload.provider, &payload.tokens);
    } else {
        internal_remove_tokens(reg, &payload.provider, &payload.tokens);
    }

    // 6. Emit exact VaultEvent
    emit!(VaultEvent {
        action: "TokensUpdated".to_string(),
        data: vec![
            create_data("provider", "string", payload.provider.as_bytes().to_vec()),
            create_data("tokens", "string", payload.tokens.join(",").as_bytes().to_vec()),
            create_data("is_add", "bool", vec![if payload.is_add { 1 } else { 0 }]),
            create_data("nonce", "u64", payload.nonce.to_le_bytes().to_vec()),
            create_data("hash", "bytes32", message_hash.to_vec()),
        ],
    });

    Ok(())
}

pub fn handle_update_token_address(
    ctx: Context<UpdateTokenAddressAction>,
    message_hash: [u8; 32],
    raw_payload: Vec<u8>,
) -> Result<()> {
    // 1. Verify that message_hash matches raw_payload
    let computed_hash = keccak::hash(&raw_payload).to_bytes();
    require!(message_hash == computed_hash, QiaraError::InvalidActionHash);

    // 2. Verify signatures from sig_buffer
    let current_epoch = ctx.accounts.epoch_config.get_current_epoch()?;
    let signatures = &ctx.accounts.sig_buffer.signatures;
    verify_signatures(
        &ctx.accounts.validator_state,
        &ctx.accounts.var_reg,
        signatures,
        &raw_payload,
        current_epoch,
    )?;

    // 3. Unpack typed payload struct
    let mut slice: &[u8] = &raw_payload[..];
    let payload = UpdateTokenAddressPayload::deserialize(&mut slice)
        .map_err(|_| error!(QiaraError::InvalidPayloadEncoding))?;
    require!(slice.is_empty(), QiaraError::TrailingDataInPayload);

    // 4. Mark action hash as consumed (replay protection)
    ctx.accounts.action_record.action_hash = message_hash;

    // 5. Update state
    let reg = &mut ctx.accounts.provider_registry;
    internal_set_token_address(reg, &payload.token, &payload.token_address);

    // 6. Emit exact VaultEvent
    emit!(VaultEvent {
        action: "TokenAddressUpdated".to_string(),
        data: vec![
            create_data("token", "string", payload.token.as_bytes().to_vec()),
            create_data("token_address", "string", payload.token_address.as_bytes().to_vec()),
            create_data("nonce", "u64", payload.nonce.to_le_bytes().to_vec()),
            create_data("hash", "bytes32", message_hash.to_vec()),
        ],
    });

    Ok(())
}

// --- Helpers ---

fn internal_insert_tokens(reg: &mut ProviderRegistry, provider: &str, tokens: &[String]) {
    if !reg.providers.iter().any(|p| p.eq_ignore_ascii_case(provider)) {
        reg.providers.push(provider.to_string());
    }

    if let Some(entry) = reg.provider_tokens.iter_mut().find(|pt| pt.provider.eq_ignore_ascii_case(provider)) {
        for t in tokens {
            if !entry.tokens.iter().any(|tok| tok.eq_ignore_ascii_case(t)) {
                entry.tokens.push(t.clone());
            }
        }
    } else {
        let mut new_tokens = Vec::new();
        for t in tokens {
            if !new_tokens.iter().any(|tok: &String| tok.eq_ignore_ascii_case(t)) {
                new_tokens.push(t.clone());
            }
        }
        reg.provider_tokens.push(ProviderTokensEntry {
            provider: provider.to_string(),
            tokens: new_tokens,
        });
    }
}

fn internal_remove_tokens(reg: &mut ProviderRegistry, provider: &str, tokens: &[String]) {
    if let Some(entry) = reg.provider_tokens.iter_mut().find(|pt| pt.provider.eq_ignore_ascii_case(provider)) {
        for t in tokens {
            if let Some(pos) = entry.tokens.iter().position(|tok| tok.eq_ignore_ascii_case(t)) {
                entry.tokens.remove(pos);
            }
        }
    }
}

fn internal_set_token_address(reg: &mut ProviderRegistry, token: &str, token_address: &str) {
    if let Some(entry) = reg.token_addresses.iter_mut().find(|ta| ta.token.eq_ignore_ascii_case(token)) {
        entry.address = token_address.to_string();
    } else {
        reg.token_addresses.push(TokenAddressEntry {
            token: token.to_string(),
            address: token_address.to_string(),
        });
    }
}

// --- Accounts Contexts ---

#[derive(Accounts)]
#[instruction(chain: String)]
pub struct InitializeProviderRegistry<'info> {
    #[account(
        init,
        payer = admin,
        space = 8 + 32 + 36 + 1 + 2048,
        seeds = [b"provider_registry"],
        bump
    )]
    pub provider_registry: Account<'info, ProviderRegistry>,

    #[account(mut)]
    pub admin: Signer<'info>,

    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct DevAction<'info> {
    #[account(
        mut,
        seeds = [b"provider_registry"],
        bump = provider_registry.bump,
        has_one = admin @ QiaraError::UnauthorizedAdmin,
        realloc = 8 + 32 + (4 + provider_registry.chain.len()) + 1 + 2048
            + (provider_registry.providers.len() * 64)
            + (provider_registry.provider_tokens.len() * 128)
            + (provider_registry.token_addresses.len() * 128),
        realloc::payer = admin,
        realloc::zero = false,
    )]
    pub provider_registry: Account<'info, ProviderRegistry>,

    #[account(mut)]
    pub admin: Signer<'info>,

    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(message_hash: [u8; 32], raw_payload: Vec<u8>)]
pub struct UpdateTokensAction<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    /// Staged buffer closed after verification to refund rent to payer
    #[account(
        mut,
        close = payer,
        seeds = [b"sig_buffer", message_hash.as_ref()],
        bump,
        constraint = sig_buffer.message_hash == message_hash @ QiaraError::InvalidActionHash
    )]
    pub sig_buffer: Account<'info, SignatureBuffer>,

    #[account(
        mut,
        seeds = [b"provider_registry"],
        bump = provider_registry.bump,
        realloc = 8 + 32 + (4 + provider_registry.chain.len()) + 1 + 2048
            + (provider_registry.providers.len() * 64)
            + (provider_registry.provider_tokens.len() * 128)
            + (provider_registry.token_addresses.len() * 128),
        realloc::payer = payer,
        realloc::zero = false,
    )]
    pub provider_registry: Account<'info, ProviderRegistry>,

    pub validator_state: Account<'info, ValidatorState>,
    pub var_reg: Account<'info, Registry>,
    pub epoch_config: Account<'info, EpochConfig>,

    #[account(
        init,
        payer = payer,
        space = 8 + 32,
        seeds = [b"action", message_hash.as_ref()],
        bump
    )]
    pub action_record: Account<'info, ActionRecord>,

    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(message_hash: [u8; 32], raw_payload: Vec<u8>)]
pub struct UpdateTokenAddressAction<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    /// Staged buffer closed after verification to refund rent to payer
    #[account(
        mut,
        close = payer,
        seeds = [b"sig_buffer", message_hash.as_ref()],
        bump,
        constraint = sig_buffer.message_hash == message_hash @ QiaraError::InvalidActionHash
    )]
    pub sig_buffer: Account<'info, SignatureBuffer>,

    #[account(
        mut,
        seeds = [b"provider_registry"],
        bump = provider_registry.bump,
        realloc = 8 + 32 + (4 + provider_registry.chain.len()) + 1 + 2048
            + (provider_registry.providers.len() * 64)
            + (provider_registry.provider_tokens.len() * 128)
            + (provider_registry.token_addresses.len() * 128),
        realloc::payer = payer,
        realloc::zero = false,
    )]
    pub provider_registry: Account<'info, ProviderRegistry>,

    pub validator_state: Account<'info, ValidatorState>,
    pub var_reg: Account<'info, Registry>,
    pub epoch_config: Account<'info, EpochConfig>,

    #[account(
        init,
        payer = payer,
        space = 8 + 32,
        seeds = [b"action", message_hash.as_ref()],
        bump
    )]
    pub action_record: Account<'info, ActionRecord>,

    pub system_program: Program<'info, System>,
}