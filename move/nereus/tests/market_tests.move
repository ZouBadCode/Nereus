#[test_only]
module nereus::market_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use std::string::{Self};
    
    use nereus::market::{Self, Market, Yes, No};
    use nereus::usdc::{USDC}; 
    use nereus::truth_oracle::{Self, TruthOracleHolder};

    const ADMIN: address = @0xA;
    const ALICE: address = @0xB; 
    const BOB: address = @0xC;   

    // =========================================================================
    // Helper Functions (封裝各階段邏輯)
    // =========================================================================

    /// 階段 1: 系統設置
    /// - 發放 USDC 給 Alice 和 Bob
    /// - 創建 Oracle
    /// - 創建 Market
    fun setup_test_world(scenario: &mut Scenario) {
        // A. 發幣 & 創建 Oracle
        ts::next_tx(scenario, ADMIN);
        {
            let ctx = ts::ctx(scenario);
            let coin_alice = coin::mint_for_testing<USDC>(100_000_000_000, ctx);
            let coin_bob = coin::mint_for_testing<USDC>(100_000_000_000, ctx);
            sui::transfer::public_transfer(coin_alice, ALICE);
            sui::transfer::public_transfer(coin_bob, BOB);
            
            truth_oracle::create_oracle_for_testing(ctx);
        };

        // B. 創建 Market
        ts::next_tx(scenario, ADMIN);
        {
            let holder = ts::take_shared<TruthOracleHolder>(scenario);
            let ctx = ts::ctx(scenario);

            market::create_market(
                &holder,
                string::utf8(b"Will it rain?"),
                string::utf8(b"Simple weather market"),
                0,           
                1000,        
                ctx
            );
            ts::return_shared(holder);
        };
    }

    /// 階段 2/3: 掛單/吃單 (買入 YES)
    fun place_yes_order(
        scenario: &mut Scenario, 
        clock: &Clock, 
        trader: address, 
        price: u64, 
        usdc_amount: u64
    ) {
        ts::next_tx(scenario, trader);
        {
            let mut market = ts::take_shared<Market>(scenario);
            // 1. 先取 Coin
            let mut usdc_coin = ts::take_from_sender<Coin<USDC>>(scenario);
            // 2. 再拿 Context
            let ctx = ts::ctx(scenario);

            let mut yes_pos = market::zero_yes(&mut market, ctx);
            let bet_coin = coin::split(&mut usdc_coin, usdc_amount, ctx); 

            market::bet_yes(
                &mut yes_pos,
                &mut market,
                price,
                bet_coin,
                clock,
                ctx
            );

            ts::return_shared(market);
            sui::transfer::public_transfer(yes_pos, trader);
            ts::return_to_sender(scenario, usdc_coin);
        };
    }

    /// 階段 2/3: 掛單/吃單 (買入 NO)
    fun place_no_order(
        scenario: &mut Scenario, 
        clock: &Clock, 
        trader: address, 
        price: u64, 
        usdc_amount: u64
    ) {
        ts::next_tx(scenario, trader);
        {
            let mut market = ts::take_shared<Market>(scenario);
            
            let mut usdc_coin = ts::take_from_sender<Coin<USDC>>(scenario);
            let ctx = ts::ctx(scenario);

            let mut no_pos = market::zero_no(&mut market, ctx);
            let bet_coin = coin::split(&mut usdc_coin, usdc_amount, ctx); 

            market::bet_no(
                &mut no_pos,
                &mut market,
                price,
                bet_coin,
                clock,
                ctx
            );

            ts::return_shared(market);
            sui::transfer::public_transfer(no_pos, trader);
            ts::return_to_sender(scenario, usdc_coin);
        };
    }

    /// 階段 4: 結算 (Oracle)
    /// - 推進時間
    /// - 設定結果
    fun resolve_market(
        scenario: &mut Scenario, 
        clock: &mut Clock, 
        timestamp_ms: u64, 
        outcome: bool
    ) {
        clock::set_for_testing(clock, timestamp_ms); 

        ts::next_tx(scenario, ADMIN);
        {
            let mut holder = ts::take_shared<TruthOracleHolder>(scenario);
            truth_oracle::set_outcome_for_testing(&mut holder, outcome);
            ts::return_shared(holder);
        };
    }

    /// 階段 5: 兌換 YES (Redeem)
    fun redeem_yes_position(scenario: &mut Scenario, clock: &Clock, trader: address) {
        ts::next_tx(scenario, trader);
        {
            let mut market = ts::take_shared<Market>(scenario);
            let holder = ts::take_shared<TruthOracleHolder>(scenario);
            
            let yes_pos = ts::take_from_sender<Yes>(scenario);
            let ctx = ts::ctx(scenario);
            
            market::redeem_yes(&yes_pos, &mut market, &holder, clock, ctx);

            sui::transfer::public_transfer(yes_pos, trader);
            ts::return_shared(market);
            ts::return_shared(holder);
        };
    }

    /// 輔助驗證餘額是否 >= amount
    fun check_balance(scenario: &mut Scenario, trader: address, min_amount: u64) {
        ts::next_tx(scenario, trader);
        {
            let coin = ts::take_from_sender<Coin<USDC>>(scenario);
            assert!(coin::value(&coin) >= min_amount, 2);
            ts::return_to_sender(scenario, coin);
        };
    }

    // =========================================================================
    // Main Test
    // =========================================================================

    #[test]
    fun test_clob_market_flow() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // 1. 系統設置
        setup_test_world(&mut scenario);

        // 2. Alice 掛單買 YES (Price 0.60, Amount 60 USDC)
        place_yes_order(
            &mut scenario, 
            &clock, 
            ALICE, 
            600_000_000, 
            60_000_000_000
        );

        // 驗證訂單簿有單
        ts::next_tx(&mut scenario, ALICE);
        {
            let market = ts::take_shared<Market>(&scenario);
            assert!(market::get_yes_orders_at_price(&market, 600_000_000).length() == 1, 0);
            ts::return_shared(market);
        };

        // 3. Bob 吃單買 NO (Price 0.40, Amount 40 USDC)
        // 系統會撮合 Bob 的 NO(0.4) 和 Alice 的 YES(0.6)
        place_no_order(
            &mut scenario, 
            &clock, 
            BOB, 
            400_000_000, 
            40_000_000_000
        );

        // 驗證訂單簿被吃光
        ts::next_tx(&mut scenario, BOB);
        {
            let market = ts::take_shared<Market>(&scenario);
            assert!(market::get_yes_orders_at_price(&market, 600_000_000).length() == 0, 1);
            ts::return_shared(market);
        };

        // 4. 結算 (Oracle = TRUE)
        resolve_market(&mut scenario, &mut clock, 2000, true);

        // 5. Alice 兌換獲利
        redeem_yes_position(&mut scenario, &clock, ALICE);

        // 驗證餘額 (Alice 贏回 100 USDC)
        check_balance(&mut scenario, ALICE, 100_000_000_000);

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }

    #[test, expected_failure]
    fun test_clob_market_flow_when_over_price_limit() {
        let mut scenario = ts::begin(ADMIN);
        let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // 1. 系統設置
        setup_test_world(&mut scenario);

        // 2. Alice 掛單買 YES (Price 0.60, Amount 60 USDC)
        place_yes_order(
            &mut scenario, 
            &clock, 
            ALICE, 
            1600_000_000, 
            160_000_000_000
        );

        // 驗證訂單簿有單
        ts::next_tx(&mut scenario, ALICE);
        {
            let market = ts::take_shared<Market>(&scenario);
            assert!(market::get_yes_orders_at_price(&market, 600_000_000).length() == 1, 0);
            ts::return_shared(market);
        };

        // 3. Bob 吃單買 NO (Price 0.40, Amount 40 USDC)
        // 系統會撮合 Bob 的 NO(0.4) 和 Alice 的 YES(0.6)
        place_no_order(
            &mut scenario, 
            &clock, 
            BOB, 
            400_000_000, 
            40_000_000_000
        );

        // 驗證訂單簿被吃光
        ts::next_tx(&mut scenario, BOB);
        {
            let market = ts::take_shared<Market>(&scenario);
            assert!(market::get_yes_orders_at_price(&market, 600_000_000).length() == 0, 1);
            ts::return_shared(market);
        };

        // 4. 結算 (Oracle = TRUE)
        resolve_market(&mut scenario, &mut clock, 2000, true);

        // 5. Alice 兌換獲利
        redeem_yes_position(&mut scenario, &clock, ALICE);

        // 驗證餘額 (Alice 贏回 100 USDC)
        check_balance(&mut scenario, ALICE, 100_000_000_000);

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }
}