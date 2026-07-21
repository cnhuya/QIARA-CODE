module dev::QiaraWrapperGateV49 {
    use std::signer;
    use std::option;
    use std::vector;
    use std::string::{Self as string, String, utf8};
    use std::table::{Self as table, Table};
    use std::bcs;
    use aptos_framework::account;
    use aptos_framework::fungible_asset::{Self, MintRef, TransferRef, BurnRef, Metadata, FungibleAsset};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object::{Self, Object};

    use dev::QiaraTokensCoreV49::{Self as TokensCore, Access as TokensCoreAccess};
    use dev::QiaraSharedV17::{Self as Shared, Access as SharedAccess};

// === ERRORS === //
    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_INVALID_UNWRAPPED_TOKEN: u64 = 2;

// === ACCESS === //
    struct Access has store, key, drop {}
    struct Permission has copy, key, drop {}

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == @dev, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_permission(access: &Access): Permission {
        Permission {}
    }

    struct Permissions has key {
        tokens_core_access: TokensCoreAccess,
        shared_access: SharedAccess,
    }

    // === STRUCTS === //
    struct UnwrappedCapabilities has store {
        mint_ref: MintRef,
        burn_ref: BurnRef,
        metadata: Object<Metadata>,
    }

    struct GlobalUnwrappedCapabilities has key {
        caps: Table<address, UnwrappedCapabilities>,
    }

// === INIT === //
    fun init_module(admin: &signer) {
        if (!exists<GlobalUnwrappedCapabilities>(@dev)) {
            move_to(admin, GlobalUnwrappedCapabilities { caps: table::new<address, UnwrappedCapabilities>() });
        };
        if (!exists<Permissions>(@dev)) {
            move_to(admin, Permissions {
                tokens_core_access: TokensCore::give_access(admin),
                shared_access: Shared::give_access(admin),
            });
        };
    }

// === UNWRAP & WRAP CORE LOGIC === //

    /// Dynamically burns the wrapped Q-token (e.g. QETH) and mints a clean, standard 
    /// standard Fungible Asset matching the specific chain and provider.
    /// Example name mapping: "Base Aave Ethereum"
    /// Example symbol mapping: "BA_ETH"
    public fun unwrap_to_standard_fa(shared: String,custom_token: String,chain: String,provider: String,custom_token_fa: FungibleAsset): FungibleAsset acquires GlobalUnwrappedCapabilities, Permissions {
        let amount = fungible_asset::amount(&custom_token_fa);
        let custom_metadata = fungible_asset::asset_metadata(&custom_token_fa);
        
        // 1. Burn the incoming custom wrapped token (e.g. QETH) using TokensCore
        let perms = borrow_global<Permissions>(@dev);
        let tokens_core_perm = TokensCore::give_permission(&perms.tokens_core_access);
        TokensCore::burn_fa(custom_token, chain, custom_token_fa, tokens_core_perm);

        // 2. Derive deterministic address for the new standard asset
        let seed = *string::bytes(&custom_token);
        vector::append(&mut seed, *string::bytes(&chain));
        vector::append(&mut seed, *string::bytes(&provider));
        vector::append(&mut seed, b"-unwrapped");
        let unwrapped_address = account::create_resource_address(&@dev, seed);

        let global_caps = borrow_global_mut<GlobalUnwrappedCapabilities>(@dev);

        // 3. Initialize the standard token on-the-fly if it doesn't exist yet
        if (!table::contains(&global_caps.caps, unwrapped_address)) {
            // Transform symbol: "QETH" -> "ETH", then prepend first letters -> "BA_ETH"
            let custom_symbol = fungible_asset::symbol(custom_metadata);
            let symbol_bytes = string::bytes(&custom_symbol);
            let unwrapped_symbol_bytes = vector::empty<u8>();
            let len = vector::length(symbol_bytes);
            let idx = 1; // Skip the leading 'Q'
            while (idx < len) {
                vector::push_back(&mut unwrapped_symbol_bytes, *vector::borrow(symbol_bytes, idx));
                idx = idx + 1;
            };

            let chain_bytes = string::bytes(&chain);
            let provider_bytes = string::bytes(&provider);
            
            let new_symbol_bytes = vector::empty<u8>();
            if (vector::length(chain_bytes) > 0) {
                vector::push_back(&mut new_symbol_bytes, *vector::borrow(chain_bytes, 0));
            };
            if (vector::length(provider_bytes) > 0) {
                vector::push_back(&mut new_symbol_bytes, *vector::borrow(provider_bytes, 0));
            };
            vector::push_back(&mut new_symbol_bytes, 95); // ASCII code for '_'
            vector::append(&mut new_symbol_bytes, unwrapped_symbol_bytes);
            let new_symbol = string::utf8(new_symbol_bytes);

            // Transform name: e.g. "Base" + "Aave" + "Ethereum" -> "Base Aave Ethereum"
            let new_name_bytes = vector::empty<u8>();
            vector::append(&mut new_name_bytes, *string::bytes(&chain));
            vector::push_back(&mut new_name_bytes, 32); // ASCII space
            vector::append(&mut new_name_bytes, *string::bytes(&provider));
            vector::push_back(&mut new_name_bytes, 32); // ASCII space
            vector::append(&mut new_name_bytes, *string::bytes(&custom_token));
            let new_name = string::utf8(new_name_bytes);

            // Create as a sticky (non-deletable) object to comply with FA standard requirements
            let constructor_ref = object::create_sticky_object(unwrapped_address);
            primary_fungible_store::create_primary_store_enabled_fungible_asset(
                &constructor_ref,
                option::none(),
                new_name,
                new_symbol,
                fungible_asset::decimals(custom_metadata),
                fungible_asset::icon_uri(custom_metadata),
                fungible_asset::project_uri(custom_metadata),
            );

            // Generate Capabilities
            let mint_ref = fungible_asset::generate_mint_ref(&constructor_ref);
            let burn_ref = fungible_asset::generate_burn_ref(&constructor_ref);
            let metadata = object::object_from_constructor_ref<Metadata>(&constructor_ref);

            table::add(&mut global_caps.caps, unwrapped_address, UnwrappedCapabilities {
                mint_ref,
                burn_ref,
                metadata,
            });
        };

        // 4. Mint and return the unwrapped standard FA
        let cap = table::borrow(&global_caps.caps, unwrapped_address);
        fungible_asset::mint(&cap.mint_ref, (amount as u64))
    }

    /// Burns the standard unwrapped FA and mints back the protocol's gated custom Q-token.
    public fun wrap_standard_fa(shared: String,custom_token: String,chain: String,provider: String,unwrapped_fa: FungibleAsset): FungibleAsset acquires GlobalUnwrappedCapabilities, Permissions {
        let amount = fungible_asset::amount(&unwrapped_fa);
        
        // 1. Derive deterministic address for the standard asset to verify validity
        let seed = *string::bytes(&custom_token);
        vector::append(&mut seed, *string::bytes(&chain));
        vector::append(&mut seed, *string::bytes(&provider));
        vector::append(&mut seed, b"-unwrapped");
        let unwrapped_address = account::create_resource_address(&@dev, seed);

        let global_caps = borrow_global_mut<GlobalUnwrappedCapabilities>(@dev);
        assert!(table::contains(&global_caps.caps, unwrapped_address), ERROR_INVALID_UNWRAPPED_TOKEN);

        let cap = table::borrow(&global_caps.caps, unwrapped_address);
        let unwrapped_metadata = fungible_asset::asset_metadata(&unwrapped_fa);
        
        // FIXED: Check metadata object equality directly to resolve randomized sticky AUID mismatch
        assert!(unwrapped_metadata == cap.metadata, ERROR_INVALID_UNWRAPPED_TOKEN);

        // 2. Burn the standard unwrapped FA
        fungible_asset::burn(&cap.burn_ref, unwrapped_fa);

        // 3. Mint the custom wrapped Q-token (QETH, etc.) using TokensCore
        let perms = borrow_global<Permissions>(@dev);
        let tokens_core_perm = TokensCore::give_permission(&perms.tokens_core_access);
        let custom_token_fa = TokensCore::mint(custom_token, chain, (amount as u64), tokens_core_perm);

        custom_token_fa
    }

// === PUBLIC WRAPPING & UNWRAPPING ENTRYPOINTS === //

    /// Withdraws wrapped custom tokens from shared storage, converts them, 
    /// and deposits the unwrapped standard FA into the user's native wallet.
    public entry fun unwrap_custom_token(signer: &signer,shared: String,custom_token: String,chain: String,provider: String,amount: u64) acquires GlobalUnwrappedCapabilities, Permissions {
        Shared::assert_is_sub_owner(shared, bcs::to_bytes(&signer::address_of(signer)));
        
        let shared_access_perm = {
            let perms = borrow_global<Permissions>(@dev);
            Shared::give_permission(&perms.shared_access)
        };
        
        let user_shared_store = Shared::ensure_shared_fungible_storage(shared, TokensCore::get_metadata(custom_token), shared_access_perm);
        let custom_fa = TokensCore::withdraw(shared, user_shared_store, amount, chain);

        let unwrapped_fa = unwrap_to_standard_fa(shared, custom_token, chain, provider, custom_fa);

        let unwrapped_metadata = fungible_asset::asset_metadata(&unwrapped_fa);
        let user_storage = primary_fungible_store::ensure_primary_store_exists(signer::address_of(signer), unwrapped_metadata);
        fungible_asset::deposit(user_storage, unwrapped_fa);
    }

    /// Withdraws standard FA tokens from the user's native wallet, converts them, 
    /// and deposits the wrapped custom tokens into their shared storage.
    public entry fun wrap_standard_token(signer: &signer,shared: String,custom_token: String,chain: String,provider: String,amount: u64) acquires GlobalUnwrappedCapabilities, Permissions {
        Shared::assert_is_sub_owner(shared, bcs::to_bytes(&signer::address_of(signer)));

        let seed = *string::bytes(&custom_token);
        vector::append(&mut seed, *string::bytes(&chain));
        vector::append(&mut seed, *string::bytes(&provider));
        vector::append(&mut seed, b"-unwrapped");
        let unwrapped_address = account::create_resource_address(&@dev, seed);

        let global_caps = borrow_global<GlobalUnwrappedCapabilities>(@dev);
        assert!(table::contains(&global_caps.caps, unwrapped_address), ERROR_INVALID_UNWRAPPED_TOKEN);
        let cap = table::borrow(&global_caps.caps, unwrapped_address);

        let user_storage = primary_fungible_store::primary_store(signer::address_of(signer), cap.metadata);
        let unwrapped_fa = fungible_asset::withdraw(signer, user_storage, amount);

        let shared_access_perm = {
            let perms = borrow_global<Permissions>(@dev);
            Shared::give_permission(&perms.shared_access)
        };

        let custom_fa = wrap_standard_fa(shared, custom_token, chain, provider, unwrapped_fa);

        let user_shared_store = Shared::ensure_shared_fungible_storage(shared, TokensCore::get_metadata(custom_token), shared_access_perm);
        TokensCore::deposit(shared, user_shared_store, custom_fa, chain);
    }
}