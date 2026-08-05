use anchor_lang::prelude::*;
use anchor_spl::token::{self, Mint, MintTo, Token, TokenAccount};
use mpl_token_metadata::{
    instructions::{CreateMetadataAccountV3Cpi, CreateMetadataAccountV3CpiAccounts, CreateMetadataAccountV3InstructionArgs},
    types::DataV2,
};

declare_id!("BS5KzFFWnvyV2gJ2V6RoDaf4a3pxFv8E8VENyoGcHvKo");

#[program]
pub mod unified_faucet {
    use super::*;

    pub fn initialize_faucet(ctx: Context<InitializeFaucet>, cooldown_seconds: i64) -> Result<()> {
        ctx.accounts.faucet_config.admin = ctx.accounts.admin.key();
        ctx.accounts.faucet_config.cooldown_seconds = cooldown_seconds;
        ctx.accounts.faucet_config.bump = ctx.bumps.faucet_config;
        Ok(())
    }

    pub fn create_token_mint(
        ctx: Context<CreateTokenMint>,
        name: String,
        symbol: String,
        uri: String,
        decimals: u8,
        claim_amount: u64,
    ) -> Result<()> {
        require!(name.len() <= 32, FaucetError::NameTooLong);
        require!(symbol.len() <= 10, FaucetError::SymbolTooLong);

        let cfg = &mut ctx.accounts.token_config;
        cfg.mint = ctx.accounts.mint.key();
        cfg.claim_amount = claim_amount;
        cfg.enabled = true;
        cfg.bump = ctx.bumps.token_config;
        cfg.decimals = decimals;
        cfg.name = name.clone();
        cfg.symbol = symbol.clone();

        let mint_key = ctx.accounts.mint.key();
        let bump_arr = [ctx.bumps.token_config];
        let signer_seeds: &[&[u8]] = &[b"token_config", mint_key.as_ref(), &bump_arr];

        let data = DataV2 {
            name,
            symbol,
            uri,
            seller_fee_basis_points: 0,
            creators: None,
            collection: None,
            uses: None,
        };

        let metadata_info = ctx.accounts.metadata.to_account_info();
        let mint_info = ctx.accounts.mint.to_account_info();
        let mint_authority_info = ctx.accounts.token_config.to_account_info();
        let payer_info = ctx.accounts.admin.to_account_info();
        let update_authority_info = ctx.accounts.admin.to_account_info();
        let system_program_info = ctx.accounts.system_program.to_account_info();
        let rent_info = ctx.accounts.rent.to_account_info();
        let token_metadata_program_info = ctx.accounts.token_metadata_program.to_account_info();

        let cpi_accounts = CreateMetadataAccountV3CpiAccounts {
            metadata: &metadata_info,
            mint: &mint_info,
            mint_authority: &mint_authority_info,
            payer: &payer_info,
            update_authority: (&update_authority_info, true),
            system_program: &system_program_info,
            rent: Some(&rent_info),
        };

        let args = CreateMetadataAccountV3InstructionArgs {
            data,
            is_mutable: true,
            collection_details: None,
        };

        CreateMetadataAccountV3Cpi::new(
            &token_metadata_program_info,
            cpi_accounts,
            args,
        )
        .invoke_signed(&[signer_seeds])?;

        Ok(())
    }

    pub fn add_token(ctx: Context<AddToken>, name: String, symbol: String, decimals: u8, claim_amount: u64) -> Result<()> {
        let cfg = &mut ctx.accounts.token_config;
        cfg.mint = ctx.accounts.mint.key();
        cfg.claim_amount = claim_amount;
        cfg.enabled = true;
        cfg.bump = ctx.bumps.token_config;
        cfg.decimals = decimals;
        cfg.name = name;
        cfg.symbol = symbol;
        Ok(())
    }

    pub fn claim_token(ctx: Context<ClaimToken>) -> Result<()> {
        let faucet = &ctx.accounts.faucet_config;
        let token_config = &ctx.accounts.token_config;
        require!(token_config.enabled, FaucetError::TokenDisabled);
        let clock = Clock::get()?;
        if ctx.accounts.user_claim.last_claim_timestamp > 0 {
            let passed = clock.unix_timestamp.saturating_sub(ctx.accounts.user_claim.last_claim_timestamp);
            require!(passed >= faucet.cooldown_seconds, FaucetError::CooldownNotMet);
        }
        if ctx.accounts.user_claim.bump == 0 {
            ctx.accounts.user_claim.bump = ctx.bumps.user_claim;
        }
        ctx.accounts.user_claim.last_claim_timestamp = clock.unix_timestamp;

        let mint_key = ctx.accounts.mint.key();
        let bump_arr = [token_config.bump];
        let seeds: &[&[u8]] = &[b"token_config", mint_key.as_ref(), &bump_arr];
        let signer = &[seeds];

        let mint_info = ctx.accounts.mint.to_account_info();
        let user_token_info = ctx.accounts.user_token_account.to_account_info();
        let authority_info = ctx.accounts.token_config.to_account_info();
        let token_program_info = ctx.accounts.token_program.to_account_info();

        let cpi_accounts = MintTo {
            mint: mint_info,
            to: user_token_info,
            authority: authority_info,
        };
        let cpi_ctx = CpiContext::new_with_signer(token_program_info, cpi_accounts, signer);
        token::mint_to(cpi_ctx, token_config.claim_amount)?;
        Ok(())
    }

