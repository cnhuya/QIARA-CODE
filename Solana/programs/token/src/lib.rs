use anchor_lang::prelude::*;
// Rename the imported token module to spl_token to avoid collisions
use anchor_spl::token::{self as spl_token, Mint, Token, TokenAccount, MintTo};
use anchor_spl::associated_token::AssociatedToken;

// Temporary valid Base58 program ID to make it compile.
// Replace this with your actual program ID using: solana address -k ~/solana/target/deploy/token-keypair.json
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
        let cpi_accounts = MintTo {
            mint: ctx.accounts.mint.to_account_info(),
            to: ctx.accounts.deployer_ata.to_account_info(),
            authority: ctx.accounts.mint.to_account_info(),
        };

        // Explicitly annotate type as &[&[u8]] to force slice coercion
        let seeds: &[&[u8]] = &[
            b"mint",
            &[ctx.bumps.mint],
        ];
        let signer_seeds = &[&seeds[..]];

        let cpi_ctx = CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            cpi_accounts,
            signer_seeds,
        );

        // Call using the renamed spl_token import
        spl_token::mint_to(cpi_ctx, initial_supply)?;

        msg!("Token created: {} ({})", name, symbol);
        msg!("Mint: {}", ctx.accounts.mint.key());
        msg!("Minted {} to {}", initial_supply, ctx.accounts.deployer.key());
        msg!("Metadata URI: {}", uri);

        Ok(())
    }

    pub fn mint_more(ctx: Context<MintMore>, amount: u64) -> Result<()> {
        let seeds: &[&[u8]] = &[
            b"mint",
            &[ctx.bumps.mint],
        ];
        let signer_seeds = &[&seeds[..]];

        let cpi_accounts = MintTo {
            mint: ctx.accounts.mint.to_account_info(),
            to: ctx.accounts.to.to_account_info(),
            authority: ctx.accounts.mint.to_account_info(),
        };
        let cpi_ctx = CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            cpi_accounts,
            signer_seeds,
        );
        spl_token::mint_to(cpi_ctx, amount)?;
        Ok(())
    }
}

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