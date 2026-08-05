module dev::unified_faucetV4 {
    use std::signer;
    use std::string::{Self, String};
    use std::option;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::fungible_asset::{Self, MintRef, Metadata};
    use aptos_framework::primary_fungible_store;
    use std::timestamp;
    use aptos_std::smart_table::{Self, SmartTable};
    use std::vector;
    // --- Error Codes ---
    const ENO_PERMISSIONS: u64 = 1;
    const ECOOLDOWN_NOT_MET: u64 = 2;
    const ETOKEN_NOT_FOUND: u64 = 3;
    const ETOKEN_DISABLED: u64 = 4;
    const EALREADY_INITIALIZED: u64 = 5;

    /// Global configuration stored at deployer address
        struct FaucetConfig has key {
            admin: address,
            cooldown_seconds: u64,
            vaults: SmartTable<Object<Metadata>, TokenVault>,
            all_assets: vector<Object<Metadata>>, // <--- new
        }

    /// Stores mint capability and claim settings for each Fungible Asset
    struct TokenVault has store {
        mint_ref: MintRef,
        claim_amount: u64,
        enabled: bool,
        last_claim: SmartTable<address, u64>,
    }

    /// Automatically runs once when the package is published
fun init_module(admin: &signer) {
    move_to(admin, FaucetConfig {
        admin: signer::address_of(admin),
        cooldown_seconds: 86400,
        vaults: smart_table::new(),
        all_assets: vector::empty(),
    });
}

    // ==========================================
    //               ADMIN LOGIC
    // ==========================================

    /**
     * @notice Creates a new Fungible Asset and stores its MintRef in the Faucet.
     * @param seed Seed byte vector used to generate the asset's named object address (e.g. b"USDC").
     */
    public entry fun create_and_register_asset(
        admin: &signer,
        name: String,
        symbol: String,
        decimals: u8,
        claim_amount: u64,
        seed: vector<u8>,
    ) acquires FaucetConfig {
        let admin_addr = signer::address_of(admin);
        let faucet_config = borrow_global_mut<FaucetConfig>(@dev);
        assert!(admin_addr == faucet_config.admin, ENO_PERMISSIONS);

        // Create a named object for the Fungible Asset
        let constructor_ref = object::create_named_object(admin, seed);
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &constructor_ref,
            option::none(), // Max supply (none = infinite for testnet faucet)
            name,
            symbol,
            decimals,
            string::utf8(b""), // Icon URI
            string::utf8(b""), // Project URI
        );

        let mint_ref = fungible_asset::generate_mint_ref(&constructor_ref);
        let metadata_obj = object::object_from_constructor_ref<Metadata>(&constructor_ref);

        assert!(!smart_table::contains(&faucet_config.vaults, metadata_obj), EALREADY_INITIALIZED);

        let vault = TokenVault {
            mint_ref,
            claim_amount,
            enabled: true,
            last_claim: smart_table::new(),
        };
        vector::push_back(&mut faucet_config.all_assets, metadata_obj); // <--- ADD THIS
        smart_table::add(&mut faucet_config.vaults, metadata_obj, vault);
    }

    /// Admin: Update claimable amount for a Fungible Asset
    public entry fun set_claim_amount(
        admin: &signer,
        asset: Object<Metadata>,
        new_amount: u64,
    ) acquires FaucetConfig {
        let admin_addr = signer::address_of(admin);
        let faucet_config = borrow_global_mut<FaucetConfig>(@dev);
        assert!(admin_addr == faucet_config.admin, ENO_PERMISSIONS);
        assert!(smart_table::contains(&faucet_config.vaults, asset), ETOKEN_NOT_FOUND);

        let vault = smart_table::borrow_mut(&mut faucet_config.vaults, asset);
        vault.claim_amount = new_amount;
    }

    /// Admin: Enable or disable claiming for a Fungible Asset
    public entry fun set_token_enabled(
        admin: &signer,
        asset: Object<Metadata>,
        enabled: bool,
    ) acquires FaucetConfig {
        let admin_addr = signer::address_of(admin);
        let faucet_config = borrow_global_mut<FaucetConfig>(@dev);
        assert!(admin_addr == faucet_config.admin, ENO_PERMISSIONS);
        assert!(smart_table::contains(&faucet_config.vaults, asset), ETOKEN_NOT_FOUND);

        let vault = smart_table::borrow_mut(&mut faucet_config.vaults, asset);
        vault.enabled = enabled;
    }

    /// Admin: Update global cooldown time in seconds
    public entry fun set_cooldown(
        admin: &signer,
        new_cooldown_seconds: u64,
    ) acquires FaucetConfig {
        let admin_addr = signer::address_of(admin);
        let config = borrow_global_mut<FaucetConfig>(@dev);
        assert!(admin_addr == config.admin, ENO_PERMISSIONS);
        config.cooldown_seconds = new_cooldown_seconds;
    }

    // ==========================================
    //             USER CLAIM LOGIC
    // ==========================================

   public entry fun claim_all(user: &signer) acquires FaucetConfig {
    let user_addr = signer::address_of(user);
    let config = borrow_global_mut<FaucetConfig>(@dev);
    let cooldown = config.cooldown_seconds;
    let now = timestamp::now_seconds();
    let assets = config.all_assets; // copy, Object has copy

    let i = 0;
    let len = vector::length(&assets);
    while (i < len) {
        let asset = *vector::borrow(&assets, i);
        let vault = smart_table::borrow_mut(&mut config.vaults, asset);
        if (vault.enabled) {
            let can = if (!smart_table::contains(&vault.last_claim, user_addr)) {
                true
            } else {
                now >= *smart_table::borrow(&vault.last_claim, user_addr) + cooldown
            };
            if (can) {
                if (smart_table::contains(&vault.last_claim, user_addr)) {
                    *smart_table::borrow_mut(&mut vault.last_claim, user_addr) = now;
                } else {
                    smart_table::add(&mut vault.last_claim, user_addr, now);
                };
                primary_fungible_store::mint(&vault.mint_ref, user_addr, vault.claim_amount);
            }
        };
        i = i + 1;
    };
}


    // ==========================================
    //               VIEW FUNCTIONS
    // ==========================================

    #[view]
    /// Returns timestamp (in seconds) when user last fetched the asset
    public fun get_last_claim_time(asset: Object<Metadata>, user: address): u64 acquires FaucetConfig {
        let faucet_config = borrow_global<FaucetConfig>(@dev);
        if (!smart_table::contains(&faucet_config.vaults, asset)) {
            return 0
        };
        let vault = smart_table::borrow(&faucet_config.vaults, asset);
        if (smart_table::contains(&vault.last_claim, user)) {
            *smart_table::borrow(&vault.last_claim, user)
        } else {
            0
        }
    }

    #[view]
    /// Returns (can_claim: bool, time_remaining_seconds: u64)
    public fun get_claim_status(asset: Object<Metadata>, user: address): (bool, u64) acquires FaucetConfig {
        let faucet_config = borrow_global<FaucetConfig>(@dev);
        if (!smart_table::contains(&faucet_config.vaults, asset)) {
            return (false, 0)
        };

        let vault = smart_table::borrow(&faucet_config.vaults, asset);
        if (!vault.enabled) {
            return (false, 0)
        };

        let now = timestamp::now_seconds();
        if (smart_table::contains(&vault.last_claim, user)) {
            let last_fetch = *smart_table::borrow(&vault.last_claim, user);
            let next_claim_time = last_fetch + faucet_config.cooldown_seconds;
            if (now >= next_claim_time) {
                (true, 0)
            } else {
                (false, next_claim_time - now)
            }
        } else {
            (true, 0)
        }
    }
}