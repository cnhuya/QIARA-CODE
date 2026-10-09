use anchor_lang::prelude::*;
use anchor_lang::solana_program::{keccak, secp256k1_recover::secp256k1_recover};
use anchor_spl::associated_token::AssociatedToken;
use anchor_spl::token::{self as spl_token, Burn, Mint, MintTo, Token, TokenAccount, Transfer};

declare_id!("8dBqVtWTWDyCMghvgU4YYkMRbi7vnfpRkaYUQkn4g31k");

pub const FEE_DENOMINATOR: u64 = 100_000_000;
pub const MAX_VALIDATORS: usize = 32;

#[program]
pub mod qiara_token {
    use super::*;

    /// Initialize the Qiara token, Config state, Validator registry, and mint initial supply.
    pub fn initialize(
        ctx: Context<Initialize>,
        chain_id: u32,
        chain_name: String,
        min_validators: u8,
        initial_validators: Vec<[u8; 20]>,
    ) -> Result<()> {
        let config = &mut ctx.accounts.config;
        config.admin = ctx.accounts.deployer.key();
        config.whitelist_admin = ctx.accounts.deployer.key();
        config.fee_recipient = ctx.accounts.fee_recipient.key();
        config.chain_id = chain_id;
        config.chain_name = chain_name.clone();
        config.min_validators = min_validators;
        config.current_epoch = 0;
        config.base_fee_rate = 0;
        config.burn_increase = 0;
        config.burn_fee_maximal = 0;
        config.burn_fee_minimal = 0;
        config.bridge_tax_fee = 0;
        config.bump = ctx.bumps.config;
        config.mint_bump = ctx.bumps.mint;

        let registry = &mut ctx.accounts.validator_registry;
        require!(
            initial_validators.len() <= MAX_VALIDATORS,
            TokenError::TooManyValidators
        );
        registry.validators = initial_validators;

        // Mint initial supply of 1,000,000 tokens (with 9 decimals)
        let initial_supply: u64 = 1_000_000 * 10u64.pow(9);
        let seeds: &[&[u8]] = &[b"mint", &[ctx.bumps.mint]];
        let signer_seeds = &[&seeds[..]];

        let cpi_ctx = CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            MintTo {
                mint: ctx.accounts.mint.to_account_info(),
                to: ctx.accounts.deployer_ata.to_account_info(),
                authority: ctx.accounts.mint.to_account_info(),
            },
            signer_seeds,
        );
        spl_token::mint_to(cpi_ctx, initial_supply)?;

        emit!(VaultEvent {
            action: "Token Created".to_string(),
            data: vec![
                create_data("name", "string", "Qiara".as_bytes().to_vec()),
                create_data("symbol", "string", "Qiara".as_bytes().to_vec()),
                create_data("chain", "string", chain_name.as_bytes().to_vec()),
                create_data("mint", "address", ctx.accounts.mint.key().to_bytes().to_vec()),
                create_data("amount", "u64", initial_supply.to_le_bytes().to_vec()),
                create_data("deployer", "address", ctx.accounts.deployer.key().to_bytes().to_vec()),
            ],
        });

