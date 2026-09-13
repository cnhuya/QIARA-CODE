use anchor_lang::prelude::*;
use anchor_lang::solana_program::keccak;
use anchor_lang::solana_program::secp256k1_recover::secp256k1_recover;
use anchor_spl::token::{self, Burn, Mint, MintTo, Token, TokenAccount, Transfer};

declare_id!("b8FfSsqju7xF2D9U1Ue7wBsfq3xMLP234HaFqiDomUL");

pub const FEE_DENOMINATOR: u128 = 100_000_000;

const ALT_BN128_ADD: u64 = 0;
const ALT_BN128_MUL: u64 = 2;
const ALT_BN128_PAIRING: u64 = 3;

extern "C" {
    fn sol_alt_bn128_group_op(group_op: u64, input: *const u8, input_size: u64, result: *mut u8) -> u64;
}

// =========================================================================
// EXACT 5-SIGNAL QIARA CONSTANTS
// =========================================================================

pub const QIARA_ALPHA_G1: [u8; 64] = [
    0x02, 0xb1, 0x64, 0xc6, 0x57, 0x7d, 0x14, 0x97, 0x9e, 0xe9, 0x60, 0x91, 0x0d, 0xfe, 0x37, 0x19,
    0x3f, 0x4a, 0x22, 0x0a, 0xd1, 0xfb, 0xf1, 0xc2, 0x3e, 0x7d, 0x12, 0x34, 0xd5, 0xa5, 0x1c, 0x89,
    0x08, 0x60, 0x99, 0xba, 0x5c, 0x83, 0x6a, 0x8c, 0xcd, 0x17, 0x3a, 0x89, 0xbf, 0x4a, 0x94, 0xa3,
    0x1f, 0x2a, 0x17, 0x3c, 0x4b, 0x78, 0x56, 0x44, 0xbf, 0x8d, 0x11, 0x92, 0x64, 0xd8, 0x6b, 0x6d,
];

pub const QIARA_BETA_NEG_G2: [u8; 128] = [
    0x01, 0x00, 0xa2, 0x77, 0xa2, 0x13, 0x74, 0x50, 0xf3, 0xa4, 0x44, 0x25, 0x18, 0x90, 0xce, 0x4d,
    0xc4, 0xe4, 0x35, 0x2d, 0xf8, 0x75, 0x66, 0x3a, 0xc0, 0xfe, 0xf7, 0xb6, 0xd1, 0x19, 0xa0, 0x01,
    0x01, 0x27, 0x89, 0x91, 0x93, 0x94, 0xd9, 0x54, 0x44, 0x08, 0xbd, 0x9c, 0xec, 0x0e, 0xd1, 0xb8,
    0x29, 0xba, 0xa7, 0x43, 0x17, 0x0f, 0x6c, 0x99, 0xc6, 0xa2, 0xd0, 0x82, 0x9e, 0x60, 0x40, 0x09,
    0x09, 0xab, 0xdd, 0x9d, 0x9e, 0x9b, 0x65, 0xdf, 0xd0, 0x8d, 0x23, 0xc7, 0x47, 0x75, 0x4c, 0xa7,
    0x53, 0xd1, 0xdc, 0xf8, 0xc5, 0x98, 0x03, 0x6a, 0x04, 0x09, 0xf0, 0xc7, 0x0b, 0xbb, 0xcf, 0x28,
    0x13, 0x9f, 0x44, 0x79, 0x97, 0x81, 0x01, 0x2a, 0xc6, 0xc9, 0x76, 0x7d, 0x6f, 0xee, 0x6c, 0x44,
    0x1d, 0x23, 0x1d, 0x8a, 0x8b, 0xa9, 0xa1, 0x6a, 0xd5, 0x7d, 0x5b, 0x1e, 0x36, 0x2c, 0xa2, 0x57,
];

