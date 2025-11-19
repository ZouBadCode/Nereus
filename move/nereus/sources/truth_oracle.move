module nereus::truth_oracle {
    use std::string::{Self, String};
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    
    // 注意：這兩個模組必須在你的 Move.toml 依賴中有定義才能編譯
    use enclave::enclave::{Self, Enclave, EnclaveConfig, Cap};
    use walrus::blob::Blob;

    const TRUTH_INTENT: u8 = 0;
    const EInvalidSignature: u64 = 1;

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
            result: false, // 預設結果
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
        _ctx: &mut TxContext, // 這裡原本沒用到 ctx，加底線避免警告
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

    // ==================================================================
    //                            TEST ONLY FUNCTIONS
    // ==================================================================

    #[test_only]
    /// 測試專用：快速創建一個 Oracle Config 與 Holder 並 Share 出去
    /// 這樣 market_tests 就不需要處理 Enclave 的複雜設定
    public fun create_oracle_for_testing(ctx: &mut TxContext) {
        let config = OracleConfig {
            id: object::new(ctx),
            blob_id: string::utf8(b"TEST_BLOB_ID"),
            code_hash: string::utf8(b"TEST_CODE_HASH"),
        };

        let holder = TruthOracleHolder {
            id: object::new(ctx),
            result: false,
            config_id: object::id(&config),
        };

        // 將 Config 與 Holder 分享出去，讓測試流程可以透過 take_shared 取得
        transfer::public_share_object(config);
        transfer::share_object(holder);
    }

    #[test_only]
    /// 測試專用：繞過 Enclave 驗證，直接設定結果
    /// 這是為了讓 market_tests 可以測試「當結果為真時，市場是否正確派彩」
    public fun set_outcome_for_testing(holder: &mut TruthOracleHolder, result: bool) {
        holder.result = result;
    }
}