module dev::QiaraHelperV28 {
    use std::string::{Self, String, utf8, bytes as b};
    use std::vector;

    use dev::QiaraCoinTypesV14::{Self as CoinTypes, SuiBitcoin, SuiEthereum, SuiSui, SuiUSDC, SuiUSDT, BaseEthereum, BaseUSDC};
    use supra_framework::supra_coin::{Self, SupraCoin};

    use dev::QiaraStorageV30::{Self as storage, Access as StorageAccess};
    use dev::QiaraCapabilitiesV30::{Self as capabilities, Access as CapabilitiesAccess};
    use dev::QiaraVaultRatesV14::{Self as VaultRates};
    use dev::QiaraVaultsV39::{Self as Market, Vault};

    use dev::QiaraMathV9::{Self as QiaraMath};

    use dev::QiaraVerifiedTokensV44::{Self as VerifiedTokens, VMetadata, Tier};

    struct Governance has copy, drop{
        minimum_tokens_to_propose: u64,
        proposal_burn_fee: u64,
        quarum_to_pass: u64,
        minimum_votes: u64,
        scale: u64,
    }

    struct Vaults has drop{
        tier: Tier,
        metadata: VMetadata,
        vault: FullVault,
    }

    struct Asset has key,store,drop,copy{
        resource: String,
        price: u256,
        denom: u256,
    }

    struct FullVault has key, store, copy, drop{
        provider: String,
        total_deposited: u256,
        total_borrowed: u256,
        utilization: u256,
        lend_rate: u256,
        borrow_rate: u256,
        locked: u256,
    }


    #[view]
    public fun viewAssets(): vector<Asset>{
        let assets = CoinTypes::return_all_coin_types();
        let len = vector::length(&assets);
        let vect = vector::empty<Asset>();

        let i = 0;
        while (i < len) {
            let asset = vector::borrow(&assets, i);
            let metadata = VerifiedTokens::get_coin_metadata_by_res(*asset);
            let ast = Asset{
                resource: *asset,
                price: VerifiedTokens::get_coin_metadata_price(&metadata),
                denom: VerifiedTokens::get_coin_metadata_denom(&metadata),       
            };
            vector::push_back(&mut vect, ast);
            i = i + 1;
        };
        vect
    }

    #[view]
    public fun viewVaults(): vector<Vaults> {
        let tokens = VerifiedTokens::get_registered_vaults();
        let len = vector::length(&tokens);
        let vect = vector::empty<Vaults>();

        let i = 0;
        while (i < len) {
            let metadata = vector::borrow(&tokens, i);
            let metadata_ = VerifiedTokens::get_coin_metadata_by_metadata(metadata);
            // get vault identifier
            let vault_res = VerifiedTokens::get_coin_metadata_resource(&metadata_);

            // fetch vault totals
                let (provider, deposited, borrowed, locked) = Market::get_vault_raw(vault_res);
                let utilization = Market::get_utilization_ratio(deposited, borrowed);


                let (lend_apy, _, _) = QiaraMath::compute_rate(
                    utilization,
                    (VerifiedTokens::get_coin_metadata_market_rate(&metadata_) as u256),
                    (VerifiedTokens::get_coin_metadata_rate_scale(&metadata_, true) as u256), // pridat check jestli to je borrow nebo lend
                    true,
                    5
                );

                let (borrow_apy, _, _) = QiaraMath::compute_rate(
                    utilization,
                    (VerifiedTokens::get_coin_metadata_market_rate(&metadata_) as u256),
                    (VerifiedTokens::get_coin_metadata_rate_scale(&metadata_, false) as u256), // pridat check jestli to je borrow nebo lend
                    false,
                    5
                );

            // push Vaults entry with all providers for this token
            vector::push_back(
                &mut vect,
                Vaults {
                    tier: VerifiedTokens::get_coin_metadata_full_tier(&metadata_),
                    metadata: metadata_,
                    vault:                     FullVault {
                        provider: provider,
                        total_deposited: deposited,
                        total_borrowed: borrowed,
                        utilization: utilization,
                        lend_rate: lend_apy,
                        borrow_rate: borrow_apy,
                        locked: (locked as u256)
                    }
                }
            );

            i = i + 1;
        };

        vect
    }



    #[view]
    public fun viewGovernance(): Governance {
        Governance {
            minimum_tokens_to_propose: storage::expect_u64(storage::viewConstant(utf8(b"QiaraGovernance"), utf8(b"MINIMUM_TOKENS_TO_PROPOSE"))),
            proposal_burn_fee: storage::expect_u64(storage::viewConstant(utf8(b"QiaraGovernance"), utf8(b"BURN_TAX"))),
            quarum_to_pass: storage::expect_u64(storage::viewConstant(utf8(b"QiaraGovernance"), utf8(b"MINIMUM_TOTAL_VOTES_PERCENTAGE_SUPPLY"))),
            minimum_votes: storage::expect_u64(storage::viewConstant(utf8(b"QiaraGovernance"), utf8(b"MINIMUM_QUARUM_FOR_PROPOSAL_TO_PASS"))),
            scale: 100_000_000,
        }
    }
}
