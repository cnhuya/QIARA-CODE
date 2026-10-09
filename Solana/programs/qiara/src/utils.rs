use anchor_lang::prelude::*;
use anchor_lang::solana_program::keccak;
use anchor_lang::solana_program::secp256k1_recover::secp256k1_recover;
use crate::error::QiaraError;
use crate::state::{Registry, ValidatorState};

pub fn verify_signatures(
    state: &ValidatorState,
    registry: &Registry,
    signatures: &[[u8; 65]],
    inputs: &[u8],
    current_epoch: u64, // <--- added current_epoch
) -> Result<[u8; 32]> {
    let min_required = registry.get_min_unique_validators(current_epoch);
    require!(signatures.len() >= min_required, QiaraError::InsufficientSignatures);

    let msg_hash = keccak::hash(inputs).to_bytes();

    let mut eth_msg = [0u8; 60];
    eth_msg[..28].copy_from_slice(b"\x19Ethereum Signed Message:\n32");
    eth_msg[28..60].copy_from_slice(&msg_hash);
    let eth_signed_hash = keccak::hash(&eth_msg).to_bytes();

    let mut seen_signers: Vec<[u8; 20]> = Vec::with_capacity(signatures.len());

    for sig in signatures {
        let mut sig_bytes = [0u8; 64];
        sig_bytes.copy_from_slice(&sig[..64]);

        let recovery_id = if sig[64] >= 27 { sig[64] - 27 } else { sig[64] };

        let recovered = secp256k1_recover(&eth_signed_hash, recovery_id, &sig_bytes)
            .or_else(|_| secp256k1_recover(&msg_hash, recovery_id, &sig_bytes))
            .map_err(|_| error!(QiaraError::InvalidSignature))?;

        let hash = keccak::hash(&recovered.0);
        let mut eth_addr = [0u8; 20];
        eth_addr.copy_from_slice(&hash.0[12..32]);

        // Dynamic O(1) epoch check
        let is_active = state.is_active(current_epoch, &eth_addr);
        require!(is_active, QiaraError::NotValidator);

        require!(!seen_signers.contains(&eth_addr), QiaraError::DuplicateSigner);
        seen_signers.push(eth_addr);
    }

    require!(seen_signers.len() >= min_required, QiaraError::InsufficientSignatures);
    Ok(msg_hash)
}