module nereus::truth_oracle;

use std::string::{Self, String};
use enclave::enclave::{Self, Enclave, EnclaveConfig, Cap};
use walrus::blob::Blob;
use sui::hash::blake2b256;

const TRUTH_INTENT: u8 = 0;
const EInvalidSignature: u64 = 1;
const ENoAccess: u64 = 2;
public struct OracleConfig has key, store {
    id: UID,
    blob_id: String,
    code_hash: String
}

public struct WBlob has key {
    id: UID,
    blob: Blob
}

public struct TruthOracleHolder has key, store {
    id: UID,
    result: bool,
    config_id: ID,
}

public struct Truth has copy, drop {
    result: bool,
}

public struct TRUTH_ORACLE has drop {}

fun init(otw: TRUTH_ORACLE, ctx: &mut TxContext) {
    let cap = enclave::new_cap(otw, ctx);
    cap.create_enclave_config(
        b"truth_oracle".to_string(),
        x"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000", // pcr0
        x"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000", // pcr1
        x"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000", // pcr2
        ctx,
    );
    transfer::public_transfer(cap, ctx.sender());
}

public fun update_enclave_setting<TRUTH_ORACLE: drop>(
    enclave: &mut EnclaveConfig<TRUTH_ORACLE>,
    cap: &Cap<TRUTH_ORACLE>,
    pcr0: vector<u8>,
    pcr1: vector<u8>,
    pcr2: vector<u8>,
){
    enclave::update_pcrs(enclave, cap, pcr0, pcr1, pcr2);
}

public fun create_config(
    code_hash: String,
    blob_id: String,
    ctx: &mut TxContext,
): OracleConfig {
    let config = OracleConfig {
        id: object::new(ctx),
        blob_id,
        code_hash,
    };
    config
}

public fun create_truth_oracle_holder(
    config: &OracleConfig,
    ctx: &mut TxContext
): TruthOracleHolder {
    let holder = TruthOracleHolder {
        id: object::new(ctx),
        result: false,
        config_id: object::id(config),
    };
    holder    
}

public fun resolve_oracke<TRUTH_ORACLE: drop>(
    holder: &mut TruthOracleHolder,
    result: bool,
    timestamp_ms: u64,
    signature: &vector<u8>,
    enclave: &Enclave<TRUTH_ORACLE>,
    ctx: &mut TxContext,
) {
    let res = enclave.verify_signature(
        TRUTH_INTENT,
        timestamp_ms,
        Truth { result },
        signature,
    );
    assert!(res, EInvalidSignature);
    holder.result = result;
}

public fun get_outcome(holder: &TruthOracleHolder): bool {
    holder.result
}

// TBD
public fun create_wblob(
    blob: Blob,
    ctx: &mut TxContext,
): WBlob {
    let wblob = WBlob {
        id: object::new(ctx),
        blob,
    };
    wblob
}

entry fun seal_approve(_id: vector<u8>, enclave: &Enclave<TRUTH_ORACLE>, ctx: &TxContext) {
    // In this example whether the enclave is the latest version is not checked. One
    // can pass EnclaveConfig as an argument and check config_version if needed.
    assert!(ctx.sender().to_bytes() == pk_to_address(enclave.pk()), ENoAccess);
}

fun pk_to_address(pk: &vector<u8>): vector<u8> {
        // Assume ed25519 flag for enclave's ephemeral key. Derive address as blake2b_hash(flag || pk).
    let mut arr = vector[0u8];
    arr.append(*pk);
    let hash = blake2b256(&arr);
    hash
}