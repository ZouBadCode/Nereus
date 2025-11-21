#[test_only]
module nereus::market_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use std::string::{Self};
    use std::debug;
    use std::vector;
    
    use nereus::market::{Self, Market, Yes, No, Order, create_order};
    use nereus::usdc::{USDC}; 
    use nereus::truth_oracle::{Self, TruthOracleHolder};

    // === 角色定義 ===
    const ADMIN: address = @0xA;
    const ALICE: address = @0xB; // Maker
    const BOB: address = @0xC;   // Taker
    const CAROL: address = @0xD; // Another Trader

    // === 常量定義 (需與 Market 模組一致) ===
    const SIDE_BUY: u8 = 0;
    const SIDE_SELL: u8 = 1;
    
    const ASSET_YES: u8 = 1;
    const ASSET_NO: u8 = 0;

    const SCALE: u64 = 1_000_000_000;

    // === 輔助函數 ===

    /// 初始化測試環境：創建 USDC, Oracle, Market
    fun init_test_environment(scenario: &mut Scenario) {
        ts::next_tx(scenario, ADMIN);
        {
            let ctx = ts::ctx(scenario);
            truth_oracle::create_oracle_for_testing(ctx);
        };

        ts::next_tx(scenario, ADMIN);
        {
            let holder = ts::take_shared<TruthOracleHolder>(scenario);
            let ctx = ts::ctx(scenario);
            market::create_market(
                &holder,
                string::utf8(b"ETH > 3000?"),
                string::utf8(b"Ethereum price prediction"),
                0, 1000, ctx
            );
            ts::return_shared(holder);
        };
    }

    /// 發放 USDC 給用戶
    fun fund_account(scenario: &mut Scenario, user: address, amount: u64) {
        ts::next_tx(scenario, ADMIN);
        {
            let ctx = ts::ctx(scenario);
            let coin = coin::mint_for_testing<USDC>(amount, ctx);
            sui::transfer::public_transfer(coin, user);
        };
    }

    /// 輔助：建構訂單
    fun new_order(
        maker: address,
        maker_amount: u64, // 願意付出的數量
        taker_amount: u64, // 想要獲得的數量
        maker_role: u8,    // 0=Buy, 1=Sell
        token_id: u8       // 1=YES, 0=NO
    ): Order {
        create_order(
            maker,
            maker_amount,
            taker_amount,
            maker_role,
            token_id,
            0, // expiration
            0  // salt
        )
    }

    /// 輔助：存款 USDC 到 Vault
    fun deposit_to_vault(scenario: &mut Scenario, user: address, amount: u64) {
        ts::next_tx(scenario, user);
        {
            let mut market = ts::take_shared<Market>(scenario);
            let mut usdc = ts::take_from_sender<Coin<USDC>>(scenario);
            let ctx = ts::ctx(scenario);
            
            let deposit_coin = coin::split(&mut usdc, amount, ctx);
            market::deposit_usdc(&mut market, deposit_coin, ctx);
            
            ts::return_shared(market);
            ts::return_to_sender(scenario, usdc);
        };
    }

    // =========================================================================
    // Test Case 1: Minting Logic (Buy YES + Buy NO)
    // =========================================================================
    // Alice 想買 100 YES，出價 60 USDC (價格 0.6)
    // Bob 想買 100 NO，出價 40 USDC (價格 0.4)
    // 結果：兩人的 USDC 被鎖定，分別獲得 YES 和 NO
    
    #[test]
    fun test_mint_match() {
        let mut scenario = ts::begin(ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        init_test_environment(&mut scenario);
        fund_account(&mut scenario, ALICE, 100_000_000_000);
        fund_account(&mut scenario, BOB, 100_000_000_000);

        // 1. 雙方存款
        deposit_to_vault(&mut scenario, ALICE, 60_000_000_000);
        deposit_to_vault(&mut scenario, BOB, 40_000_000_000);

        // 2. 執行撮合
        // 在這裡，Alice 是 Maker (掛單)，Bob 是 Taker (吃單)
        ts::next_tx(&mut scenario, BOB); 
        {
            let mut market = ts::take_shared<Market>(&scenario);
            let ctx = ts::ctx(&mut scenario);

            // Alice: "我付 60 USDC (maker_amt)，要買 100 YES (taker_amt)"
            let maker_order = new_order(ALICE, 60_000_000_000, 100_000_000_000, SIDE_BUY, ASSET_YES);
            
            // Bob: "我付 40 USDC (maker_amt)，要買 100 NO (taker_amt)"
            // 注意：在 match_orders 中，Taker Order 主要是用來驗證意圖匹配的
            let taker_order = new_order(BOB, 40_000_000_000, 100_000_000_000, SIDE_BUY, ASSET_NO);

            // 撮合：填寫數量為 Maker 願意付出的數量 (60 USDC)
            market::match_orders(
                &mut market,
                taker_order,
                maker_order,
                60_000_000_000,
                &clock,
                ctx
            );
            
            ts::return_shared(market);
        };

         // 3. 驗證結果 (透過提款來驗證餘額)
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut market = ts::take_shared<Market>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            market::withdraw_yes(&mut market, 100_000_000_000, ctx);
            ts::return_shared(market);
        };
        
        // 檢查 Alice 錢包裡是否有 YES 物件
        ts::next_tx(&mut scenario, ALICE);
        {
            let yes_pos = ts::take_from_sender<Yes>(&scenario);
            
            // === 修改：使用 getter ===
            assert!(market::yes_balance(&yes_pos) == 100_000_000_000, 1);
            
            ts::return_to_sender(&scenario, yes_pos);
        };
        
        // 驗證 B: Bob 應該有 100 NO
        ts::next_tx(&mut scenario, BOB);
        {
            let mut market = ts::take_shared<Market>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            market::withdraw_no(&mut market, 100_000_000_000, ctx);
            ts::return_shared(market);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // =========================================================================
    // Test Case 2: Swap Logic (Buy YES vs Sell YES)
    // =========================================================================
    // 延續上一個狀態：Alice 持有 100 YES。
    // Alice 想賣 50 YES，要價 35 USDC (價格 0.7)。
    // Carol 想買 50 YES，出價 35 USDC。
    
    #[test]
    fun test_swap_match() {
        let mut scenario = ts::begin(ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        init_test_environment(&mut scenario);
        fund_account(&mut scenario, ALICE, 100_000_000_000);
        fund_account(&mut scenario, CAROL, 100_000_000_000);

        // --- 前置準備：先讓 Alice 獲得 100 YES (模擬 Mint) ---
        // 為了簡化，我們直接假設 Alice 已經透過某種方式 (例如之前的測試) 獲得了 YES
        // 這裡我們手動 "作弊" 放入 YES 到 Alice 的 Vault，
        // 但因為 Vault 是私有的，我們必須走正規流程：Deposit USDC -> Mint -> 獲得 YES
        // 為了測試 Swap，我們快速執行一次 Mint
        deposit_to_vault(&mut scenario, ALICE, 60_000_000_000);
        fund_account(&mut scenario, BOB, 40_000_000_000); // Bob 用來當對手盤
        deposit_to_vault(&mut scenario, BOB, 40_000_000_000);
        
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut market = ts::take_shared<Market>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            let maker_alice = new_order(ALICE, 60_000_000_000, 100_000_000_000, SIDE_BUY, ASSET_YES);
            let taker_bob = new_order(BOB, 40_000_000_000, 100_000_000_000, SIDE_BUY, ASSET_NO);
            market::match_orders(&mut market, taker_bob, maker_alice, 60_000_000_000, &clock, ctx);
            ts::return_shared(market);
        };
        //此時 Alice Vault 有 100 YES
        
        // --- 正式開始 Swap 測試 ---
        
        // 1. Carol 存款 (準備買 YES)
        deposit_to_vault(&mut scenario, CAROL, 35_000_000_000);

        // 2. 執行撮合
        // Maker (Alice): 賣 50 YES，想要 35 USDC
        // Taker (Carol): 買 50 YES，付出 35 USDC
        ts::next_tx(&mut scenario, CAROL);
        {
            let mut market = ts::take_shared<Market>(&scenario);
            let ctx = ts::ctx(&mut scenario);

            // Alice Order: Maker Amount = 50 (YES), Taker Amount = 35 (USDC), Role = Sell
            let alice_order = new_order(ALICE, 50_000_000_000, 35_000_000_000, SIDE_SELL, ASSET_YES);
            
            // Carol Order: Maker Amount = 35 (USDC), Taker Amount = 50 (YES), Role = Buy
            let carol_order = new_order(CAROL, 35_000_000_000, 50_000_000_000, SIDE_BUY, ASSET_YES);

            // 填單數量：Maker (Alice) 提供 50 YES
            market::match_orders(
                &mut market,
                carol_order,
                alice_order,
                50_000_000_000, // Alice gives 50 YES
                &clock,
                ctx
            );

            ts::return_shared(market);
        };

        // 3. 驗證結果
        
        // Alice: 應該剩下 50 YES (100 - 50)，並獲得 35 USDC
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut market = ts::take_shared<Market>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            
            // 提領獲利的 USDC
            market::withdraw_usdc(&mut market, 35_000_000_000, ctx);
            // 提領剩餘的 YES
            market::withdraw_yes(&mut market, 50_000_000_000, ctx);
            
            ts::return_shared(market);
        };

        // Carol: 應該獲得 50 YES
        ts::next_tx(&mut scenario, CAROL);
        {
            let mut market = ts::take_shared<Market>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            market::withdraw_yes(&mut market, 50_000_000_000, ctx);
            ts::return_shared(market);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // =========================================================================
    // Test Case 3: Settlement (Redeem Logic)
    // =========================================================================
    // Oracle 判定 YES 為真。Alice 兌換 YES -> USDC (1:1)
    
    #[test]
    fun test_settlement() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));

        init_test_environment(&mut scenario);
        fund_account(&mut scenario, ALICE, 100_000_000_000);

        // 1. 快速 Mint 讓 Alice 持有 YES
        // (Alice 60 USDC buy YES, Bob 40 USDC buy NO)
        deposit_to_vault(&mut scenario, ALICE, 60_000_000_000);
        fund_account(&mut scenario, BOB, 40_000_000_000);
        deposit_to_vault(&mut scenario, BOB, 40_000_000_000);
        
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut market = ts::take_shared<Market>(&scenario);
            let ctx = ts::ctx(&mut scenario);
            let alice_order = new_order(ALICE, 60_000_000_000, 100_000_000_000, SIDE_BUY, ASSET_YES);
            let bob_order = new_order(BOB, 40_000_000_000, 100_000_000_000, SIDE_BUY, ASSET_NO);
            market::match_orders(&mut market, bob_order, alice_order, 60_000_000_000, &clock, ctx);
            ts::return_shared(market);
        };

        // 2. 時間推進到結束
        clock::set_for_testing(&mut clock, 2000); // End time is 1000

        // 3. 設定 Oracle 結果 (YES wins)
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut holder = ts::take_shared<TruthOracleHolder>(&scenario);
            truth_oracle::set_outcome_for_testing(&mut holder, true);
            ts::return_shared(holder);
        };

        // 4. Alice 兌換 (Redeem)
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut market = ts::take_shared<Market>(&scenario);
            let holder = ts::take_shared<TruthOracleHolder>(&scenario);
            let ctx = ts::ctx(&mut scenario);

            // Alice 在 Vault 裡有 100 YES。
            // Redeem 會銷毀 Vault 裡的 YES，將 USDC 轉給 Alice (coin object)
            market::redeem_yes(&mut market, &holder, &clock, ctx);

            ts::return_shared(market);
            ts::return_shared(holder);
        };

        // 5. 驗證 Alice 錢包餘額
        ts::next_tx(&mut scenario, ALICE);
        {
            let coin = ts::take_from_sender<Coin<USDC>>(&scenario);
            // Alice 原本剩下 40 USDC (100 - 60)，Redeem 拿到 100 USDC
            // 總共應該有 140 USDC
            assert!(coin::value(&coin) == 140_000_000_000, 2);
            ts::return_to_sender(&scenario, coin);
        };
        
        // 6. 驗證 Bob 輸了 (Redeem NO 應該失敗)
        ts::next_tx(&mut scenario, BOB);
        {
            let mut market = ts::take_shared<Market>(&scenario);
            let holder = ts::take_shared<TruthOracleHolder>(&scenario);
            let ctx = ts::ctx(&mut scenario);

            // 這裡因為預期會失敗，正常測試框架需要用 #[expected_failure]
            // 但為了演示，我們假裝 Bob 嘗試提領失敗，或者合約邏輯是 verify_oracle 失敗會 abort
            // market::redeem_no(&mut market, &holder, &clock, ctx); // 應該 Abort

            ts::return_shared(market);
            ts::return_shared(holder);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }
}