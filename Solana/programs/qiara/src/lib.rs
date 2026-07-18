// programs/qiara/src/lib.rs
use anchor_lang::prelude::*;
use anchor_lang::solana_program::secp256k1_recover::secp256k1_recover;
use anchor_lang::solana_program::keccak;

pub mod extractor;
pub mod verifier;

declare_id!("gJQs9vx9y4zvxNeVqRzZX8iQiZ2y4sLb6X3tKwe3yW1");

#[program]
pub mod qiara {
    use super::*;

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

    pub fn initialize_registry(ctx: Context<InitializeRegistry>) -> Result<()> {
        let registry = &mut ctx.accounts.registry;
        registry.is_locked = false;
        registry.last_processed_epoch = 0;
        registry.active_variables = Vec::new();
        registry.pending_variables = Vec::new();
        Ok(())
    }

    pub fn initialize_validator_state(ctx: Context<InitializeValidatorState>) -> Result<()> {
        let state = &mut ctx.accounts.validator_state;
        state.last_processed_epoch = 0;
        state.active_pubkeys = Vec::new();
        state.pending_updates = Vec::new();
        Ok(())
    }

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

        verify_signatures(&ctx.accounts.validator_state, &signatures, &public_inputs)?;

        let is_valid = verifier::verify_variable_proof(&public_inputs, &proof_points)?;
        require!(is_valid, QiaraError::InvalidProof);

        let (header, name, data) = extractor::extract_variable_strings(&public_inputs)?;

        check_and_handle_epoch_rollover(registry, &ctx.accounts.epoch_config)?;
        internal_add_pending(registry, header, name, data);
        Ok(())
    }

    pub fn lock_registry(ctx: Context<LockRegistry>) -> Result<()> {
        ctx.accounts.registry.is_locked = true;
        Ok(())
    }

    pub fn add_pending_pubkey(
        ctx: Context<AddPendingPubkey>,
        public_inputs: Vec<u8>,
        proof_points: Vec<u8>,
        signatures: Vec<Vec<u8>>,
    ) -> Result<()> {
        let validator_state = &mut ctx.accounts.validator_state;

        verify_signatures(validator_state, &signatures, &public_inputs)?;

        let is_valid = verifier::verify_validator_proof(&public_inputs, &proof_points)?;
        require!(is_valid, QiaraError::InvalidProof);

        let pubkey = extractor::extract_validator_pubkey(&public_inputs)?;
        let is_removal = extractor::extract_validator_is_removal(&public_inputs)?;

        check_and_handle_validator_rollover(validator_state, &ctx.accounts.epoch_config)?;
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

    /// CPI TARGET: Verifies balance proof and signatures, returning Ok(()) to Vault [2]
    pub fn verify_balance_proof(
        ctx: Context<VerifyBalanceProof>,
        public_inputs: Vec<u8>,
        proof_points: Vec<u8>,
        signatures: Vec<Vec<u8>>,
    ) -> Result<()> {
        // 1. Verify signatures against active validator state [2]
        verify_signatures(&ctx.accounts.validator_state, &signatures, &public_inputs)?;

        // 2. Verify ZK Balance Proof
        let is_valid = verifier::verify_proof_with_vk::<6>(verifier::BALANCE_RAW_VK, &public_inputs, &proof_points)?;
        require!(is_valid, QiaraError::InvalidProof);

        Ok(())
    }
}

// ==========================================
// DATA STRUCTURES & CONTEXTS
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
    pub variables: Vec<PendingVariable>,
}

#[account]
pub struct Registry {
    pub active_variables: Vec<ActiveVariableMap>,
    pub pending_variables: Vec<ActiveVariableMap>,
    pub is_locked: bool,
    pub last_processed_epoch: u64,
}

impl Registry {
    pub fn get_active_variable(&self, header: &str, name: &str) -> Option<Vec<u8>> {
        if let Some(pos) = self.active_variables.iter().position(|x| x.header == header) {
            let map = &self.active_variables[pos];
            if let Some(v_pos) = map.variables.iter().position(|x| x.name == name) {
                return Some(map.variables[v_pos].value.clone());
            }
        }
        None
    }
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

#[derive(Accounts)]
pub struct VerifyProof<'info> {
    /// CHECK: Dummy account
    pub signer: UncheckedAccount<'info>,
}

#[derive(Accounts)]
pub struct VerifyBalanceProof<'info> {
    pub validator_state: Account<'info, ValidatorState>, // Needed to verify signatures [2]
}

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
    #[account(init, payer = admin, space = 8 + 4000)]
    pub registry: Account<'info, Registry>,
    #[account(mut)]
    pub admin: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct InitializeValidatorState<'info> {
    #[account(init, payer = admin, space = 8 + 2000)]
    pub validator_state: Account<'info, ValidatorState>,
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

// Helpers
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

        let msg_hash = keccak::hash(inputs).to_bytes();
        let recovered_raw = secp256k1_recover(&msg_hash, recovery_id, &sig_bytes)
            .map_err(|_| QiaraError::InvalidSignature)?;

        let mut recovered_uncompressed = vec![0x04];
        recovered_uncompressed.extend_from_slice(&recovered_raw.to_bytes());

        require!(
            state.active_pubkeys.contains(&recovered_uncompressed),
            QiaraError::NotValidator
        );
    }
    Ok(())
}

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
    #[msg("Wrong chain ID.")]
    WrongChainId,
}