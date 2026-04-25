module Qiara::QiaraEpochManagerV1 {
    use sui::clock::{Self, Clock};
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;

    /// Error codes
    const EGenesisInFuture: u64 = 0;
    const EDurationIsZero: u64 = 1;

    /// The configuration object (equivalent to Solidity state variables)
    /// This is created once during deployment.
    public struct Config has key {
        id: UID,
        genesis_timestamp_ms: u64,
        epoch_duration_ms: u64,
    }

    /// On Sui, we typically initialize state in an 'init' or a setup function.
    /// Note: Solidity timestamps are in seconds, Sui Clock is in milliseconds.
    public entry fun initialize(genesis_timestamp_sec: u64, epoch_duration_sec: u64, clock: &Clock,ctx: &mut TxContext) {
        let now_ms = clock::timestamp_ms(clock);
        let genesis_ms = genesis_timestamp_sec * 1000;
        
        assert!(genesis_ms <= now_ms, EGenesisInFuture);
        assert!(epoch_duration_sec > 0, EDurationIsZero);

        let config = Config {
            id: object::new(ctx),
            genesis_timestamp_ms: genesis_ms,
            epoch_duration_ms: epoch_duration_sec * 1000,
        };

        // Make the config globally readable but immutable (like 'immutable' in Solidity)
        transfer::freeze_object(config);
    }

    /// Calculates the current epoch
    public fun get_current_epoch(config: &Config, clock: &Clock): u64 {
        let now_ms = clock::timestamp_ms(clock);
        
        if (now_ms < config.genesis_timestamp_ms) {
            return 0
        };
        
        (now_ms - config.genesis_timestamp_ms) / config.epoch_duration_ms
    }

    /// Returns the exact second (converted from ms) an epoch ends
    public fun get_epoch_end_time(config: &Config, epoch: u64): u64 {
        let end_ms = config.genesis_timestamp_ms + ((epoch + 1) * config.epoch_duration_ms);
        end_ms / 1000
    }

    /// Checks if a specific epoch has finished
    public fun is_epoch_over(config: &Config, epoch: u64, clock: &Clock): bool {
        let now_ms = clock::timestamp_ms(clock);
        let end_ms = config.genesis_timestamp_ms + ((epoch + 1) * config.epoch_duration_ms);
        now_ms >= end_ms
    }
}