        Ok(())
    }

    /// ZK Mint with Groth16 signals and validator signatures verification
    pub fn zk_mint(
        ctx: Context<ZkMint>,
        _proof: [u8; 256],          // Groth16 proof (A, B, C)
        pub_signals: [[u8; 32]; 5],  // 5 public inputs
        signatures: Vec<u8>,        // Concatenated 65-byte ECDSA signatures (r, s, v)
    ) -> Result<()> {
        let config = &ctx.accounts.config;

        // Signal 4: PackedTxData = [Amount:64 | ChainID:32 | Nonce:32] (EVM Big-Endian byte layout)
        let signal_4 = &pub_signals[4];
        let amount = u64::from_be_bytes(signal_4[24..32].try_into().unwrap());
        let chain_id = u32::from_be_bytes(signal_4[20..24].try_into().unwrap());
        let nonce = u32::from_be_bytes(signal_4[16..20].try_into().unwrap());

        require!(chain_id == config.chain_id, TokenError::WrongChain);

        // Compute nullifier = keccak256(pubSignals[0..5])
        let mut packed_signals = [0u8; 160];
        for i in 0..5 {
            packed_signals[i * 32..(i + 1) * 32].copy_from_slice(&pub_signals[i]);
        }
        let nullifier = keccak::hash(&packed_signals);

        // Verify nullifier matches the PDA seed
        require!(
            ctx.accounts.nullifier_record.key()
                == Pubkey::find_program_address(
                    &[b"nullifier", nullifier.as_ref()],
                    ctx.program_id
                )
                .0,
            TokenError::ReplayAttack
        );

        // Verify Multi-Validator Signatures
        verify_signatures(
            nullifier.0,
            &signatures,
            config.min_validators as usize,
            &ctx.accounts.validator_registry.validators,
        )?;

        // Mint tokens to recipient
        let seeds: &[&[u8]] = &[b"mint", &[config.mint_bump]];
        let signer_seeds = &[&seeds[..]];

        let cpi_ctx = CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            MintTo {
                mint: ctx.accounts.mint.to_account_info(),
                to: ctx.accounts.user_ata.to_account_info(),
                authority: ctx.accounts.mint.to_account_info(),
            },
            signer_seeds,
        );
        spl_token::mint_to(cpi_ctx, amount)?;

        // Mark nullifier as used
        let nullifier_record = &mut ctx.accounts.nullifier_record;
        nullifier_record.nullifier = nullifier.0;

        emit!(VaultEvent {
            action: "ZkMint".to_string(),
            data: vec![
                create_data("to", "address", ctx.accounts.user.key().to_bytes().to_vec()),
                create_data("amount", "uint256", amount.to_le_bytes().to_vec()),
                create_data("nonce", "uint256", (nonce as u64).to_le_bytes().to_vec()),
                create_data("nullifier", "uint256", nullifier.0.to_vec()),
            ],
        });

        Ok(())
    }

    /// Request bridge: bridges tokens to destination chain, burns net amount, sends tax to fee_recipient
    pub fn request_bridge(
        ctx: Context<RequestBridge>,
        shared: String,
        destination_chain: String,
        amount: u64,
    ) -> Result<()> {
        require!(amount > 0, TokenError::ZeroAmount);

        let fee = calculate_bridge_tax(amount, ctx.accounts.config.bridge_tax_fee);
        let net_amount = amount.checked_sub(fee).ok_or(TokenError::ArithmeticOverflow)?;
        require!(net_amount > 0, TokenError::ZeroAmount);

        // 1. Send bridge tax to fee_recipient
        if fee > 0 {
            let cpi_transfer = CpiContext::new(
                ctx.accounts.token_program.to_account_info(),
                Transfer {
                    from: ctx.accounts.user_ata.to_account_info(),
                    to: ctx.accounts.fee_recipient_ata.to_account_info(),
                    authority: ctx.accounts.user.to_account_info(),
                },
            );
            spl_token::transfer(cpi_transfer, fee)?;
        }

        // 2. Burn net amount leaving this chain
        let cpi_burn = CpiContext::new(
            ctx.accounts.token_program.to_account_info(),
            Burn {
                mint: ctx.accounts.mint.to_account_info(),
                from: ctx.accounts.user_ata.to_account_info(),
                authority: ctx.accounts.user.to_account_info(),
            },
        );
        spl_token::burn(cpi_burn, net_amount)?;

        emit!(VaultEvent {
            action: "Request Qiara Bridge".to_string(),
            data: vec![
                create_data("user", "address", ctx.accounts.user.key().to_bytes().to_vec()),
                create_data("shared", "string", shared.as_bytes().to_vec()),
                create_data("chain", "string", destination_chain.as_bytes().to_vec()),
                create_data("amount", "uint256", net_amount.to_le_bytes().to_vec()),
                create_data("fee", "uint256", fee.to_le_bytes().to_vec()),
            ],
        });

        Ok(())
    }

    /// Standard transfer that burns dynamic transfer fee unless sender is whitelisted
    pub fn transfer(ctx: Context<TransferTokens>, amount: u64) -> Result<()> {
        require!(amount > 0, TokenError::ZeroAmount);

        let is_exempt = match &ctx.accounts.fee_exemption {
            Some(record) => record.is_exempt,
            None => false,
        };

        if is_exempt {
            // Transfer without fee
            let cpi_transfer = CpiContext::new(
                ctx.accounts.token_program.to_account_info(),
                Transfer {
                    from: ctx.accounts.from_ata.to_account_info(),
                    to: ctx.accounts.to_ata.to_account_info(),
                    authority: ctx.accounts.authority.to_account_info(),
                },
            );
            spl_token::transfer(cpi_transfer, amount)?;
        } else {
            let fee = calculate_transfer_fee(amount, &ctx.accounts.config);
            let send_amount = amount.checked_sub(fee).ok_or(TokenError::ArithmeticOverflow)?;

            if fee > 0 {
                // Burn the fee
                let cpi_burn = CpiContext::new(
                    ctx.accounts.token_program.to_account_info(),
                    Burn {
                        mint: ctx.accounts.mint.to_account_info(),
                        from: ctx.accounts.from_ata.to_account_info(),
                        authority: ctx.accounts.authority.to_account_info(),
                    },
                );
                spl_token::burn(cpi_burn, fee)?;
            }

            if send_amount > 0 {
                let cpi_transfer = CpiContext::new(
                    ctx.accounts.token_program.to_account_info(),
                    Transfer {
                        from: ctx.accounts.from_ata.to_account_info(),
                        to: ctx.accounts.to_ata.to_account_info(),
                        authority: ctx.accounts.authority.to_account_info(),
                    },
                );
                spl_token::transfer(cpi_transfer, send_amount)?;
            }
        }

        Ok(())
    }

    /// Whitelist administration: set fee exemption for a given account
    pub fn set_fee_exempt(ctx: Context<SetFeeExempt>, exempt: bool) -> Result<()> {
        let exemption = &mut ctx.accounts.fee_exemption;
        exemption.account = ctx.accounts.target.key();
        exemption.is_exempt = exempt;

        emit!(VaultEvent {
            action: "FeeExemptUpdated".to_string(),
            data: vec![
                create_data("account", "address", ctx.accounts.target.key().to_bytes().to_vec()),
                create_data("exempt", "bool", vec![if exempt { 1 } else { 0 }]),
            ],
        });

        Ok(())
    }

    /// Update fee receiver
    pub fn set_fee_recipient(ctx: Context<AdminOnly>, new_recipient: Pubkey) -> Result<()> {
        let config = &mut ctx.accounts.config;
        config.fee_recipient = new_recipient;

        emit!(VaultEvent {
            action: "FeeRecipientUpdated".to_string(),
            data: vec![
                create_data("recipient", "address", new_recipient.to_bytes().to_vec()),
            ],
        });

        Ok(())
    }

    /// Update whitelist admin
    pub fn set_whitelist_admin(ctx: Context<AdminOnly>, new_admin: Pubkey) -> Result<()> {
        ctx.accounts.config.whitelist_admin = new_admin;
        Ok(())
    }

    /// Update dynamic fee settings
    pub fn update_fee_config(
        ctx: Context<AdminOnly>,
        base_fee_rate: u64,
        burn_increase: u64,
        burn_fee_maximal: u64,
        burn_fee_minimal: u64,
        bridge_tax_fee: u64,
    ) -> Result<()> {
        let config = &mut ctx.accounts.config;
        config.base_fee_rate = base_fee_rate;
        config.burn_increase = burn_increase;
        config.burn_fee_maximal = burn_fee_maximal;
        config.burn_fee_minimal = burn_fee_minimal;
        config.bridge_tax_fee = bridge_tax_fee;
        Ok(())
    }

    /// Advance epoch
    pub fn set_epoch(ctx: Context<AdminOnly>, new_epoch: u64) -> Result<()> {
        ctx.accounts.config.current_epoch = new_epoch;
        Ok(())
    }

    /// Update active bridge validators
    pub fn set_validators(
        ctx: Context<AdminOnly>,
        new_validators: Vec<[u8; 20]>,
        min_validators: u8,
    ) -> Result<()> {
        require!(new_validators.len() <= MAX_VALIDATORS, TokenError::TooManyValidators);
        ctx.accounts.validator_registry.validators = new_validators;
        ctx.accounts.config.min_validators = min_validators;
        Ok(())
    }
}

