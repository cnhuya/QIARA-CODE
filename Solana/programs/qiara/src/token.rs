use anchor_lang::prelude::*;
use anchor_spl::token::{self, Burn, Mint, MintTo, Token, TokenAccount, Transfer};
use anchor_spl::associated_token::AssociatedToken;
use anchor_spl::metadata::{
    create_metadata_accounts_v3,
    CreateMetadataAccountsV3,
    mpl_token_metadata::types::DataV2,
    Metadata as Metaplex,
};
use crate::error::*;
use crate::state::*;
use crate::utils::verify_signatures;

pub const FEE_DENOMINATOR: u128 = 100_000_000;

// =========================================================================
// INSTRUCTION HANDLERS
// =========================================================================

pub fn handle_initialize_token(
    ctx: Context<InitializeToken>,
    variable_header: String,
    chain: String,
    chain_id: u32,
    name: String,
    symbol: String,
    uri: String,
) -> Result<()> {
    let config = &mut ctx.accounts.config;
    config.authority = ctx.accounts.authority.key();
    config.mint = ctx.accounts.mint.key();
    config.mint_bump = ctx.bumps.mint_authority;
    config.chain_id = chain_id;
    config.chain = if chain.is_empty() { "SOLANA".to_string() } else { chain };
    config.variable_header = if variable_header.is_empty() {
        "QiaraToken".to_string()
    } else {
        variable_header
    };
    config.fee_recipient = None;

    let seeds = &[b"mint-authority".as_ref(), &[config.mint_bump]];
    let signer_seeds = &[&seeds[..]];

    token::mint_to(
        CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            MintTo {
                mint: ctx.accounts.mint.to_account_info(),
                to: ctx.accounts.admin_token_account.to_account_info(),
                authority: ctx.accounts.mint_authority.to_account_info(),
            },
            signer_seeds,
        ),
        1_000_000 * 1_000_000_000,
    )?;

    let token_data = DataV2 {
        name,
        symbol,
        uri,
        seller_fee_basis_points: 0,
        creators: None,
        collection: None,
        uses: None,
    };

    create_metadata_accounts_v3(
        CpiContext::new_with_signer(
            ctx.accounts.token_metadata_program.to_account_info(),
            CreateMetadataAccountsV3 {
                metadata: ctx.accounts.metadata_account.to_account_info(),
                mint: ctx.accounts.mint.to_account_info(),
                mint_authority: ctx.accounts.mint_authority.to_account_info(),
                payer: ctx.accounts.authority.to_account_info(),
                update_authority: ctx.accounts.authority.to_account_info(),
                system_program: ctx.accounts.system_program.to_account_info(),
                rent: ctx.accounts.rent.to_account_info(),
            },
            signer_seeds,
        ),
        token_data,
        true,
        true,
        None,
    )?;

    Ok(())
}

