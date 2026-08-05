module qiara_faucet::unified_faucet {
    use sui::coin::{Self, TreasuryCap};
    use sui::clock::{Self, Clock};
    use sui::table::{Self, Table};
    use sui::dynamic_object_field as dof;
    use std::type_name::{Self, TypeName};

    // --- Error Codes ---
    const ECooldownNotMet: u64 = 0;
    const ETokenDisabled: u64 = 1;
    const ETokenNotRegistered: u64 = 2;
    const ETokenAlreadyExists: u64 = 3;

    /// Admin capability required to adjust settings and register tokens
    public struct AdminCap has key, store {
        id: UID,
    }

    /// Shared global Faucet object
    public struct Faucet has key {
        id: UID,
        cooldown_ms: u64, // Default: 24 hours in milliseconds (86,400,000 ms)
    }

    /// Internal storage wrapper attached to Faucet for each registered token `T`
    public struct TokenVault<phantom T> has key, store {
        id: UID,
        treasury_cap: TreasuryCap<T>,
        claim_amount: u64,
        enabled: bool,
        last_claim: Table<address, u64>,
    }

    // --- Module Initializer ---
    fun init(ctx: &mut TxContext) {
        // Transfer AdminCap to deployer
        let admin_cap = AdminCap {
            id: object::new(ctx),
        };
        transfer::public_transfer(admin_cap, ctx.sender());

        // Create and share the central Faucet object
        let faucet = Faucet {
            id: object::new(ctx),
            cooldown_ms: 86_400_000, // 24 hours in milliseconds
        };
        transfer::share_object(faucet);
    }

    // ==========================================
    //             USER CLAIM LOGIC
    // ==========================================

    /**
     * @notice Claims testnet tokens for type `T`.
     * @param faucet Shared Faucet object
     * @param clock Sui system Clock object (0x6)
     */
    public fun claim<T>(
        faucet: &mut Faucet,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let type_name = type_name::get<T>();
        assert!(dof::exists_(&faucet.id, type_name), ETokenNotRegistered);

        let vault = dof::borrow_mut<TypeName, TokenVault<T>>(&mut faucet.id, type_name);
        assert!(vault.enabled, ETokenDisabled);

        let sender = ctx.sender();
        let current_time = clock::timestamp_ms(clock);

        // Rate limit check (24 hours per user per token)
        if (table::contains(&vault.last_claim, sender)) {
            let last_fetch = *table::borrow(&vault.last_claim, sender);
            assert!(current_time >= last_fetch + faucet.cooldown_ms, ECooldownNotMet);
            *table::borrow_mut(&mut vault.last_claim, sender) = current_time;
        } else {
            table::add(&mut vault.last_claim, sender, current_time);
        };

        // Mint coins directly to recipient
        let minted_coin = coin::mint(&mut vault.treasury_cap, vault.claim_amount, ctx);
        transfer::public_transfer(minted_coin, sender);
    }

    // ==========================================
    //               VIEW FUNCTIONS
    // ==========================================

    /**
     * @notice Returns timestamp (in ms) when user last fetched token `T`. Returns 0 if never fetched.
     */
    public fun get_last_claim_time<T>(
        faucet: &Faucet,
        user: address,
    ): u64 {
        let type_name = type_name::get<T>();
        if (!dof::exists_(&faucet.id, type_name)) {
            return 0
        };

        let vault = dof::borrow<TypeName, TokenVault<T>>(&faucet.id, type_name);
        if (table::contains(&vault.last_claim, user)) {
            *table::borrow(&vault.last_claim, user)
        } else {
            0
        }
    }

    /**
     * @notice Returns (can_claim: bool, time_remaining_ms: u64) for token `T`.
     */
    public fun get_claim_status<T>(
        faucet: &Faucet,
        clock: &Clock,
        user: address,
    ): (bool, u64) {
        let type_name = type_name::get<T>();
        if (!dof::exists_(&faucet.id, type_name)) {
            return (false, 0)
        };

        let vault = dof::borrow<TypeName, TokenVault<T>>(&faucet.id, type_name);
        if (!vault.enabled) {
            return (false, 0)
        };

        let current_time = clock::timestamp_ms(clock);
        if (table::contains(&vault.last_claim, user)) {
            let last_fetch = *table::borrow(&vault.last_claim, user);
            let next_claim_time = last_fetch + faucet.cooldown_ms;

            if (current_time >= next_claim_time) {
                (true, 0)
            } else {
                (false, next_claim_time - current_time)
            }
        } else {
            (true, 0)
        }
    }

    // ==========================================
    //               ADMIN LOGIC
    // ==========================================

    /**
     * @notice Registers a token by moving its `TreasuryCap<T>` into the Faucet.
     */
    public fun add_token<T>(
        _admin: &AdminCap,
        faucet: &mut Faucet,
        treasury_cap: TreasuryCap<T>,
        claim_amount: u64,
        ctx: &mut TxContext,
    ) {
        let type_name = type_name::get<T>();
        assert!(!dof::exists_(&faucet.id, type_name), ETokenAlreadyExists);

        let vault = TokenVault<T> {
            id: object::new(ctx),
            treasury_cap,
            claim_amount,
            enabled: true,
            last_claim: table::new(ctx),
        };

        // Dynamically store the vault inside the shared Faucet object
        dof::add(&mut faucet.id, type_name, vault);
    }

    /**
     * @notice Admin function to update the claim amount for token `T`.
     */
    public fun set_claim_amount<T>(
        _admin: &AdminCap,
        faucet: &mut Faucet,
        new_amount: u64,
    ) {
        let type_name = type_name::get<T>();
        assert!(dof::exists_(&faucet.id, type_name), ETokenNotRegistered);

        let vault = dof::borrow_mut<TypeName, TokenVault<T>>(&mut faucet.id, type_name);
        vault.claim_amount = new_amount;
    }

    /**
     * @notice Admin function to toggle enable/disable status for token `T`.
     */
    public fun set_token_enabled<T>(
        _admin: &AdminCap,
        faucet: &mut Faucet,
        enabled: bool,
    ) {
        let type_name = type_name::get<T>();
        assert!(dof::exists_(&faucet.id, type_name), ETokenNotRegistered);

        let vault = dof::borrow_mut<TypeName, TokenVault<T>>(&mut faucet.id, type_name);
        vault.enabled = enabled;
    }

    /**
     * @notice Admin function to update the global cooldown (in milliseconds).
     */
    public fun set_cooldown(
        _admin: &AdminCap,
        faucet: &mut Faucet,
        new_cooldown_ms: u64,
    ) {
        faucet.cooldown_ms = new_cooldown_ms;
    }
}