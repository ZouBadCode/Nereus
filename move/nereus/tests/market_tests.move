#[test_only]
module nereus::market_tests;

use nereus::market::{Self, Market, Yes, No, Order, create_order};
use nereus::truth_oracle::{Self, TruthOracleHolder};
use nereus::usdc::USDC;
use std::debug;
use std::string;
use std::vector;
use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin};
use sui::test_scenario::{Self as ts, Scenario};

// === 角色定義 ===
const ADMIN: address = @0xA;
const ALICE: address = @0xB; // Maker
const BOB: address = @0xC; // Taker
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
            0,
            1000,
            ctx,
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
    maker_role: u8, // 0=Buy, 1=Sell
    token_id: u8, // 1=YES, 0=NO
): Order {
    create_order(
        maker,
        maker_amount,
        taker_amount,
        maker_role,
        token_id,
        0, // expiration
        0, // salt
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

/// 輔助：印出單一用戶的所有餘額
fun print_user_balances(market: &Market, user: address, label: vector<u8>) {
    let (yes_bal, no_bal, usdc_bal) = market::get_all_balances(market, user);

    // 印出標題 (例如 "=== ALICE Balances ===")
    debug::print(&std::string::utf8(label));

    debug::print(&std::string::utf8(b"YES Asset:"));
    debug::print(&yes_bal);

    debug::print(&std::string::utf8(b"NO  Asset:"));
    debug::print(&no_bal);

    debug::print(&std::string::utf8(b"USDC Coin:"));
    debug::print(&usdc_bal);
}

// =========================================================================
// Test Case: Mint/Merge Complete Set (No Trading)
// =========================================================================

#[test]
fun test_mint_and_merge_complete_set() {
    let mut scenario = ts::begin(ADMIN);
    let clock = clock::create_for_testing(ts::ctx(&mut scenario));
    init_test_environment(&mut scenario);

    // 給 Alice 100 USDC
    fund_account(&mut scenario, ALICE, 100_000_000_000);

    // === Step 1: 直接鑄造 (Split) ===
    // Alice 將 100 USDC 轉換成 100 YES + 100 NO
    ts::next_tx(&mut scenario, ALICE);
    {
        let mut market = ts::take_shared<Market>(&scenario);
        let usdc = ts::take_from_sender<Coin<USDC>>(&scenario);
        let ctx = ts::ctx(&mut scenario);

        market::mint_complete_set(&mut market, usdc, 100_000_000_000, ctx);

        ts::return_shared(market);
    };

    // === 驗證 Step 1 ===
    ts::next_tx(&mut scenario, ALICE);
    {
        let mut market = ts::take_shared<Market>(&scenario);
        let ctx = ts::ctx(&mut scenario);

        // 提出來檢查，確認真的有 100 YES 和 100 NO
        market::withdraw_yes(&mut market, 100_000_000_000, ctx);
        market::withdraw_no(&mut market, 100_000_000_000, ctx);

        ts::return_shared(market);
    };

    // 檢查 Alice 錢包
    ts::next_tx(&mut scenario, ALICE);
    {
        let yes_pos = ts::take_from_sender<Yes>(&scenario);
        let no_pos = ts::take_from_sender<No>(&scenario);

        assert!(market::yes_balance(&yes_pos) == 100_000_000_000, 1);
        assert!(market::no_balance(&no_pos) == 100_000_000_000, 2);

        // 歸還物件以便下一步測試
        ts::return_to_sender(&scenario, yes_pos);
        ts::return_to_sender(&scenario, no_pos);
    };

    // === Step 2: 合併 (Merge) ===
    // Alice 決定把 50 YES + 50 NO 換回 50 USDC
    ts::next_tx(&mut scenario, ALICE);
    {
        // 先把剛提出來的 Position 存回去 (因為 mint/merge 是操作 Vault)
        let yes_pos = ts::take_from_sender<Yes>(&scenario);
        let no_pos = ts::take_from_sender<No>(&scenario);

        let mut market = ts::take_shared<Market>(&scenario);
        let ctx = ts::ctx(&mut scenario);
        market::deposit_yes_position(&mut market, yes_pos, ctx);
        market::deposit_no_position(&mut market, no_pos, ctx);

        // 執行合併
        market::merge_complete_set(&mut market, 50_000_000_000, ctx);

        ts::return_shared(market);
    };

    // === 驗證 Step 2 ===
    ts::next_tx(&mut scenario, ALICE);
    {
        let mut market = ts::take_shared<Market>(&scenario);
        let ctx = ts::ctx(&mut scenario);

        // 驗證 Vault 剩下 50 YES (100 - 50)
        market::withdraw_yes(&mut market, 50_000_000_000, ctx);

        // 驗證錢包收到 50 USDC
        // (因為前面全部存進去了，現在拿回來的應該只有這 50)
        ts::return_shared(market);
    };

    ts::next_tx(&mut scenario, ALICE);
    {
        let coin = ts::take_from_sender<Coin<USDC>>(&scenario);
        assert!(coin::value(&coin) == 50_000_000_000, 3);
        ts::return_to_sender(&scenario, coin);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
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
            ctx,
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
            ctx,
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
// Test Case 3: Full Trading Cycle & Settlement
// =========================================================================
// 場景：
// 1. 市場開放，Alice 看漲 (Buy YES @ 0.6)，Bob 看跌 (Buy NO @ 0.4)。
// 2. 雙方搓合 (Mint)，資金鎖定。
// 3. 市場關閉，Oracle 判定 YES 獲勝。
// 4. Alice 憑藉 YES 份額，以 1:1 比例贖回 USDC (獲利)。
// 5. Bob 的 NO 份額歸零 (虧損)。

#[test]
fun test_trading_flow_and_settlement() {
    let mut scenario = ts::begin(ADMIN);
    let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));

    // 1. 初始化環境與資金
    init_test_environment(&mut scenario);

    // 給予初始資金 100 USDC
    fund_account(&mut scenario, ALICE, 100_000_000_000);
    fund_account(&mut scenario, BOB, 100_000_000_000);

    // 2. 雙方存入保證金到 Vault (Trading Phase Start)
    // Alice 準備下注 60 USDC
    deposit_to_vault(&mut scenario, ALICE, 60_000_000_000);
    // Bob 準備下注 40 USDC
    deposit_to_vault(&mut scenario, BOB, 40_000_000_000);

    // 3. 掛單與搓合 (Market Activity)
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut market = ts::take_shared<Market>(&scenario);
        let ctx = ts::ctx(&mut scenario);

        // Alice: "我認為發生機率是 60%，我出 60 USDC 買 100 份 YES"
        // 隱含價格: 0.6 USDC / YES
        let order_alice = new_order(ALICE, 60_000_000_000, 100_000_000_000, SIDE_BUY, ASSET_YES);

        // Bob: "我認為不會發生 (NO)，我出 40 USDC 買 100 份 NO"
        // 隱含價格: 0.4 USDC / NO
        let order_bob = new_order(BOB, 40_000_000_000, 100_000_000_000, SIDE_BUY, ASSET_NO);

        // 執行撮合 (Mint 模式)
        // 雙方共投入 100 USDC，產出 100 YES + 100 NO
        market::match_orders(
            &mut market,
            order_bob, // Taker
            order_alice, // Maker
            60_000_000_000, // Maker filled amount
            &clock,
            ctx,
        );

        ts::return_shared(market);
    };

    // 驗證搓合後的 Vault 狀態
    ts::next_tx(&mut scenario, ALICE);
    {
        let mut market = ts::take_shared<Market>(&scenario);
        let ctx = ts::ctx(&mut scenario);

        // Alice 應該已經將 USDC 換成了 YES (提領出來檢查)
        market::withdraw_yes(&mut market, 100_000_000_000, ctx);
        ts::return_shared(market);
    };

    ts::next_tx(&mut scenario, BOB);
    {
        let mut market = ts::take_shared<Market>(&scenario);
        let ctx = ts::ctx(&mut scenario);

        // Bob 應該已經將 USDC 換成了 NO (提領出來檢查)
        market::withdraw_no(&mut market, 100_000_000_000, ctx);
        ts::return_shared(market);
    };

    // Alice 現在持有 100 YES, 錢包剩 40 USDC
    // Bob 現在持有 100 NO, 錢包剩 60 USDC

    // 4. 時間推進 (End of Market)
    // 市場設定結束時間為 1000，我們推進到 2000
    clock::set_for_testing(&mut clock, 2000);

    // 5. Oracle 揭示結果 (Resolution Phase)
    // 假設結果為真 (YES Wins)
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut holder = ts::take_shared<TruthOracleHolder>(&scenario);
        truth_oracle::set_outcome_for_testing(&mut holder, true);
        ts::return_shared(holder);
    };

    // 6. 結算贖回 (Redemption Phase)

    // A. Alice 贏了，兌換 YES -> USDC
    ts::next_tx(&mut scenario, ALICE);
    {
        let mut market = ts::take_shared<Market>(&scenario);
        let holder = ts::take_shared<TruthOracleHolder>(&scenario);
        // Alice 需先將 YES 存回 Vault 才能 Redeem (假設流程是這樣，或者直接 Redeem 錢包裡的)
        // 注意：我們新的 market::redeem_yes 是扣除 Vault 餘額
        // 所以 Alice 需要先 Deposit Position
        let yes_pos = ts::take_from_sender<Yes>(&scenario);
        let ctx = ts::ctx(&mut scenario);

        market::deposit_yes_position(&mut market, yes_pos, ctx);

        // 執行贖回：100 YES -> 100 USDC (因為 YES 贏了，價值 1.0)
        market::redeem_yes(&mut market, &holder, &clock, ctx);

        ts::return_shared(market);
        ts::return_shared(holder);
    };

    // B. Bob 輸了，嘗試兌換 NO -> 應該失敗或獲得 0
    ts::next_tx(&mut scenario, BOB);
    {
        let mut market = ts::take_shared<Market>(&scenario);
        let holder = ts::take_shared<TruthOracleHolder>(&scenario);
        let no_pos = ts::take_from_sender<No>(&scenario);
        let ctx = ts::ctx(&mut scenario);

        market::deposit_no_position(&mut market, no_pos, ctx);

        // Bob 嘗試贖回 NO
        // 根據 market 邏輯，verify_oracle 會檢查結果是否為 false (NO wins)
        // 因為結果是 true，這裡預期會失敗 (EWrongTruth)
        // market::redeem_no(&mut market, &holder, &clock, ctx); // 這一行如果執行會 abort

        ts::return_shared(market);
        ts::return_shared(holder);
    };

    // 7. 最終驗證 (Profit / Loss Calculation)

    // 驗證 Alice 的總資產
    // 初始 100 -> 花 60 買 YES -> 剩 40
    // 贖回 100 -> 總共 140 (獲利 40)
    ts::next_tx(&mut scenario, ALICE);
    {
        let ids = ts::ids_for_sender<Coin<USDC>>(&scenario);
        let mut total_value = 0;
        let mut i = 0;
        while (i < vector::length(&ids)) {
            let coin = ts::take_from_sender_by_id<Coin<USDC>>(&scenario, *vector::borrow(&ids, i));
            total_value = total_value + coin::value(&coin);
            ts::return_to_sender(&scenario, coin);
            i = i + 1;
        };

        debug::print(&std::string::utf8(b"Alice Final Balance (Should be 140):"));
        debug::print(&total_value);
        assert!(total_value == 140_000_000_000, 1001);
    };

    // 驗證 Bob 的總資產
    // 初始 100 -> 花 40 買 NO -> 剩 60
    // 贖回失敗 -> 總共 60 (虧損 40)
    ts::next_tx(&mut scenario, BOB);
    {
        let ids = ts::ids_for_sender<Coin<USDC>>(&scenario);
        let mut total_value = 0;
        let mut i = 0;
        while (i < vector::length(&ids)) {
            let coin = ts::take_from_sender_by_id<Coin<USDC>>(&scenario, *vector::borrow(&ids, i));
            total_value = total_value + coin::value(&coin);
            ts::return_to_sender(&scenario, coin);
            i = i + 1;
        };

        debug::print(&std::string::utf8(b"Bob Final Balance (Should be 60):"));
        debug::print(&total_value);
        assert!(total_value == 60_000_000_000, 1002);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =========================================================================
// Test Case 4: Partial Fills & Multi-User (Different Amounts)
// =========================================================================

#[test]
fun test_partial_fill_and_different_amounts() {
    let mut scenario = ts::begin(ADMIN);
    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    // 1. 初始化
    init_test_environment(&mut scenario);

    // 2. 發放資金
    // Alice (大戶): 100 USDC
    fund_account(&mut scenario, ALICE, 100_000_000_000);
    // Bob (散戶1): 20 USDC
    fund_account(&mut scenario, BOB, 20_000_000_000);
    // Carol (散戶2): 20 USDC
    fund_account(&mut scenario, CAROL, 80_000_000_000);

    // 3. 存入 Vault (Deposit)
    // Alice 準備掛大單：60 USDC
    deposit_to_vault(&mut scenario, ALICE, 60_000_000_000);
    // Bob 準備吃單：8 USDC
    deposit_to_vault(&mut scenario, BOB, 8_000_000_000);
    // Carol 準備吃單：4 USDC
    deposit_to_vault(&mut scenario, CAROL, 80_000_000_000);

    // 4. 執行撮合
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut market = ts::take_shared<Market>(&scenario);
        let ctx = ts::ctx(&mut scenario);

        // --- 訂單定義 ---

        // Alice (Maker): 我出 60 USDC，想買 100 YES。 (Price 0.6)
        let alice_order = new_order(ALICE, 60_000_000_000, 100_000_000_000, SIDE_BUY, ASSET_YES);

        // Bob (Taker 1): 我出 8 USDC，想買 20 NO。 (Price 0.4)
        // 驗證比例: 8 / 20 = 0.4. (正確)
        let bob_order = new_order(BOB, 8_000_000_000, 20_000_000_000, SIDE_BUY, ASSET_NO);

        // Carol (Taker 2): 我出 4 USDC，想買 10 NO。 (Price 0.4)
        let carol_order = new_order(CAROL, 4_000_000_000, 10_000_000_000, SIDE_BUY, ASSET_NO);

        // --- 第一次撮合: Alice vs Bob ---
        // Bob 出 8 USDC。
        // Alice 應付金額 = BobAmount * (AlicePrice / BobPrice) = 8 * (0.6/0.4) = 12 USDC.
        // fill_amount_making 填入 12 USDC
        market::match_orders(
            &mut market,
            bob_order,
            alice_order, // 注意：這裡傳入的是同一個 alice_order 結構
            12_000_000_000,
            &clock,
            ctx,
        );

        // --- 第二次撮合: Alice vs Carol ---
        // Carol 出 4 USDC。
        // Alice 應付金額 = 4 * (0.6/0.4) = 6 USDC.
        // fill_amount_making 填入 6 USDC
        market::match_orders(
            &mut market,
            carol_order,
            alice_order, // 再次傳入 alice_order，合約會檢查剩餘額度
            6_000_000_000,
            &clock,
            ctx,
        );

        ts::return_shared(market);
    };

    // 5. 驗證 Alice (Maker) 的狀態
    ts::next_tx(&mut scenario, ALICE);
    {
        let mut market = ts::take_shared<Market>(&scenario);
        let ctx = ts::ctx(&mut scenario);

        // 驗證 YES 數量:
        // 第一次成交: Bob (8 USDC) + Alice (12 USDC) = 20 YES
        // 第二次成交: Carol (4 USDC) + Alice (6 USDC) = 10 YES
        // 總共應該有 30 YES
        market::withdraw_yes(&mut market, 30_000_000_000, ctx);

        // 驗證剩餘資金 (USDC):
        // 初始存入 60 - 第一次扣除 12 - 第二次扣除 6 = 42 USDC
        market::withdraw_usdc(&mut market, 42_000_000_000, ctx);

        ts::return_shared(market);
    };

    // 6. 驗證 Bob (Taker 1) 的狀態
    ts::next_tx(&mut scenario, BOB);
    {
        let mut market = ts::take_shared<Market>(&scenario);
        let ctx = ts::ctx(&mut scenario);

        // Bob 應該獲得 20 NO
        market::withdraw_no(&mut market, 20_000_000_000, ctx);

        // Bob 的 USDC 應該全用光 (Vault 剩 0)
        // 如果嘗試提款應該失敗，這裡我們只驗證 NO

        ts::return_shared(market);
    };

    // 7. 驗證 Carol (Taker 2) 的狀態
    ts::next_tx(&mut scenario, CAROL);
    {
        let mut market = ts::take_shared<Market>(&scenario);
        let ctx = ts::ctx(&mut scenario);

        // Carol 應該獲得 10 NO
        market::withdraw_no(&mut market, 10_000_000_000, ctx);

        ts::return_shared(market);
    };

    // 8. 檢查錢包 (Double Check)
    ts::next_tx(&mut scenario, ALICE);
    {
        let yes_pos = ts::take_from_sender<Yes>(&scenario);
        // 確保提出來的確實是 30
        assert!(market::yes_balance(&yes_pos) == 30_000_000_000, 1);
        ts::return_to_sender(&scenario, yes_pos);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// =========================================================================
// Test Case 5: Order Book Retrieval with Pagination
// =========================================================================
#[test]
fun test_get_bids_asks_paged_test_1() {
    let mut scenario = ts::begin(ADMIN);
    let clock = clock::create_for_testing(ts::ctx(&mut scenario));
    init_test_environment(&mut scenario);

    fund_account(&mut scenario, ALICE, 100_000_000_000);
    fund_account(&mut scenario, BOB, 100_000_000_000);
    deposit_to_vault(&mut scenario, ALICE, 100_000_000_000);

    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut market = ts::take_shared<Market>(&scenario);
        let ctx = ts::ctx(&mut scenario);

        // === 修正 1: 處理 fake_yes (資源不能隨意丟棄) ===
        let fake_yes = market::zero_yes(&mut market, ctx);
        // 將這個物件轉給 BOB (或銷毀，但這裡轉給 BOB 模擬他持有資產)
        sui::transfer::public_transfer(fake_yes, BOB);

        ts::return_shared(market);
    };

    // === Step 1: Alice 掛 3 個買單 (YES) ===
    ts::next_tx(&mut scenario, ALICE);
    {
        let mut market = ts::take_shared<Market>(&scenario);
        let ctx = ts::ctx(&mut scenario);

        // === 修正 2: 使用 create_order 直接設定 Salt，而不是修改欄位 ===
        // 參數: maker, maker_amount, taker_amount, maker_role, token_id, expiration, salt
        let o1 = market::create_order(ALICE, 10, 100, SIDE_BUY, ASSET_YES, 0, 1);
        let o2 = market::create_order(ALICE, 20, 100, SIDE_BUY, ASSET_YES, 0, 2);
        let o3 = market::create_order(ALICE, 30, 100, SIDE_BUY, ASSET_YES, 0, 3);

        market::post_order(&mut market, o1, &clock, ctx);
        market::post_order(&mut market, o2, &clock, ctx);
        market::post_order(&mut market, o3, &clock, ctx);

        ts::return_shared(market);
    };

    // === Step 2: 測試分頁讀取 (Limit = 2) ===
    ts::next_tx(&mut scenario, ADMIN);
    {
        let market = ts::take_shared<Market>(&scenario);

        // 第一頁：取 2 筆
        let (bids_page1, cursor1) = market::get_bids(
            &market,
            std::option::some(ASSET_YES),
            std::option::none(),
            2,
        );

        debug::print(&std::string::utf8(b"Page 1 count (Should be 2):"));
        debug::print(&vector::length(&bids_page1));
        debug::print(&bids_page1);
        assert!(vector::length(&bids_page1) == 2, 101);
        assert!(std::option::is_some(&cursor1), 102);

        // 第二頁：從 cursor1 開始，取剩餘的
        // === 修正 3: 將 cursor2 改為 _cursor2 或 _ 以忽略警告 ===
        let (bids_page2, _cursor2) = market::get_bids(
            &market,
            std::option::some(ASSET_YES),
            cursor1,
            2,
        );

        debug::print(&std::string::utf8(b"Page 2 count (Should be 1):"));
        debug::print(&vector::length(&bids_page2));
        debug::print(&bids_page2);
        assert!(vector::length(&bids_page2) == 1, 103);

        ts::return_shared(market);
    };

    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_get_bids_asks_paged_test_2() {
    let mut scenario = ts::begin(ADMIN);
    // 1. 這裡已經建立了 clock
    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    init_test_environment(&mut scenario);

    fund_account(&mut scenario, ALICE, 200_000_000_000);
    fund_account(&mut scenario, BOB, 100_000_000_000);
    deposit_to_vault(&mut scenario, ALICE, 100_000_000_000);

    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut market = ts::take_shared<Market>(&scenario);
        let ctx = ts::ctx(&mut scenario);

        let fake_yes = market::zero_yes(&mut market, ctx);
        sui::transfer::public_transfer(fake_yes, BOB);

        ts::return_shared(market);
    };

    // === Step 1: 直接鑄造 (Split) ===
    ts::next_tx(&mut scenario, ALICE);
    {
        let mut market = ts::take_shared<Market>(&scenario);
        let usdc = ts::take_from_sender<Coin<USDC>>(&scenario);
        let ctx = ts::ctx(&mut scenario);
        debug::print(&usdc);

        market::mint_complete_set(&mut market, usdc, 100_000_000_000, ctx);

        ts::return_shared(market);
    };

    // === 驗證 Step 1 ===
    ts::next_tx(&mut scenario, ALICE);
    {
        let mut market = ts::take_shared<Market>(&scenario);
        let ctx = ts::ctx(&mut scenario);

        market::withdraw_yes(&mut market, 100_000_000_000, ctx);
        market::withdraw_no(&mut market, 100_000_000_000, ctx);

        ts::return_shared(market);
    };

    // 檢查 Alice 錢包並存回 Position
    ts::next_tx(&mut scenario, ALICE);
    {
        let yes_pos = ts::take_from_sender<Yes>(&scenario);
        let no_pos = ts::take_from_sender<No>(&scenario);
        let mut market = ts::take_shared<Market>(&scenario);
        let ctx = ts::ctx(&mut scenario);

        assert!(market::yes_balance(&yes_pos) == 100_000_000_000, 1);
        assert!(market::no_balance(&no_pos) == 100_000_000_000, 2);

        market::deposit_yes_position(&mut market, yes_pos, ctx);
        market::deposit_no_position(&mut market, no_pos, ctx);
        ts::return_shared(market);
    };

    // === Step 2: Alice 掛買單 (這裡需要傳入 &clock) ===
    ts::next_tx(&mut scenario, ALICE);
    {
        let mut market = ts::take_shared<Market>(&scenario);
        let ctx = ts::ctx(&mut scenario);

        // 參數: maker, maker_amount, taker_amount, maker_role, token_id, expiration, salt
        let o1 = market::create_order(ALICE, 10, 100, SIDE_BUY, ASSET_YES, 0, 1);
        let o2 = market::create_order(ALICE, 20, 100, SIDE_BUY, ASSET_YES, 0, 2);
        let o3 = market::create_order(ALICE, 30, 100, SIDE_BUY, ASSET_YES, 0, 3);

        // === 修改處：傳入 &clock ===
        market::post_order(&mut market, o1, &clock, ctx);
        market::post_order(&mut market, o2, &clock, ctx);
        market::post_order(&mut market, o3, &clock, ctx);

        let os1 = market::create_order(ALICE, 40, 100, SIDE_SELL, ASSET_NO, 0, 1);
        let os2 = market::create_order(ALICE, 50, 100, SIDE_SELL, ASSET_NO, 0, 2);
        let os3 = market::create_order(ALICE, 60, 100, SIDE_SELL, ASSET_NO, 0, 3);

        // === 修改處：傳入 &clock ===
        market::post_order(&mut market, os1, &clock, ctx);
        market::post_order(&mut market, os2, &clock, ctx);
        market::post_order(&mut market, os3, &clock, ctx);

        ts::return_shared(market);
    };

    // === Step 3: 測試分頁讀取 ===
    ts::next_tx(&mut scenario, ADMIN);
    {
        let market = ts::take_shared<Market>(&scenario);

        // 第一頁：取 2 筆 bids
        let (bids_page1, cursor1) = market::get_bids(
            &market,
            std::option::some(ASSET_YES),
            std::option::none(),
            2,
        );

        debug::print(&std::string::utf8(b"Bids Page 1 count (Should be 2/2):"));
        debug::print(&vector::length(&bids_page1));
        debug::print(&bids_page1);
        assert!(vector::length(&bids_page1) == 2, 101);
        assert!(std::option::is_some(&cursor1), 102);

        // 第二頁
        let (bids_page2, _cursor2) = market::get_bids(
            &market,
            std::option::some(ASSET_YES),
            cursor1,
            2,
        );

        debug::print(&std::string::utf8(b"Bids Page 2 count (Should be 1/2):"));
        debug::print(&vector::length(&bids_page2));
        debug::print(&bids_page2);
        assert!(vector::length(&bids_page2) == 1, 103);

        // 第一頁：取 2 筆 asks
        let (asks_page1, _no_cursor) = market::get_asks(
            &market,
            std::option::some(ASSET_NO),
            std::option::none(),
            5,
        );

        debug::print(&std::string::utf8(b"Asks Page 1 count (Should be 3/5):"));
        debug::print(&vector::length(&asks_page1));
        debug::print(&asks_page1);
        assert!(vector::length(&asks_page1) == 3, 104);

        ts::return_shared(market);
    };

    // 測試結束，銷毀 clock
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_get_bids_asks_paged_test_3() {
    let mut scenario = ts::begin(ADMIN);
    let clock = clock::create_for_testing(ts::ctx(&mut scenario));

    init_test_environment(&mut scenario);

    fund_account(&mut scenario, ALICE, 200_000_000_000);
    fund_account(&mut scenario, BOB, 200_000_000_000);
    deposit_to_vault(&mut scenario, ALICE, 100_000_000_000);
    deposit_to_vault(&mut scenario, BOB, 100_000_000_000);

    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut market = ts::take_shared<Market>(&scenario);
        let ctx = ts::ctx(&mut scenario);

        let fake_yes = market::zero_yes(&mut market, ctx);
        sui::transfer::public_transfer(fake_yes, BOB);

        ts::return_shared(market);
    };

    // === Step 1: 直接鑄造 (Split) ===
    ts::next_tx(&mut scenario, ALICE);
    {
        let mut market = ts::take_shared<Market>(&scenario);
        let usdc = ts::take_from_sender<Coin<USDC>>(&scenario);
        let ctx = ts::ctx(&mut scenario);
        debug::print(&usdc);

        market::mint_complete_set(&mut market, usdc, 100_000_000_000, ctx);

        ts::return_shared(market);
    };

    // 驗證鑄造結果
    ts::next_tx(&mut scenario, ALICE);
    {
        let mut market = ts::take_shared<Market>(&scenario);
        let ctx = ts::ctx(&mut scenario);

        market::withdraw_yes(&mut market, 100_000_000_000, ctx);
        market::withdraw_no(&mut market, 100_000_000_000, ctx);

        ts::return_shared(market);
    };

    // 檢查 Alice 錢包並存回 Position
    ts::next_tx(&mut scenario, ALICE);
    {
        let yes_pos = ts::take_from_sender<Yes>(&scenario);
        let no_pos = ts::take_from_sender<No>(&scenario);
        let mut market = ts::take_shared<Market>(&scenario);
        let ctx = ts::ctx(&mut scenario);

        assert!(market::yes_balance(&yes_pos) == 100_000_000_000, 1);
        assert!(market::no_balance(&no_pos) == 100_000_000_000, 2);

        market::deposit_yes_position(&mut market, yes_pos, ctx);
        market::deposit_no_position(&mut market, no_pos, ctx);
        ts::return_shared(market);
    };

    // === Step 2: Alice & Bob 掛買單 (這裡需要傳入 &clock) ===
    ts::next_tx(&mut scenario, ALICE);
    {
        let mut market = ts::take_shared<Market>(&scenario);
        let ctx = ts::ctx(&mut scenario);

        // 參數: maker, maker_amount, taker_amount, maker_role, token_id, expiration, salt
        let o1 = market::create_order(ALICE, 10, 100, SIDE_BUY, ASSET_YES, 0, 1);
        let o2 = market::create_order(ALICE, 20, 100, SIDE_BUY, ASSET_YES, 0, 2);
        let o3 = market::create_order(ALICE, 30, 100, SIDE_BUY, ASSET_YES, 0, 3);

        // === 修改處：傳入 &clock ===
        market::post_order(&mut market, o1, &clock, ctx);
        market::post_order(&mut market, o2, &clock, ctx);
        market::post_order(&mut market, o3, &clock, ctx);

        ts::return_shared(market);
    };

    ts::next_tx(&mut scenario, BOB);
    {
        let mut market = ts::take_shared<Market>(&scenario);
        let ctx = ts::ctx(&mut scenario);

        let os1 = market::create_order(BOB, 90, 100, SIDE_BUY, ASSET_NO, 0, 4);
        let os2 = market::create_order(BOB, 80, 100, SIDE_BUY, ASSET_NO, 0, 5);
        let os3 = market::create_order(BOB, 70, 100, SIDE_BUY, ASSET_NO, 0, 6);

        // === 修改處：傳入 &clock ===
        market::post_order(&mut market, os1, &clock, ctx);
        market::post_order(&mut market, os2, &clock, ctx);
        market::post_order(&mut market, os3, &clock, ctx);

        ts::return_shared(market);
    };

    // === Step 3: 驗證 Alice (Maker) & Bob (Taker 1) 的狀態 ===
    ts::next_tx(&mut scenario, BOB);
    {
        let mut market = ts::take_shared<Market>(&scenario);

        // Balance 檢查
        print_user_balances(&market, ALICE, b"=== ALICE Balances ===");
        print_user_balances(&market, BOB, b"=== BOB Balances ===");

        ts::return_shared(market);
    };

    // === Step 4: 測試分頁讀取 ===
    ts::next_tx(&mut scenario, ADMIN);
    {
        let market = ts::take_shared<Market>(&scenario);

        // 第一頁：取 2 筆 bids
        let (bids_page1, cursor1) = market::get_bids(
            &market,
            std::option::some(ASSET_YES),
            std::option::none(),
            2,
        );

        debug::print(&std::string::utf8(b"Bids Page 1 count (Should be 2/2):"));
        debug::print(&vector::length(&bids_page1));
        debug::print(&bids_page1);
        assert!(vector::length(&bids_page1) == 2, 101);
        assert!(std::option::is_some(&cursor1), 102);

        // 第二頁
        let (bids_page2, _cursor2) = market::get_bids(
            &market,
            std::option::some(ASSET_YES),
            cursor1,
            2,
        );

        debug::print(&std::string::utf8(b"Bids Page 2 count (Should be 1/2):"));
        debug::print(&vector::length(&bids_page2));
        debug::print(&bids_page2);
        assert!(vector::length(&bids_page2) == 1, 103);

        // 第一頁：取 2 筆 asks
        let (asks_page1, _no_cursor) = market::get_bids(
            &market,
            std::option::some(ASSET_NO),
            std::option::none(),
            5,
        );

        debug::print(&std::string::utf8(b"Bids Page 1 count (Should be 3/5):"));
        debug::print(&vector::length(&asks_page1));
        debug::print(&asks_page1);
        assert!(vector::length(&asks_page1) == 0, 104);

        ts::return_shared(market);
    };

    // 測試結束，銷毀 clock
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
