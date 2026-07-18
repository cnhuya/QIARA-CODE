// programs/vault/src/lib.rs
use anchor_lang::prelude::*;
use anchor_spl::token::{self, Token, TokenAccount, Transfer};

// Import the core Qiara State program
use qiara::program::Qiara;

pub mod extractor;
//AGfiBehJcHhXEspoCSQJ8kterZxSgMspmoaxhKxLgn2y
declare_id!("AGfiBehJcHhXEspoCSQJ8kterZxSgMspmoaxhKxLgn2y");

const MIN_RATE: u64 = 2_750_000;
const MAX_RATE: u64 = 11_275_000;

#[program]
pub mod vault {
    use super::*;

    pub fn create_vault(ctx: Context<CreateVault>, provider_name: String) -> Result<()> {
        let vault_key = format!("{}_vault", provider_name);
        let registry_bytes = ctx.accounts.registry.get_active_variable("QiaraSolanaAssets", &vault_key)
            .ok_or(error!(QiaraError::WrongProviderProvided))?;
        
        require!(registry_bytes.len() == 32, QiaraError::RegistryLocked);
        let expected_vault_pubkey = Pubkey::new_from_array(registry_bytes.try_into().unwrap());
        require!(ctx.accounts.vault.key() == expected_vault_pubkey, QiaraError::WrongProviderProvided);

        let vault = &mut ctx.accounts.vault;
        vault.provider_name = provider_name;
        vault.authority = ctx.accounts.payer.key();
        vault.bump = ctx.bumps.vault;
        Ok(())
    }

    pub fn list_new_token(ctx: Context<ListNewToken>, asset_name: String) -> Result<()> {
        let vault = &ctx.accounts.vault;
        let token_mint = ctx.accounts.token_mint.key();

        let token_key = format!("{}_{}", asset_name, vault.provider_name);
        let registry_bytes = ctx.accounts.registry.get_active_variable("QiaraSolanaAssets", &token_key)
            .ok_or(error!(QiaraError::WrongProviderProvided))?;

        require!(registry_bytes.len() == 32, QiaraError::RegistryLocked);
        let expected_mint_pubkey = Pubkey::new_from_array(registry_bytes.try_into().unwrap());
        require!(token_mint == expected_mint_pubkey, QiaraError::WrongProviderProvided);

        let supported_token = &mut ctx.accounts.supported_token;
        supported_token.is_supported = true;

        emit!(TokenListed {
            vault: vault.key(),
            token_mint,
            provider_name: vault.provider_name.clone(),
        });

        Ok(())
    }
pub fn deposit(
        ctx: Context<DepositYieldToken>,
        shared: String,
        _token_name: String,
        amount: u64,
    ) -> Result<()> {
        let user_state = &mut ctx.accounts.user_state;

        let cpi_accounts = Transfer {
            from: ctx.accounts.user_ata.to_account_info(),
            to: ctx.accounts.vault_ata.to_account_info(),
            authority: ctx.accounts.payer.to_account_info(),
        };
        let cpi_program = ctx.accounts.token_program.to_account_info();
        let cpi_ctx = CpiContext::new(cpi_program, cpi_accounts);
        token::transfer(cpi_ctx, amount)?;

        let rate = get_pseudo_random_rate(&ctx.accounts.payer.key())?;
        let rewards = accrue_user_yield(user_state, rate)?;

        let clock = Clock::get()?;
        user_state.balance = user_state.balance
            .checked_add(amount)
            .unwrap()
            .checked_add(rewards)
            .unwrap();
        user_state.last_interacted_timestamp = clock.unix_timestamp;

        // 1. Pack deposit parameters into your dynamic Data structure
        let data = vec![
            Data { name: "sender".to_string(), type_name: "address".to_string(), value: ctx.accounts.payer.key().to_bytes().to_vec() },
            Data { name: "shared".to_string(), type_name: "string".to_string(), value: shared.into_bytes() },
            Data { name: "token".to_string(), type_name: "string".to_string(), value: "Solana".as_bytes().to_vec() },
            Data { name: "provider".to_string(), type_name: "string".to_string(), value: ctx.accounts.vault.provider_name.clone().into_bytes() },
            Data { name: "amount".to_string(), type_name: "u64".to_string(), value: amount.to_le_bytes().to_vec() },
            Data { name: "rate".to_string(), type_name: "u64".to_string(), value: rate.to_le_bytes().to_vec() },
            Data { name: "rewards".to_string(), type_name: "u64".to_string(), value: rewards.to_le_bytes().to_vec() },
        ];

        // 2. Emit the event natively as a VaultEvent [1]
        emit!(VaultEvent {
            name: "Deposit".to_string(),
            aux: data,
        });

        Ok(())
    }