pub const QIARA_GAMMA_NEG_G2: [u8; 128] = [
    0x21, 0x66, 0xd9, 0x62, 0xa5, 0x47, 0x6c, 0xb5, 0x4c, 0x62, 0xeb, 0x31, 0x10, 0xa2, 0x4c, 0x72,
    0x46, 0x23, 0xc2, 0xef, 0x75, 0xcd, 0x2f, 0xd9, 0x2b, 0x6d, 0x6e, 0x7e, 0xbf, 0xff, 0xd6, 0x53,
    0x0f, 0xf4, 0x08, 0xe3, 0xc3, 0x5f, 0xe1, 0xf7, 0x37, 0x7c, 0x54, 0x35, 0x42, 0x79, 0x17, 0x6f,
    0x11, 0x56, 0x9a, 0x96, 0x21, 0xa4, 0x6e, 0x7a, 0x05, 0x96, 0x3a, 0xc3, 0xf4, 0xe3, 0x7f, 0x7c,
    0x27, 0x6d, 0x7d, 0x2f, 0xb8, 0x61, 0xc2, 0x3b, 0xee, 0x1f, 0x63, 0x2c, 0xe4, 0xb4, 0x5b, 0x3a,
    0xa9, 0xba, 0x81, 0x04, 0x29, 0xf0, 0x7f, 0x27, 0xb5, 0xca, 0x4c, 0x7f, 0x2e, 0x3c, 0x14, 0x6f,
    0x17, 0xe2, 0x7f, 0x52, 0x35, 0x10, 0x80, 0x47, 0x06, 0xbd, 0x93, 0x11, 0xc2, 0x20, 0x05, 0x03,
    0xdc, 0x9e, 0x7e, 0xe0, 0x2b, 0x24, 0x22, 0x88, 0x30, 0xfd, 0x77, 0xe6, 0x6f, 0x3e, 0x50, 0x4e,
];

pub const QIARA_DELTA_NEG_G2: [u8; 128] = [
    0x2b, 0xa9, 0x97, 0x8b, 0x3d, 0xea, 0x1d, 0x84, 0xb0, 0x94, 0x4b, 0xf7, 0x32, 0xc4, 0x8b, 0x56,
    0x83, 0xc2, 0xfd, 0x10, 0x1f, 0x67, 0x54, 0xef, 0xd1, 0x9e, 0x59, 0xd3, 0x0e, 0xfb, 0x9a, 0xe4,
    0x2c, 0x7b, 0xa5, 0x19, 0xb3, 0xc8, 0x40, 0x38, 0x52, 0x28, 0x11, 0x80, 0xe1, 0x57, 0xf5, 0xdc,
    0x93, 0x89, 0x2d, 0xe6, 0x23, 0xed, 0x98, 0xb9, 0x52, 0x8b, 0x78, 0xb8, 0x48, 0x62, 0x9a, 0x9a,
    0x21, 0xb7, 0x09, 0x41, 0x0b, 0xda, 0x01, 0x24, 0x45, 0x8b, 0x81, 0xe9, 0x98, 0xee, 0x52, 0x86,
    0x05, 0x5c, 0xf9, 0x6b, 0xf1, 0x9e, 0x38, 0x94, 0x1f, 0xc2, 0x3b, 0x11, 0x82, 0x68, 0x39, 0xf1,
    0x24, 0x5b, 0x92, 0x64, 0x57, 0x2b, 0xb4, 0x46, 0xc4, 0xba, 0xb6, 0x92, 0xd1, 0x5b, 0x26, 0x98,
    0x61, 0x53, 0xe3, 0x49, 0x76, 0x41, 0x30, 0xbc, 0x6c, 0xe0, 0x42, 0xee, 0x06, 0x74, 0x23, 0x9b,
];