// === Calculations ===

pub fn calculate_transfer_fee(value: u64, config: &Config) -> u64 {
    if config.base_fee_rate == 0 {
        return 0;
    }

    let increase = config.burn_increase.saturating_mul(config.current_epoch);
    let mut rate = config.base_fee_rate.saturating_add(increase);

    if config.burn_fee_maximal > 0 && rate > config.burn_fee_maximal {
        rate = config.burn_fee_maximal;
    } else if rate > FEE_DENOMINATOR {
        rate = FEE_DENOMINATOR;
    }

    let mut fee = ((value as u128) * (rate as u128) / (FEE_DENOMINATOR as u128)) as u64;

    let raw_min = config.burn_fee_minimal;
    if raw_min > 0 {
        let min_fee = if raw_min >= 100_000 { raw_min } else { raw_min * 1000 };
        if fee < min_fee {
            fee = min_fee;
        }
    }

    if fee > value {
        value
    } else {
        fee
    }
}

pub fn calculate_bridge_tax(amount: u64, bridge_tax_rate: u64) -> u64 {
    let rate = if bridge_tax_rate > FEE_DENOMINATOR {
        FEE_DENOMINATOR
    } else {
        bridge_tax_rate
    };
    ((amount as u128) * (rate as u128) / (FEE_DENOMINATOR as u128)) as u64
}