   pub fn direct_withdraw(
        ctx: Context<DirectWithdrawYieldToken>,
        _shared: String,
        token_name: String,
        public_inputs: Vec<u8>,
        _proof_points: Vec<u8>,
    ) -> Result<()> {
        require!(ctx.accounts.verifier_program.key() == qiara::id(), QiaraError::NotValidator);

        let user_address = extractor::extract_user_address(&public_inputs)?;
        let tx_data = extractor::extract_all_tx_data(&public_inputs)?;
        let proof_provider_name = extractor::extract_provider(&public_inputs)?;

        require!(ctx.accounts.vault.provider_name == proof_provider_name, QiaraError::WrongProviderProvided);
        require!(ctx.accounts.user.key() == user_address, QiaraError::NotValidator);

        let user_state = &mut ctx.accounts.user_state;

        let rate = get_pseudo_random_rate(&ctx.accounts.user.key())?;
        let rewards = accrue_user_yield(user_state, rate)?;

        let total_available = user_state.balance.checked_add(rewards).unwrap();
        let amount = tx_data.amount;
        require!(total_available >= amount, QiaraError::InsufficientBalance);

        let clock = Clock::get()?;
        user_state.balance = total_available.checked_sub(amount).unwrap();
        user_state.last_interacted_timestamp = clock.unix_timestamp;

        let provider_name_bytes = ctx.accounts.vault.provider_name.as_bytes();
        let vault_bump = ctx.accounts.vault.bump;
        let seeds = &[
            b"vault",
            provider_name_bytes,
            &[vault_bump],
        ];
        let signer_seeds = &[&seeds[..]];

        let cpi_accounts = Transfer {
            from: ctx.accounts.vault_ata.to_account_info(),
            to: ctx.accounts.user_ata.to_account_info(),
            authority: ctx.accounts.vault.to_account_info(),
        };
        let cpi_program = ctx.accounts.token_program.to_account_info();
        let cpi_ctx = CpiContext::new_with_signer(cpi_program, cpi_accounts, signer_seeds);
        token::transfer(cpi_ctx, amount)?;

        // 1. Pack withdrawal parameters into your dynamic Data structure
        let data = vec![
            Data { name: "addr".to_string(), type_name: "address".to_string(), value: user_address.to_bytes().to_vec() },
            Data { name: "token".to_string(), type_name: "string".to_string(), value: token_name.into_bytes() },
            Data { name: "provider".to_string(), type_name: "string".to_string(), value: proof_provider_name.into_bytes() },
            Data { name: "amount".to_string(), type_name: "u64".to_string(), value: amount.to_le_bytes().to_vec() },
            Data { name: "rewards".to_string(), type_name: "u64".to_string(), value: rewards.to_le_bytes().to_vec() },
        ];

        // 2. Emit the event natively as a VaultEvent [1]
        emit!(VaultEvent {
            name: "DirectWithdraw".to_string(),
            aux: data,
        });

        Ok(())
    }
}

// ==========================================
// DATA STRUCTURES
// ==========================================

#[account]
pub struct UserState {
    pub balance: u64,
    pub last_interacted_timestamp: i64,
}

#[account]
pub struct Vault {
    pub provider_name: String,
    pub authority: Pubkey,
    pub bump: u8,
}

#[account]
pub struct SupportedToken {
    pub is_supported: bool,
}

// ==========================================
// CONTEXTS
// ==========================================

#[derive(Accounts)]
#[instruction(provider_name: String)]
pub struct CreateVault<'info> {
    #[account(
        init,
        payer = payer,
        space = 8 + 4 + provider_name.len() + 32 + 1,
        seeds = [b"vault", provider_name.as_bytes()],
        bump
    )]
    pub vault: Account<'info, Vault>,
 pub registry: Account<'info, qiara::Registry>, // Removed state:: [1.2.3]
    #[account(mut)]
    pub payer: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(asset_name: String)]
pub struct ListNewToken<'info> {
    pub vault: Account<'info, Vault>,
    pub registry: Account<'info, qiara::Registry>, // Removed state:: [1.2.3]
    #[account(
        init,
        payer = payer,
        space = 8 + 1,
        seeds = [b"supported-token", vault.key().as_ref(), token_mint.key().as_ref()],
        bump
    )]
    pub supported_token: Account<'info, SupportedToken>,
    /// CHECK: Safe
    pub token_mint: UncheckedAccount<'info>,
    #[account(mut)]
    pub payer: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(shared: String)]
