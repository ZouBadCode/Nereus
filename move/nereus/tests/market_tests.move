#[test_only]
module nereus::market_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use std::string::{Self};
    use std::debug;
    use std::vector;
    
    use nereus::market::{Self, Market, Yes, No};
    use nereus::usdc::{USDC}; 
    use nereus::truth_oracle::{Self, TruthOracleHolder};

    // === 角色定義 ===
    const ADMIN: address = @0xA;
    const MAKER: address = @0xB; // 提供流動性的人 (Alice)
    const TAKER: address = @0xC; // 消耗流動性的人 (Bob)

    // === 訂單方向定義 ===
    const SIDE_BID_YES: bool = true;  
    const SIDE_BID_NO: bool = false; 

    // === 測試錯誤代碼 (Test Error Codes) ===
    /// 訂單簿長度不符合預期
    const EOrderBookLengthMismatch: u64 = 1;
    /// 市場價格不符合預期
    const EPriceMismatch: u64 = 2;
    /// 餘額不符合預期 (USDC)
    const EBalanceMismatch: u64 = 3;
    /// 資產數量不符合預期 (Yes/No 股票)
    const EAssetMismatch: u64 = 4;

    // =========================================================================
    // Helper Functions
    // =========================================================================

    /// 初始化測試環境
    fun init_test_environment(scenario: &mut Scenario) {
        ts::next_tx(scenario, ADMIN);
        {
            let ctx = ts::ctx(scenario);
            let coin_maker = coin::mint_for_testing<USDC>(100_000_000_000, ctx);
            let coin_taker = coin::mint_for_testing<USDC>(100_000_000_000, ctx);
            sui::transfer::public_transfer(coin_maker, MAKER);
            sui::transfer::public_transfer(coin_taker, TAKER);
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

    /// 封裝下單邏輯
    fun place_order(
        scenario: &mut Scenario, 
        clock: &Clock, 
        trader: address, 
        is_bid_yes: bool, 
        price: u64, 
        usdc_amount: u64
    ) {
        ts::next_tx(scenario, trader);
        {
            let mut market = ts::take_shared<Market>(scenario);
            let mut usdc_coin = ts::take_from_sender<Coin<USDC>>(scenario);
            let ctx = ts::ctx(scenario);
            
            let bet_coin = coin::split(&mut usdc_coin, usdc_amount, ctx); 

            let mut yes_pos = market::zero_yes(&mut market, ctx);
            let mut no_pos = market::zero_no(&mut market, ctx);

            market::place_limit_order(
                &mut market,
                &mut yes_pos,
                &mut no_pos,
                is_bid_yes,
                price,
                bet_coin,
                clock,
                ctx
            );

            ts::return_shared(market);
            sui::transfer::public_transfer(yes_pos, trader);
            sui::transfer::public_transfer(no_pos, trader);
            ts::return_to_sender(scenario, usdc_coin);
        };
    }

    /// 印出並回傳所有 USDC 的總餘額
    fun get_and_print_total_balance(scenario: &mut Scenario, owner: address): u64 {
        // 注意：這裡會切換 Transaction
        ts::next_tx(scenario, owner);
        
        let ids = ts::ids_for_sender<Coin<USDC>>(scenario);
        let len = vector::length(&ids);
        
        debug::print(&std::string::utf8(b"=== USDC BALANCES CHECK ==="));
        
        let mut i = 0;
        let mut total_balance: u64 = 0;

        while (i < len) {
            let id = *vector::borrow(&ids, i);
            let coin = ts::take_from_sender_by_id<Coin<USDC>>(scenario, id);
            let val = coin::value(&coin);
            
            debug::print(&std::string::utf8(b"Value:"));
            debug::print(&val);

            total_balance = total_balance + val;
            ts::return_to_sender(scenario, coin);
            i = i + 1;
        };
        debug::print(&std::string::utf8(b"Total:"));
        debug::print(&total_balance);
        
        total_balance 
    }

    /// 根據索引產生測試用地址 (例如: index 1 -> address @0x101)
    fun get_trader_address(index: u64): address {
        sui::address::from_u256((0x100 + index) as u256)
    }

    // =========================================================================
    // Test Case 1: Order Book Flow (CLOB)
    // =========================================================================

    #[test]
    fun test_order_book_flow() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // 1. 初始化
        init_test_environment(&mut scenario);

        // 2. Maker 掛單: 買入 YES @ 0.60
        place_order(
            &mut scenario, 
            &clock, 
            MAKER, 
            SIDE_BID_YES, 
            600_000_000, 
            60_000_000_000
        );

        // 驗證：訂單簿上應該有一筆 YES 訂單
        ts::next_tx(&mut scenario, MAKER);
        {
            let market = ts::take_shared<Market>(&scenario);
            // 檢查點：使用正確的錯誤代碼
            assert!(
                market::get_yes_orders_at_price(&market, 600_000_000).length() == 1, 
                EOrderBookLengthMismatch
            );
            // 價格尚未變動
            assert!(
                market::get_price(&market) == 500_000_000, 
                EPriceMismatch
            ); 
            ts::return_shared(market);
        };

        // 3. Taker 吃單: 買入 NO @ 0.40
        place_order(
            &mut scenario, 
            &clock, 
            TAKER, 
            SIDE_BID_NO, 
            400_000_000, 
            40_000_000_000
        );

        // =========================================================
        // 4. 精確模擬驗證：確認 YES/NO 資產流向
        // =========================================================
        
        // 驗證 A: Taker (Bob) 買了 NO
        ts::next_tx(&mut scenario, TAKER);
        {
            let market = ts::take_shared<Market>(&scenario);
            // 檢查點：訂單應該被吃光
            assert!(
                market::get_yes_orders_at_price(&market, 600_000_000).length() == 0, 
                EOrderBookLengthMismatch
            );
            // 檢查點：成交價更新
            assert!(
                market::get_price(&market) == 600_000_000, 
                EPriceMismatch
            );

            let yes_pos = ts::take_from_sender<Yes>(&scenario);
            let no_pos = ts::take_from_sender<No>(&scenario);

            // Taker 沒買 YES -> 0
            assert!(nereus::market::yes_amount(&yes_pos) == 0, EAssetMismatch);
            // Taker 買了 NO -> 100
            assert!(nereus::market::no_amount(&no_pos) == 100_000_000_000, EAssetMismatch);

            ts::return_shared(market);
            ts::return_to_sender(&scenario, yes_pos);
            ts::return_to_sender(&scenario, no_pos);
        };

        // 驗證 B: Maker (Alice) 應該收到 YES (合約自動轉帳)
        ts::next_tx(&mut scenario, MAKER);
        {
            // 注意：take_from_sender 會拿最新的物件 (也就是合約剛發給他的那個 YES)
            let yes_pos = ts::take_from_sender<Yes>(&scenario);
            
            // Maker 應該收到 100 股 YES
            assert!(nereus::market::yes_amount(&yes_pos) == 100_000_000_000, EAssetMismatch);
            
            ts::return_to_sender(&scenario, yes_pos);
        };

        // 5. Oracle 結算 (結果: YES 贏)
        clock::set_for_testing(&mut clock, 2000); 
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut holder = ts::take_shared<TruthOracleHolder>(&scenario);
            truth_oracle::set_outcome_for_testing(&mut holder, true);
            ts::return_shared(holder);
        };

        // 6. Maker 兌換獲利 (Redeem YES)
        ts::next_tx(&mut scenario, MAKER);
        {
            let mut market = ts::take_shared<Market>(&scenario);
            let holder = ts::take_shared<TruthOracleHolder>(&scenario);
            let yes_pos = ts::take_from_sender<Yes>(&scenario);
            let ctx = scenario.ctx();

            market::redeem_yes(&yes_pos, &mut market, &holder, &clock, ctx);
            sui::transfer::public_transfer(yes_pos, MAKER);

            ts::return_shared(market);
            ts::return_shared(holder);
        };

        // 7. 驗證 Maker 餘額
        ts::next_tx(&mut scenario, MAKER);
        {
            let coin = ts::take_from_sender<Coin<USDC>>(&scenario);
            assert!(coin::value(&coin) >= 100_000_000_000, EBalanceMismatch);
            ts::return_to_sender(&scenario, coin);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    // =========================================================================
    // Test Case 2: Manual Split & Merge
    // =========================================================================

    #[test]
    fun test_manual_split_merge() {
        let mut scenario = ts::begin(ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        init_test_environment(&mut scenario);

        // 1. Maker 手動 Split
        ts::next_tx(&mut scenario, MAKER);
        {
            let mut market = ts::take_shared<Market>(&scenario);
            let mut usdc_coin = ts::take_from_sender<Coin<USDC>>(&scenario);
            let ctx = ts::ctx(&mut scenario);

            let mut yes_pos = market::zero_yes(&mut market, ctx);
            let mut no_pos = market::zero_no(&mut market, ctx);
            
            let split_amount = 10_000_000_000;
            let split_coin = coin::split(&mut usdc_coin, split_amount, ctx);

            market::split_usdc(&mut market, &mut yes_pos, &mut no_pos, split_coin, ctx);

            ts::return_shared(market);
            sui::transfer::public_transfer(yes_pos, MAKER);
            sui::transfer::public_transfer(no_pos, MAKER);
            ts::return_to_sender(&scenario, usdc_coin);
        };

        // 2. Maker 手動 Merge
        ts::next_tx(&mut scenario, MAKER);
        {
            let mut market = ts::take_shared<Market>(&scenario);
            let mut yes_pos = ts::take_from_sender<Yes>(&scenario);
            let mut no_pos = ts::take_from_sender<No>(&scenario);
            let ctx = ts::ctx(&mut scenario);

            market::merge_shares(
                &mut market, 
                &mut yes_pos, 
                &mut no_pos, 
                10_000_000_000, 
                ctx
            );

            ts::return_shared(market);
            sui::transfer::public_transfer(yes_pos, MAKER);
            sui::transfer::public_transfer(no_pos, MAKER);
        };

        // 3. 驗證 Maker 的錢回來了
        // 這裡不需要 ts::next_tx，因為 helper 函數第一行就會切換
        let total = get_and_print_total_balance(&mut scenario, MAKER);

        assert!(total == 100_000_000_000, EBalanceMismatch);

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }


    // =========================================================================
    // Test Case 3: Simulation 500 Transactions (Optimized)
    // =========================================================================

    // #[test]
    // fun test_simulation_500_txs() {
    //     let mut scenario = ts::begin(ADMIN);
    //     let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    //     // 1. 初始化環境
    //     init_test_environment(&mut scenario);

    //     // 2. [增發資金] 給 Maker 和 Taker 足夠的錢
    //     ts::next_tx(&mut scenario, ADMIN);
    //     {
    //         let ctx = ts::ctx(&mut scenario);
    //         // 給予巨額資金避免餘額不足
    //         let coin_maker = coin::mint_for_testing<USDC>(1_000_000_000_000_000, ctx);
    //         let coin_taker = coin::mint_for_testing<USDC>(1_000_000_000_000_000, ctx);
    //         sui::transfer::public_transfer(coin_maker, MAKER);
    //         sui::transfer::public_transfer(coin_taker, TAKER);
    //     };

    //     // 3. [優化關鍵] 預先為 Maker 和 Taker 創建好 Position 物件
    //     // 這樣就不需要在迴圈中每次都創建新的，節省 1000 個 UID 的記憶體
    //     ts::next_tx(&mut scenario, MAKER);
    //     {
    //         let mut market = ts::take_shared<Market>(&scenario);
    //         let ctx = ts::ctx(&mut scenario);
    //         let yes = market::zero_yes(&mut market, ctx);
    //         let no = market::zero_no(&mut market, ctx);
    //         sui::transfer::public_transfer(yes, MAKER);
    //         sui::transfer::public_transfer(no, MAKER);
    //         ts::return_shared(market);
    //     };

    //     ts::next_tx(&mut scenario, TAKER);
    //     {
    //         let mut market = ts::take_shared<Market>(&scenario);
    //         let ctx = ts::ctx(&mut scenario);
    //         let yes = market::zero_yes(&mut market, ctx);
    //         let no = market::zero_no(&mut market, ctx);
    //         sui::transfer::public_transfer(yes, TAKER);
    //         sui::transfer::public_transfer(no, TAKER);
    //         ts::return_shared(market);
    //     };

    //     // 4. 開始 500 次交易循環
    //     let total_txs = 500;
    //     let mut i = 0;
        
    //     debug::print(&std::string::utf8(b"=== STARTING 500 TX SIMULATION (OPTIMIZED) ==="));

    //     while (i < total_txs) {
    //         if (i % 50 == 0) {
    //             debug::print(&std::string::utf8(b"Processing TX:"));
    //             debug::print(&i);
    //         };

    //         // 決定當前交易者與方向
    //         let (trader, is_bid_yes, price, amount) = if (i % 2 == 0) {
    //             (MAKER, true, 600_000_000, 10_000_000_000)
    //         } else {
    //             (TAKER, false, 400_000_000, 10_000_000_000)
    //         };

    //         ts::next_tx(&mut scenario, trader);
    //         {
    //             let mut market = ts::take_shared<Market>(&scenario);
    //             let mut usdc_coin = ts::take_from_sender<Coin<USDC>>(&scenario);
                
    //             // 取出之前創建好的 Position 物件 (重複使用)
    //             // take_from_sender 會取出該使用者身上最新的該型別物件
    //             let mut yes_pos = ts::take_from_sender<Yes>(&scenario);
    //             let mut no_pos = ts::take_from_sender<No>(&scenario);
                
    //             let ctx = ts::ctx(&mut scenario);
                
    //             let bet_coin = coin::split(&mut usdc_coin, amount, ctx); 

    //             market::place_limit_order(
    //                 &mut market,
    //                 &mut yes_pos,
    //                 &mut no_pos,
    //                 is_bid_yes,
    //                 price,
    //                 bet_coin,
    //                 &clock,
    //                 ctx
    //             );

    //             ts::return_shared(market);
    //             sui::transfer::public_transfer(yes_pos, trader);
    //             sui::transfer::public_transfer(no_pos, trader);
    //             ts::return_to_sender(&scenario, usdc_coin);
    //         };

    //         i = i + 1;
    //     };

    //     debug::print(&std::string::utf8(b"=== SIMULATION COMPLETED ==="));

    //     // 5. 驗證最終狀態
    //     ts::next_tx(&mut scenario, ADMIN);
    //     {
    //         let market = ts::take_shared<Market>(&scenario);
            
    //         // 驗證訂單簿清空 (全部成交)
    //         assert!(
    //             market::get_yes_orders_at_price(&market, 600_000_000).length() == 0, 
    //             EOrderBookLengthMismatch
    //         );

    //         // 驗證最後成交價
    //         assert!(
    //             market::get_price(&market) == 600_000_000, 
    //             EPriceMismatch
    //         );

    //         ts::return_shared(market);
    //     };

    //     clock::destroy_for_testing(clock);
    //     ts::end(scenario);
    // }


    // =========================================================================
    // Test Case 4: Multi-User Simulation (50 Users, 500 Txs)
    // =========================================================================

    #[test]
    fun test_simulation_multi_user() {
        let mut scenario = ts::begin(ADMIN);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // 1. 初始化市場
        init_test_environment(&mut scenario);

        // 設定參數
        let total_txs = 4;      // 總交易次數
        let user_pool_size = 30;  // 用戶池大小 (幾十個地址)
        let amount_per_tx = 10_000_000_000; // 每次下注 10 USDC
        // 每個用戶需要的總資金預估 (稍微多給一點)
        let funding_per_user = amount_per_tx * (total_txs / user_pool_size + 5); 

        debug::print(&std::string::utf8(b"=== INITIALIZING 50 TRADERS ==="));

        // 2. [預先初始化] 為這 50 個用戶準備資金與倉位物件
        let mut i = 0;
        while (i < user_pool_size) {
            let trader = get_trader_address(i);
            
            // A. 發錢
            ts::next_tx(&mut scenario, ADMIN);
            {
                let ctx = ts::ctx(&mut scenario);
                let coin = coin::mint_for_testing<USDC>(funding_per_user, ctx);
                sui::transfer::public_transfer(coin, trader);
            };

            // B. 創建空的 Yes/No 物件 (避免在交易迴圈中不斷 new object)
            ts::next_tx(&mut scenario, trader);
            {
                let mut market = ts::take_shared<Market>(&scenario);
                let ctx = ts::ctx(&mut scenario);
                
                let yes = market::zero_yes(&mut market, ctx);
                let no = market::zero_no(&mut market, ctx);
                
                sui::transfer::public_transfer(yes, trader);
                sui::transfer::public_transfer(no, trader);
                
                ts::return_shared(market);
            };
            
            i = i + 1;
        };

        // 3. 開始 500 次隨機交易模擬
        // 邏輯：偶數次買 YES，奇數次買 NO (確保成交)
        let mut tx_idx = 0;
        debug::print(&std::string::utf8(b"=== STARTING TRADING LOOP ==="));

        while (tx_idx < total_txs) {
            // 從池子中選出一位交易者 (Round Robin)
            let trader_idx = tx_idx % user_pool_size;
            let trader = get_trader_address(trader_idx);

            // 決定方向與價格
            let (is_bid_yes, price) = if (tx_idx % 2 == 0) {
                (SIDE_BID_YES, 600_000_000) // 買 YES @ 0.6
            } else {
                (SIDE_BID_NO, 400_000_000)  // 買 NO @ 0.4
            };

            // 執行交易
            ts::next_tx(&mut scenario, trader);
            {
                let mut market = ts::take_shared<Market>(&scenario);
                let mut usdc_coin = ts::take_from_sender<Coin<USDC>>(&scenario);
                let mut yes_pos = ts::take_from_sender<Yes>(&scenario);
                let mut no_pos = ts::take_from_sender<No>(&scenario);
                let ctx = ts::ctx(&mut scenario);

                // 切分出本次交易的資金
                let bet_coin = coin::split(&mut usdc_coin, amount_per_tx, ctx);

                market::place_limit_order(
                    &mut market,
                    &mut yes_pos,
                    &mut no_pos,
                    is_bid_yes,
                    price,
                    bet_coin,
                    &clock,
                    ctx
                );

                // 歸還物件 (重複使用)
                ts::return_shared(market);
                sui::transfer::public_transfer(yes_pos, trader);
                sui::transfer::public_transfer(no_pos, trader);
                ts::return_to_sender(&scenario, usdc_coin);
            };

            // 每 50 筆印一次進度
            if (tx_idx % 50 == 0) {
                debug::print(&std::string::utf8(b"Tx Processed:"));
                debug::print(&tx_idx);
            };

            tx_idx = tx_idx + 1;
        };

        debug::print(&std::string::utf8(b"=== SIMULATION DONE ==="));

        // 4. 驗證最終狀態 (訂單應該全部成交)
        ts::next_tx(&mut scenario, ADMIN);
        {
            let market = ts::take_shared<Market>(&scenario);
            
            // 驗證訂單簿清空
            assert!(
                market::get_yes_orders_at_price(&market, 600_000_000).length() == 0, 
                EOrderBookLengthMismatch
            );

            // 驗證最後成交價
            assert!(
                market::get_price(&market) == 600_000_000, 
                EPriceMismatch
            );

            ts::return_shared(market);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }
}