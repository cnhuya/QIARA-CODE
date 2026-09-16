use anchor_lang::prelude::*;
use anchor_lang::solana_program::keccak;
use anchor_lang::solana_program::secp256k1_recover::secp256k1_recover;
use crate::{QiaraError, ValidatorState, Registry};

pub const ACTION_UPDATE_TOKENS: u8 = 1;
pub const ACTION_UPDATE_TOKEN_ADDRESS: u8 = 2;
pub const CHAIN_NAME: &[u8] = b"Solana";

#[account]
pub struct ProviderRegistry {
    pub admin: Pubkey,
    pub dev_access_revoked: bool,
    pub providers: Vec<ProviderEntry>,
    pub token_addresses: Vec<TokenAddressEntry>,
}

#[account]
pub struct ActionRecord {
    pub is_used: bool,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Debug)]
pub struct ProviderEntry {
    pub provider_name: String,
    pub tokens: Vec<String>,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Debug)]
pub struct TokenAddressEntry {
    pub token_name: String,
    pub token_address: String,
}

impl ProviderRegistry {
    pub fn is_provider_supported(&self, provider: &str) -> bool {
        self.providers.iter().any(|p| p.provider_name.eq_ignore_ascii_case(provider))
    }

    pub fn is_token_supported(&self, provider: &str, token: &str) -> bool {
        self.providers.iter()
            .find(|p| p.provider_name.eq_ignore_ascii_case(provider))
            .map_or(false, |entry| entry.tokens.iter().any(|t| t.eq_ignore_ascii_case(token)))
    }

    pub fn get_token_address(&self, token: &str) -> Option<String> {
        self.token_addresses.iter()
            .find(|t| t.token_name.eq_ignore_ascii_case(token))
            .map(|t| t.token_address.clone())
    }
}

// --- Instructions ---

pub fn initialize(ctx: Context<InitializeProviderRegistry>) -> Result<()> {
    let registry = &mut ctx.accounts.provider_registry;
    registry.admin = ctx.accounts.admin.key();
    registry.dev_access_revoked = false;
    registry.providers = Vec::new();
    registry.token_addresses = Vec::new();
    Ok(())
}

pub fn dev_add_tokens(
    ctx: Context<DevTokensAction>,
    provider_name: String,
    tokens: Vec<String>,
) -> Result<()> {
    let registry = &mut ctx.accounts.provider_registry;
    require!(!registry.dev_access_revoked, QiaraError::RegistryLocked);
    require!(ctx.accounts.admin.key() == registry.admin, QiaraError::NotValidator);
    
    insert_tokens(registry, provider_name, tokens);
    Ok(())
}

pub fn dev_set_token_address(
    ctx: Context<DevTokensAction>,
    token_name: String,
    token_address: String,
) -> Result<()> {
    let registry = &mut ctx.accounts.provider_registry;
    require!(!registry.dev_access_revoked, QiaraError::RegistryLocked);
    require!(ctx.accounts.admin.key() == registry.admin, QiaraError::NotValidator);

    set_token_address(registry, token_name, token_address);
    Ok(())
}

pub fn revoke_dev_access(ctx: Context<DevTokensAction>) -> Result<()> {
    let registry = &mut ctx.accounts.provider_registry;
    require!(!registry.dev_access_revoked, QiaraError::RegistryLocked);
    require!(ctx.accounts.admin.key() == registry.admin, QiaraError::NotValidator);
    
    registry.dev_access_revoked = true;
    Ok(())
}

pub fn update_tokens_with_signatures(
    ctx: Context<UpdateTokensWithSignatures>,
    is_add: bool,
    provider_name: String,
    tokens: Vec<String>,
    nonce: u64,
    signatures: Vec<Vec<u8>>,
) -> Result<()> {
    let tokens_len: usize = tokens.iter().map(|t| t.len()).sum();
    let mut payload = Vec::with_capacity(2 + CHAIN_NAME.len() + provider_name.len() + tokens_len + 8);
    payload.push(ACTION_UPDATE_TOKENS);
    payload.push(if is_add { 1u8 } else { 0u8 });
    payload.extend_from_slice(CHAIN_NAME);
    payload.extend_from_slice(provider_name.as_bytes());
    for t in &tokens {
        payload.extend_from_slice(t.as_bytes());
    }
    payload.extend_from_slice(&nonce.to_be_bytes());
    let action_hash = keccak::hash(&payload).to_bytes();

    verify_action_hash_signatures(
        &ctx.accounts.validator_state,
        &ctx.accounts.registry,
        &signatures,
        &action_hash,
    )?;

    ctx.accounts.action_record.is_used = true;

    let registry = &mut ctx.accounts.provider_registry;
    if is_add {
        insert_tokens(registry, provider_name, tokens);
    } else if let Some(pos) = registry.providers.iter().position(|p| p.provider_name.eq_ignore_ascii_case(&provider_name)) {
        registry.providers[pos].tokens.retain(|t| !tokens.iter().any(|rem| rem.eq_ignore_ascii_case(t)));
    }

    Ok(())
}