pub const QIARA_IC_POINTS: &[[u8; 64]] = &[
    // Point 0: Constant
    [
        0x14, 0x71, 0x22, 0x02, 0xd0, 0x6d, 0xc1, 0xf9, 0x4a, 0x14, 0xf5, 0xcb, 0x1c, 0xf4, 0x13, 0x9d,
        0x62, 0xca, 0xfa, 0x25, 0x0f, 0xef, 0x18, 0x93, 0xdc, 0x86, 0xb3, 0x8a, 0x1c, 0x08, 0xbf, 0xae,
        0x08, 0xdf, 0xd9, 0x5d, 0x97, 0x04, 0xbb, 0xce, 0x03, 0x2c, 0xf6, 0x30, 0xf4, 0x98, 0xe4, 0xd8,
        0xed, 0x7a, 0xa4, 0x71, 0x2b, 0x41, 0xf7, 0x37, 0xf5, 0x1d, 0x39, 0xa7, 0x18, 0x6b, 0x2c, 0x9c,
    ],
    // Point 1: OldAccountRoot
    [
        0x17, 0x10, 0xef, 0xce, 0xc8, 0x37, 0xc5, 0xc3, 0x8d, 0xec, 0x12, 0x40, 0xa2, 0x38, 0x1c, 0x01,
        0xcf, 0x5a, 0x0a, 0xaa, 0x23, 0x03, 0x37, 0x76, 0x0f, 0x74, 0xfe, 0x61, 0x8d, 0xa2, 0xc8, 0xef,
        0x0e, 0x0f, 0xe7, 0xaf, 0x6b, 0x8e, 0x40, 0x31, 0x22, 0xea, 0x7a, 0x55, 0x39, 0x7f, 0x17, 0x81,
        0x95, 0x0c, 0x23, 0x16, 0x7a, 0x7e, 0xf9, 0x04, 0x50, 0x8c, 0x5e, 0x40, 0xab, 0x69, 0x23, 0xd1,
    ],
    // Point 2: NewAccountRoot
    [
        0x18, 0xef, 0xef, 0xa4, 0xda, 0x50, 0x0b, 0x5d, 0xca, 0x51, 0xdd, 0xcc, 0x21, 0x2b, 0x34, 0x2a,
        0xe7, 0x28, 0x3b, 0xd1, 0xe3, 0x5a, 0x60, 0x77, 0xe0, 0xa8, 0x85, 0x34, 0x55, 0xfa, 0x76, 0xc9,
        0x12, 0xde, 0xb6, 0x38, 0x15, 0x6e, 0xa4, 0xbc, 0x2c, 0xc4, 0xff, 0x21, 0xd3, 0x89, 0xf7, 0x48,
        0xaf, 0x67, 0x14, 0x04, 0xe1, 0xa2, 0x3f, 0x76, 0x1a, 0x48, 0xcd, 0xaa, 0x46, 0x77, 0x25, 0x36,
    ],
    // Point 3: UserAddressL
    [
        0x2e, 0x87, 0x04, 0x59, 0x27, 0x93, 0xee, 0xb8, 0x31, 0xc2, 0x26, 0xbf, 0xca, 0xf7, 0xbe, 0x93,
        0x94, 0xcb, 0x22, 0x63, 0x11, 0xca, 0x0c, 0x0f, 0x8f, 0xee, 0x5d, 0x6c, 0x29, 0x99, 0x1d, 0x97,
        0x10, 0x90, 0x52, 0xda, 0x1e, 0x2c, 0xd2, 0x43, 0xf8, 0xac, 0xe6, 0xbf, 0x27, 0x55, 0x42, 0x75,
        0xea, 0x97, 0xb4, 0xb1, 0xe7, 0x75, 0xbf, 0x94, 0xce, 0x1f, 0xfe, 0x5a, 0xb7, 0x0e, 0xe1, 0x44,
    ],
    // Point 4: UserAddressH
    [
        0x19, 0x67, 0x7f, 0xa5, 0x34, 0x26, 0xcf, 0x2c, 0x08, 0xdc, 0xb3, 0x0e, 0x7c, 0xfb, 0x28, 0x50,
        0x42, 0xbf, 0xf8, 0x1e, 0x2f, 0xc9, 0x1f, 0x86, 0x25, 0xdc, 0xeb, 0xb7, 0xc3, 0xf7, 0x7e, 0x68,
        0x0e, 0xac, 0x5a, 0x5f, 0xcf, 0x45, 0x7a, 0x3d, 0x14, 0x35, 0x65, 0x88, 0xb2, 0x67, 0x65, 0x09,
        0xbd, 0xab, 0x46, 0xbd, 0xa4, 0x4c, 0xc0, 0x9f, 0x0c, 0xb7, 0xed, 0xd4, 0xb4, 0x08, 0x7f, 0x88,
    ],
    // Point 5: PackedTxData
    [
        0x18, 0xda, 0xeb, 0xfc, 0xa3, 0x7c, 0x60, 0x62, 0x59, 0xd5, 0xbe, 0x5a, 0x06, 0x6a, 0x52, 0x87,
        0xc7, 0x7f, 0x73, 0x8c, 0x58, 0x71, 0x8b, 0x6b, 0xc0, 0xe0, 0x66, 0xf2, 0x8e, 0x38, 0x79, 0x93,
        0x2d, 0xc1, 0x6c, 0x6b, 0xc9, 0x29, 0x11, 0x8a, 0x8e, 0xdc, 0xdc, 0x75, 0x90, 0x9d, 0x97, 0xb0,
        0x0e, 0xd3, 0xea, 0x82, 0x36, 0x6a, 0xec, 0x44, 0xd4, 0xbb, 0x35, 0x8f, 0x72, 0xf2, 0x10, 0xc4,
    ],
];

