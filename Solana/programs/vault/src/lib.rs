use anchor_lang::prelude::*;
use anchor_spl::token::{self, Mint, Token, TokenAccount, Transfer};
use qiara::program::Qiara;
use qiara::{EpochConfig, ProviderRegistry, Registry, SignatureBuffer, ValidatorState};
use serde::{Deserialize, Serialize};

declare_id!("3Qjxo2dutJc5aktnk1bJZGuujVsRiH6JHp3UkusYJXuc");

const DEFAULT_MIN_RATE: u64 = 2_750_000;
const DEFAULT_MAX_RATE: u64 = 11_275_000;
const YIELD_DENOMINATOR: u128 = 360_000_000_000;

#[derive(AnchorSerialize, AnchorDeserialize, Serialize, Deserialize, Clone, Debug)]
pub struct DirectWithdrawPayload {
    pub chain_id: u32,
    pub user: Vec<u8>, // <--- Vec<u8> reads the ULEB128 length prefix!
    pub provider: String,
    pub token_name: String,
    pub amount: u64,
    pub nonce: u64,
}

#[program]
pub mod vault {
    use super::*;

    pub trait ProviderRegistryExt {
        fn is_provider_supported(&self, provider: &str) -> bool;
        fn is_token_supported(&self, provider: &str, token: &str) -> bool;
        fn get_token_address(&self, token: &str) -> String;
    }

    impl ProviderRegistryExt for ProviderRegistry {
        fn is_provider_supported(&self, provider: &str) -> bool {
            self.providers.iter().any(|p| p.eq_ignore_ascii_case(provider))
        }

        fn is_token_supported(&self, provider: &str, token: &str) -> bool {
            if let Some(entry) = self.provider_tokens.iter().find(|pt| pt.provider.eq_ignore_ascii_case(provider)) {
                entry.tokens.iter().any(|t| t.eq_ignore_ascii_case(token))
            } else {
                false
            }
        }

        fn get_token_address(&self, token: &str) -> String {
            if let Some(entry) = self.token_addresses.iter().find(|ta| ta.token.eq_ignore_ascii_case(token)) {
                return entry.address.clone();
            }
            String::new()
        }
    }

    pub fn create_vault(ctx: Context<CreateVault>, provider_name: String) -> Result<()> {
        let registry = &ctx.accounts.provider_registry;
        require!(
            registry.is_provider_supported(&provider_name),
            QiaraError::ProviderNotSupported
        );

        let vault = &mut ctx.accounts.vault;
        vault.provider_name = provider_name;
        vault.authority = ctx.accounts.payer.key();
        vault.provider_registry = ctx.accounts.provider_registry.key();
        vault.min_rate = DEFAULT_MIN_RATE;
        vault.max_rate = DEFAULT_MAX_RATE;
        vault.nonce = 0;
        vault.bump = ctx.bumps.vault;

        Ok(())
    }

    pub fn set_provider_range(ctx: Context<SetProviderRange>, min: u64, max: u64) -> Result<()> {
        require!(max >= min, QiaraError::InvalidRange);
        let vault = &mut ctx.accounts.vault;
        vault.min_rate = min;
        vault.max_rate = max;

        emit!(ProviderRangeSet {
            provider: vault.provider_name.clone(),
            min,
            max,
        });
        Ok(())
    }

