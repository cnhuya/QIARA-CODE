module Qiara::QiaraEventsV1 {
    use std::vector;
    use sui::address;
    use std::string::{Self, String};
    use sui::event;
// --- Events ---

    public struct Data has copy, drop, store{
        name: String,
        type_name: String,
        value: vector<u8>,
    }

    public struct VaultEvent has copy, drop {
        name: String,
        aux: vector<Data>
    }

    public fun create_data_struct(name: String, type_name: String, value: vector<u8>): Data {
        Data {name: name,type_name: type_name,value: value}
    }

    public fun emit_deposit_event(name: String, data: vector<Data>) {
         event::emit(VaultEvent {name: name,aux: data,});
    }
    public fun emit_withdraw_event(name: String, data: vector<Data>) {
         event::emit(VaultEvent {name: name,aux: data,});
    }
    public fun emit_withdraw_grant_event(name: String, data: vector<Data>) {
         event::emit(VaultEvent {name: name,aux: data,});
    }
}