// === Signature Verification Helper ===

pub fn verify_signatures(
    message_hash: [u8; 32],
    signatures: &[u8],
    min_validators: usize,
    active_validators: &[[u8; 20]],
) -> Result<()> {
    let num_sigs = signatures.len() / 65;
    require!(num_sigs > 0 && signatures.len() % 65 == 0, TokenError::InvalidSignatures);
    require!(num_sigs >= min_validators, TokenError::InsufficientValidators);

    // Ethereum Signed Message: "\x19Ethereum Signed Message:\n32" + messageHash
    let mut eth_msg = [0u8; 60];
    eth_msg[..28].copy_from_slice(b"\x19Ethereum Signed Message:\n32");
    eth_msg[28..60].copy_from_slice(&message_hash);
    let eth_signed_hash = keccak::hash(&eth_msg);

    let mut last_signer = [0u8; 20];

    for i in 0..num_sigs {
        let offset = i * 65;
        let mut r = [0u8; 32];
        let mut s = [0u8; 32];
        r.copy_from_slice(&signatures[offset..offset + 32]);
        s.copy_from_slice(&signatures[offset + 32..offset + 64]);
        let v = signatures[offset + 64];

        let recovery_id = if v >= 27 { v - 27 } else { v };

        let mut sig64 = [0u8; 64];
        sig64[..32].copy_from_slice(&r);
        sig64[32..].copy_from_slice(&s);

        let recovered_pubkey = secp256k1_recover(&eth_signed_hash.0, recovery_id, &sig64)
            .map_err(|_| TokenError::InvalidSignatures)?;

        // Address is last 20 bytes of keccak256(pubkey_uncompressed_64)
        let hash = keccak::hash(&recovered_pubkey.0);
        let mut signer = [0u8; 20];
        signer.copy_from_slice(&hash.0[12..32]);

        // Duplicate and sorted check: signer must be strictly greater than last_signer
        require!(signer > last_signer, TokenError::DuplicateSignature);
        last_signer = signer;

        // Check if signer is an authorized active validator
        let is_authorized = active_validators.iter().any(|v| *v == signer);
        require!(is_authorized, TokenError::UnauthorizedValidator);
    }

    Ok(())
}