    pub fn list_new_token(ctx: Context<ListNewToken>, asset_name: String) -> Result<()> {
        let vault = &ctx.accounts.vault;
        let p_reg = &ctx.accounts.provider_registry;

        require!(
            p_reg.is_provider_supported(&vault.provider_name),
            QiaraError::ProviderNotSupported
        );

        require!(
            p_reg.is_token_supported(&vault.provider_name, &asset_name),
            QiaraError::TokenNotSupported
        );

        let token_mint = ctx.accounts.token_mint.key();

        let registered_token_addr_str = p_reg.get_token_address(&asset_name);
        if !registered_token_addr_str.is_empty() {
            if let Ok(reg_mint) = registered_token_addr_str.parse::<Pubkey>() {
                require!(token_mint == reg_mint, QiaraError::InvalidAssetAddress);
            }
        }

        let supported_token = &mut ctx.accounts.supported_token;
        supported_token.is_supported = true;
        supported_token.mint = token_mint;
        supported_token.name = asset_name;
        supported_token.reserves = 0;
        supported_token.bump = ctx.bumps.supported_token;

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
        token_name: String,
        amount: u64,
    ) -> Result<()> {
        require!(amount > 0, QiaraError::ZeroAmount);
        
        let vault = &ctx.accounts.vault;
        let p_reg = &ctx.accounts.provider_registry;

        require!(
            p_reg.is_provider_supported(&vault.provider_name),
            QiaraError::ProviderNotSupported
        );

        require!(
            p_reg.is_token_supported(&vault.provider_name, &token_name),
            QiaraError::TokenNotSupported
        );

        let supported_token = &ctx.accounts.supported_token;
        require!(supported_token.is_supported, QiaraError::TokenNotSupported);
        require!(supported_token.name.eq_ignore_ascii_case(&token_name), QiaraError::TokenMismatch);

        let registered_token_addr_str = p_reg.get_token_address(&token_name);
        if !registered_token_addr_str.is_empty() {
            if let Ok(reg_mint) = registered_token_addr_str.parse::<Pubkey>() {
                require!(ctx.accounts.mint.key() == reg_mint, QiaraError::InvalidAssetAddress);
            }
        }

        let cpi_accounts = Transfer {
            from: ctx.accounts.user_ata.to_account_info(),
            to: ctx.accounts.vault_ata.to_account_info(),
            authority: ctx.accounts.payer.to_account_info(),
        };
        token::transfer(
            CpiContext::new(ctx.accounts.token_program.to_account_info(), cpi_accounts),
            amount,
        )?;

        let clock = Clock::get()?;
        let current_time = clock.unix_timestamp;
        let rate = get_pseudo_random_range(&mut ctx.accounts.vault, &ctx.accounts.payer.key())?;
        
        let user_state = &mut ctx.accounts.user_state;
        let rewards = calculate_yield(user_state.balance, user_state.last_interacted_timestamp, current_time, rate);

        user_state.balance = user_state.balance
            .checked_add(amount).ok_or(QiaraError::MathOverflow)?
            .checked_add(rewards).ok_or(QiaraError::MathOverflow)?;
        user_state.last_interacted_timestamp = current_time;

        let supported_token_mut = &mut ctx.accounts.supported_token;
        supported_token_mut.reserves = supported_token_mut.reserves
            .checked_add(amount).ok_or(QiaraError::MathOverflow)?;

        let data = vec![
            Data { name: "user".to_string(), type_name: "address".to_string(), value: ctx.accounts.payer.key().to_bytes().to_vec() },
            Data { name: "shared".to_string(), type_name: "string".to_string(), value: shared.into_bytes() },
            Data { name: "amount".to_string(), type_name: "uint256".to_string(), value: amount.to_le_bytes().to_vec() },
            Data { name: "token".to_string(), type_name: "string".to_string(), value: token_name.into_bytes() },
            Data { name: "provider".to_string(), type_name: "string".to_string(), value: ctx.accounts.vault.provider_name.clone().into_bytes() },
            Data { name: "timestamp".to_string(), type_name: "uint256".to_string(), value: current_time.to_le_bytes().to_vec() },
            Data { name: "rate".to_string(), type_name: "uint256".to_string(), value: rate.to_le_bytes().to_vec() },
            Data { name: "rewards".to_string(), type_name: "uint256".to_string(), value: rewards.to_le_bytes().to_vec() },
        ];
        emit!(VaultEvent { name: "Deposit".to_string(), aux: data });

        Ok(())
    }
    
/// Direct withdrawal using the unified cross-chain payload and staged signatures
    pub fn direct_withdraw(
        ctx: Context<DirectWithdrawYieldToken>,
        nullifier_bytes: [u8; 32],
        raw_payload: Vec<u8>,
    ) -> Result<()> {
        // 1. Cryptographic binding check (nullifier IS the hash of raw_payload)
        let computed_nullifier = anchor_lang::solana_program::keccak::hash(&raw_payload).to_bytes();
        require!(nullifier_bytes == computed_nullifier, QiaraError::InvalidActionHash);
        require!(
            ctx.accounts.sig_buffer.message_hash == nullifier_bytes,
            QiaraError::InvalidActionHash
        );

        // 2. Verify validator signatures against current epoch
        let current_epoch = ctx.accounts.epoch_config.get_current_epoch()?;
        let signatures = &ctx.accounts.sig_buffer.signatures;
        qiara::utils::verify_signatures(
            &ctx.accounts.validator_state,
            &ctx.accounts.registry,
            signatures,
            &raw_payload,
            current_epoch,
        )?;

        // 3. Unpack canonical Move-compatible BCS payload
        let payload: DirectWithdrawPayload = bcs::from_bytes(&raw_payload)
            .map_err(|_| error!(QiaraError::InvalidPayloadEncoding))?;

        // 4. Assert payload matches instruction accounts & context
        require!(
            ctx.accounts.vault.provider_name.eq_ignore_ascii_case(&payload.provider),
            QiaraError::WrongProviderProvided
        );

        require!(
            ctx.accounts.user.key().to_bytes().as_ref() == payload.user.as_slice(), 
            QiaraError::NotValidator
        );
        
        let supported_token = &ctx.accounts.supported_token;
        require!(supported_token.is_supported, QiaraError::TokenNotSupported);
        require!(supported_token.name.eq_ignore_ascii_case(&payload.token_name), QiaraError::TokenMismatch);

        let local_chain_id = 901; // or from config PDA
        if payload.chain_id != 0 {
            require!(payload.chain_id == local_chain_id, QiaraError::WrongChainId);
        }

        let amount = payload.amount;
        require!(amount > 0, QiaraError::ZeroAmount);

        // 5. Mark nullifier as used (Replay protection)
        require!(!ctx.accounts.nullifier_record.is_used, QiaraError::InvalidActionHash);
        ctx.accounts.nullifier_record.is_used = true;

        // 6. Liquidity and balance accounting
        let supported_token_mut = &mut ctx.accounts.supported_token;
        require!(supported_token_mut.reserves >= amount, QiaraError::InsufficientLiquidity);
        supported_token_mut.reserves -= amount;

        let clock = Clock::get()?;
        let current_time = clock.unix_timestamp;
        let rate = get_pseudo_random_range(&mut ctx.accounts.vault, &ctx.accounts.payer.key())?;
        
        let user_state = &mut ctx.accounts.user_state;
        let rewards = calculate_yield(user_state.balance, user_state.last_interacted_timestamp, current_time, rate);
        let total_available = user_state.balance.checked_add(rewards).ok_or(QiaraError::MathOverflow)?;

        user_state.balance = if total_available >= amount { total_available - amount } else { 0 };
        user_state.last_interacted_timestamp = current_time;

        // 7. Transfer tokens to user
        let seeds = &[
            b"vault",
            ctx.accounts.vault.provider_name.as_bytes(),
            &[ctx.accounts.vault.bump],
        ];
        let cpi_accounts = Transfer {
            from: ctx.accounts.vault_ata.to_account_info(),
            to: ctx.accounts.user_ata.to_account_info(),
            authority: ctx.accounts.vault.to_account_info(),
        };
        token::transfer(
            CpiContext::new_with_signer(ctx.accounts.token_program.to_account_info(), cpi_accounts, &[&seeds[..]]),
            amount,
        )?;


        // 8. Emit Direct Withdraw event
        let data = vec![
            Data { name: "sender".to_string(), type_name: "address".to_string(), value: ctx.accounts.payer.key().to_bytes().to_vec() },
            Data { name: "user".to_string(), type_name: "address".to_string(), value: payload.user }, // <--- Fixed here
            Data { name: "amount".to_string(), type_name: "uint256".to_string(), value: amount.to_le_bytes().to_vec() },
            Data { name: "token".to_string(), type_name: "string".to_string(), value: payload.token_name.into_bytes() },
            Data { name: "provider".to_string(), type_name: "string".to_string(), value: payload.provider.into_bytes() },
            Data { name: "nonce".to_string(), type_name: "uint256".to_string(), value: payload.nonce.to_le_bytes().to_vec() },
            Data { name: "nullifier".to_string(), type_name: "uint256".to_string(), value: nullifier_bytes.to_vec() },
            Data { name: "timestamp".to_string(), type_name: "uint256".to_string(), value: current_time.to_le_bytes().to_vec() },
        ];
        emit!(VaultEvent { name: "Direct Withdraw".to_string(), aux: data });

        Ok(())
    }