pub fn handle_request_bridge(
    ctx: Context<RequestBridge>,
    shared: String,
    destination_chain: String,
    amount: u64,
) -> Result<()> {
    require!(amount > 0, TokenError::ZeroAmount);

    let current_epoch = ctx.accounts.epoch_config.get_current_epoch()?;

    let fee = calculate_bridge_tax(
        &ctx.accounts.registry,
        current_epoch,
        &ctx.accounts.config.variable_header,
        amount,
    );
    let net_amount = amount.checked_sub(fee).ok_or(TokenError::FeeExceedsAmount)?;
    require!(net_amount > 0, TokenError::ZeroAmount);

    if fee > 0 {
        let fee_recipient = get_fee_recipient_admin(
            &ctx.accounts.registry,
            current_epoch,
            &ctx.accounts.config.variable_header,
            &ctx.accounts.config.chain,
            ctx.accounts.config.fee_recipient,
            ctx.accounts.config.authority,
        );

        let fee_ata = ctx.accounts.fee_recipient_ata.as_ref().ok_or(TokenError::MissingFeeRecipientAta)?;
        require!(fee_ata.owner == fee_recipient, TokenError::InvalidFeeRecipient);

        token::transfer(
            CpiContext::new(
                ctx.accounts.token_program.to_account_info(),
                Transfer {
                    from: ctx.accounts.user_token_account.to_account_info(),
                    to: fee_ata.to_account_info(),
                    authority: ctx.accounts.user.to_account_info(),
                },
            ),
            fee,
        )?;
    }

    token::burn(
        CpiContext::new(
            ctx.accounts.token_program.to_account_info(),
            Burn {
                mint: ctx.accounts.mint.to_account_info(),
                from: ctx.accounts.user_token_account.to_account_info(),
                authority: ctx.accounts.user.to_account_info(),
            },
        ),
        net_amount,
    )?;

    emit!(VaultEvent {
        action: "Request Qiara Bridge".to_string(),
        data: vec![
            create_data("user", "address", ctx.accounts.user.key().to_bytes().to_vec()),
            create_data("shared", "string", shared.as_bytes().to_vec()),
            create_data("chain", "string", destination_chain.as_bytes().to_vec()),
            create_data("amount", "u64", net_amount.to_le_bytes().to_vec()),
            create_data("fee", "u64", fee.to_le_bytes().to_vec()),
        ],
    });

    Ok(())
}
pub fn handle_consensus_mint(
    ctx: Context<ConsensusMint>,
    nullifier: [u8; 32],
    raw_payload: Vec<u8>,
) -> Result<()> {
    let current_epoch = ctx.accounts.epoch_config.get_current_epoch()?;
    let signatures = &ctx.accounts.sig_buffer.signatures;

    // 1. Verify signatures over raw_payload and get computed nullifier
    let computed_nullifier = verify_signatures(
        &ctx.accounts.validator_state,
        &ctx.accounts.registry,
        signatures,
        &raw_payload,
        current_epoch,
    )?;

    // 2. Unpack canonical Move-compatible BCS payload
    let payload: MintPayload = bcs::from_bytes(&raw_payload)
        .map_err(|_| error!(QiaraError::InvalidPayloadEncoding))?;

    // 3. Replay Protection & Nullifier Checks
    require!(payload.nullifier == nullifier, TokenError::InvalidNullifier);
    require!(payload.nullifier == computed_nullifier, TokenError::InvalidNullifier);

    let nullifier_record = &mut ctx.accounts.nullifier_record;
    require!(!nullifier_record.is_used, TokenError::NullifierAlreadyUsed);
    nullifier_record.is_used = true;

    // 4. Chain ID & Recipient Guards
    if ctx.accounts.config.chain_id != 0 {
        require!(payload.chain_id == ctx.accounts.config.chain_id, TokenError::WrongChain);
    }
    require!(
        ctx.accounts.recipient.key() == payload.recipient,
        TokenError::UnauthorizedRecipient
    );

    // 5. Mint tokens via PDA authority
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
        payload.amount,
    )?;

    // 6. Emit vault event
    emit!(VaultEvent {
        action: "ConsensusMint".to_string(),
        data: vec![
            create_data("to", "address", payload.recipient.to_bytes().to_vec()),
            create_data("amount", "u64", payload.amount.to_le_bytes().to_vec()),
            create_data("nonce", "u64", payload.nonce.to_le_bytes().to_vec()),
            create_data("nullifier", "bytes32", payload.nullifier.to_vec()),
        ],
    });

    Ok(())
}

