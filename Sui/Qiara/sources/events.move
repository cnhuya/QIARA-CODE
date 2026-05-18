module Qiara::QiaraEventsV1 {
    use std::vector;
    use std::string::{Self, String};
    use sui::event;
    use sui::clock::{Self, Clock}; // Added Clock
    use sui::bcs;                  // Added for byte conversion

    // --- Events ---

    public struct Data has copy, drop, store {
        name: String,
        type_name: String,
        value: vector<u8>,
    }

    public struct VaultEvent has copy, drop {
        name: String,
        aux: vector<Data>
    }

    public fun create_data_struct(name: String, type_name: String, value: vector<u8>): Data {
        Data { name, type_name, value }
    }

    /// Internal helper to create the timestamp Data struct
    fun create_timestamp_data(clock: &Clock): Data {
        let ts_ms = clock::timestamp_ms(clock);
        Data {name: string::utf8(b"timestamp"),type_name: string::utf8(b"u64"),value: bcs::to_bytes(&ts_ms)
        }
    }

    public fun emit_event(clock: &Clock, name: String, mut data: vector<Data>) {
        vector::insert(&mut data, create_timestamp_data(clock), 0);
        event::emit(VaultEvent { name, aux: data });
    }


}