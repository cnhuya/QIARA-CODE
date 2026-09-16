use anchor_lang::prelude::*;
use anchor_spl::token::{self as spl_token, Mint, Token, TokenAccount, MintTo, Burn};
use anchor_spl::associated_token::AssociatedToken;

declare_id!("8dBqVtWTWDyCMghvgU4YYkMRbi7vnfpRkaYUQkn4g31k");

#[program]
pub mod token {
    use super::*;

    pub fn initialize(
        ctx: Context<Initialize>,
        name: String,
        symbol: String,
        uri: String,
        _decimals: u8,
        initial_supply: u64,
    ) -> Result<()> {
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
                create_data("name", "string", name.as_bytes().to_vec()),
                create_data("symbol", "string", symbol.as_bytes().to_vec()),
                create_data("mint", "address", ctx.accounts.mint.key().to_bytes().to_vec()),
                create_data("amount", "u64", initial_supply.to_le_bytes().to_vec()),
                create_data("deployer", "address", ctx.accounts.deployer.key().to_bytes().to_vec()),
                create_data("uri", "string", uri.as_bytes().to_vec()),
            ],
        });

        Ok(())
    }

    pub fn mint_more(ctx: Context<MintMore>, amount: u64) -> Result<()> {
        let seeds: &[&[u8]] = &[b"mint", &[ctx.bumps.mint]];
        let signer_seeds = &[&seeds[..]];

        let cpi_ctx = CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            MintTo {
                mint: ctx.accounts.mint.to_account_info(),
                to: ctx.accounts.to.to_account_info(),
                authority: ctx.accounts.mint.to_account_info(),
            },
            signer_seeds,
        );
        spl_token::mint_to(cpi_ctx, amount)?;

        emit!(VaultEvent {
            action: "Mint".to_string(),
            data: vec![
                create_data("to", "address", ctx.accounts.to.key().to_bytes().to_vec()),
                create_data("amount", "u64", amount.to_le_bytes().to_vec()),
            ],
        });

        Ok(())
    }

    pub fn request_bridge(
        ctx: Context<RequestBridge>,
        shared: String,
        destination_chain: String,
        amount: u64,
    ) -> Result<()> {
        require!(amount > 0, TokenError::ZeroAmount);

        let cpi_ctx = CpiContext::new(
            ctx.accounts.token_program.to_account_info(),
            Burn {
                mint: ctx.accounts.mint.to_account_info(),
                from: ctx.accounts.user_ata.to_account_info(),
                authority: ctx.accounts.user.to_account_info(),
            },
        );
        spl_token::burn(cpi_ctx, amount)?;

        let clock = Clock::get()?;
        emit!(VaultEvent {
            action: "Request Qiara Bridge".to_string(),
            data: vec![
                create_data("user", "address", ctx.accounts.user.key().to_bytes().to_vec()),
                create_data("shared", "string", shared.as_bytes().to_vec()),
                create_data("chain", "string", destination_chain.as_bytes().to_vec()),
                create_data("amount", "u64", amount.to_le_bytes().to_vec()),
            ],
        });

        Ok(())
    }
}

// === Accounts ===

#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(mut)]
    pub deployer: Signer<'info>,

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
pub struct MintMore<'info> {
    #[account(mut)]
    pub authority: Signer<'info>,

    #[account(
        mut,
        seeds = [b"mint"],
        bump,
        mint::authority = mint,
    )]
    pub mint: Account<'info, Mint>,

    #[account(mut)]
    pub to: Account<'info, TokenAccount>,

    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct RequestBridge<'info> {
    #[account(mut)]
    pub user: Signer<'info>,

    #[account(
        mut,
        seeds = [b"mint"],
        bump,
    )]
    pub mint: Account<'info, Mint>,

    #[account(
        mut,
        associated_token::mint = mint,
        associated_token::authority = user,
    )]
    pub user_ata: Account<'info, TokenAccount>,

    pub token_program: Program<'info, Token>,
    pub system_program: Program<'info, System>,
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

#[error_code]
pub enum TokenError {
    #[msg("Bridge amount must be greater than zero")]
    ZeroAmount,
}