#[program]
pub mod qiara_token {
    use super::*;

    pub fn initialize(ctx: Context<Initialize>, variable_header: String) -> Result<()> {
        let config = &mut ctx.accounts.config;
        config.authority = ctx.accounts.authority.key();
        config.mint = ctx.accounts.mint.key();
        config.mint_bump = ctx.bumps.mint_authority;
        config.variable_header = if variable_header.is_empty() { "QiaraToken".to_string() } else { variable_header };
        config.fee_recipient = None;

        let seeds = &[b"mint-authority".as_ref(), &[config.mint_bump]];
        token::mint_to(
            CpiContext::new_with_signer(
                ctx.accounts.token_program.to_account_info(),
                MintTo {
                    mint: ctx.accounts.mint.to_account_info(),
                    to: ctx.accounts.admin_token_account.to_account_info(),
                    authority: ctx.accounts.mint_authority.to_account_info(),
                },
                &[&seeds[..]],
            ),
            1_000_000 * 1_000_000_000,
        )?;
        Ok(())
    }

    pub fn request_bridge(
        ctx: Context<RequestBridge>,
        shared: String,
        destination_chain: String,
        amount: u64,
    ) -> Result<()> {
        require!(amount > 0, QiaraTokenError::InvalidAmount);
        emit!(RequestQiaraBridge {
            user: ctx.accounts.user.key(),
            shared,
            destination_chain,
            amount,
            timestamp: Clock::get()?.unix_timestamp,
        });
        Ok(())
    }

    pub fn zk_mint(
        ctx: Context<ZkMint>,
        nullifier: [u8; 32],
        public_inputs: Vec<u8>,
        proof_points: Vec<u8>,
        signatures: Vec<Vec<u8>>,
    ) -> Result<()> {
        // 5 public signals = 160 bytes
        require!(public_inputs.len() == 160, QiaraTokenError::InvalidInputLength);

        // 1. Validator Quorum Check
        verify_signatures(
            &ctx.accounts.validator_state,
            &ctx.accounts.registry,
            &signatures,
            &public_inputs,
        )?;

        // 2. Alt-BN128 Proof Verification
        let is_valid = verify_groth16_proof(&public_inputs, &proof_points)?;
        require!(is_valid, QiaraTokenError::InvalidProof);

        // 3. Mark Nullifier as Used
        ctx.accounts.nullifier_record.is_used = true;

        // 4. Reconstruct 32-byte Solana Pubkey from UserAddressL (64..80) & UserAddressH (96..112)
        let mut user_bytes = [0u8; 32];
        user_bytes[0..16].copy_from_slice(&public_inputs[64..80]);
        user_bytes[16..32].copy_from_slice(&public_inputs[96..112]);
        let expected_user = Pubkey::new_from_array(user_bytes);
        require!(ctx.accounts.recipient.key() == expected_user, QiaraTokenError::UnauthorizedRecipient);

        // 5. Unpack Amount from PackedTxData (Signal 4: bytes 128..136)
        let amount = u64::from_le_bytes(public_inputs[128..136].try_into().unwrap());

        // 6. Mint tokens via PDA
        let seeds = &[b"mint-authority".as_ref(), &[ctx.accounts.config.mint_bump]];
        token::mint_to(
            CpiContext::new_with_signer(
                ctx.accounts.token_program.to_account_info(),
                MintTo {
                    mint: ctx.accounts.mint.to_account_info(),
                    to: ctx.accounts.recipient_token_account.to_account_info(),
                    authority: ctx.accounts.mint_authority.to_account_info(),
                },
                &[&seeds[..]],
            ),
            amount,
        )?;

        emit!(ZkMintEvent { recipient: expected_user, amount, nullifier });
        Ok(())
    }