// === Account Contexts ===

#[derive(Accounts)]
#[instruction(chain_id: u32, chain_name: String)]
pub struct Initialize<'info> {
    #[account(mut)]
    pub deployer: Signer<'info>,

    /// CHECK: Target recipient of bridge taxes
    pub fee_recipient: AccountInfo<'info>,

    #[account(
        init,
        payer = deployer,
        space = 8 + Config::INIT_SPACE,
        seeds = [b"config"],
        bump,
    )]
    pub config: Account<'info, Config>,

    #[account(
        init,
        payer = deployer,
        space = 8 + 4 + (MAX_VALIDATORS * 20),
        seeds = [b"validators"],
        bump,
    )]
    pub validator_registry: Account<'info, ValidatorRegistry>,

    #[account(
        init,
        payer = deployer,
        seeds = [b"mint"],
        bump,
        mint::decimals = 9,
        mint::authority = mint,
        mint::freeze_authority = mint,
    )]
    pub mint: Account<'info, Mint>,

    #[account(
        init,
        payer = deployer,
        associated_token::mint = mint,
        associated_token::authority = deployer,
    )]
    pub deployer_ata: Account<'info, TokenAccount>,

    pub token_program: Program<'info, Token>,
    pub associated_token_program: Program<'info, AssociatedToken>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(_proof: [u8; 256], pub_signals: [[u8; 32]; 5])]
pub struct ZkMint<'info> {
    #[account(mut)]
    pub user: Signer<'info>,

    #[account(
        seeds = [b"config"],
        bump = config.bump
    )]
    pub config: Account<'info, Config>,

    #[account(
        seeds = [b"validators"],
        bump
    )]
    pub validator_registry: Account<'info, ValidatorRegistry>,

    #[account(
        init,
        payer = user,
        space = 8 + 32,
        seeds = [b"nullifier", keccak::hash(&get_signals_bytes(&pub_signals)).as_ref()],
        bump
    )]
    pub nullifier_record: Account<'info, NullifierRecord>,

    #[account(
        mut,
        seeds = [b"mint"],
        bump = config.mint_bump,
    )]
    pub mint: Account<'info, Mint>,

    #[account(
        init_if_needed,
        payer = user,
        associated_token::mint = mint,
        associated_token::authority = user,
    )]
    pub user_ata: Account<'info, TokenAccount>,

    pub token_program: Program<'info, Token>,
    pub associated_token_program: Program<'info, AssociatedToken>,
    pub system_program: Program<'info, System>,
}

fn get_signals_bytes(signals: &[[u8; 32]; 5]) -> [u8; 160] {
    let mut out = [0u8; 160];
    for i in 0..5 {
        out[i * 32..(i + 1) * 32].copy_from_slice(&signals[i]);
    }
    out
}