    pub fn m_withdraw(
        ctx: Context<ModularWithdraw>,
        shared: String,
        token_name: String,
        amount: u64,
    ) -> Result<()> {
        require!(amount > 0, QiaraError::ZeroAmount);
        
        let p_reg = &ctx.accounts.provider_registry;
        require!(
            p_reg.is_provider_supported(&ctx.accounts.vault.provider_name),
            QiaraError::ProviderNotSupported
        );
        require!(
            p_reg.is_token_supported(&ctx.accounts.vault.provider_name, &token_name),
            QiaraError::TokenNotSupported
        );

        require!(ctx.accounts.supported_token.is_supported, QiaraError::TokenNotSupported);
        require!(ctx.accounts.supported_token.name.eq_ignore_ascii_case(&token_name), QiaraError::TokenMismatch);

        let data = vec![
            Data { name: "user".to_string(), type_name: "address".to_string(), value: ctx.accounts.user.key().to_bytes().to_vec() },
            Data { name: "shared".to_string(), type_name: "string".to_string(), value: shared.into_bytes() },
            Data { name: "amount".to_string(), type_name: "uint256".to_string(), value: amount.to_le_bytes().to_vec() },
            Data { name: "provider".to_string(), type_name: "string".to_string(), value: ctx.accounts.vault.provider_name.clone().into_bytes() },
            Data { name: "token".to_string(), type_name: "string".to_string(), value: token_name.into_bytes() },
        ];
        emit!(VaultEvent { name: "Modular Withdraw".to_string(), aux: data });
        Ok(())
    }

