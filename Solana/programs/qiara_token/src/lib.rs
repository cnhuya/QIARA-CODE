use anchor_lang::prelude::*;
use anchor_spl::token::{self, Burn, Mint, MintTo, Token, TokenAccount, Transfer};

declare_id!("QiarAToken1111111111111111111111111111111111");

pub const FEE_DENOMINATOR: u128 = 100_000_000; // 1_000_000 = 1% | 250 = 0.00025%

#[program]
pub mod qiara_token {
    use super::*;

    /// Initialize Qiara Token with 1,000,000 initial supply (9 decimals)
    pub fn initialize(ctx: Context<Initialize>, variable_header: String) -> Result<()> {
        let config = &mut ctx.accounts.config;
        config.authority = ctx.accounts.authority.key();
        config.mint = ctx.accounts.mint.key();
        config.mint_bump = ctx.bumps.mint_authority;
        config.variable_header = if variable_header.is_empty() { "QiaraToken".to_string() } else { variable_header };
        config.fee_recipient = None; // None = burn fees directly

        // Mint initial supply: 1,000,000 * 10^9
        let seeds = &[b"mint-authority".as_ref(), &[config.mint_bump]];
        let signer = &[&seeds[..]];

        token::mint_to(
            CpiContext::new_with_signer(
                ctx.accounts.token_program.to_account_info(),
                MintTo {
                    mint: ctx.accounts.mint.to_account_info(),
                    to: ctx.accounts.admin_token_account.to_account_info(),
                    authority: ctx.accounts.mint_authority.to_account_info(),
                },
                signer,
            ),
            1_000_000 * 1_000_000_000,
        )?;

        Ok(())
    }


    
    /// ZK Mint: Verifies Groth16 proof & validator signatures via CPI to Qiara Delegator, then mints tokens
    pub fn zk_mint(
        ctx: Context<ZkMint>,
        nullifier: [u8; 32],
        public_inputs: Vec<u8>,
        proof_points: Vec<u8>,
        signatures: Vec<Vec<u8>>,
    ) -> Result<()> {
        require!(public_inputs.len() >= 128, QiaraTokenError::InvalidInputLength);

        // 1. Verify Groth16 proof and validator quorum via CPI to Qiara Delegator
        let cpi_accounts = qiara::cpi::accounts::VerifyBalanceProof {
            validator_state: ctx.accounts.validator_state.to_account_info(),
            registry: ctx.accounts.registry.to_account_info(),
        };
        let cpi_ctx = CpiContext::new(ctx.accounts.verifier_program.to_account_info(), cpi_accounts);
        qiara::cpi::verify_balance_proof(cpi_ctx, public_inputs.clone(), proof_points, signatures)?;

        // 2. Mark Nullifier as Used
        ctx.accounts.nullifier_record.is_used = true;

        // 3. Unpack PackedTxData from 4th public signal (offset 96..128): [Nonce:32 | ChainID:32 | Amount:64]
        let packed_bytes = &public_inputs[96..128];
        let amount = u64::from_le_bytes(packed_bytes[0..8].try_into().unwrap());
        let _chain_id = u32::from_le_bytes(packed_bytes[8..12].try_into().unwrap());
        let _nonce = u32::from_le_bytes(packed_bytes[12..16].try_into().unwrap());

        // 4. Mint tokens using PDA mint authority
        let seeds = &[b"mint-authority".as_ref(), &[ctx.accounts.config.mint_bump]];
        let signer = &[&seeds[..]];

        token::mint_to(
            CpiContext::new_with_signer(
                ctx.accounts.token_program.to_account_info(),
                MintTo {
                    mint: ctx.accounts.mint.to_account_info(),
                    to: ctx.accounts.recipient_token_account.to_account_info(),
                    authority: ctx.accounts.mint_authority.to_account_info(),
                },
                signer,
            ),
            amount,
        )?;

        emit!(ZkMintEvent {
            recipient: ctx.accounts.recipient.key(),
            amount,
            nullifier,
        });

        Ok(())
    }

