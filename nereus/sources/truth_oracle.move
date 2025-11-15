module nereus::truth_oracle;

use std::string::{Self, String};
use enclave::enclave::{Self, Enclave, Cap};

public struct TruthOracleHolder has key {
    id: UID,
    market_id: ID
}

public struct EnclaveCapManager<phantom T> has key {
    id: UID,
    cap: Cap<T>
}

public struct TRUTH_ORACLE has drop {}

fun init(otw: TRUTH_ORACLE, ctx: &mut TxContext) {
    let cap = enclave::new_cap(otw, ctx);
    let manager = EnclaveCapManager<TRUTH_ORACLE> {
        id: object::new(ctx),
        cap,
    };
    transfer::share_object(manager);
}