    pub fn stake(
        ctx: Context<Stake>,
        shared: String,
        token_name: String,
        amount: u64,
        epoch: u64,
    ) -> Result<()> {
        require!(amount > 0, QiaraError::ZeroAmount);

        let vault = &ctx.accounts.vault;
        let p_reg = &ctx.accounts.provider_registry;

        require!(
            p_reg.is_provider_supported(&vault.provider_name),
            QiaraError::ProviderNotSupported
        );

        require!(
            p_reg.is_token_supported(&vault.provider_name, &token_name),
            QiaraError::TokenNotSupported
        );

        let supported_token = &ctx.accounts.supported_token;
        require!(supported_token.is_supported, QiaraError::TokenNotSupported);
        require!(supported_token.name.eq_ignore_ascii_case(&token_name), QiaraError::TokenMismatch);

        let cpi_accounts = Transfer {
            from: ctx.accounts.user_ata.to_account_info(),
            to: ctx.accounts.vault_ata.to_account_info(),
            authority: ctx.accounts.payer.to_account_info(),
        };
        token::transfer(CpiContext::new(ctx.accounts.token_program.to_account_info(), cpi_accounts), amount)?;

        let supported_token_mut = &mut ctx.accounts.supported_token;
        supported_token_mut.reserves = supported_token_mut.reserves.checked_add(amount).ok_or(QiaraError::MathOverflow)?;

        let user_state = &mut ctx.accounts.user_state;
        user_state.balance = user_state.balance.checked_add(amount).ok_or(QiaraError::MathOverflow)?;

        let data = vec![
            Data { name: "user".to_string(), type_name: "address".to_string(), value: ctx.accounts.payer.key().to_bytes().to_vec() },
            Data { name: "shared".to_string(), type_name: "string".to_string(), value: shared.into_bytes() },
            Data { name: "token".to_string(), type_name: "string".to_string(), value: token_name.into_bytes() },
            Data { name: "provider".to_string(), type_name: "string".to_string(), value: ctx.accounts.vault.provider_name.clone().into_bytes() },
            Data { name: "amount".to_string(), type_name: "uint256".to_string(), value: amount.to_le_bytes().to_vec() },
            Data { name: "epoch".to_string(), type_name: "uint256".to_string(), value: epoch.to_le_bytes().to_vec() },
        ];
        emit!(VaultEvent { name: "Stake".to_string(), aux: data });

        Ok(())
    }