    /// Transfer with dynamic epoch escalation fee
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

        // 1. Transfer net amount to recipient
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

        // 2. Handle Fee: Burn directly (if fee_recipient == None) or transfer to fee_recipient
        if fee > 0 {
            if let Some(fee_recipient_ata) = &ctx.accounts.fee_recipient_ata {
                token::transfer(
                    CpiContext::new(
                        ctx.accounts.token_program.to_account_info(),
                        Transfer {
                            from: ctx.accounts.from.to_account_info(),
                            to: fee_recipient_ata.to_account_info(),
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

    /// Set wallet fee exemption status (Authorized by WHITELIST_ADMIN from Registry or config.authority)
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

// =========================================================================
// FEE LOGIC
// =========================================================================

pub fn calculate_transfer_fee(
    registry: &qiara::Registry,
    epoch_config: &qiara::EpochConfig,
    header: &str,
    amount: u64,
) -> Result<u64> {
    let base_rate = read_u64(registry, header, "BURN_FEE").unwrap_or(0);
    if base_rate == 0 {
        return Ok(0);
    }

    let increase = read_u64(registry, header, "BURN_INCREASE").unwrap_or(0);
    let epoch = epoch_config.get_current_epoch()?;
    let mut rate = (base_rate as u128) + ((increase as u128) * (epoch as u128));

    if let Some(max_rate) = read_u64(registry, header, "BURN_FEE_MAXIMAL") {
        if max_rate > 0 && rate > (max_rate as u128) {
            rate = max_rate as u128;
        }
    }
    if rate > FEE_DENOMINATOR {
        rate = FEE_DENOMINATOR;
    }

    let mut fee = (((amount as u128) * rate) / FEE_DENOMINATOR) as u64;

    // Minimum fee: 100 in 6 decimals = 0.0001 token -> scaled to 9 decimals (* 1000)
    if let Some(raw_min) = read_u64(registry, header, "BURN_FEE_MINIMAL") {
        let min_fee = if raw_min >= 100_000 { raw_min } else { raw_min * 1000 };
        if fee < min_fee {
            fee = min_fee;
        }
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

// =========================================================================
// ACCOUNTS & CONTEXTS
// =========================================================================

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

    #[account(
        init,
        payer = authority,
        mint::decimals = 9,
        mint::authority = mint_authority,
    )]
    pub mint: Account<'info, Mint>,

    /// CHECK: PDA used as mint authority
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

    /// CHECK: Recipient user receiving minted tokens
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

    // Verification CPI accounts
    pub registry: Account<'info, qiara::Registry>,
    pub validator_state: Account<'info, qiara::ValidatorState>,
    pub verifier_program: Program<'info, qiara::program::Qiara>,

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

    // Optional fee recipient account (if configured; if omitted, tokens are burned)
    #[account(mut)]
    pub fee_recipient_ata: Option<Account<'info, TokenAccount>>,

    #[account(seeds = [b"exempt", from.owner.as_ref()], bump)]
    pub sender_exempt: Option<Account<'info, ExemptRecord>>,
    #[account(seeds = [b"exempt", to.owner.as_ref()], bump)]
    pub recipient_exempt: Option<Account<'info, ExemptRecord>>,

    pub token_program: Program<'info, Token>,
}

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

// =========================================================================
// EVENTS & ERRORS
// =========================================================================

#[event]
pub struct ZkMintEvent {
    pub recipient: Pubkey,
    pub amount: u64,
    pub nullifier: [u8; 32],
}

#[error_code]
pub enum QiaraTokenError {
    #[msg("Input length too short to contain packed tx data.")]
    InvalidInputLength,
    #[msg("Transfer fee exceeds total transfer amount.")]
    FeeExceedsAmount,
    #[msg("Signer is not authorized to edit whitelist.")]
    UnauthorizedWhitelistAdmin,
}