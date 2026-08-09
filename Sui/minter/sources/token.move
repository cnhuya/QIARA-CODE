// ========================================================
// 1. REUSABLE HELPER MODULE (No Initial Minting)
// ========================================================
module qiara_faucet::coin_helperV2 {
    use sui::coin::{Self};

    /// Generic helper: creates currency, freezes metadata, and transfers TreasuryCap to deployer
    public fun create_token<T: drop>(
        witness: T,
        decimals: u8,
        symbol: vector<u8>,
        name: vector<u8>,
        ctx: &mut TxContext,
    ) {
        let (treasury, metadata) = coin::create_currency(
            witness,
            decimals,
            symbol,
            name,
            b"Qiara Testnet Ecosystem Token",
            option::none(),
            ctx,
        );

        // Freeze metadata so metadata fields cannot be altered
        transfer::public_freeze_object(metadata);

        // Transfer TreasuryCap directly to deployer (0 tokens minted during creation)
        transfer::public_transfer(treasury, ctx.sender());
    }
}

// ========================================================
// 2. TOKEN DEFINITIONS
// ========================================================

/// Qiara Test USDC (6 Decimals)
module qiara_faucet::usdc {
    use qiara_faucet::coin_helperV2;

    public struct USDC has drop {}

    fun init(witness: USDC, ctx: &mut TxContext) {
        coin_helperV2::create_token(
            witness,
            8,                  // Decimals
            b"USDC",           // Symbol
            b"USDC",  // Name
            ctx
        );
    }
}

/// Qiara Test USDT (6 Decimals)
module qiara_faucet::usdt {
    use qiara_faucet::coin_helperV2;

    public struct USDT has drop {}

    fun init(witness: USDT, ctx: &mut TxContext) {
        coin_helperV2::create_token(
            witness,
            8,                  // Decimals
            b"USDT",           // Symbol
            b"USDT",  // Name
            ctx
        );
    }
}

/// Qiara Test Wrapped BTC (8 Decimals)
module qiara_faucet::eth {
    use qiara_faucet::coin_helperV2;

    public struct ETH has drop {}

    fun init(witness: ETH, ctx: &mut TxContext) {
        coin_helperV2::create_token(
            witness,
            8,                  // Decimals
            b"ETH",            // Symbol
            b"Ether",  // Name
            ctx
        );
    }
}

/// Qiara Test Wrapped BTC (8 Decimals)
module qiara_faucet::btc {
    use qiara_faucet::coin_helperV2;

    public struct BTC has drop {}

    fun init(witness: BTC, ctx: &mut TxContext) {
        coin_helperV2::create_token(
            witness,
            8,                  // Decimals
            b"BTC",            // Symbol
            b"Bitcoin",  // Name
            ctx
        );
    }
}

module qiara_faucet::sui {
    use qiara_faucet::coin_helperV2;

    public struct SUI has drop {}

    fun init(witness: SUI, ctx: &mut TxContext) {
        coin_helperV2::create_token(
            witness,
            8,                  // Decimals
            b"SUI",            // Symbol
            b"Sui",  // Name
            ctx
        );
    }
}

module qiara_faucet::DEEP {
    use qiara_faucet::coin_helperV2;

    public struct DEEP has drop {}

    fun init(witness: DEEP, ctx: &mut TxContext) {
        coin_helperV2::create_token(
            witness,
            8,                  // Decimals
            b"DEEP",            // Symbol
            b"deepbook",  // Name
            ctx
        );
    }
}