    pub fn unstake(
        ctx: Context<Unstake>,
        shared: String,
        token_name: String,
        amount: u64,
    ) -> Result<()> {
        require!(amount > 0, QiaraError::ZeroAmount);
        
        let p_reg = &ctx.accounts.provider_registry;
        require!(
            p_reg.is_provider_supported(&ctx.accounts.vault.provider_name),
            QiaraError::ProviderNotSupported
        );
        require!(
            p_reg.is_token_supported(&ctx.accounts.vault.provider_name, &token_name),
            QiaraError::TokenNotSupported
        );

        require!(ctx.accounts.supported_token.is_supported, QiaraError::TokenNotSupported);
        require!(ctx.accounts.supported_token.name.eq_ignore_ascii_case(&token_name), QiaraError::TokenMismatch);

        let data = vec![
            Data { name: "user".to_string(), type_name: "address".to_string(), value: ctx.accounts.user.key().to_bytes().to_vec() },
            Data { name: "shared".to_string(), type_name: "string".to_string(), value: shared.into_bytes() },
            Data { name: "amount".to_string(), type_name: "uint256".to_string(), value: amount.to_le_bytes().to_vec() },
            Data { name: "provider".to_string(), type_name: "string".to_string(), value: ctx.accounts.vault.provider_name.clone().into_bytes() },
            Data { name: "token".to_string(), type_name: "string".to_string(), value: token_name.into_bytes() },
        ];
        emit!(VaultEvent { name: "Unstake".to_string(), aux: data });

        Ok(())
    }

    pub fn borrow(
        ctx: Context<Borrow>,
        shared: String,
        token_name: String,
        amount: u64,
    ) -> Result<()> {
        require!(amount > 0, QiaraError::ZeroAmount);

        let p_reg = &ctx.accounts.provider_registry;
        require!(
            p_reg.is_provider_supported(&ctx.accounts.vault.provider_name),
            QiaraError::ProviderNotSupported
        );
        require!(
            p_reg.is_token_supported(&ctx.accounts.vault.provider_name, &token_name),
            QiaraError::TokenNotSupported
        );

        require!(ctx.accounts.supported_token.is_supported, QiaraError::TokenNotSupported);
        require!(ctx.accounts.supported_token.name.eq_ignore_ascii_case(&token_name), QiaraError::TokenMismatch);

        let data = vec![
            Data { name: "user".to_string(), type_name: "address".to_string(), value: ctx.accounts.user.key().to_bytes().to_vec() },
            Data { name: "shared".to_string(), type_name: "string".to_string(), value: shared.into_bytes() },
            Data { name: "amount".to_string(), type_name: "uint256".to_string(), value: amount.to_le_bytes().to_vec() },
            Data { name: "provider".to_string(), type_name: "string".to_string(), value: ctx.accounts.vault.provider_name.clone().into_bytes() },
            Data { name: "token".to_string(), type_name: "string".to_string(), value: token_name.into_bytes() },
        ];
        emit!(VaultEvent { name: "Borrow".to_string(), aux: data });

        Ok(())
    }
}

