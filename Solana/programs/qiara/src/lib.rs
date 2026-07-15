use anchor_lang::prelude::*;
use anchor_lang::solana_program::secp256k1_recover;
use anchor_lang::solana_program::secp256k1_recover::secp256k1_recover;
use anchor_lang::solana_program::keccak;

pub mod extractor;
pub mod verifier;

declare_id!("Fy8y5rxmhogaw1DvqA1ghcJJBCvKrfu2eRWK4es721Ec");

#[program]
pub mod qiara {
    use super::*;

    // ==========================================
    // 1. EPOCH MANAGER
    // ==========================================

    pub fn initialize_epoch(
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

    // ==========================================
    // 2. VARIABLES REGISTRY
    // ==========================================

    pub fn admin_add_variable(
        ctx: Context<AdminAddVariable>,
        header: String,
        name: String,
        data: Vec<u8>,
    ) -> Result<()> {
        let registry = &mut ctx.accounts.registry;
        require!(!registry.is_locked, QiaraError::RegistryLocked);
        
        internal_add_direct(registry, header, name, data);
        Ok(())
    }

    pub fn friend_add_variable(
        ctx: Context<FriendAddVariable>,
        public_inputs: Vec<u8>,
        proof_points: Vec<u8>,
        signatures: Vec<Vec<u8>>,
    ) -> Result<()> {
        let registry = &mut ctx.accounts.registry;
        require!(!registry.is_locked, QiaraError::RegistryLocked);

        // 1. Verify signatures from validators
        verify_signatures(&ctx.accounts.validator_state, &signatures, &public_inputs)?;

        // 2. Verify ZK Proof
        require!(
            verifier::verify_variable_proof(&public_inputs, &proof_points)?,
            QiaraError::InvalidProof
        );

        // 3. Extract properties
        let (header, name, data) = extractor::extract_variable_strings(&public_inputs)?;

        // 4. Handle rollover check
        check_and_handle_epoch_rollover(registry, &ctx.accounts.epoch_config)?;

        // 5. Append to pending queue
        internal_add_pending(registry, header, name, data);
        Ok(())
    }

    pub fn lock_registry(ctx: Context<LockRegistry>) -> Result<()> {
        ctx.accounts.registry.is_locked = true;
        Ok(())
    }

    // ==========================================
    // 3. VALIDATORS MANAGER
    // ==========================================

    pub fn add_pending_pubkey(
        ctx: Context<AddPendingPubkey>,
        public_inputs: Vec<u8>,
        proof_points: Vec<u8>,
        signatures: Vec<Vec<u8>>,
    ) -> Result<()> {
        let validator_state = &mut ctx.accounts.validator_state;

        // 1. Verify Signatures of Current Quorum
        verify_signatures(validator_state, &signatures, &public_inputs)?;

        // 2. Verify ZK Proof
        require!(
            verifier::verify_validator_proof(&public_inputs, &proof_points)?,
            QiaraError::InvalidProof
        );

        let pubkey = extractor::extract_validator_pubkey(&public_inputs)?;
        let is_removal = extractor::extract_validator_is_removal(&public_inputs)?;

        // 3. Check and handle epoch rollover
        check_and_handle_validator_rollover(validator_state, &ctx.accounts.epoch_config)?;

        // 4. Push update to queue
        validator_state.pending_updates.push(PendingUpdate { pubkey, is_removal });
        Ok(())
    }

    pub fn add_active_pubkey_direct(
        ctx: Context<AddActivePubkeyDirect>,
        pubkey: Vec<u8>,
    ) -> Result<()> {
        let validator_state = &mut ctx.accounts.validator_state;
        validator_state.active_pubkeys.push(pubkey);
        Ok(())
    }

    // ==========================================
    // 4. DELEGATOR / VAULT
    // ==========================================

    pub fn create_vault(ctx: Context<CreateVault>, provider_name: String) -> Result<()> {
        let vault = &mut ctx.accounts.vault;
        vault.provider_name = provider_name;
        vault.authority = ctx.accounts.payer.key();
        vault.bump = ctx.bumps.vault;
        Ok(())
    }

    pub fn list_new_token(ctx: Context<ListNewToken>) -> Result<()> {
        let vault = &ctx.accounts.vault;
        let token_mint = ctx.accounts.token_mint.key();

        emit!(TokenListed {
            vault: vault.key(),
            token_mint,
            provider_name: vault.provider_name.clone(),
        });

        Ok(())
    }
}

// ==========================================
// 5. DATA STRUCTURES & ACCOUNTS
// ==========================================

#[account]
pub struct EpochConfig {
    pub genesis_timestamp_ms: u64,
    pub epoch_duration_ms: u64,
    pub authority: Pubkey,
}

impl EpochConfig {
    pub fn get_current_epoch(&self) -> Result<u64> {
        let clock = Clock::get()?;
        let now_ms = (clock.unix_timestamp * 1000) as u64;
        if now_ms < self.genesis_timestamp_ms {
            return Ok(0);
        }
        Ok((now_ms - self.genesis_timestamp_ms) / self.epoch_duration_ms)
    }
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Debug)]
pub struct PendingVariable {
    pub name: String,
    pub value: Vec<u8>,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Debug)]