#[derive(Accounts)]
pub struct RequestBridge<'info> {
    #[account(mut)]
    pub user: Signer<'info>,

    #[account(
        seeds = [b"config"],
        bump = config.bump,
    )]
    pub config: Account<'info, Config>,

    #[account(
        mut,
        seeds = [b"mint"],
        bump = config.mint_bump,
    )]
    pub mint: Account<'info, Mint>,

    #[account(
        mut,
        associated_token::mint = mint,
        associated_token::authority = user,
    )]
    pub user_ata: Account<'info, TokenAccount>,

    #[account(
        mut,
        associated_token::mint = mint,
        associated_token::authority = config.fee_recipient,
    )]
    pub fee_recipient_ata: Account<'info, TokenAccount>,

    pub token_program: Program<'info, Token>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct TransferTokens<'info> {
    #[account(mut)]
    pub authority: Signer<'info>,

    #[account(
        seeds = [b"config"],
        bump = config.bump,
    )]
    pub config: Account<'info, Config>,

    #[account(
        mut,
        seeds = [b"mint"],
        bump = config.mint_bump,
    )]
    pub mint: Account<'info, Mint>,

    #[account(
        mut,
        token::authority = authority,
        token::mint = mint,
    )]
    pub from_ata: Account<'info, TokenAccount>,

    #[account(
        mut,
        token::mint = mint,
    )]
    pub to_ata: Account<'info, TokenAccount>,

    #[account(
        seeds = [b"fee_exempt", authority.key().as_ref()],
        bump,
    )]
    pub fee_exemption: Option<Account<'info, FeeExemption>>,

    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct SetFeeExempt<'info> {
    #[account(
        mut,
        constraint = authority.key() == config.admin || authority.key() == config.whitelist_admin @ TokenError::UnauthorizedWhitelistAdmin
    )]
    pub authority: Signer<'info>,

    pub config: Account<'info, Config>,

    /// CHECK: Target address being exempted/unexempted
    pub target: AccountInfo<'info>,

    #[account(
        init_if_needed,
        payer = authority,
        space = 8 + FeeExemption::INIT_SPACE,
        seeds = [b"fee_exempt", target.key().as_ref()],
        bump
    )]
    pub fee_exemption: Account<'info, FeeExemption>,

    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct AdminOnly<'info> {
    #[account(
        mut,
        constraint = admin.key() == config.admin @ TokenError::UnauthorizedAdmin
    )]
    pub admin: Signer<'info>,

    #[account(
        mut,
        seeds = [b"config"],
        bump = config.bump
    )]
    pub config: Account<'info, Config>,

    #[account(
        mut,
        seeds = [b"validators"],
        bump
    )]
    pub validator_registry: Account<'info, ValidatorRegistry>,
}

// === State Accounts ===

#[account]
#[derive(InitSpace)]
pub struct Config {
    pub admin: Pubkey,
    pub whitelist_admin: Pubkey,
    pub fee_recipient: Pubkey,
    pub chain_id: u32,
    #[max_len(32)]
    pub chain_name: String,
    pub min_validators: u8,
    pub current_epoch: u64,
    pub base_fee_rate: u64,
    pub burn_increase: u64,
    pub burn_fee_maximal: u64,
    pub burn_fee_minimal: u64,
    pub bridge_tax_fee: u64,
    pub bump: u8,
    pub mint_bump: u8,
}

#[account]
pub struct ValidatorRegistry {
    pub validators: Vec<[u8; 20]>,
}

#[account]
pub struct NullifierRecord {
    pub nullifier: [u8; 32],
}

#[account]
#[derive(InitSpace)]
pub struct FeeExemption {
    pub account: Pubkey,
    pub is_exempt: bool,
}

// === Custom Events ===

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
fn create_data(name: &str, type_name: &str, value: Vec<u8>) -> EventData {
    EventData {
        name: name.to_string(),
        type_name: type_name.to_string(),
        value,
    }
}

// === Error Codes ===

#[error_code]
pub enum TokenError {
    #[msg("Bridge or transfer amount must be greater than zero")]
    ZeroAmount,
    #[msg("Chain ID does not match")]
    WrongChain,
    #[msg("Nullifier has already been used")]
    ReplayAttack,
    #[msg("Signatures length is invalid")]
    InvalidSignatures,
    #[msg("Not enough unique validator signatures provided")]
    InsufficientValidators,
    #[msg("Duplicate or unsorted signature detected")]
    DuplicateSignature,
    #[msg("Signer is not an active validator")]
    UnauthorizedValidator,
    #[msg("Caller is not authorized to modify whitelist")]
    UnauthorizedWhitelistAdmin,
    #[msg("Caller is not authorized admin")]
    UnauthorizedAdmin,
    #[msg("Too many validators configured")]
    TooManyValidators,
    #[msg("Arithmetic overflow")]
    ArithmeticOverflow,
}