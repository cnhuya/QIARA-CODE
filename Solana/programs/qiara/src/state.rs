use anchor_lang::prelude::*;
use serde::{Deserialize, Serialize};
// ==========================================
// CENTRAL SIGNATURE BUFFER & EVENTS
// ==========================================

#[account]
pub struct SignatureBuffer {
    pub message_hash: [u8; 32],
    pub signatures: Vec<[u8; 65]>,
}

#[event]
pub struct VaultEvent {
    pub action: String,
    pub data: Vec<EventData>,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Debug)]
pub struct EventData {
    pub name: String,
    pub type_name: String,
    pub value: Vec<u8>,
}

#[inline(always)]
pub fn create_data(name: &str, type_name: &str, value: Vec<u8>) -> EventData {
    EventData {
        name: name.to_string(),
        type_name: type_name.to_string(),
        value,
    }
}

// ==========================================
// TYPED CONSENSUS PAYLOADS
// ==========================================


#[derive(AnchorSerialize, AnchorDeserialize, Serialize, Deserialize, Clone, Debug)]
pub struct VariablePayload {
    pub nonce: u64,
    pub header: String,
    pub name: String,
    pub data: Vec<u8>,
}

#[derive(AnchorSerialize, AnchorDeserialize, Serialize, Deserialize, Clone, Debug)]
pub struct ValidatorRotationPayload {
    pub nonce: u64,
    pub pubkey: Vec<u8>, // 20-byte recovered Ethereum address
    pub is_removal: bool,
}

#[derive(AnchorSerialize, AnchorDeserialize, Serialize, Deserialize, Clone, Debug)]
pub struct MintPayload {
    pub nullifier: [u8; 32],
    pub recipient: Pubkey,
    pub amount: u64,
    pub chain_id: u32,
    pub nonce: u64,
}

// ==========================================
// REGISTRY & EPOCH ACCOUNTS (EVM-MATCHED)
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

/// Matches EVM TimedValue: active vs pending with effectiveEpoch
#[derive(AnchorSerialize, AnchorDeserialize, Clone, Debug, Default)]
pub struct TimedVariable {
    pub name: String,
    pub active_data: Vec<u8>,
    pub pending_data: Vec<u8>,
    pub effective_epoch: u64,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Debug, Default)]
pub struct VariableHeaderEntry {
    pub header: String,
    pub variables: Vec<TimedVariable>,
}

#[account]
pub struct Registry {
    pub headers: Vec<VariableHeaderEntry>,
    pub is_locked: bool,
}

impl Registry {
    /// O(1) dynamic read matching EVM getActiveVariable():
    /// Automatically returns pending_data if current_epoch >= effective_epoch
    pub fn get_active_variable(&self, current_epoch: u64, header: &str, name: &str) -> Option<Vec<u8>> {
        let head_entry = self.headers.iter().find(|h| h.header == header)?;
        let var_entry = head_entry.variables.iter().find(|v| v.name == name)?;

        if var_entry.effective_epoch != 0 && current_epoch >= var_entry.effective_epoch {
            Some(var_entry.pending_data.clone())
        } else {
            Some(var_entry.active_data.clone())
        }
    }

    pub fn get_min_unique_validators(&self, current_epoch: u64) -> usize {
        if let Some(data) = self.get_active_variable(current_epoch, "QiaraValidators", "MINIMUM_UNIQUE_VALIDATORS")
            .or_else(|| self.get_active_variable(current_epoch, "QiaraBridge", "MINIMUM_UNIQUE_VALIDATORS")) {
            if !data.is_empty() {
                return data[data.len() - 1] as usize;
            }
        }
        1
    }
}

// ==========================================
// VALIDATOR ACCOUNTS (EVM-MATCHED)
// ==========================================

/// Matches EVM TimedStatus: isActive vs targetStatus with effectiveEpoch
#[derive(AnchorSerialize, AnchorDeserialize, Clone, Debug, Default)]
pub struct TimedValidator {
    pub pubkey: Vec<u8>, // 20-byte recovered Ethereum address
    pub is_active: bool,
    pub target_status: bool,
    pub effective_epoch: u64,
}

#[account]
pub struct ValidatorState {
    pub validators: Vec<TimedValidator>,
}

impl ValidatorState {
    /// O(1) dynamic check matching EVM isValidatorActive(address)
    pub fn is_active(&self, current_epoch: u64, pubkey: &[u8]) -> bool {
        if let Some(v) = self.validators.iter().find(|val| val.pubkey == pubkey) {
            if v.effective_epoch != 0 && current_epoch >= v.effective_epoch {
                return v.target_status;
            }
            return v.is_active;
        }
        false
    }
}

// ==========================================
// TOKEN ACCOUNTS
// ==========================================

#[account]
pub struct TokenConfig {
    pub authority: Pubkey,
    pub mint: Pubkey,
    pub mint_bump: u8,
    pub chain_id: u32,
    pub chain: String,
    pub variable_header: String,
    pub fee_recipient: Option<Pubkey>,
}

#[account]
pub struct NullifierRecord {
    pub is_used: bool,
}

#[account]
pub struct ExemptRecord {
    pub account: Pubkey,
    pub is_exempt: bool,
}

// ==========================================
// PROVIDER REGISTRY ACCOUNTS
// ==========================================

#[account]
pub struct ProviderRegistry {
    pub admin: Pubkey,
    pub chain: String,
    pub dev_access_revoked: bool,
    pub providers: Vec<String>,
    pub provider_tokens: Vec<ProviderTokensEntry>,
    pub token_addresses: Vec<TokenAddressEntry>,
    pub bump: u8,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Default)]
pub struct ProviderTokensEntry {
    pub provider: String,
    pub tokens: Vec<String>,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Default)]
pub struct TokenAddressEntry {
    pub token: String,
    pub address: String,
}

#[account]
pub struct ActionRecord {
    pub action_hash: [u8; 32],
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Debug)]
pub struct UpdateTokensPayload {
    pub nonce: u64,
    pub is_add: bool,
    pub provider: String,
    pub tokens: Vec<String>,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Debug)]
pub struct UpdateTokenAddressPayload {
    pub nonce: u64,
    pub token: String,
    pub token_address: String,
}