pub struct ActiveVariableMap {
    pub header: String,
    pub variables: Vec<PendingVariable>, // Uses the same flat structure
}

#[account]
pub struct Registry {
    pub active_variables: Vec<ActiveVariableMap>,
    pub pending_variables: Vec<ActiveVariableMap>,
    pub is_locked: bool,
    pub last_processed_epoch: u64,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Debug)]
pub struct PendingUpdate {
    pub pubkey: Vec<u8>,
    pub is_removal: bool,
}

#[account]
pub struct ValidatorState {
    pub active_pubkeys: Vec<Vec<u8>>,
    pub pending_updates: Vec<PendingUpdate>,
    pub last_processed_epoch: u64,
}

#[account]
pub struct Vault {
    pub provider_name: String,
    pub authority: Pubkey,
    pub bump: u8,
}

#[account]
pub struct SupportedToken {
    pub is_supported: bool,
}

// ==========================================
// 6. INSTRUCTION CONTEXTS
// ==========================================

#[derive(Accounts)]
pub struct InitializeEpoch<'info> {
    #[account(init, payer = authority, space = 8 + 8 + 8 + 32)]
    pub config: Account<'info, EpochConfig>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct AdminAddVariable<'info> {
    #[account(mut)]
    pub registry: Account<'info, Registry>,
    pub admin: Signer<'info>,
}

#[derive(Accounts)]
pub struct FriendAddVariable<'info> {
    #[account(mut)]
    pub registry: Account<'info, Registry>,
    pub validator_state: Account<'info, ValidatorState>,
    pub epoch_config: Account<'info, EpochConfig>,
    pub friend: Signer<'info>,
}

#[derive(Accounts)]
pub struct LockRegistry<'info> {
    #[account(mut)]
    pub registry: Account<'info, Registry>,
    pub admin: Signer<'info>,
}

#[derive(Accounts)]
pub struct AddPendingPubkey<'info> {
    #[account(mut)]
    pub validator_state: Account<'info, ValidatorState>,
    pub epoch_config: Account<'info, EpochConfig>,
    pub signer: Signer<'info>,
}

#[derive(Accounts)]
pub struct AddActivePubkeyDirect<'info> {
    #[account(mut)]
    pub validator_state: Account<'info, ValidatorState>,
    pub admin: Signer<'info>,
}

#[derive(Accounts)]
#[instruction(provider_name: String)]
pub struct CreateVault<'info> {
    #[account(
        init,
        payer = payer,
        space = 8 + 4 + provider_name.len() + 32 + 1,
        seeds = [b"vault", provider_name.as_bytes()],
        bump
    )]
    pub vault: Account<'info, Vault>,
    #[account(mut)]
    pub payer: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct ListNewToken<'info> {
    pub vault: Account<'info, Vault>,
    #[account(
        init,
        payer = payer,
        space = 8 + 1,
        seeds = [b"supported-token", vault.key().as_ref(), token_mint.key().as_ref()],
        bump
    )]
    pub supported_token: Account<'info, SupportedToken>,
    /// CHECK: Safe
    /// CHECK: Safe
    pub token_mint: UncheckedAccount<'info>,
    #[account(mut)]
    pub payer: Signer<'info>,
    pub system_program: Program<'info, System>,
}

// ==========================================
// 7. INTERNAL HELPER IMPLEMENTATIONS
// ==========================================

fn internal_add_direct(registry: &mut Registry, header: String, name: String, data: Vec<u8>) {
    if let Some(pos) = registry.active_variables.iter().position(|x| x.header == header) {
        let active_map = &mut registry.active_variables[pos];
        if let Some(v_pos) = active_map.variables.iter().position(|x| x.name == name) {
            active_map.variables.remove(v_pos);
        }
        active_map.variables.push(PendingVariable { name, value: data });
    } else {
        registry.active_variables.push(ActiveVariableMap {
            header,
            variables: vec![PendingVariable { name, value: data }],
        });
    }
}