// ==========================================
// ACCOUNTS & CONTEXTS
// ==========================================

#[account]
pub struct Vault {
    pub provider_name: String,
    pub authority: Pubkey,
    pub provider_registry: Pubkey,
    pub min_rate: u64,
    pub max_rate: u64,
    pub nonce: u64,
    pub bump: u8,
}

#[account]
pub struct SupportedToken {
    pub is_supported: bool,
    pub mint: Pubkey,
    pub name: String,
    pub reserves: u64,
    pub bump: u8,
}

#[account]
pub struct UserState {
    pub balance: u64,
    pub last_interacted_timestamp: i64,
}

#[account]
pub struct NullifierRecord {
    pub is_used: bool,
}

#[derive(Accounts)]
#[instruction(provider_name: String)]
pub struct CreateVault<'info> {
    #[account(
        init,
        payer = payer,
        space = 8 + (4 + provider_name.len()) + 32 + 32 + 8 + 8 + 8 + 1,
        seeds = [b"vault", provider_name.as_bytes()],
        bump
    )]
    pub vault: Account<'info, Vault>,
    pub provider_registry: Account<'info, ProviderRegistry>,
    #[account(mut)]
    pub payer: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct SetProviderRange<'info> {
    #[account(
        mut,
        has_one = authority @ QiaraError::NotValidator
    )]
    pub vault: Account<'info, Vault>,
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
#[instruction(asset_name: String)]
pub struct ListNewToken<'info> {
    #[account(has_one = provider_registry @ QiaraError::ProviderNotSupported)]
    pub vault: Account<'info, Vault>,
    pub provider_registry: Account<'info, ProviderRegistry>,
    #[account(
        init,
        payer = payer,
        space = 8 + 1 + 32 + (4 + asset_name.len()) + 8 + 1,
        seeds = [b"supported-token", vault.key().as_ref(), token_mint.key().as_ref()],
        bump
    )]
    pub supported_token: Account<'info, SupportedToken>,
    pub token_mint: Account<'info, Mint>,
    #[account(mut)]
    pub payer: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct DepositYieldToken<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    #[account(
        init_if_needed,
        payer = payer,
        space = 8 + 8 + 8,
        seeds = [b"user-state", payer.key().as_ref(), vault.key().as_ref(), user_ata.mint.as_ref()],
        bump
    )]
    pub user_state: Account<'info, UserState>,

    #[account(
        mut, 
        seeds = [b"vault", vault.provider_name.as_bytes()], 
        bump = vault.bump,
        has_one = provider_registry @ QiaraError::ProviderNotSupported
    )]
    pub vault: Account<'info, Vault>,

    pub provider_registry: Account<'info, ProviderRegistry>,

    #[account(
        mut,
        seeds = [b"supported-token", vault.key().as_ref(), user_ata.mint.as_ref()],
        bump = supported_token.bump,
        has_one = mint
    )]
    pub supported_token: Account<'info, SupportedToken>,

    #[account(mut)]
    pub user_ata: Account<'info, TokenAccount>,
    #[account(mut)]
    pub vault_ata: Account<'info, TokenAccount>,
    pub mint: Account<'info, Mint>,
    pub token_program: Program<'info, Token>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(nullifier_bytes: [u8; 32], raw_payload: Vec<u8>)]
