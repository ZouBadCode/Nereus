#[test_only]
module nereus::market_tests {
    use sui::test_scenario::{Self as ts};
    use sui::coin::{Self, Coin};
    use sui::clock::{Self};
    use std::string::{Self};
    
    use nereus::market::{Self, Market, Yes, No};
    use nereus::usdc::{USDC}; 
    use nereus::truth_oracle::{Self, TruthOracleHolder};

    const ADMIN: address = @0xA;
    const ALICE: address = @0xB; 
    const BOB: address = @0xC;   

    #[test]
    fun test_clob_market_flow() {
        let mut scenario = ts::begin(ADMIN);
        // 修正點 1: clock 必須是 mut，因為後面會推進時間
        let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));

        // ====================================================
        // 階段 1: 系統設置
        // ====================================================
        ts::next_tx(&mut scenario, ADMIN);
        {
            let ctx = ts::ctx(&mut scenario);
            
            let coin_alice = coin::mint_for_testing<USDC>(100_000_000_000, ctx);
            let coin_bob = coin::mint_for_testing<USDC>(100_000_000_000, ctx);

            sui::transfer::public_transfer(coin_alice, ALICE);
            sui::transfer::public_transfer(coin_bob, BOB);

            truth_oracle::create_oracle_for_testing(ctx);
        };

        // 3. 創建 Market
        ts::next_tx(&mut scenario, ADMIN);
        {
            let holder = ts::take_shared<TruthOracleHolder>(&scenario);
            let ctx = ts::ctx(&mut scenario);

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

        // ====================================================
        // 階段 2: Alice 掛單 (Maker: Buy YES @ 0.60)
        // ====================================================
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut market = ts::take_shared<Market>(&scenario);
            
            // 修正點 2: 先取出 Coin，再取得 ctx
            // 避免 "scenario still mutably borrowed by ctx" 錯誤
            let mut usdc_coin = ts::take_from_sender<Coin<USDC>>(&scenario);
            
            // 現在可以安全取得 ctx
            let ctx = ts::ctx(&mut scenario);

            let mut yes_pos = market::zero_yes(&mut market, ctx);
            let bet_coin = coin::split(&mut usdc_coin, 60_000_000_000, ctx); 

            market::bet_yes(
                &mut yes_pos,
                &mut market,
                600_000_000, // Price: 0.60
                bet_coin,
                &clock,
                ctx
            );

            assert!(market::get_yes_orders_at_price(&market, 600_000_000).length() == 1, 0);

            ts::return_shared(market);
            sui::transfer::public_transfer(yes_pos, ALICE);
            ts::return_to_sender(&scenario, usdc_coin);
        };

        // ====================================================
        // 階段 3: Bob 吃單 (Taker: Buy NO @ 0.40)
        // ====================================================
        ts::next_tx(&mut scenario, BOB);
        {
            let mut market = ts::take_shared<Market>(&scenario);
            
            // 修正點 3: 同樣先取出 Coin，再拿 ctx
            let mut usdc_coin = ts::take_from_sender<Coin<USDC>>(&scenario);
            
            let ctx = ts::ctx(&mut scenario);

            let mut no_pos = market::zero_no(&mut market, ctx);
            let bet_coin = coin::split(&mut usdc_coin, 40_000_000_000, ctx); 

            market::bet_no(
                &mut no_pos,
                &mut market,
                400_000_000, // Price: 0.40
                bet_coin,
                &clock,
                ctx
            );

            assert!(market::get_yes_orders_at_price(&market, 600_000_000).length() == 0, 1);

            ts::return_shared(market);
            sui::transfer::public_transfer(no_pos, BOB);
            ts::return_to_sender(&scenario, usdc_coin);
        };

        // ====================================================
        // 階段 4: 結算 (Oracle)
        // ====================================================
        
        // 修正點 4: clock 是 mut 變數，這裡可以傳入 &mut clock
        clock::set_for_testing(&mut clock, 2000); 

        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut holder = ts::take_shared<TruthOracleHolder>(&scenario);
            
            truth_oracle::set_outcome_for_testing(&mut holder, true);
            
            ts::return_shared(holder);
        };

        // ====================================================
        // 階段 5: 兌換 (Redeem)
        // ====================================================
        
        ts::next_tx(&mut scenario, ALICE);
        {
            let mut market = ts::take_shared<Market>(&scenario);
            let holder = ts::take_shared<TruthOracleHolder>(&scenario);
            
            // 修正點 5: 先取出 Yes Position，再拿 ctx
            let yes_pos = ts::take_from_sender<Yes>(&scenario);
            
            let ctx = ts::ctx(&mut scenario);
            
            market::redeem_yes(&yes_pos, &mut market, &holder, &clock, ctx);

            sui::transfer::public_transfer(yes_pos, ALICE);
            ts::return_shared(market);
            ts::return_shared(holder);
        };

        // 檢查餘額
        ts::next_tx(&mut scenario, ALICE);
        {
            let coin = ts::take_from_sender<Coin<USDC>>(&scenario);
            assert!(coin::value(&coin) >= 100_000_000_000, 2);
            ts::return_to_sender(&scenario, coin);
        };

        clock::destroy_for_testing(clock);
        ts::end(scenario);
    }
}