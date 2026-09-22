module dev::QiaraTokensQiaraV73 {
    use std::signer;
    use std::option;
    use std::vector;
    use std::bcs;
    use std::timestamp;
    use std::string::{String, utf8};
    use aptos_std::table::{Self, Table};
    use aptos_std::secp256k1;
    use aptos_std::aptos_hash::keccak256;
    use aptos_framework::fungible_asset::{Self, MintRef, BurnRef, Metadata};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object::{Self, Object};
    use aptos_std::from_bcs;

    use event::QiaraEventV1 as Event;
    use dev::QiaraCapabilitiesV22 as capabilities;
    use dev::QiaraStorageV22 as storage;
    use dev::QiaraTokenTypesV74 as TokensType;
    use dev::QiaraGenesisV4 as Genesis;

    use dev::Groth16VerifierV73 as Groth16Verifier;

    const ADMIN: address = @dev;
    const CHAIN_ID_APTOS: u64 = 1; // Match runtime chain id

    const ERROR_NOT_ADMIN: u64 = 1;
    const ERROR_NOT_AUTHORIZED_FOR_CLAIMING: u64 = 2;
    const ERROR_REPLAY_ATTACK: u64 = 3;
    const ERROR_INVALID_PROOF: u64 = 4;
    const ERROR_INVALID_SIGNATURES: u64 = 5;
    const ERROR_INSUFFICIENT_VALIDATORS: u64 = 6;
    const ERROR_WRONG_CHAIN: u64 = 7;
    const ERROR_ZERO_AMOUNT: u64 = 8;

    struct Access has store, key, drop {}
    struct Permission has copy, key, drop {}

    struct Timers has copy, key, drop {
        creation: u64,
        last_claimed: u64,
    }

    struct AssetRefs has key {
        mint_ref: MintRef,
        burn_ref: BurnRef,
    }

    struct BridgeState has key {
        used_nullifiers: Table<vector<u8>, bool>,
        vk: vector<u8>,
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

    public entry fun init_qiara(admin: &signer) {
        let addr = signer::address_of(admin);
        assert!(addr == ADMIN, ERROR_NOT_ADMIN);

        if (!exists<Timers>(ADMIN)) {
            move_to(admin, Timers { creation: timestamp::now_seconds(), last_claimed: timestamp::now_seconds() });
        };
        if (!exists<BridgeState>(ADMIN)) {
            move_to(admin, BridgeState {
                used_nullifiers: table::new(),
                vk: vector::empty(),
            });
        };
    }

    public fun init_token_refs(admin: &signer, mint_ref: MintRef, burn_ref: BurnRef) {
        assert!(signer::address_of(admin) == ADMIN, ERROR_NOT_ADMIN);
        move_to(admin, AssetRefs { mint_ref, burn_ref });
    }

    public entry fun set_vk(admin: &signer, vk: vector<u8>) acquires BridgeState {
        assert!(signer::address_of(admin) == ADMIN, ERROR_NOT_ADMIN);
        borrow_global_mut<BridgeState>(ADMIN).vk = vk;
    }

    public fun change_last_claim(shared: String, _perm: Permission) acquires Timers {
        assert!(capabilities::assert_wallet_capability(shared, utf8(b"QiaraToken"), utf8(b"INFLATION_CLAIM")), ERROR_NOT_AUTHORIZED_FOR_CLAIMING);
        borrow_global_mut<Timers>(ADMIN).last_claimed = timestamp::now_seconds();
    }

    // === BRIDGE & ZK FUNCTIONS === //

    public entry fun request_bridge(user: &signer,shared: String,destination_chain: String,amount: u64) acquires AssetRefs {
        assert!(amount > 0, ERROR_ZERO_AMOUNT);
        let user_addr = signer::address_of(user);
        let refs = borrow_global<AssetRefs>(ADMIN);
        primary_fungible_store::burn(&refs.burn_ref, user_addr, amount);

        let data = vector[
            Event::create_data_struct(utf8(b"user"), utf8(b"address"), bcs::to_bytes(&user_addr)),
            Event::create_data_struct(utf8(b"shared"), utf8(b"string"), bcs::to_bytes(&shared)),
            Event::create_data_struct(utf8(b"chain"), utf8(b"string"), bcs::to_bytes(&destination_chain)),
            Event::create_data_struct(utf8(b"amount"), utf8(b"u64"), bcs::to_bytes(&amount))
        ];
        Event::emit_qiara_burn_event(data);
    }

    public entry fun zk_mint(proof: vector<u8>,pub_signals: vector<vector<u8>>,signatures: vector<vector<u8>>,validator_keys: vector<vector<u8>>) acquires BridgeState, AssetRefs {
        let state = borrow_global_mut<BridgeState>(ADMIN);

        // Groth16 Verification via dev::Groth16Verifier
        assert!(Groth16Verifier::verify(&state.vk, &proof, &pub_signals), ERROR_INVALID_PROOF);

        // Packed signal 4: [Amount:64 | ChainID:32 | Nonce:32]
        let packed_bytes = *vector::borrow(&pub_signals, 4);
        let amount = bcs_to_u64_le(&slice(&packed_bytes, 0, 8));
        let chain_id = (bcs_to_u32_le(&slice(&packed_bytes, 8, 12)) as u64);
        let nonce = (bcs_to_u32_le(&slice(&packed_bytes, 12, 16)) as u64);

        assert!(chain_id == CHAIN_ID_APTOS, ERROR_WRONG_CHAIN);

        // Nullifier computation: keccak256(pub_signals[0..5])
        let flat_signals = vector::empty<u8>();
        let i = 0;
        while (i < 5) {
            vector::append(&mut flat_signals, *vector::borrow(&pub_signals, i));
            i = i + 1;
        };
        let nullifier = keccak256(flat_signals);

        assert!(!table::contains(&state.used_nullifiers, nullifier), ERROR_REPLAY_ATTACK);
        table::add(&mut state.used_nullifiers, nullifier, true);

        verify_signatures(&nullifier, &signatures, &validator_keys);

        // Decode recipient: 16B from pub_signals[3] + 16B from pub_signals[2]
        let addr_bytes = slice(vector::borrow(&pub_signals, 3), 0, 16);
        vector::append(&mut addr_bytes, slice(vector::borrow(&pub_signals, 2), 0, 16));
        let recipient = from_bcs::to_address(addr_bytes);

        let refs = borrow_global<AssetRefs>(ADMIN);
        primary_fungible_store::mint(&refs.mint_ref, recipient, amount);

        let event_data = vector[
            Event::create_data_struct(utf8(b"to"), utf8(b"address"), bcs::to_bytes(&recipient)),
            Event::create_data_struct(utf8(b"amount"), utf8(b"u64"), bcs::to_bytes(&amount)),
            Event::create_data_struct(utf8(b"nonce"), utf8(b"u64"), bcs::to_bytes(&nonce)),
            Event::create_data_struct(utf8(b"nullifier"), utf8(b"vector<u8>"), nullifier)
        ];
        Event::emit_qiara_burn_event(event_data);
    }

    // === SIGNATURE VERIFICATION === //

   fun verify_signatures(msg_hash: &vector<u8>, signatures: &vector<vector<u8>>, validator_pubkeys: &vector<vector<u8>>) {
        let num_sigs = vector::length(signatures);
        let min_validators = storage::expect_u64(storage::viewConstant(utf8(b"QiaraValidators"), utf8(b"MINIMUM_UNIQUE_VALIDATORS")));
        assert!(num_sigs >= min_validators, ERROR_INSUFFICIENT_VALIDATORS);

        let eth_prefix = b"\x19Ethereum Signed Message:\n32";
        vector::append(&mut eth_prefix, *msg_hash);
        let eth_signed_hash = keccak256(eth_prefix);

        let i = 0;
        while (i < num_sigs) {
            let sig_65 = vector::borrow(signatures, i);
            assert!(vector::length(sig_65) == 65, ERROR_INVALID_SIGNATURES);

            let sig_64 = slice(sig_65, 0, 64);
            let v = *vector::borrow(sig_65, 64);
            let recovery_id = if (v >= 27) { v - 27 } else { v };

            let ecdsa_sig = secp256k1::ecdsa_signature_from_bytes(sig_64);
            let recovered_key = secp256k1::ecdsa_recover(eth_signed_hash, recovery_id, &ecdsa_sig);
            assert!(option::is_some(&recovered_key), ERROR_INVALID_SIGNATURES);

            let pubkey_bytes = secp256k1::ecdsa_raw_public_key_to_bytes(option::borrow(&recovered_key));
            assert!(vector::contains(validator_pubkeys, &pubkey_bytes), ERROR_INVALID_SIGNATURES);
            i = i + 1;
        };
    }

    // === OPTIMIZED VIEW & HELPER FUNCTIONS === //

    public fun emit_qiara_events() acquires Timers {
        let d = get_qiara_data();
        let data = vector[
            Event::create_data_struct(utf8(b"qiara_supply"), utf8(b"u256"), bcs::to_bytes(&d.qiara_supply)),
            Event::create_data_struct(utf8(b"total_burned"), utf8(b"u256"), bcs::to_bytes(&d.burned_qiara)),
            Event::create_data_struct(utf8(b"inflation"), utf8(b"u64"), bcs::to_bytes(&d.actual_inflation)),
            Event::create_data_struct(utf8(b"burn_fee"), utf8(b"u64"), bcs::to_bytes(&d.actual_burn_fee)),
            Event::create_data_struct(utf8(b"burned_qiara_rate"), utf8(b"u64"), bcs::to_bytes(&d.burned_qiara_rate))
        ];
        Event::emit_qiara_burn_event(data);
    }

    #[view]
    public fun get_metadata(symbol: String): Object<Metadata> {
        let asset_address = object::create_object_address(&ADMIN, bcs::to_bytes(&TokensType::convert_token_nickName_to_name(symbol)));
        object::address_to_object<Metadata>(asset_address)
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
        let b = (option::destroy_some(fungible_asset::supply(get_metadata(utf8(b"Burned Qiara")))) as u256);
        let q = (option::destroy_some(fungible_asset::supply(get_metadata(utf8(b"Qiara")))) as u256);
        (b, q, (b * 100_000_000) / q)
    }

    #[view]
    public fun get_burned_qiara_rate(): u64 {
        let (_, _, ratio) = get_ratio();
        get_locked_qiara_rate() + ((ratio as u64) / 10)
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
        let delta = timestamp::now_seconds() - borrow_global<Timers>(ADMIN).last_claimed;
        let actual_inflation = (get_inflation() - get_inflation_debt()) / 100_000_000;
        (circulating_supply * (actual_inflation as u128) * (delta as u128)) / 31_536_000
    }

    #[view]
    public fun burn_fee(): u64 acquires Timers {
        get_burn_fee_increase() + get_burn_fee()
    }

    #[view]
    public fun burn_calculation(amount: u64): u64 acquires Timers {
        let min = get_burn_fee_minimal();
        let fee = (amount * burn_fee()) / 100_000_000;
        if (fee == 0) {
            if (min > amount) amount else min
        } else {
            if (fee > min) fee else min
        }
    }

    #[view]
    public fun calculate_emissions(): u64 {
        let cur_supply = option::destroy_with_default(fungible_asset::supply(get_metadata(utf8(b"Qiara"))), 0) / 100_000_000;
        (get_emissions_validators() * (cur_supply as u64)) / 100_000_000
    }

    // === INLINE SLICE & INT UTILS === //

    fun slice(bytes: &vector<u8>, from: u64, to: u64): vector<u8> {
        let out = vector::empty();
        let i = from;
        while (i < to) {
            vector::push_back(&mut out, *vector::borrow(bytes, i));
            i = i + 1;
        };
        out
    }

    fun bcs_to_u32_le(bytes: &vector<u8>): u32 {
        let val = (*vector::borrow(bytes, 0) as u32);
        val = val | ((*vector::borrow(bytes, 1) as u32) << 8);
        val = val | ((*vector::borrow(bytes, 2) as u32) << 16);
        val | ((*vector::borrow(bytes, 3) as u32) << 24)
    }

fun bcs_to_u64_le(bytes: &vector<u8>): u64 {
    let val = (*vector::borrow(bytes, 0) as u64);
    let i = 1;
    while (i < 8) {
        val = val | ((*vector::borrow(bytes, i) as u64) << ((i * 8) as u8));
        i = i + 1;
    };
    val
}
}