    pub fn transfer_with_fee(ctx: Context<TransferWithFee>, amount: u64) -> Result<()> {
        let is_sender_exempt = ctx.accounts.sender_exempt.is_some();
        let is_recipient_exempt = ctx.accounts.recipient_exempt.is_some();

        let fee = if is_sender_exempt || is_recipient_exempt {
            0
        } else {
            calculate_transfer_fee(
                &ctx.accounts.registry,
                &ctx.accounts.epoch_config,
                &ctx.accounts.config.variable_header,
                amount,
            )?
        };

        let transfer_amount = amount.checked_sub(fee).ok_or(QiaraTokenError::FeeExceedsAmount)?;

        token::transfer(
            CpiContext::new(
                ctx.accounts.token_program.to_account_info(),
                Transfer {
                    from: ctx.accounts.from.to_account_info(),
                    to: ctx.accounts.to.to_account_info(),
                    authority: ctx.accounts.authority.to_account_info(),
                },
            ),
            transfer_amount,
        )?;

        if fee > 0 {
            if let Some(fee_ata) = &ctx.accounts.fee_recipient_ata {
                token::transfer(
                    CpiContext::new(
                        ctx.accounts.token_program.to_account_info(),
                        Transfer {
                            from: ctx.accounts.from.to_account_info(),
                            to: fee_ata.to_account_info(),
                            authority: ctx.accounts.authority.to_account_info(),
                        },
                    ),
                    fee,
                )?;
            } else {
                token::burn(
                    CpiContext::new(
                        ctx.accounts.token_program.to_account_info(),
                        Burn {
                            mint: ctx.accounts.mint.to_account_info(),
                            from: ctx.accounts.from.to_account_info(),
                            authority: ctx.accounts.authority.to_account_info(),
                        },
                    ),
                    fee,
                )?;
            }
        }
        Ok(())
    }

    pub fn set_fee_exempt(ctx: Context<SetFeeExempt>, exempt: bool) -> Result<()> {
        let admin_bytes = ctx.accounts.registry.get_active_variable(&ctx.accounts.config.variable_header, "WHITELIST_ADMIN");
        let authorized_admin = admin_bytes
            .and_then(|b| if b.len() == 32 { Some(Pubkey::new_from_array(b.try_into().unwrap())) } else { None })
            .unwrap_or(ctx.accounts.config.authority);

        require!(
            ctx.accounts.signer.key() == authorized_admin || ctx.accounts.signer.key() == ctx.accounts.config.authority,
            QiaraTokenError::UnauthorizedWhitelistAdmin
        );

        ctx.accounts.exempt_record.account = ctx.accounts.target_wallet.key();
        ctx.accounts.exempt_record.is_exempt = exempt;
        Ok(())
    }
}

pub fn verify_groth16_proof(public_inputs: &[u8], proof_points: &[u8]) -> Result<bool> {
    if proof_points.len() < 256 || public_inputs.len() < 160 {
        return err!(QiaraTokenError::InvalidProof);
    }

    let proof_a = &proof_points[0..64];
    let proof_b = &proof_points[64..192];
    let proof_c = &proof_points[192..256];

    let mut prepared_inputs = [0u8; 64];
    prepared_inputs.copy_from_slice(&QIARA_IC_POINTS[0]);

    for (i, chunk) in public_inputs.chunks_exact(32).enumerate() {
        if i + 1 >= QIARA_IC_POINTS.len() { break; }
        let ic_point = &QIARA_IC_POINTS[i + 1];
        if ic_point.iter().all(|&b| b == 0) { continue; }

        let mut mul_input = [0u8; 96];
        mul_input[0..64].copy_from_slice(ic_point);
        mul_input[64..96].copy_from_slice(chunk);

        let mut mul_output = [0u8; 64];
        let res = unsafe { sol_alt_bn128_group_op(ALT_BN128_MUL, mul_input.as_ptr(), 96, mul_output.as_mut_ptr()) };
        if res != 0 { return err!(QiaraTokenError::InvalidProof); }

        let mut add_input = [0u8; 128];
        add_input[0..64].copy_from_slice(&prepared_inputs);
        add_input[64..128].copy_from_slice(&mul_output);

        let mut add_output = [0u8; 64];
        let res = unsafe { sol_alt_bn128_group_op(ALT_BN128_ADD, add_input.as_ptr(), 128, add_output.as_mut_ptr()) };
        if res != 0 { return err!(QiaraTokenError::InvalidProof); }

        prepared_inputs = add_output;
    }

    let mut pairing_input = [0u8; 768];
    pairing_input[0..64].copy_from_slice(proof_a);
    pairing_input[64..192].copy_from_slice(proof_b);
    pairing_input[192..256].copy_from_slice(proof_c);
    pairing_input[256..384].copy_from_slice(&QIARA_DELTA_NEG_G2);
    pairing_input[384..448].copy_from_slice(&QIARA_ALPHA_G1);
    pairing_input[448..576].copy_from_slice(&QIARA_BETA_NEG_G2);
    pairing_input[576..640].copy_from_slice(&prepared_inputs);
    pairing_input[640..768].copy_from_slice(&QIARA_GAMMA_NEG_G2);

    let mut pairing_result = [0u8; 32];
    let res = unsafe { sol_alt_bn128_group_op(ALT_BN128_PAIRING, pairing_input.as_ptr(), 768, pairing_result.as_mut_ptr()) };
    if res != 0 || pairing_result[31] != 1 { return err!(QiaraTokenError::InvalidProof); }

    Ok(true)
}

