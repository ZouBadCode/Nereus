module nereus::market {
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use std::string::String;
    use sui::clock::{Self, Clock};
    use sui::table::{Self, Table};
    use sui::event;
    use sui::hash::blake2b256;
    use sui::bcs;

    use nereus::usdc::{USDC};
    use nereus::truth_oracle::{Self, TruthOracleHolder};

    /// === Error codes ===
    const EWrongMarket: u64 = 1;
    const EWrongTime: u64 = 2;
    const EOrderExpired: u64 = 3;
    const EInsufficientBalance: u64 = 4;
    const EOrderFilledOrCancelled: u64 = 5;
    const EWrongTruth: u64 = 6;
    const ENotCrossing: u64 = 7;
    const EMismatchedTokenIds: u64 = 8;

    /// === Constants ===
    const PRICE_SCALE: u64 = 1_000_000_000; 

    // Side definition
    const SIDE_BUY: u8 = 0;
    const SIDE_SELL: u8 = 1;

    // Asset IDs for CTF logic
    const ASSET_YES: u8 = 1;
    const ASSET_NO: u8 = 0;

    // Match Types
    const MATCH_COMPLEMENTARY: u8 = 0; // Buy YES vs Sell YES
    const MATCH_MINT: u8 = 1;          // Buy YES vs Buy NO (Complimentary Outcomes)
    const MATCH_MERGE: u8 = 2;         // Sell YES vs Sell NO

    /// === Structs ===

    /// 鏈下訂單結構 (不會儲存在鏈上，只作為參數傳入)
    public struct Order has copy, drop, store {
        maker: address,
        maker_amount: u64,      // Maker 願意支付的數量
        taker_amount: u64,      // Maker 想要獲得的數量
        maker_role: u8,         // 0 = Buy, 1 = Sell
        token_id: u8,           // 1 = YES, 0 = NO
        expiration: u64,
        salt: u64,              // 防止 hash 碰撞
    }

    /// 訂單狀態 (儲存在鏈上，防止重放)
    public struct OrderStatus has store, drop {
        remaining: u64,
        is_cancelled: bool,
    }

    /// 代表 YES 份額的物件 (可從 Vault 提領出來)
    public struct Yes has key, store {
        id: UID,
        amount: u64,
        market_id: ID
    }

    /// 代表 NO 份額的物件 (可從 Vault 提領出來)
    public struct No has key, store {
        id: UID,
        amount: u64,
        market_id: ID
    }

    public struct Market has key {
        id: UID,
        
        /// 用於存放所有抵押品 (USDC) 的餘額
        /// 這包含兩部分：
        /// 1. 用戶存入 Vault 的閒置資金
        /// 2. 已經鑄造成 YES/NO 但尚未結算的鎖定資金
        balance: Balance<USDC>,
        
        topic: String,
        description: String,
        start_time: u64,
        end_time: u64,
        oracle_config_id: ID,
        
        /// === Vault Logic ===
        /// 用戶在合約內的餘額表。
        /// Maker 必須先 deposit 才能下單。
        vault_usdc: Table<address, u64>, // 用戶 -> USDC 餘額
        vault_yes: Table<address, u64>,  // 用戶 -> YES 餘額
        vault_no: Table<address, u64>,   // 用戶 -> NO 餘額

        /// === Order Logic ===
        /// 記錄訂單哈希的執行狀態
        order_statuses: Table<vector<u8>, OrderStatus>,
    }

    /// === Events ===
    public struct OrderFilled has copy, drop {
        order_hash: vector<u8>,
        maker: address,
        taker: address,
        maker_amount: u64,
        taker_amount: u64,
        match_type: u8
    }

    /// === Initialization ===

    public fun create_market(
        holder: &TruthOracleHolder,
        topic: String,
        description: String,
        start_time: u64,
        end_time: u64,
        ctx: &mut TxContext
    ) {
        let market = Market {
            id: object::new(ctx),
            balance: balance::zero<USDC>(),
            topic,
            description,
            start_time,
            end_time,
            oracle_config_id: object::id(holder),
            vault_usdc: table::new(ctx),
            vault_yes: table::new(ctx),
            vault_no: table::new(ctx),
            order_statuses: table::new(ctx),
        };
        transfer::share_object(market);
    }

    // Helper to mint zero value objects (unchanged)
    public fun zero_yes(market: &mut Market, ctx: &mut TxContext): Yes {
        Yes { id: object::new(ctx), amount: 0, market_id: object::id(market) }
    }
    public fun zero_no(market: &mut Market, ctx: &mut TxContext): No {
        No { id: object::new(ctx), amount: 0, market_id: object::id(market) }
    }

    /// === Vault Management (Deposit / Withdraw) ===

    /// 存入 USDC 到合約 Vault，以便作為 Maker 掛單
    public fun deposit_usdc(
        market: &mut Market,
        coin: Coin<USDC>,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        let amount = coin::value(&coin);
        balance::join(&mut market.balance, coin::into_balance(coin));
        
        let bal = if (table::contains(&market.vault_usdc, sender)) {
            *table::borrow(&market.vault_usdc, sender)
        } else { 0 };
        
        if (table::contains(&market.vault_usdc, sender)) {
            *table::borrow_mut(&mut market.vault_usdc, sender) = bal + amount;
        } else {
            table::add(&mut market.vault_usdc, sender, amount);
        };
    }

    /// 從 Vault 提領 USDC
    public fun withdraw_usdc(
        market: &mut Market,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(table::contains(&market.vault_usdc, sender), EInsufficientBalance);
        
        let bal_ref = table::borrow_mut(&mut market.vault_usdc, sender);
        assert!(*bal_ref >= amount, EInsufficientBalance);
        *bal_ref = *bal_ref - amount;

        let withdraw_coin = coin::take(&mut market.balance, amount, ctx);
        transfer::public_transfer(withdraw_coin, sender);
    }

    /// 存入 Position (YES/NO) 到 Vault 以便賣出
    public fun deposit_position(
        market: &mut Market,
        yes_pos: Yes, // 如果要存 NO，可以另寫一個函數或用泛型封裝，這裡為演示分開寫
        ctx: &mut TxContext
    ) {
        assert!(yes_pos.market_id == object::id(market), EWrongMarket);
        let sender = tx_context::sender(ctx);
        let amount = yes_pos.amount;
        
        // Destroy object, move balance to table
        let Yes { id, amount: _, market_id: _ } = yes_pos;
        object::delete(id);

        let bal = if (table::contains(&market.vault_yes, sender)) {
            *table::borrow(&market.vault_yes, sender)
        } else { 0 };

        if (table::contains(&market.vault_yes, sender)) {
            *table::borrow_mut(&mut market.vault_yes, sender) = bal + amount;
        } else {
            table::add(&mut market.vault_yes, sender, amount);
        };
    }

     public fun deposit_no_position(
        market: &mut Market,
        no_pos: No,
        ctx: &mut TxContext
    ) {
        assert!(no_pos.market_id == object::id(market), EWrongMarket);
        let sender = tx_context::sender(ctx);
        let amount = no_pos.amount;
        
        let No { id, amount: _, market_id: _ } = no_pos;
        object::delete(id);

        let bal = if (table::contains(&market.vault_no, sender)) {
            *table::borrow(&market.vault_no, sender)
        } else { 0 };

        if (table::contains(&market.vault_no, sender)) {
            *table::borrow_mut(&mut market.vault_no, sender) = bal + amount;
        } else {
            table::add(&mut market.vault_no, sender, amount);
        };
    }


    /// 從 Vault 提領 YES Position
    public fun withdraw_yes(market: &mut Market, amount: u64, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        let bal_ref = table::borrow_mut(&mut market.vault_yes, sender);
        assert!(*bal_ref >= amount, EInsufficientBalance);
        *bal_ref = *bal_ref - amount;

        let yes_obj = Yes { id: object::new(ctx), amount, market_id: object::id(market) };
        transfer::public_transfer(yes_obj, sender);
    }

    public fun withdraw_no(market: &mut Market, amount: u64, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        let bal_ref = table::borrow_mut(&mut market.vault_no, sender);
        assert!(*bal_ref >= amount, EInsufficientBalance);
        *bal_ref = *bal_ref - amount;

        let no_obj = No { id: object::new(ctx), amount, market_id: object::id(market) };
        transfer::public_transfer(no_obj, sender);
    }


    /// === CTF Trading Logic (Core) ===

    /// 撮合兩筆訂單 (Maker vs Taker)
    /// 在這個模型中，兩個訂單都是 Order 結構。
    /// 通常 Taker 是主動方，Maker 是被動方（簽名掛單）。
    /// 但為了符合 `match_orders` 的概念，我們將其視為兩個意圖的碰撞。
    public fun match_orders(
        market: &mut Market,
        taker_order: Order,
        maker_order: Order,
        fill_amount_making: u64, // 基於 Maker 的 making amount 填單數量
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // 1. 驗證訂單有效性 (過期時間等)
        // 注意：這裡省略了簽名驗證，實際應用需傳入 maker_signature 並驗證
        verify_order_validity(market, &maker_order, clock);
        verify_order_validity(market, &taker_order, clock); // Taker 其實是用戶當下交易，通常不需要簽名驗證，但檢查參數是好的

        // 2. 更新 Maker 的訂單狀態 (防止超額成交)
        let maker_hash = hash_order(&maker_order);
        update_order_status(market, maker_hash, maker_order.maker_amount, fill_amount_making);

        // Taker 這裡假設是當下執行，不存儲狀態 (或者也可以存，看業務邏輯)

        // 3. 判斷撮合類型
        let match_type = derive_match_type(&taker_order, &maker_order);
        
        // 4. 驗證價格是否匹配 (Is Crossing)
        validate_crossing(&taker_order, &maker_order, match_type);

        // 5. 計算 Taker 需要的數量 (Taking Amount)
        // taking = making * taker_amt / maker_amt
        let fill_amount_taking = (fill_amount_making as u128) * (maker_order.taker_amount as u128) / (maker_order.maker_amount as u128);
        let fill_amount_taking = fill_amount_taking as u64;

        // 6. 執行資金轉移/鑄造/銷毀
        execute_trade(
            market, 
            taker_order.maker, // Taker Address
            maker_order.maker, // Maker Address
            fill_amount_taking, // Taker Gives (Maker Wants)
            fill_amount_making, // Maker Gives (Taker Wants)
            &taker_order,
            &maker_order,
            match_type
        );

        event::emit(OrderFilled {
            order_hash: maker_hash,
            maker: maker_order.maker,
            taker: taker_order.maker,
            maker_amount: fill_amount_making,
            taker_amount: fill_amount_taking,
            match_type
        });
    }

    /// 執行具體的資產變動
    fun execute_trade(
        market: &mut Market,
        taker: address,
        maker: address,
        taker_gives: u64,
        maker_gives: u64,
        taker_order: &Order,
        maker_order: &Order,
        match_type: u8
    ) {
        if (match_type == MATCH_COMPLEMENTARY) {
            // 普通交換 (Swap)
            // Taker 買 YES (付 USDC) vs Maker 賣 YES (付 YES)
            // 或 Taker 賣 YES (付 YES) vs Maker 買 YES (付 USDC)
            
            // 這裡需要根據 Order 內容判斷誰付 USDC 誰付 Position
            // 簡單起見：根據 maker_role 處理
            
            if (maker_order.maker_role == SIDE_BUY) {
                // Maker 買 YES (Maker 付 USDC, Taker 付 YES)
                transfer_internal(market, maker, taker, maker_gives, 2); // 2 represents USDC
                transfer_internal(market, taker, maker, taker_gives, maker_order.token_id); 
            } else {
                // Maker 賣 YES (Maker 付 YES, Taker 付 USDC)
                transfer_internal(market, maker, taker, maker_gives, maker_order.token_id);
                transfer_internal(market, taker, maker, taker_gives, 2); // USDC
            };
        } 
        else if (match_type == MATCH_MINT) {
            // 鑄造 (Buy YES vs Buy NO)
            // Maker 買 YES (付 USDC) + Taker 買 NO (付 USDC)
            // 結果：Maker 獲得 YES, Taker 獲得 NO (兩者的 USDC 都鎖入 Pool)
            
            // 1. 扣除 Maker 的 USDC
            decrease_balance(market, maker, 2, maker_gives);
            // 2. 扣除 Taker 的 USDC
            decrease_balance(market, taker, 2, taker_gives);
            
            // 3. 增加 Maker 的 YES (maker_order.token_id)
            // 注意：如果是 Mint，獲得的份額數量等於投入的 USDC 總和嗎？
            // 不，CTF 邏輯是：1 USDC = 1 YES + 1 NO.
            // Maker 出 0.6 USDC 買 YES, Taker 出 0.4 USDC 買 NO.
            // 總共 1 USDC -> 產生 1 YES 給 Maker, 1 NO 給 Taker.
            // 這裡的數量關係： Shares Amount = maker_gives + taker_gives (如果價格歸一化)
            // 但這裡我們簡化：shares amount = taker_gives (如果 taker_gives 是份額數) -- 這取決於 Order 定義
            // 在 Solidity CTF 中，Maker Amount 和 Taker Amount 通常指代幣數量。
            // 讓我們假設 maker_gives 是 Maker 出的 USDC, taker_gives 是 Taker 出的 USDC
            
            // 修正邏輯：根據 CTF 標準，Order 的 maker_amount 是 output token 還是 input token?
            // 通常 Maker Order: "I want to buy 100 YES for 60 USDC".
            // maker_amount = 60 (USDC), taker_amount = 100 (YES).
            
            // 在 Mint 場景：
            // Maker: Buy 100 YES for 60 USDC.
            // Taker: Buy 100 NO for 40 USDC.
            // 撮合後：Maker 拿到 100 YES, Taker 拿到 100 NO.
            // 消耗：Maker 60 USDC, Taker 40 USDC.
            
            increase_balance(market, maker, maker_order.token_id, maker_order.taker_amount); 
            increase_balance(market, taker, taker_order.token_id, taker_order.taker_amount);
        }
        else if (match_type == MATCH_MERGE) {
            // 合併 (Sell YES vs Sell NO)
            // Maker 賣 YES (給出 YES, 要 USDC) + Taker 賣 NO (給出 NO, 要 USDC)
            // 本質上是銷毀：Market 收回 1 YES + 1 NO，釋放 1 USDC。
            
            // 1. 扣除 Maker 的 YES
            decrease_balance(market, maker, maker_order.token_id, maker_gives);
            // 2. 扣除 Taker 的 NO
            decrease_balance(market, taker, taker_order.token_id, taker_gives);
            
            // 3. 給 Maker USDC (maker wants taker_amount USDC)
            increase_balance(market, maker, 2, maker_order.taker_amount);
            // 4. 給 Taker USDC
            increase_balance(market, taker, 2, taker_order.taker_amount);
        }
    }

    // --- Internal Balance Helpers ---
    // asset_type: 0=NO, 1=YES, 2=USDC
    fun transfer_internal(market: &mut Market, from: address, to: address, amount: u64, asset_type: u8) {
        decrease_balance(market, from, asset_type, amount);
        increase_balance(market, to, asset_type, amount);
    }

    fun decrease_balance(market: &mut Market, user: address, asset_type: u8, amount: u64) {
        let table_ref = if (asset_type == ASSET_YES) { &mut market.vault_yes }
                   else if (asset_type == ASSET_NO) { &mut market.vault_no }
                   else { &mut market.vault_usdc };
        
        assert!(table::contains(table_ref, user), EInsufficientBalance);
        let bal = table::borrow_mut(table_ref, user);
        assert!(*bal >= amount, EInsufficientBalance);
        *bal = *bal - amount;
    }

    fun increase_balance(market: &mut Market, user: address, asset_type: u8, amount: u64) {
        let table_ref = if (asset_type == ASSET_YES) { &mut market.vault_yes }
                   else if (asset_type == ASSET_NO) { &mut market.vault_no }
                   else { &mut market.vault_usdc };
        
        if (!table::contains(table_ref, user)) {
            table::add(table_ref, user, 0);
        };
        let bal = table::borrow_mut(table_ref, user);
        *bal = *bal + amount;
    }

    // --- Logic Helpers ---

    fun verify_order_validity(market: &Market, order: &Order, clock: &Clock) {
        let now = clock::timestamp_ms(clock);
        // Check expiration
        if (order.expiration > 0 && order.expiration < now) {
             abort EOrderExpired
        };
        // Check signature here (omitted for brevity)
    }

    fun update_order_status(market: &mut Market, hash: vector<u8>, total_amount: u64, fill_amount: u64) {
        if (!table::contains(&market.order_statuses, hash)) {
            table::add(&mut market.order_statuses, hash, OrderStatus {
                remaining: total_amount,
                is_cancelled: false
            });
        };
        let status = table::borrow_mut(&mut market.order_statuses, hash);
        assert!(!status.is_cancelled, EOrderFilledOrCancelled);
        assert!(status.remaining >= fill_amount, EInsufficientBalance); // Making > Remaining
        
        status.remaining = status.remaining - fill_amount;
        if (status.remaining == 0) {
            status.is_cancelled = true;
        }
    }

    fun derive_match_type(taker: &Order, maker: &Order): u8 {
        // Maker Role: 0=Buy, 1=Sell
        if (taker.maker_role == SIDE_BUY && maker.maker_role == SIDE_BUY) {
            MATCH_MINT // Buy vs Buy
        } else if (taker.maker_role == SIDE_SELL && maker.maker_role == SIDE_SELL) {
            MATCH_MERGE // Sell vs Sell
        } else {
            MATCH_COMPLEMENTARY // Buy vs Sell
        }
    }

    fun validate_crossing(taker: &Order, maker: &Order, match_type: u8) {
        // Price calculation: Price = MakerAmount / TakerAmount (depends on perspective)
        // Simplified: Check if they are compatible
        
        if (match_type == MATCH_COMPLEMENTARY) {
            // Must trade same token (YES vs YES)
            assert!(taker.token_id == maker.token_id, EMismatchedTokenIds);
        } else {
            // Must trade opposite tokens (YES vs NO)
            assert!(taker.token_id != maker.token_id, EMismatchedTokenIds);
        }
        
        // Price crossing check omitted for brevity, but essential in prod
        // e.g. Taker willing to pay >= Maker asking price
    }

    public fun hash_order(order: &Order): vector<u8> {
        let mut data = bcs::to_bytes(order);
        blake2b256(&data)
    }

    /// === Settlement ===

    public fun redeem_yes(
        market: &mut Market,
        truth: &TruthOracleHolder,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        verify_oracle(market, truth, clock, true);
        let sender = tx_context::sender(ctx);
        
        // Burn YES balance from vault
        let amount = *table::borrow(&market.vault_yes, sender);
        decrease_balance(market, sender, ASSET_YES, amount);
        
        // Payout USDC
        let payout = coin::take(&mut market.balance, amount, ctx); // 1 YES = 1 USDC if won
        transfer::public_transfer(payout, sender);
    }

    public fun redeem_no(
        market: &mut Market,
        truth: &TruthOracleHolder,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        verify_oracle(market, truth, clock, false);
        let sender = tx_context::sender(ctx);
        
        let amount = *table::borrow(&market.vault_no, sender);
        decrease_balance(market, sender, ASSET_NO, amount);
        
        let payout = coin::take(&mut market.balance, amount, ctx);
        transfer::public_transfer(payout, sender);
    }

    fun verify_oracle(market: &Market, truth: &TruthOracleHolder, clock: &Clock, expected_outcome: bool) {
        assert!(market.oracle_config_id == object::id(truth), EWrongMarket);
        assert!(clock::timestamp_ms(clock) >= market.end_time, EWrongTime);
        assert!(truth_oracle::get_outcome(truth) == expected_outcome, EWrongTruth);
    }

    // === Helper Functions (解決可見性問題) ===

    /// 公開的構造函數，讓外部可以創建 Order
    public fun create_order(
        maker: address,
        maker_amount: u64,
        taker_amount: u64,
        maker_role: u8,
        token_id: u8,
        expiration: u64,
        salt: u64
    ): Order {
        Order {
            maker,
            maker_amount,
            taker_amount,
            maker_role,
            token_id,
            expiration,
            salt
        }
    }

    /// 讀取 YES 物件的餘額
    public fun yes_balance(yes: &Yes): u64 {
        yes.amount
    }

    /// 讀取 NO 物件的餘額
    public fun no_balance(no: &No): u64 {
        no.amount
    }
}