pub struct DepositYieldToken<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    #[account(
        init_if_needed,
        payer = payer,
        space = 8 + 8 + 8,
        seeds = [b"user-state", payer.key().as_ref(), shared.as_bytes()],
        bump
    )]
    pub user_state: Account<'info, UserState>,

    #[account(
        mut,
        seeds = [b"vault", vault.provider_name.as_bytes()],
        bump = vault.bump
    )]
    pub vault: Account<'info, Vault>,

    #[account(
        seeds = [b"supported-token", vault.key().as_ref(), user_ata.mint.as_ref()],
        bump
    )]
    pub supported_token: Account<'info, SupportedToken>,

    #[account(mut)]
    pub user_ata: Account<'info, TokenAccount>,

    #[account(mut)]
    pub vault_ata: Account<'info, TokenAccount>,

    pub token_program: Program<'info, Token>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(shared: String)]
pub struct DirectWithdrawYieldToken<'info> {
    #[account(mut)]
    pub user: Signer<'info>,

    #[account(
        mut,
        seeds = [b"user-state", user.key().as_ref(), shared.as_bytes()],
        bump
    )]
    pub user_state: Account<'info, UserState>,

    #[account(
        mut,
        seeds = [b"vault", vault.provider_name.as_bytes()],
        bump = vault.bump
    )]
    pub vault: Account<'info, Vault>,

    #[account(
        seeds = [b"supported-token", vault.key().as_ref(), user_ata.mint.as_ref()],
        bump
    )]
    pub supported_token: Account<'info, SupportedToken>,

    #[account(mut)]
    pub user_ata: Account<'info, TokenAccount>,

    #[account(mut)]
    pub vault_ata: Account<'info, TokenAccount>,

    pub token_program: Program<'info, Token>,
    pub validator_state: Account<'info, qiara::ValidatorState>, // Removed state:: [1.2.3]
    pub verifier_program: Program<'info, Qiara>,
}

// Helpers
pub fn get_pseudo_random_rate(payer: &Pubkey) -> Result<u64> {
    let clock = Clock::get()?;
    let mut msg_bytes = Vec::new();
    msg_bytes.extend_from_slice(&clock.unix_timestamp.to_le_bytes());
    msg_bytes.extend_from_slice(&clock.slot.to_le_bytes());
    msg_bytes.extend_from_slice(&payer.to_bytes());

    let hash_bytes = anchor_lang::solana_program::keccak::hash(&msg_bytes).to_bytes();

    let mut val_u64: u64 = 0;
    for i in 0..8 {
        val_u64 = (val_u64 << 8) | (hash_bytes[i] as u64);
    }

    let range_span = MAX_RATE - MIN_RATE + 1;
    Ok(MIN_RATE + (val_u64 % range_span))
}

pub fn accrue_user_yield(user_state: &UserState, rate: u64) -> Result<u64> {
    let clock = Clock::get()?;
    let current_time_seconds = clock.unix_timestamp;
    let mut rewards: u64 = 0;

    if user_state.balance > 0 && current_time_seconds > user_state.last_interacted_timestamp {
        let elapsed = current_time_seconds - user_state.last_interacted_timestamp;
        let scale: u128 = 100_000_000;
        let seconds_per_year: u128 = 31_536_000;
        let calculated_rewards = ((user_state.balance as u128) * (rate as u128) * (elapsed as u128)) / (scale * seconds_per_year);
        rewards = calculated_rewards as u64;
    }
    Ok(rewards)
}

// ==========================================
// 8. CUSTOM EVENTS
// ==========================================

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Debug)]
pub struct Data {
    pub name: String,
    pub type_name: String,
    pub value: Vec<u8>,
}

#[event]
pub struct VaultEvent {
    pub name: String,
    pub aux: Vec<Data>,
}

#[event]
pub struct TokenListed {
    pub vault: Pubkey,
    pub token_mint: Pubkey,
    pub provider_name: String,
}


#[event]
pub struct DepositEvent {
    pub sender: Pubkey,
    pub shared: String,
    pub token: String,
    pub provider: String,
    pub amount: u64,
    pub rate: u64,
    pub rewards: u64,
}

#[event]
pub struct DirectWithdrawEvent {
    pub addr: Pubkey,
    pub token: String,
    pub provider: String,
    pub amount: u64,
    pub rewards: u64,
}

#[error_code]
pub enum QiaraError {
    #[msg("Specified provider does not match the ZK proof.")]
    WrongProviderProvided,
    #[msg("User balance is too low to complete the action.")]
    InsufficientBalance,
    #[msg("Registry variables have been locked.")]
    RegistryLocked,
    #[msg("Caller is not authorized.")]
    NotValidator,
    #[msg("ZK variables proof validation failed.")]
    InvalidProof,                  // Added variant [1.1.2]
    #[msg("Contiguous input parser out of bounds.")]
    InvalidInputLength,            // Added variant [1.1.2]
}