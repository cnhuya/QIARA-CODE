module dev::QiaraTokensQiaraV87 {
    use std::signer;
    use std::option;
    use std::vector;
    use std::bcs;
    use std::timestamp;
    use std::string::{String, utf8};
    use aptos_std::table::{Self, Table};
    use aptos_std::secp256k1;
    use aptos_std::aptos_hash::keccak256;
    use aptos_framework::fungible_asset::{Self, MintRef, BurnRef, TransferRef, Metadata, FungibleAsset};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::dispatchable_fungible_asset;
    use aptos_framework::function_info;
    use aptos_std::from_bcs;
    use aptos_std::bcs_stream;

    use event::QiaraEventV1 as Event;
    use dev::QiaraCapabilitiesV24 as capabilities;
    use dev::QiaraStorageV24 as storage;
    use dev::QiaraGenesisV4 as Genesis;
    use dev::QiaraNonceV4 as Nonce;

    const ADMIN: address = @dev;
    const CHAIN_ID_APTOS: u32 = 2;
    const DECIMALS: u8 = 9;
    const INITIAL_SUPPLY: u64 = 1_000_000 * 1_000_000_000; // 1,000,000 QIARA (9 decimals)

    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_NOT_AUTHORIZED_FOR_CLAIMING: u64 = 2;
    const ERROR_REPLAY_ATTACK: u64 = 3;
    const ERROR_INSUFFICIENT_VALIDATORS: u64 = 6;
    const ERROR_WRONG_CHAIN: u64 = 7;
    const ERROR_ZERO_AMOUNT: u64 = 8;
    const ERROR_UNAUTHORIZED_WHITELIST_ADMIN: u64 = 9;
    const ERROR_INVALID_FEE: u64 = 10;
    const ERROR_INVALID_NULLIFIER: u64 = 101;

    struct Access has store, key, drop {}
    struct Permission has copy, key, drop {}

    struct Timers has copy, key, drop {
        creation: u64,
        last_claimed: u64,
    }

    struct AssetRefs has key {
        mint_ref: MintRef,
        burn_ref: BurnRef,
        transfer_ref: TransferRef,
    }

    struct BridgeState has key {
        used_nullifiers: Table<vector<u8>, bool>,
        validator_keys: vector<vector<u8>>,
        fee_exempt: vector<address>,
    }

    struct QiaraData has copy, drop {
        timers: Timers,
        epoch: u64,
        inflation: u64,
        actual_inflation: u64,
        inflation_minimal: u64,
        inflation_debt: u64,
        burn_fee: u64,
        actual_burn_fee: u64,
        burn_fee_increase: u64,
        burn_fee_minimal: u64,
        validator_emissions_rate: u64,
        validator_emissions: u64,
        base_burned_qiara_rate: u64,
        burned_qiara_rate: u64,
        qiara_supply: u256,
        burned_qiara: u256,
        ratio: u256
    }

    public fun give_access(s: &signer): Access {
        assert!(signer::address_of(s) == ADMIN, ERROR_NOT_ADMIN);
        Access {}
    }

    public fun give_permission(_access: &Access): Permission {
        Permission {}
    }

    // =========================================================================
    // INITIALIZATION (Standard Fungible Asset + Dispatchable Hooks)
    // =========================================================================

    public entry fun init_qiara(admin: &signer) {
        let addr = signer::address_of(admin);
        assert!(addr == ADMIN, ERROR_NOT_ADMIN);

        if (!exists<Timers>(ADMIN)) {
            move_to(admin, Timers {
                creation: timestamp::now_seconds(),
                last_claimed: timestamp::now_seconds()
            });
        };

        if (!exists<BridgeState>(ADMIN)) {
            move_to(admin, BridgeState {
                used_nullifiers: table::new(),
                validator_keys: vector::empty(),
                fee_exempt: vector::empty(),
            });
        };

        // Create the official, non-prefixed standard Fungible Asset directly
        if (!exists<AssetRefs>(ADMIN)) {
            let constructor_ref = &object::create_named_object(admin, b"QIARA2");

            primary_fungible_store::create_primary_store_enabled_fungible_asset(
                constructor_ref,
                option::none(),              // Max supply: unbounded (managed by mint_ref)
                utf8(b"Qiara"),              // Name
                utf8(b"QIARA"),              // Symbol
                DECIMALS,                    // Decimals: 9
                utf8(b"https://raw.githubusercontent.com/cnhuya/AEXIS-CDN/main/tokens/qiara.webp"),
                utf8(b"https://x.com/QiaraProtocol"),
            );

            // Register native dispatch hooks to ensure dynamic burn fees on all transfers
            let withdraw_hook = function_info::new_function_info(
                admin,
                utf8(b"QiaraTokensQiaraV87"),
                utf8(b"withdraw"),
            );
            let deposit_hook = function_info::new_function_info(
                admin,
                utf8(b"QiaraTokensQiaraV87"),
                utf8(b"deposit"),
            );
            dispatchable_fungible_asset::register_dispatch_functions(
                constructor_ref,
                option::some(withdraw_hook),
                option::some(deposit_hook),
                option::none(),
            );

            let mint_ref = fungible_asset::generate_mint_ref(constructor_ref);
            let burn_ref = fungible_asset::generate_burn_ref(constructor_ref);
            let transfer_ref = fungible_asset::generate_transfer_ref(constructor_ref);

            // Mint 1,000,000 QIARA directly to deployer's primary store (Shows in Petra!)
            primary_fungible_store::mint(&mint_ref, addr, INITIAL_SUPPLY);

            move_to(admin, AssetRefs { mint_ref, burn_ref, transfer_ref });
        };
    }

    // =========================================================================
    // DISPATCHABLE HOOKS (Matches EVM _update())
    // =========================================================================

    /// Custom withdraw hook called whenever QIARA is withdrawn from any store (transfers, DEX swaps, etc.)
    public fun withdraw<T: key>(
        store: Object<T>,
        amount: u64,
        transfer_ref: &TransferRef,
    ): FungibleAsset acquires BridgeState, Timers, AssetRefs {
        let store_owner = object::owner(store);
        let mut_fa = fungible_asset::withdraw_with_ref(transfer_ref, store, amount);

        // If sender is fee exempt or amount is 0, transfer without fee
        if (is_fee_exempt(store_owner) || amount == 0) {
            return mut_fa
        };

        let fee = burn_calculation(amount);
        if (fee > 0) {
            let refs = borrow_global<AssetRefs>(ADMIN);
            // Extract the fee and burn it directly (1:1 with EVM _update burn)
            let fee_fa = fungible_asset::extract(&mut mut_fa, fee);
            fungible_asset::burn(&refs.burn_ref, fee_fa);
        };

        mut_fa
    }

    /// Custom deposit hook for dispatchable fungible asset standard compliance
    public fun deposit<T: key>(
        store: Object<T>,
        fa: FungibleAsset,
        transfer_ref: &TransferRef,
    ) {
        fungible_asset::deposit_with_ref(transfer_ref, store, fa);
    }

    // =========================================================================
    // INFLATION CLAIMING
    // =========================================================================

    /// Claims accrued inflation and mints directly to the recipient primary store
    public entry fun claim_inflation(claimer: &signer,shared: String,recipient: address) acquires Timers, AssetRefs {
        let claimer_addr = signer::address_of(claimer);

        // Caller must either be ADMIN or authorized with the INFLATION_CLAIM capability on the shared wallet
        if (claimer_addr != ADMIN) {
            assert!(
                capabilities::assert_wallet_capability(shared, utf8(b"QiaraToken"), utf8(b"INFLATION_CLAIM")),
                ERROR_NOT_AUTHORIZED_FOR_CLAIMING
            );
        };

        let metadata = get_metadata();
        let supply = (option::destroy_with_default(fungible_asset::supply(metadata), 0) as u128);
        let claimable_amount = (claimable(supply) as u64);
        assert!(claimable_amount > 0, ERROR_ZERO_AMOUNT);

        // Update timer
        borrow_global_mut<Timers>(ADMIN).last_claimed = timestamp::now_seconds();

        // Mint inflation to recipient
        let refs = borrow_global<AssetRefs>(ADMIN);
        primary_fungible_store::mint(&refs.mint_ref, recipient, claimable_amount);

        // Emit on-chain event
        let event_data = vector[
            Event::create_data_struct(utf8(b"claimer"), utf8(b"address"), bcs::to_bytes(&claimer_addr)),
            Event::create_data_struct(utf8(b"recipient"), utf8(b"address"), bcs::to_bytes(&recipient)),
            Event::create_data_struct(utf8(b"amount"), utf8(b"u64"), bcs::to_bytes(&claimable_amount)),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
        ];
        Event::emit_consensus_event(utf8(b"Claim Inflation"), event_data);
    }

    /// Convenience entry function to claim inflation directly to the caller's account
    public entry fun claim_inflation_to_self(claimer: &signer,shared: String) acquires Timers, AssetRefs {
        let caller = signer::address_of(claimer);
        claim_inflation(claimer, shared, caller);
    }

    // =========================================================================
    // PERMISSIONED BRIDGE / WRAPPER HOOKS
    // =========================================================================

    public fun mint_to_user(recipient: address, amount: u64, _perm: &Permission) acquires AssetRefs {
        let refs = borrow_global<AssetRefs>(ADMIN);
        primary_fungible_store::mint(&refs.mint_ref, recipient, amount);
    }

    public fun burn_from_user(account: address, amount: u64, _perm: &Permission) acquires AssetRefs {
        let refs = borrow_global<AssetRefs>(ADMIN);
        primary_fungible_store::burn(&refs.burn_ref, account, amount);
    }

    public fun mint_fa(amount: u64, _perm: &Permission): FungibleAsset acquires AssetRefs {
        let refs = borrow_global<AssetRefs>(ADMIN);
        fungible_asset::mint(&refs.mint_ref, amount)
    }

    // =========================================================================
    // METADATA RESOLVERS
    // =========================================================================

    #[view]
    public fun get_metadata(): Object<Metadata> {
        let metadata_address = object::create_object_address(&ADMIN, b"QIARA");
        object::address_to_object<Metadata>(metadata_address)
    }

    #[view]
    public fun get_metadata_address(): address {
        object::create_object_address(&ADMIN, b"QIARA")
    }

    // =========================================================================
    // CONSENSUS MINT (1:1 with Solana & EVM)
    // =========================================================================

    public entry fun consensus_mint(nullifier: vector<u8>,raw_payload: vector<u8>,signatures: vector<vector<u8>>) acquires BridgeState, AssetRefs {
        let state = borrow_global_mut<BridgeState>(ADMIN);

        let computed_nullifier = keccak256(raw_payload);
        assert!(vector::length(&nullifier) == 32, ERROR_INVALID_NULLIFIER);
        assert!(nullifier == computed_nullifier, ERROR_INVALID_NULLIFIER);

        verify_signatures(&nullifier, &signatures, &state.validator_keys);

        assert!(!table::contains(&state.used_nullifiers, nullifier), ERROR_REPLAY_ATTACK);
        table::add(&mut state.used_nullifiers, nullifier, true);

        let stream = bcs_stream::new(raw_payload);
        let addr_bytes = bcs_stream::deserialize_vector<u8>(&mut stream, |s| bcs_stream::deserialize_u8(s));
        let recipient = from_bcs::to_address(addr_bytes);
        let amount = bcs_stream::deserialize_u64(&mut stream);
        let chain_id = (bcs_stream::deserialize_u32(&mut stream) as u32);
        let nonce = bcs_stream::deserialize_u64(&mut stream);

        assert!(chain_id == CHAIN_ID_APTOS, ERROR_WRONG_CHAIN);

        let refs = borrow_global<AssetRefs>(ADMIN);
        primary_fungible_store::mint(&refs.mint_ref, recipient, amount);

        let event_data = vector[
            Event::create_data_struct(utf8(b"to"), utf8(b"address"), bcs::to_bytes(&recipient)),
            Event::create_data_struct(utf8(b"amount"), utf8(b"u64"), bcs::to_bytes(&amount)),
            Event::create_data_struct(utf8(b"nonce"), utf8(b"u64"), bcs::to_bytes(&nonce)),
            Event::create_data_struct(utf8(b"nullifier"), utf8(b"vector<u8>"), nullifier)
        ];
        Event::emit_consensus_event(utf8(b"Consensus Mint"), event_data);
    }

    // =========================================================================
    // BRIDGE REQUEST
    // =========================================================================

    public entry fun request_bridge(user: &signer,chain: String,amount: u64,receiver: vector<u8>) acquires BridgeState, AssetRefs {
        assert!(amount > 0, ERROR_ZERO_AMOUNT);
        let user_addr = signer::address_of(user);
        let refs = borrow_global<AssetRefs>(ADMIN);

        let fee_rate = get_bridge_tax_fee();
        assert!(fee_rate <= 100_000_000, ERROR_INVALID_FEE);

        let bridge_tax_amount = if (is_fee_exempt(user_addr)) {
            0
        } else {
            (((amount as u128) * (fee_rate as u128) / 100_000_000) as u64)
        };
        let net_amount = amount - bridge_tax_amount;
        assert!(net_amount > 0, ERROR_ZERO_AMOUNT);

        let metadata = fungible_asset::transfer_ref_metadata(&refs.transfer_ref);

        if (bridge_tax_amount > 0) {
            let user_store = primary_fungible_store::primary_store(user_addr, metadata);
            let receiver_store = primary_fungible_store::ensure_primary_store_exists(get_bridge_tax_receiver(), metadata);
            let fee_fa = fungible_asset::withdraw_with_ref(&refs.transfer_ref, user_store, bridge_tax_amount);
            fungible_asset::deposit_with_ref(&refs.transfer_ref, receiver_store, fee_fa);
        };

        primary_fungible_store::burn(&refs.burn_ref, user_addr, net_amount);

        let nonce = Nonce::return_user_nonce_by_type(receiver, utf8(b"qiara"));

        let data = vector[
            Event::create_data_struct(utf8(b"consensus_type"), utf8(b"string"), bcs::to_bytes(&utf8(b"zk"))),
            Event::create_data_struct(utf8(b"sender"), utf8(b"address"), bcs::to_bytes(&user_addr)),
            Event::create_data_struct(utf8(b"addr"), utf8(b"vector<u8>"), receiver),
            Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&chain)),
            Event::create_data_struct(utf8(b"nonce"), utf8(b"u256"), bcs::to_bytes(&nonce)),
            Event::create_data_struct(utf8(b"amount"), utf8(b"u64"), bcs::to_bytes(&net_amount)),
            Event::create_data_struct(utf8(b"fee"), utf8(b"u64"), bcs::to_bytes(&bridge_tax_amount)),
        ];
        Event::emit_consensus_event(utf8(b"Request Qiara Bridge"), data);
    }

    // =========================================================================
    // SIGNATURE VERIFICATION
    // =========================================================================

    fun verify_signatures(msg_hash: &vector<u8>, signatures: &vector<vector<u8>>, validator_pubkeys: &vector<vector<u8>>) {
        let num_sigs = vector::length(signatures);
        let min_validators = storage::expect_u8(storage::viewConstant(utf8(b"QiaraBridge"), utf8(b"MINIMUM_UNIQUE_VALIDATORS")));
        assert!((num_sigs as u8) >= min_validators, ERROR_INSUFFICIENT_VALIDATORS);

        let eth_prefix = b"\x19Ethereum Signed Message:\n32";
        vector::append(&mut eth_prefix, *msg_hash);
        let eth_signed_hash = keccak256(eth_prefix);

        let i = 0;
        while (i < num_sigs) {
            let sig_65 = vector::borrow(signatures, i);
            assert!(vector::length(sig_65) == 65, 101);

            let sig_64 = slice(sig_65, 0, 64);
            let v = *vector::borrow(sig_65, 64);
            let recovery_id = if (v >= 27) { v - 27 } else { v };

            let ecdsa_sig = secp256k1::ecdsa_signature_from_bytes(sig_64);
            let recovered_key = secp256k1::ecdsa_recover(eth_signed_hash, recovery_id, &ecdsa_sig);
            assert!(option::is_some(&recovered_key), 102);

            let pubkey_bytes = secp256k1::ecdsa_raw_public_key_to_bytes(option::borrow(&recovered_key));
            assert!(vector::contains(validator_pubkeys, &pubkey_bytes), 103);
            i = i + 1;
        };
    }

    // =========================================================================
    // ADMIN & CONFIGURATION
    // =========================================================================

    public fun sync_validator_keys(keys: vector<vector<u8>>, _perm: &Permission) acquires BridgeState {
        let state = borrow_global_mut<BridgeState>(ADMIN);
        if (&state.validator_keys == &keys) return;
        state.validator_keys = keys;
    }

    public entry fun set_fee_exempt(caller: &signer, account: address, exempt: bool) acquires BridgeState {
        let caller_addr = signer::address_of(caller);
        let state = borrow_global_mut<BridgeState>(ADMIN);

        assert!(caller_addr == get_whitelist_admin(), ERROR_UNAUTHORIZED_WHITELIST_ADMIN);

        let (found, idx) = vector::index_of(&state.fee_exempt, &account);
        if (exempt && !found) {
            vector::push_back(&mut state.fee_exempt, account);
        } else if (!exempt && found) {
            vector::swap_remove(&mut state.fee_exempt, idx);
        };
    }

    public fun change_last_claim(shared: String, _perm: Permission) acquires Timers {
        assert!(capabilities::assert_wallet_capability(shared, utf8(b"QiaraToken"), utf8(b"INFLATION_CLAIM")), ERROR_NOT_AUTHORIZED_FOR_CLAIMING);
        borrow_global_mut<Timers>(ADMIN).last_claimed = timestamp::now_seconds();
    }

    public fun get_bridge_tax_receiver(): address {
        storage::expect_address_padded(storage::viewConstant(utf8(b"QiaraToken"), utf8(b"APTOS_BRIDGE_TAX_FEE_RECEIVER")))
    }

    public fun get_whitelist_admin(): address {
        storage::expect_address_padded(storage::viewConstant(utf8(b"QiaraToken"), utf8(b"APTOS_WHITELIST_ADMIN")))
    }

    public fun get_bridge_tax_fee(): u64 {
        storage::expect_u64(storage::viewConstant(utf8(b"QiaraToken"), utf8(b"BRIDGE_TAX_FEE")))
    }