fn verify_signatures(
    state: &qiara::ValidatorState,
    registry: &qiara::Registry,
    signatures: &[Vec<u8>],
    inputs: &[u8],
) -> Result<()> {
    let min_required = registry.get_min_unique_validators();
    require!(signatures.len() >= min_required, QiaraTokenError::InsufficientSignatures);

    let mut data = Vec::with_capacity(inputs.len());
    for chunk in inputs.chunks_exact(32) {
        let mut chunk_rev = [0u8; 32];
        chunk_rev.copy_from_slice(chunk);
        chunk_rev.reverse();
        data.extend_from_slice(&chunk_rev);
    }
    let msg_hash = keccak::hash(&data).to_bytes();
    let mut seen: Vec<Vec<u8>> = Vec::with_capacity(signatures.len());

    for sig in signatures {
        if sig.len() != 65 { continue; }
        let mut sig_bytes = [0u8; 64];
        sig_bytes.copy_from_slice(&sig[0..64]);
        let recovery_id = sig[64];

        if let Ok(recovered_raw) = secp256k1_recover(&msg_hash, recovery_id, &sig_bytes) {
            let mut key = Vec::with_capacity(65);
            key.push(0x04);
            key.extend_from_slice(&recovered_raw.to_bytes());

            if state.active_pubkeys.contains(&key) && !seen.contains(&key) {
                seen.push(key);
            }
        }
    }

    require!(seen.len() >= min_required, QiaraTokenError::InsufficientSignatures);
    Ok(())
}

pub fn calculate_transfer_fee(
    registry: &qiara::Registry,
    epoch_config: &qiara::EpochConfig,
    header: &str,
    amount: u64,
) -> Result<u64> {
    let base_rate = read_u64(registry, header, "BURN_FEE").unwrap_or(0);
    if base_rate == 0 { return Ok(0); }

    let increase = read_u64(registry, header, "BURN_INCREASE").unwrap_or(0);
    let epoch = epoch_config.get_current_epoch()?;
    let mut rate = (base_rate as u128) + ((increase as u128) * (epoch as u128));

    if let Some(max_rate) = read_u64(registry, header, "BURN_FEE_MAXIMAL") {
        if max_rate > 0 && rate > (max_rate as u128) { rate = max_rate as u128; }
    }
    if rate > FEE_DENOMINATOR { rate = FEE_DENOMINATOR; }

    let mut fee = (((amount as u128) * rate) / FEE_DENOMINATOR) as u64;
    if let Some(raw_min) = read_u64(registry, header, "BURN_FEE_MINIMAL") {
        let min_fee = if raw_min >= 100_000 { raw_min } else { raw_min * 1000 };
        if fee < min_fee { fee = min_fee; }
    }

    Ok(if fee > amount { amount } else { fee })
}

fn read_u64(registry: &qiara::Registry, header: &str, name: &str) -> Option<u64> {
    let bytes = registry.get_active_variable(header, name)?;
    if bytes.len() == 8 {
        Some(u64::from_be_bytes(bytes.try_into().unwrap()))
    } else {
        None
    }
}