fn internal_add_pending(registry: &mut Registry, header: String, name: String, data: Vec<u8>) {
    if let Some(pos) = registry.pending_variables.iter().position(|x| x.header == header) {
        registry.pending_variables[pos].variables.push(PendingVariable { name, value: data });
    } else {
        registry.pending_variables.push(ActiveVariableMap {
            header,
            variables: vec![PendingVariable { name, value: data }],
        });
    }
}

fn check_and_handle_epoch_rollover(registry: &mut Registry, epoch_config: &EpochConfig) -> Result<()> {
    let current_epoch = epoch_config.get_current_epoch()?;
    if current_epoch > registry.last_processed_epoch {
        let pending = std::mem::take(&mut registry.pending_variables);
        for item in pending {
            for v in item.variables {
                internal_add_direct(registry, item.header.clone(), v.name, v.value);
            }
        }
        registry.last_processed_epoch = current_epoch;
    }
    Ok(())
}

fn check_and_handle_validator_rollover(state: &mut ValidatorState, epoch_config: &EpochConfig) -> Result<()> {
    let current_epoch = epoch_config.get_current_epoch()?;
    if current_epoch > state.last_processed_epoch {
        let updates = std::mem::take(&mut state.pending_updates);
        for update in updates {
            if update.is_removal {
                if let Some(pos) = state.active_pubkeys.iter().position(|x| x == &update.pubkey) {
                    state.active_pubkeys.remove(pos);
                }
            } else if !state.active_pubkeys.contains(&update.pubkey) {
                state.active_pubkeys.push(update.pubkey);
            }
        }
        state.last_processed_epoch = current_epoch;
    }
    Ok(())
}

/// Recovers ECDSA secp256k1 keys and validates them against the active validator state
pub fn verify_signatures(
    state: &ValidatorState,
    signatures: &[Vec<u8>],
    inputs: &[u8],
) -> Result<()> {
    for sig in signatures {
        require!(sig.len() == 65, QiaraError::InvalidSignatureLength);
        
        let mut sig_bytes = [0u8; 64];
        sig_bytes.copy_from_slice(&sig[0..64]);
        let recovery_id = sig[64];

        // 1. Keccak256 hash inputs
        let msg_hash = keccak::hash(inputs).to_bytes();

        // 2. Recover 64-byte uncompressed key from system call
        let recovered_raw = secp256k1_recover(&msg_hash, recovery_id, &sig_bytes)
            .map_err(|_| QiaraError::InvalidSignature)?;

        // 3. SEC1 Decompress Prefix (Adds 0x04)
        let mut recovered_uncompressed = vec![0x04];
        recovered_uncompressed.extend_from_slice(&recovered_raw.to_bytes());

        require!(
            state.active_pubkeys.contains(&recovered_uncompressed),
            QiaraError::NotValidator
        );
    }
    Ok(())
}

// ==========================================
// 8. CUSTOM EVENTS
// ==========================================

#[event]
pub struct TokenListed {
    pub vault: Pubkey,
    pub token_mint: Pubkey,
    pub provider_name: String,
}

// ==========================================
// 9. ERROR HANDLING
// ==========================================

// ==========================================
// 9. ERROR HANDLING
// ==========================================

#[error_code]
pub enum QiaraError {
    #[msg("Genesis timestamp is in the future.")]
    GenesisInFuture,
    #[msg("Epoch duration must be greater than zero.")]
    DurationIsZero,
    #[msg("Registry variable map has been locked.")]
    RegistryLocked,
    #[msg("ZK variables proof validation failed.")]
    InvalidProof,
    #[msg("Contiguous input parser out of bounds.")]
    InvalidInputLength,
    #[msg("Signature size does not equal 65 bytes.")]
    InvalidSignatureLength,
    #[msg("Derivation recovered invalid SECP256K1 signature.")]
    InvalidSignature,
    #[msg("Caller is not a registered active validator.")]
    NotValidator,
    #[msg("Shared name can't be empty")]
    SharedNameCantBeEmpty,
    #[msg("Referral code can't be empty")]
    RefCodeCantBeEmpty,
    #[msg("Sub owner can't be empty")]
    SubOwnerCantBeEmpty,
    #[msg("Wrong chain ID.")]
    WrongChainId, // Added to resolve the verifier assertion error
}