pub struct DirectWithdrawYieldToken<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    /// CHECK: Recipient pubkey verified against payload.user
    #[account(mut)]
    pub user: AccountInfo<'info>,

    /// Signature buffer created on qiara program.
    /// Remove `close = payer` because `vault` does not own this account!
    #[account(
        seeds = [b"sig_buffer", nullifier_bytes.as_ref()],
        seeds::program = verifier_program.key(),
        bump,
        constraint = sig_buffer.message_hash == nullifier_bytes @ QiaraError::InvalidActionHash
    )]
    pub sig_buffer: Account<'info, SignatureBuffer>,

    #[account(
        init_if_needed,
        payer = payer,
        space = 8 + 8 + 8,
        seeds = [b"user-state", user.key().as_ref(), vault.key().as_ref(), user_ata.mint.as_ref()],
        bump
    )]
    pub user_state: Account<'info, UserState>,

    #[account(mut, seeds = [b"vault", vault.provider_name.as_bytes()], bump = vault.bump)]
    pub vault: Account<'info, Vault>,

    #[account(
        mut,
        seeds = [b"supported-token", vault.key().as_ref(), user_ata.mint.as_ref()],
        bump = supported_token.bump
    )]
    pub supported_token: Account<'info, SupportedToken>,

    #[account(
        init,
        payer = payer,
        space = 8 + 1,
        seeds = [b"nullifier", nullifier_bytes.as_ref()],
        bump
    )]
    pub nullifier_record: Account<'info, NullifierRecord>,

    #[account(
        mut,
        constraint = user_ata.mint == supported_token.mint @ QiaraError::TokenMismatch
    )]
    pub user_ata: Account<'info, TokenAccount>,

    #[account(
        mut,
        constraint = vault_ata.mint == supported_token.mint @ QiaraError::TokenMismatch
    )]
    pub vault_ata: Account<'info, TokenAccount>,

    pub token_program: Program<'info, Token>,
    pub system_program: Program<'info, System>,

    pub registry: Account<'info, Registry>,
    pub validator_state: Account<'info, ValidatorState>,
    pub epoch_config: Account<'info, EpochConfig>,
    pub verifier_program: Program<'info, Qiara>,
}

#[derive(Accounts)]
pub struct ModularWithdraw<'info> {
    #[account(mut)]
    pub user: Signer<'info>,
    #[account(
        seeds = [b"vault", vault.provider_name.as_bytes()], 
        bump = vault.bump,
        has_one = provider_registry @ QiaraError::ProviderNotSupported
    )]
    pub vault: Account<'info, Vault>,
    pub provider_registry: Account<'info, ProviderRegistry>,
    #[account(
        seeds = [b"supported-token", vault.key().as_ref(), user_ata.mint.as_ref()],
        bump = supported_token.bump
    )]
    pub supported_token: Account<'info, SupportedToken>,
    pub user_ata: Account<'info, TokenAccount>,
}

#[derive(Accounts)]
pub struct Stake<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    #[account(
        init_if_needed,
        payer = payer,
        space = 8 + 8 + 8,
        seeds = [b"user-state", payer.key().as_ref(), vault.key().as_ref(), user_ata.mint.as_ref()],
        bump
    )]
    pub user_state: Account<'info, UserState>,

    #[account(
        mut,
        seeds = [b"vault", vault.provider_name.as_bytes()], 
        bump = vault.bump,
        has_one = provider_registry @ QiaraError::ProviderNotSupported
    )]
    pub vault: Account<'info, Vault>,

    pub provider_registry: Account<'info, ProviderRegistry>,

    #[account(
        mut,
        seeds = [b"supported-token", vault.key().as_ref(), user_ata.mint.as_ref()],
        bump = supported_token.bump
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
pub struct Unstake<'info> {
    #[account(mut)]
    pub user: Signer<'info>,
    #[account(
        seeds = [b"vault", vault.provider_name.as_bytes()], 
        bump = vault.bump,
        has_one = provider_registry @ QiaraError::ProviderNotSupported
    )]
    pub vault: Account<'info, Vault>,
    pub provider_registry: Account<'info, ProviderRegistry>,
    #[account(
        seeds = [b"supported-token", vault.key().as_ref(), user_ata.mint.as_ref()],
        bump = supported_token.bump
    )]
    pub supported_token: Account<'info, SupportedToken>,
    pub user_ata: Account<'info, TokenAccount>,
}