pub fn handle_transfer_with_fee(ctx: Context<TransferWithFee>, amount: u64) -> Result<()> {
    let is_sender_exempt = ctx.accounts.sender_exempt.as_ref().map_or(false, |r| r.is_exempt);

    let fee = if is_sender_exempt {
        0
    } else {
        calculate_transfer_fee(
            &ctx.accounts.registry,
            &ctx.accounts.epoch_config,
            &ctx.accounts.config.variable_header,
            amount,
        )?
    };

    let transfer_amount = amount.checked_sub(fee).ok_or(TokenError::FeeExceedsAmount)?;

    if transfer_amount > 0 {
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
    }

    if fee > 0 {
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
    Ok(())
}

pub fn handle_set_fee_exempt(ctx: Context<SetFeeExempt>, exempt: bool) -> Result<()> {
    let current_epoch = ctx.accounts.epoch_config.get_current_epoch()?;
    let authorized_admin = get_whitelist_admin(
        &ctx.accounts.registry,
        current_epoch,
        &ctx.accounts.config.variable_header,
        &ctx.accounts.config.chain,
        ctx.accounts.config.authority,
    );

    require!(
        ctx.accounts.signer.key() == authorized_admin || ctx.accounts.signer.key() == ctx.accounts.config.authority,
        TokenError::UnauthorizedWhitelistAdmin
    );

    let target_key = ctx.accounts.target_wallet.key();
    let exempt_info = &ctx.accounts.exempt_record;

    if exempt_info.data_is_empty() {
        let rent = Rent::get()?;
        let space = 8 + 32 + 1;
        let lamports = rent.minimum_balance(space);

        let seeds = &[
            b"exempt".as_ref(),
            target_key.as_ref(),
            &[ctx.bumps.exempt_record],
        ];

        anchor_lang::system_program::create_account(
            CpiContext::new_with_signer(
                ctx.accounts.system_program.to_account_info(),
                anchor_lang::system_program::CreateAccount {
                    from: ctx.accounts.signer.to_account_info(),
                    to: exempt_info.to_account_info(),
                },
                &[seeds],
            ),
            lamports,
            space as u64,
            ctx.program_id,
        )?;
    }

    let mut data = exempt_info.try_borrow_mut_data()?;
    let record = ExemptRecord {
        account: target_key,
        is_exempt: exempt,
    };

    let discriminator = &ExemptRecord::DISCRIMINATOR;
    data[..8].copy_from_slice(discriminator);
    record.try_serialize(&mut &mut data[8..])?;

    emit!(VaultEvent {
        action: "FeeExemptUpdated".to_string(),
        data: vec![
            create_data("account", "address", target_key.to_bytes().to_vec()),
            create_data("exempt", "bool", vec![if exempt { 1 } else { 0 }]),
        ],
    });

    Ok(())
}

pub fn handle_set_fee_recipient(ctx: Context<SetFeeRecipient>, new_recipient: Pubkey) -> Result<()> {
    require!(
        ctx.accounts.authority.key() == ctx.accounts.config.authority,
        TokenError::UnauthorizedAdmin
    );
    ctx.accounts.config.fee_recipient = Some(new_recipient);

    emit!(VaultEvent {
        action: "FeeRecipientUpdated".to_string(),
        data: vec![
            create_data("recipient", "address", new_recipient.to_bytes().to_vec()),
        ],
    });
    Ok(())
}

// =========================================================================
// HELPERS
// =========================================================================

pub fn calculate_transfer_fee(
    registry: &Registry,
    epoch_config: &EpochConfig,
    header: &str,
    amount: u64,
) -> Result<u64> {
    let epoch = epoch_config.get_current_epoch()?;
    let base_rate = read_u64(registry, epoch, header, "BURN_FEE").unwrap_or(0);
    if base_rate == 0 { return Ok(0); }

    let increase = read_u64(registry, epoch, header, "BURN_INCREASE").unwrap_or(0);
    let mut rate = (base_rate as u128) + ((increase as u128) * (epoch as u128));

    if let Some(max_rate) = read_u64(registry, epoch, header, "BURN_FEE_MAXIMAL") {
        if max_rate > 0 && rate > (max_rate as u128) { rate = max_rate as u128; }
    }
    if rate > FEE_DENOMINATOR { rate = FEE_DENOMINATOR; }

    let mut fee = (((amount as u128) * rate) / FEE_DENOMINATOR) as u64;
    if let Some(raw_min) = read_u64(registry, epoch, header, "BURN_FEE_MINIMAL") {
        if raw_min > 0 {
            let min_fee = if raw_min >= 100_000 { raw_min } else { raw_min * 1000 };
            if fee < min_fee { fee = min_fee; }
        }
    }

    Ok(if fee > amount { amount } else { fee })
}

pub fn calculate_bridge_tax(registry: &Registry, current_epoch: u64, header: &str, amount: u64) -> u64 {
    let rate = read_u64(registry, current_epoch, header, "BRIDGE_TAX_FEE").unwrap_or(0);
    let effective_rate = if (rate as u128) > FEE_DENOMINATOR { FEE_DENOMINATOR } else { rate as u128 };
    (((amount as u128) * effective_rate) / FEE_DENOMINATOR) as u64
}

pub fn get_whitelist_admin(
    registry: &Registry,
    current_epoch: u64,
    header: &str,
    chain: &str,
    fallback: Pubkey,
) -> Pubkey {
    let specific_var = format!("{}_WHITELIST_ADMIN", chain.to_ascii_uppercase());
    read_pubkey(registry, current_epoch, header, &specific_var)
        .or_else(|| read_pubkey(registry, current_epoch, header, "WHITELIST_ADMIN"))
        .unwrap_or(fallback)
}

pub fn get_fee_recipient_admin(
    registry: &Registry,
    current_epoch: u64,
    header: &str,
    chain: &str,
    config_recipient: Option<Pubkey>,
    fallback: Pubkey,
) -> Pubkey {
    let specific_var = format!("{}_BRIDGE_TAX_FEE_RECEIVER", chain.to_ascii_uppercase());
    read_pubkey(registry, current_epoch, header, &specific_var)
        .or_else(|| read_pubkey(registry, current_epoch, header, "BRIDGE_TAX_FEE_RECEIVER"))
        .or(config_recipient)
        .unwrap_or(fallback)
}

fn read_u64(registry: &Registry, current_epoch: u64, header: &str, name: &str) -> Option<u64> {
    let bytes = registry.get_active_variable(current_epoch, header, name)?;
    if bytes.len() == 8 {
        let be = u64::from_be_bytes(bytes.clone().try_into().unwrap());
        let le = u64::from_le_bytes(bytes.try_into().unwrap());
        if be > 0 && be <= (FEE_DENOMINATOR as u64) * 100 { Some(be) } else { Some(le) }
    } else if bytes.len() == 32 {
        Some(u64::from_be_bytes(bytes[24..32].try_into().unwrap()))
    } else {
        None
    }
}

fn read_pubkey(registry: &Registry, current_epoch: u64, header: &str, name: &str) -> Option<Pubkey> {
    let bytes = registry.get_active_variable(current_epoch, header, name)?;
    if bytes.len() == 32 {
        Some(Pubkey::new_from_array(bytes.try_into().unwrap()))
    } else {
        None
    }
}

// =========================================================================
// ACCOUNTS CONTEXTS
// =========================================================================

#[derive(Accounts)]
#[instruction(variable_header: String, chain: String, chain_id: u32, name: String, symbol: String, uri: String)]
pub struct InitializeToken<'info> {
    #[account(
        init,
        payer = authority,
        space = 8 + 32 + 32 + 1 + 4 + (4 + 32) + (4 + 64) + 33,
        seeds = [b"token_config"],
        bump
    )]
    pub config: Account<'info, TokenConfig>,

    #[account(init, payer = authority, mint::decimals = 9, mint::authority = mint_authority)]
    pub mint: Account<'info, Mint>,

    /// CHECK: PDA mint authority
    #[account(seeds = [b"mint-authority"], bump)]
    pub mint_authority: AccountInfo<'info>,

    #[account(
        init,
        payer = authority,
        associated_token::mint = mint,
        associated_token::authority = authority,
    )]
    pub admin_token_account: Account<'info, TokenAccount>,

    /// CHECK: Metaplex metadata account PDA
    #[account(
        mut,
        seeds = [
            b"metadata",
            token_metadata_program.key().as_ref(),
            mint.key().as_ref(),
        ],
        seeds::program = token_metadata_program.key(),
        bump,
    )]
    pub metadata_account: UncheckedAccount<'info>,

    #[account(mut)]
    pub authority: Signer<'info>,

    pub system_program: Program<'info, System>,
    pub token_program: Program<'info, Token>,
    pub associated_token_program: Program<'info, AssociatedToken>,
    pub token_metadata_program: Program<'info, Metaplex>,
    pub rent: Sysvar<'info, Rent>,
}