// =========================================================================
    // PROTOCOL STATE EVENT EMISSION
    // =========================================================================

    /// Emits the current token protocol state (epoch, supply, inflation, burn rate, etc.)
    /// Called after key state changes (like burns / reward claims) or by off-chain indexers.
    public entry fun emit_qiara_events() acquires Timers {
        let data = get_qiara_data();
        let event_data = vector[
            Event::create_data_struct(utf8(b"epoch"), utf8(b"u64"), bcs::to_bytes(&data.epoch)),
            Event::create_data_struct(utf8(b"inflation"), utf8(b"u64"), bcs::to_bytes(&data.inflation)),
            Event::create_data_struct(utf8(b"actual_inflation"), utf8(b"u64"), bcs::to_bytes(&data.actual_inflation)),
            Event::create_data_struct(utf8(b"burn_fee"), utf8(b"u64"), bcs::to_bytes(&data.burn_fee)),
            Event::create_data_struct(utf8(b"actual_burn_fee"), utf8(b"u64"), bcs::to_bytes(&data.actual_burn_fee)),
            Event::create_data_struct(utf8(b"validator_emissions"), utf8(b"u64"), bcs::to_bytes(&data.validator_emissions)),
            Event::create_data_struct(utf8(b"base_burned_qiara_rate"), utf8(b"u64"), bcs::to_bytes(&data.base_burned_qiara_rate)),
            Event::create_data_struct(utf8(b"burned_qiara_rate"), utf8(b"u64"), bcs::to_bytes(&data.burned_qiara_rate)),
            Event::create_data_struct(utf8(b"qiara_supply"), utf8(b"u256"), bcs::to_bytes(&data.qiara_supply)),
            Event::create_data_struct(utf8(b"ratio"), utf8(b"u256"), bcs::to_bytes(&data.ratio)),
        ];
        Event::emit_consensus_event(utf8(b"Qiara Token Update"), event_data);
    }

    #[view]
    public fun is_fee_exempt(account: address): bool acquires BridgeState {
        // ADMIN and Token Metadata address are inherently exempt to prevent recursive taxation
        if (account == ADMIN || account == get_metadata_address()) {
            return true
        };
        vector::contains(&borrow_global<BridgeState>(ADMIN).fee_exempt, &account)
    }

    #[view]
    public fun get_exempt_accounts(): vector<address> acquires BridgeState {
        borrow_global<BridgeState>(ADMIN).fee_exempt
    }

    #[view]
    public fun get_qiara_data(): QiaraData acquires Timers {
        let (burned_qiara, qiara_supply, ratio) = get_ratio();
        QiaraData {
            timers: *borrow_global<Timers>(ADMIN),
            epoch: get_epoch(),
            inflation: get_inflation(),
            actual_inflation: get_actual_inflation(),
            inflation_minimal: get_minimal_inflation(),
            inflation_debt: get_inflation_debt(),
            burn_fee: get_burn_fee(),
            actual_burn_fee: burn_fee(),
            burn_fee_increase: get_burn_fee_increase(),
            burn_fee_minimal: get_burn_fee_minimal(),
            validator_emissions_rate: get_emissions_validators(),
            validator_emissions: calculate_emissions(),
            base_burned_qiara_rate: get_locked_qiara_rate(),
            burned_qiara_rate: get_burned_qiara_rate(),
            qiara_supply,
            burned_qiara,
            ratio,
        }
    }

    #[view]
    public fun get_actual_inflation(): u64 acquires Timers {
        let debt = get_inflation_debt();
        let infl = get_inflation();
        if (debt > infl) { get_minimal_inflation() } else { infl - debt }
    }

    #[view]
    public fun get_ratio(): (u256, u256, u256) {
        let metadata = get_metadata();
        let q = (option::destroy_some(fungible_asset::supply(metadata)) as u256);
        (0, q, 0)
    }

    #[view]
    public fun get_burned_qiara_rate(): u64 {
        get_locked_qiara_rate()
    }

    #[view]
    public fun get_last_claimed(): u64 acquires Timers {
        borrow_global<Timers>(ADMIN).last_claimed
    }

    #[view]
    public fun get_inflation(): u64 {
        storage::expect_u64(storage::viewConstant(utf8(b"QiaraToken"), utf8(b"INFLATION")))
    }

    #[view]
    public fun get_minimal_inflation(): u64 {
        storage::expect_u64(storage::viewConstant(utf8(b"QiaraToken"), utf8(b"MINIMAL_INFLATION")))
    }

    #[view]
    public fun get_emissions_validators(): u64 {
        storage::expect_u64(storage::viewConstant(utf8(b"QiaraToken"), utf8(b"EMISSIONS_VALIDATORS")))
    }

    #[view]
    public fun get_locked_qiara_rate(): u64 {
        storage::expect_u64(storage::viewConstant(utf8(b"QiaraToken"), utf8(b"LOCKED_QIARA_REWARD_RATE")))
    }

    #[view]
    public fun get_inflation_debt(): u64 acquires Timers {
        get_epoch() * storage::expect_u64(storage::viewConstant(utf8(b"QiaraToken"), utf8(b"INFLATION_DEBT")))
    }

    #[view]
    public fun get_burn_fee(): u64 {
        storage::expect_u64(storage::viewConstant(utf8(b"QiaraToken"), utf8(b"BURN_FEE")))
    }

    #[view]
    public fun get_burn_fee_minimal(): u64 {
        storage::expect_u64(storage::viewConstant(utf8(b"QiaraToken"), utf8(b"BURN_FEE_MINIMAL")))
    }

    #[view]
    public fun get_burn_fee_increase(): u64 acquires Timers {
        get_epoch() * storage::expect_u64(storage::viewConstant(utf8(b"QiaraToken"), utf8(b"BURN_INCREASE")))
    }

    #[view]
    public fun get_epoch(): u64 acquires Timers {
        (timestamp::now_seconds() - borrow_global<Timers>(ADMIN).creation) / (Genesis::return_epoch_duration() as u64)
    }

    #[view]
    public fun claimable(circulating_supply: u128): u128 acquires Timers {
        let delta = (timestamp::now_seconds() - borrow_global<Timers>(ADMIN).last_claimed as u128);
        let actual_inflation = (get_actual_inflation() as u128);
        (circulating_supply * actual_inflation * delta) / (31_536_000u128 * 100_000_000u128)
    }

    #[view]
    public fun burn_fee(): u64 acquires Timers {
        get_burn_fee_increase() + get_burn_fee()
    }

    #[view]
    public fun burn_calculation(amount: u64): u64 acquires Timers {
        let min = get_burn_fee_minimal();
        let fee = (((amount as u128) * (burn_fee() as u128) / 100_000_000) as u64);
        let final_fee = if (fee == 0) {
            if (min > amount) amount else min
        } else {
            if (fee > min) fee else min
        };
        if (final_fee > amount) { amount } else { final_fee }
    }

    #[view]
    public fun calculate_emissions(): u64 {
        let cur_supply = option::destroy_with_default(fungible_asset::supply(get_metadata()), 0) / 100_000_000;
        (get_emissions_validators() * (cur_supply as u64)) / 100_000_000
    }

    fun slice(bytes: &vector<u8>, from: u64, to: u64): vector<u8> {
        let out = vector::empty();
        let i = from;
        while (i < to) {
            vector::push_back(&mut out, *vector::borrow(bytes, i));
            i = i + 1;
        };
        out
    }
}