pub fn update_token_address_with_signatures(
    ctx: Context<UpdateTokenAddressWithSignatures>,
    token_name: String,
    token_address: String,
    nonce: u64,
    signatures: Vec<Vec<u8>>,
) -> Result<()> {
    // Canonical payload: [action_id (1B)] + [chain] + [token] + [token_address] + [nonce (8B)]
    let mut payload = Vec::with_capacity(1 + CHAIN_NAME.len() + token_name.len() + token_address.len() + 8);
    payload.push(ACTION_UPDATE_TOKEN_ADDRESS);
    payload.extend_from_slice(CHAIN_NAME);
    payload.extend_from_slice(token_name.as_bytes());
    payload.extend_from_slice(token_address.as_bytes());
    payload.extend_from_slice(&nonce.to_be_bytes());
    let action_hash = keccak::hash(&payload).to_bytes();

    verify_action_hash_signatures(
        &ctx.accounts.validator_state,
        &ctx.accounts.registry,
        &signatures,
        &action_hash,
    )?;

    ctx.accounts.action_record.is_used = true;

    let registry = &mut ctx.accounts.provider_registry;
    set_token_address(registry, token_name, token_address);

    Ok(())
}

// --- Helpers ---

fn verify_action_hash_signatures(
    state: &ValidatorState,
    registry: &Registry,
    signatures: &[Vec<u8>],
    action_hash: &[u8; 32],
) -> Result<()> {
    let min_required = registry.get_min_unique_validators();
    let mut valid_count = 0;
    let mut seen: Vec<Vec<u8>> = Vec::with_capacity(signatures.len());

    for sig in signatures {
        if sig.len() != 65 { continue; }
        let mut sig_bytes = [0u8; 64];
        sig_bytes.copy_from_slice(&sig[0..64]);

        if let Ok(recovered) = secp256k1_recover(action_hash, sig[64], &sig_bytes) {
            let mut uncompressed = Vec::with_capacity(65);
            uncompressed.push(0x04);
            uncompressed.extend_from_slice(&recovered.to_bytes());
            if state.active_pubkeys.contains(&uncompressed) && !seen.contains(&uncompressed) {
                seen.push(uncompressed);
                valid_count += 1;
            }
        }
    }
    require!(valid_count >= min_required, QiaraError::InsufficientSignatures);
    Ok(())
}

fn insert_tokens(registry: &mut ProviderRegistry, provider_name: String, tokens: Vec<String>) {
    if let Some(pos) = registry.providers.iter().position(|p| p.provider_name.eq_ignore_ascii_case(&provider_name)) {
        let list = &mut registry.providers[pos].tokens;
        for token in tokens {
            if !list.iter().any(|t| t.eq_ignore_ascii_case(&token)) {
                list.push(token);
            }
        }
    } else {
        registry.providers.push(ProviderEntry { provider_name, tokens });
    }
}

fn set_token_address(registry: &mut ProviderRegistry, token_name: String, token_address: String) {
    if let Some(pos) = registry.token_addresses.iter().position(|t| t.token_name.eq_ignore_ascii_case(&token_name)) {
        registry.token_addresses[pos].token_address = token_address;
    } else {
        registry.token_addresses.push(TokenAddressEntry { token_name, token_address });
    }
}

// --- Accounts ---

#[derive(Accounts)]
pub struct InitializeProviderRegistry<'info> {
    #[account(
        init,
        payer = admin,
        space = 8 + 32 + 1 + 4 + 4096,
        seeds = [b"provider-registry"],
        bump
    )]
    pub provider_registry: Account<'info, ProviderRegistry>,
    #[account(mut)]
    pub admin: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct DevTokensAction<'info> {
    #[account(mut, seeds = [b"provider-registry"], bump)]
    pub provider_registry: Account<'info, ProviderRegistry>,
    pub admin: Signer<'info>,
}

#[derive(Accounts)]
#[instruction(is_add: bool, provider_name: String, tokens: Vec<String>, nonce: u64)]
pub struct UpdateTokensWithSignatures<'info> {
    #[account(mut, seeds = [b"provider-registry"], bump)]
    pub provider_registry: Account<'info, ProviderRegistry>,

    #[account(
        init,
        payer = signer,
        space = 8 + 1,
        seeds = [b"action-record", provider_name.as_bytes(), &nonce.to_be_bytes()],
        bump
    )]
    pub action_record: Account<'info, ActionRecord>,

    pub validator_state: Account<'info, ValidatorState>,
    pub registry: Account<'info, Registry>,

    #[account(mut)]
    pub signer: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(token_name: String, token_address: String, nonce: u64)]
pub struct UpdateTokenAddressWithSignatures<'info> {
    #[account(mut, seeds = [b"provider-registry"], bump)]
    pub provider_registry: Account<'info, ProviderRegistry>,

    #[account(
        init,
        payer = signer,
        space = 8 + 1,
        seeds = [b"action-record", token_name.as_bytes(), &nonce.to_be_bytes()],
        bump
    )]
    pub action_record: Account<'info, ActionRecord>,

    pub validator_state: Account<'info, ValidatorState>,
    pub registry: Account<'info, Registry>,

    #[account(mut)]
    pub signer: Signer<'info>,
    pub system_program: Program<'info, System>,
}