#[derive(Accounts)]
pub struct RequestBridge<'info> {
    #[account(mut)]
    pub user: Signer<'info>,

    #[account(seeds = [b"token_config"], bump)]
    pub config: Account<'info, TokenConfig>,

    pub registry: Account<'info, Registry>,
    pub epoch_config: Account<'info, EpochConfig>,

    #[account(mut, address = config.mint)]
    pub mint: Account<'info, Mint>,

    #[account(
        mut,
        token::mint = mint,
        token::authority = user,
    )]
    pub user_token_account: Account<'info, TokenAccount>,

    #[account(mut)]
    pub fee_recipient_ata: Option<Account<'info, TokenAccount>>,

    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
#[instruction(nullifier: [u8; 32], raw_payload: Vec<u8>)]
pub struct ConsensusMint<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    #[account(
        mut,
        close = payer,
        seeds = [b"sig_buffer", nullifier.as_ref()],
        bump,
        constraint = sig_buffer.message_hash == nullifier @ TokenError::InvalidNullifier
    )]
    pub sig_buffer: Account<'info, SignatureBuffer>,

    /// CHECK: Checked against payload.recipient in handler
    pub recipient: AccountInfo<'info>,

    #[account(mut, seeds = [b"token_config"], bump)]
    pub config: Account<'info, TokenConfig>,

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

    pub registry: Account<'info, Registry>,
    pub validator_state: Account<'info, ValidatorState>,
    pub epoch_config: Account<'info, EpochConfig>,
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
    #[account(seeds = [b"token_config"], bump = config.mint_bump)]
    pub config: Account<'info, TokenConfig>,
    pub registry: Account<'info, Registry>,
    pub epoch_config: Account<'info, EpochConfig>,

    #[account(seeds = [b"exempt", from.owner.as_ref()], bump)]
    pub sender_exempt: Option<Account<'info, ExemptRecord>>,

    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct SetFeeExempt<'info> {
    #[account(mut)]
    pub signer: Signer<'info>,

    /// CHECK: Target wallet being whitelisted/exempted
    pub target_wallet: AccountInfo<'info>,

    /// CHECK: PDA initialized manually if empty
    #[account(
        mut,
        seeds = [b"exempt", target_wallet.key().as_ref()],
        bump
    )]
    pub exempt_record: UncheckedAccount<'info>,

    #[account(seeds = [b"token_config"], bump = config.mint_bump)]
    pub config: Account<'info, TokenConfig>,
    pub registry: Account<'info, Registry>,
    pub epoch_config: Account<'info, EpochConfig>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct SetFeeRecipient<'info> {
    pub authority: Signer<'info>,
    #[account(mut, seeds = [b"token_config"], bump = config.mint_bump)]
    pub config: Account<'info, TokenConfig>,
}