#[account]
pub struct Config {
    pub authority: Pubkey,
    pub mint: Pubkey,
    pub mint_bump: u8,
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

#[derive(Accounts)]
#[instruction(variable_header: String)]
pub struct Initialize<'info> {
    #[account(
        init,
        payer = authority,
        space = 8 + 32 + 32 + 1 + (4 + variable_header.len()) + 33,
        seeds = [b"config"],
        bump
    )]
    pub config: Account<'info, Config>,

    #[account(init, payer = authority, mint::decimals = 9, mint::authority = mint_authority)]
    pub mint: Account<'info, Mint>,

    /// CHECK: PDA mint authority
    #[account(seeds = [b"mint-authority"], bump)]
    pub mint_authority: AccountInfo<'info>,

    #[account(mut)]
    pub admin_token_account: Account<'info, TokenAccount>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
#[instruction(nullifier: [u8; 32])]
pub struct ZkMint<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    /// CHECK: Recipient user matching public signal
    pub recipient: AccountInfo<'info>,

    #[account(mut)]
    pub config: Account<'info, Config>,

    #[account(mut, address = config.mint)]
    pub mint: Account<'info, Mint>,

    /// CHECK: PDA mint authority
    #[account(seeds = [b"mint-authority"], bump = config.mint_bump)]
    pub mint_authority: AccountInfo<'info>,

    #[account(mut)]
    pub recipient_token_account: Account<'info, TokenAccount>,

    #[account(
        init,
        payer = payer,
        space = 8 + 1,
        seeds = [b"nullifier", nullifier.as_ref()],
        bump
    )]
    pub nullifier_record: Account<'info, NullifierRecord>,

    pub registry: Account<'info, qiara::Registry>,
    pub validator_state: Account<'info, qiara::ValidatorState>,

    pub system_program: Program<'info, System>,
    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct TransferWithFee<'info> {
    #[account(mut)]
    pub from: Account<'info, TokenAccount>,
    #[account(mut)]
    pub to: Account<'info, TokenAccount>,
    #[account(mut)]
    pub mint: Account<'info, Mint>,

    pub authority: Signer<'info>,
    pub config: Account<'info, Config>,
    pub registry: Account<'info, qiara::Registry>,
    pub epoch_config: Account<'info, qiara::EpochConfig>,

    #[account(mut)]
    pub fee_recipient_ata: Option<Account<'info, TokenAccount>>,

    #[account(seeds = [b"exempt", from.owner.as_ref()], bump)]
    pub sender_exempt: Option<Account<'info, ExemptRecord>>,
    #[account(seeds = [b"exempt", to.owner.as_ref()], bump)]
    pub recipient_exempt: Option<Account<'info, ExemptRecord>>,

    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct RequestBridge<'info> {
    pub user: Signer<'info>,
}

#[event]
pub struct RequestQiaraBridge {
    pub user: Pubkey,
    pub shared: String,
    pub destination_chain: String,
    pub amount: u64,
    pub timestamp: i64,
}

// Inside enum QiaraTokenError:
    #[msg("Vault: Deposit must be > 0")]
    InvalidAmount,

#[derive(Accounts)]
pub struct SetFeeExempt<'info> {
    #[account(mut)]
    pub signer: Signer<'info>,

    /// CHECK: Target wallet
    pub target_wallet: AccountInfo<'info>,

    #[account(
        init_if_needed,
        payer = signer,
        space = 8 + 32 + 1,
        seeds = [b"exempt", target_wallet.key().as_ref()],
        bump
    )]
    pub exempt_record: Account<'info, ExemptRecord>,

    pub config: Account<'info, Config>,
    pub registry: Account<'info, qiara::Registry>,
    pub system_program: Program<'info, System>,
}

#[event]
pub struct ZkMintEvent {
    pub recipient: Pubkey,
    pub amount: u64,
    pub nullifier: [u8; 32],
}

#[error_code]
pub enum QiaraTokenError {
    #[msg("Input length must equal 160 bytes for 5 public signals.")]
    InvalidInputLength,
    #[msg("Alt-BN128 Groth16 proof verification failed.")]
    InvalidProof,
    #[msg("Validator signatures below required quorum.")]
    InsufficientSignatures,
    #[msg("Recipient does not match ZK public input address.")]
    UnauthorizedRecipient,
    #[msg("Transfer fee exceeds total transfer amount.")]
    FeeExceedsAmount,
    #[msg("Signer is not authorized to edit whitelist.")]
    UnauthorizedWhitelistAdmin,
}