#[derive(Accounts)]
pub struct Borrow<'info> {
    #[account(mut)]
    pub user: Signer<'info>,
    #[account(
        seeds = [b"vault", vault.provider_name.as_bytes()], 
        bump = vault.bump,
        has_one = provider_registry @ QiaraError::ProviderNotSupported
    )]
    pub vault: Account<'info, Vault>,
    pub provider_registry: Account<'info, ProviderRegistry>,
    #[account(
        seeds = [b"supported-token", vault.key().as_ref(), user_ata.mint.as_ref()],
        bump = supported_token.bump
    )]
    pub supported_token: Account<'info, SupportedToken>,
    pub user_ata: Account<'info, TokenAccount>,
}

// ==========================================
// HELPERS
// ==========================================

pub fn get_pseudo_random_range(vault: &mut Vault, payer: &Pubkey) -> Result<u64> {
    let clock = Clock::get()?;
    vault.nonce = vault.nonce.wrapping_add(1);

    let mut msg_bytes = Vec::with_capacity(8 + 8 + 32 + 8);
    msg_bytes.extend_from_slice(&clock.unix_timestamp.to_le_bytes());
    msg_bytes.extend_from_slice(&clock.slot.to_le_bytes());
    msg_bytes.extend_from_slice(payer.as_ref());
    msg_bytes.extend_from_slice(&vault.nonce.to_le_bytes());

    let hash_bytes = anchor_lang::solana_program::keccak::hash(&msg_bytes).to_bytes();
    let val_u64 = u64::from_le_bytes(hash_bytes[..8].try_into().unwrap());
    
    let range_span = (vault.max_rate.saturating_sub(vault.min_rate) + 1).max(1);
    Ok(vault.min_rate + (val_u64 % range_span))
}

pub fn calculate_yield(balance: u64, last_interacted: i64, current_timestamp: i64, rate: u64) -> u64 {
    if balance > 0 && last_interacted > 0 && current_timestamp > last_interacted {
        let elapsed = (current_timestamp - last_interacted) as u128;
        let rewards = ((balance as u128) * (rate as u128) * elapsed) / YIELD_DENOMINATOR;
        rewards as u64
    } else {
        0
    }
}

// ==========================================
// EVENTS & ERRORS
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
pub struct ProviderRangeSet {
    pub provider: String,
    pub min: u64,
    pub max: u64,
}

#[error_code]
pub enum QiaraError {
    #[msg("Amount must be greater than zero.")]
    ZeroAmount,
    #[msg("Token is not supported by the provider.")]
    TokenNotSupported,
    #[msg("Invalid token asset address.")]
    InvalidAssetAddress,
    #[msg("Provider reserves are insufficient to complete this withdrawal.")]
    InsufficientLiquidity,
    #[msg("Invalid rate range: max must be greater than or equal to min.")]
    InvalidRange,
    #[msg("Caller is not authorized.")]
    NotValidator,
    #[msg("Math operation resulted in an overflow.")]
    MathOverflow,
    #[msg("Specified provider does not match the payload.")]
    WrongProviderProvided,
    #[msg("Provider is not registered in ProviderRegistry.")]
    ProviderNotSupported,
    #[msg("Token name does not match the registered mint.")]
    TokenMismatch,
    #[msg("Action hash does not match computed payload hash.")]
    InvalidActionHash,
    #[msg("Invalid payload encoding format.")]
    InvalidPayloadEncoding,
    #[msg("Trailing data detected in signed payload.")]
    TrailingDataInPayload,
    #[msg("Wrong chain ID.")]
    WrongChainId, // <--- Add this here in programs/vault/src/lib.rs!
}