    pub fn set_claim_amount(ctx: Context<SetClaimAmount>, new_amount: u64) -> Result<()> {
        ctx.accounts.token_config.claim_amount = new_amount;
        Ok(())
    }
    pub fn set_token_enabled(ctx: Context<SetTokenEnabled>, enabled: bool) -> Result<()> {
        ctx.accounts.token_config.enabled = enabled;
        Ok(())
    }
}

#[derive(Accounts)]
pub struct InitializeFaucet<'info> {
    #[account(init, payer=admin, space=8+32+8+1, seeds=[b"faucet_config"], bump)]
    pub faucet_config: Account<'info, FaucetConfig>,
    #[account(mut)] pub admin: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(name: String, symbol: String, uri: String, decimals: u8, claim_amount: u64)]
pub struct CreateTokenMint<'info> {
    #[account(seeds=[b"faucet_config"], bump=faucet_config.bump, has_one=admin @ FaucetError::Unauthorized)]
    pub faucet_config: Account<'info, FaucetConfig>,
    #[account(init, payer=admin, mint::decimals=decimals, mint::authority=token_config, mint::freeze_authority=faucet_config)]
    pub mint: Account<'info, Mint>,
    #[account(init, payer=admin, space=300, seeds=[b"token_config", mint.key().as_ref()], bump)]
    pub token_config: Account<'info, TokenConfig>,
    /// CHECK: Metaplex metadata account, will be created by token-metadata program
    #[account(mut, seeds=[b"metadata", mpl_token_metadata::ID.as_ref(), mint.key().as_ref()], bump, seeds::program=mpl_token_metadata::ID)]
    pub metadata: UncheckedAccount<'info>,
    #[account(mut)] pub admin: Signer<'info>,
    pub system_program: Program<'info, System>,
    pub token_program: Program<'info, Token>,
    pub rent: Sysvar<'info, Rent>,
    /// CHECK: Metaplex token metadata program
    #[account(address=mpl_token_metadata::ID)]
    pub token_metadata_program: UncheckedAccount<'info>,
}

#[derive(Accounts)]
#[instruction(name: String, symbol: String, decimals: u8, claim_amount: u64)]
pub struct AddToken<'info> {
    #[account(seeds=[b"faucet_config"], bump=faucet_config.bump, has_one=admin @ FaucetError::Unauthorized)]
    pub faucet_config: Account<'info, FaucetConfig>,
    pub mint: Account<'info, Mint>,
    #[account(init, payer=admin, space=300, seeds=[b"token_config", mint.key().as_ref()], bump)]
    pub token_config: Account<'info, TokenConfig>,
    #[account(mut)] pub admin: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)] pub struct SetClaimAmount<'info> {
    #[account(seeds=[b"faucet_config"], bump=faucet_config.bump, has_one=admin @ FaucetError::Unauthorized)]
    pub faucet_config: Account<'info, FaucetConfig>,
    #[account(mut, seeds=[b"token_config", token_config.mint.as_ref()], bump=token_config.bump)]
    pub token_config: Account<'info, TokenConfig>,
    pub admin: Signer<'info>,
}
#[derive(Accounts)] pub struct SetTokenEnabled<'info> {
    #[account(seeds=[b"faucet_config"], bump=faucet_config.bump, has_one=admin @ FaucetError::Unauthorized)]
    pub faucet_config: Account<'info, FaucetConfig>,
    #[account(mut, seeds=[b"token_config", token_config.mint.as_ref()], bump=token_config.bump)]
    pub token_config: Account<'info, TokenConfig>,
    pub admin: Signer<'info>,
}
#[derive(Accounts)] pub struct ClaimToken<'info> {
    #[account(seeds=[b"faucet_config"], bump=faucet_config.bump)] pub faucet_config: Account<'info, FaucetConfig>,
    #[account(seeds=[b"token_config", mint.key().as_ref()], bump=token_config.bump)] pub token_config: Account<'info, TokenConfig>,
    #[account(mut)] pub mint: Account<'info, Mint>,
    #[account(mut, constraint=user_token_account.mint==mint.key(), constraint=user_token_account.owner==user.key())]
    pub user_token_account: Account<'info, TokenAccount>,
    #[account(init_if_needed, payer=user, space=8+8+1, seeds=[b"user_claim", user.key().as_ref(), mint.key().as_ref()], bump)]
    pub user_claim: Account<'info, UserClaim>,
    #[account(mut)] pub user: Signer<'info>,
    pub token_program: Program<'info, Token>,
    pub system_program: Program<'info, System>,
}

#[account] pub struct FaucetConfig { pub admin: Pubkey, pub cooldown_seconds: i64, pub bump: u8 }
#[account] pub struct TokenConfig {
    pub mint: Pubkey, pub claim_amount: u64, pub enabled: bool, pub bump: u8, pub decimals: u8,
    pub name: String, pub symbol: String,
}
#[account] pub struct UserClaim { pub last_claim_timestamp: i64, pub bump: u8 }

#[error_code] pub enum FaucetError {
    #[msg("Cooldown")] CooldownNotMet,
    #[msg("Disabled")] TokenDisabled,
    #[msg("Unauthorized")] Unauthorized,
    #[msg("Name too long")] NameTooLong,
    #[msg("Symbol too long")] SymbolTooLong,
}
