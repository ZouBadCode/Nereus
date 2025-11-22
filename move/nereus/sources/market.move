module nereus::market;

use nereus::truth_oracle::{Self, TruthOracleHolder};
use nereus::usdc::USDC;
use std::option::{Self, Option};
use std::string::String;
use std::vector;
use sui::balance::{Self, Balance};
use sui::bcs;
use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin};
use sui::event;
use sui::hash::blake2b256;
use sui::linked_table::{Self, LinkedTable};
use sui::object::{Self, UID, ID};
use sui::table::{Self, Table};
use sui::transfer;
use sui::tx_context::{Self, TxContext};

/// === Error codes ===
const EWrongMarket: u64 = 1;
const EWrongTime: u64 = 2;
const EOrderExpired: u64 = 3;
const EInsufficientBalance: u64 = 4;
const EOrderFilledOrCancelled: u64 = 5;
const EWrongTruth: u64 = 6;
const ENotCrossing: u64 = 7;
const EMismatchedTokenIds: u64 = 8;
const EInvalidPrice: u64 = 9;
const ENotOwner: u64 = 10;

/// === Constants ===
const PRICE_SCALE: u64 = 1_000_000_000; // 1.0 = 10^9

/// === 新增：價格限制常數 (1% ~ 99%) ===
const MIN_PRICE: u64 = 10_000_000; // 1% (0.01)
const MAX_PRICE: u64 = 990_000_000; // 99% (0.99)

// Side definition
const SIDE_BUY: u8 = 0;
const SIDE_SELL: u8 = 1;

// Asset IDs for CTF logic
const ASSET_YES: u8 = 1;
const ASSET_NO: u8 = 0;

// Match Types
const MATCH_COMPLEMENTARY: u8 = 0;
const MATCH_MINT: u8 = 1;
const MATCH_MERGE: u8 = 2;

/// === Structs ===

public struct Order has copy, drop, store {
    maker: address,
    maker_amount: u64,
    taker_amount: u64,
    maker_role: u8,
    token_id: u8,
    expiration: u64,
    salt: u64,
}

public struct OrderStatus has drop, store {
    remaining: u64,
    is_cancelled: bool,
}

public struct Yes has key, store {
    id: UID,
    amount: u64,
    market_id: ID,
}

public struct No has key, store {
    id: UID,
    amount: u64,
    market_id: ID,
}

public struct Market has key {
    id: UID,
    balance: Balance<USDC>,
    topic: String,
    description: String,
    start_time: u64,
    end_time: u64,
    oracle_config_id: ID,
    vault_usdc: Table<address, u64>,
    vault_yes: Table<address, u64>,
    vault_no: Table<address, u64>,
    order_statuses: Table<vector<u8>, OrderStatus>,
    active_orders: LinkedTable<vector<u8>, Order>,
    /// 最新成交價格 (YES 的機率)
    /// 範圍限制在 1% ~ 99% (10_000_000 ~ 990_000_000)
    last_yes_price: u64,
}

/// === Events ===
public struct OrderFilled has copy, drop {
    order_hash: vector<u8>,
    maker: address,
    taker: address,
    maker_amount: u64,
    taker_amount: u64,
    match_type: u8,
    price: u64,
}

public struct OrderPosted has copy, drop {
    order_hash: vector<u8>,
    maker: address,
    maker_amount: u64,
    taker_amount: u64,
    token_id: u8,
}

public struct OrderCancelled has copy, drop {
    order_hash: vector<u8>,
    maker: address,
}

public struct SetMinted has copy, drop {
    user: address,
    amount: u64,
}

public struct SetMerged has copy, drop {
    user: address,
    amount: u64,
}

/// === Initialization ===

public fun create_market(
    holder: &TruthOracleHolder,
    topic: String,
    description: String,
    start_time: u64,
    end_time: u64,
    ctx: &mut TxContext,
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
        active_orders: linked_table::new(ctx),
        // 初始化價格為 0.5 (50%)
        last_yes_price: PRICE_SCALE / 2,
    };
    transfer::share_object(market);
}

// ... (Helper functions: zero_yes, zero_no, deposit_*, withdraw_*, post_order, cancel_posted_order, get_active_orders) ...
// 這些函數保持不變，為了節省篇幅省略

public fun zero_yes(market: &mut Market, ctx: &mut TxContext): Yes {
    Yes { id: object::new(ctx), amount: 0, market_id: object::id(market) }
}

public fun zero_no(market: &mut Market, ctx: &mut TxContext): No {
    No { id: object::new(ctx), amount: 0, market_id: object::id(market) }
}

public fun deposit_usdc(market: &mut Market, coin: Coin<USDC>, ctx: &mut TxContext) {
    let sender = tx_context::sender(ctx);
    let amount = coin::value(&coin);
    balance::join(&mut market.balance, coin::into_balance(coin));
    let bal = if (table::contains(&market.vault_usdc, sender)) {
        *table::borrow(&market.vault_usdc, sender)
    } else { 0 };
    if (table::contains(&market.vault_usdc, sender)) {
        *table::borrow_mut(&mut market.vault_usdc, sender) = bal + amount;
    } else { table::add(&mut market.vault_usdc, sender, amount); };
}

public fun withdraw_usdc(market: &mut Market, amount: u64, ctx: &mut TxContext) {
    let sender = tx_context::sender(ctx);
    assert!(table::contains(&market.vault_usdc, sender), EInsufficientBalance);
    let bal_ref = table::borrow_mut(&mut market.vault_usdc, sender);
    assert!(*bal_ref >= amount, EInsufficientBalance);
    *bal_ref = *bal_ref - amount;
    let withdraw_coin = coin::take(&mut market.balance, amount, ctx);
    transfer::public_transfer(withdraw_coin, sender);
}

public fun deposit_yes_position(market: &mut Market, yes_pos: Yes, ctx: &mut TxContext) {
    assert!(yes_pos.market_id == object::id(market), EWrongMarket);
    let sender = tx_context::sender(ctx);
    let amount = yes_pos.amount;
    let Yes { id, amount: _, market_id: _ } = yes_pos;
    object::delete(id);
    let bal = if (table::contains(&market.vault_yes, sender)) {
        *table::borrow(&market.vault_yes, sender)
    } else { 0 };
    if (table::contains(&market.vault_yes, sender)) {
        *table::borrow_mut(&mut market.vault_yes, sender) = bal + amount;
    } else { table::add(&mut market.vault_yes, sender, amount); };
}

public fun deposit_no_position(market: &mut Market, no_pos: No, ctx: &mut TxContext) {
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
    } else { table::add(&mut market.vault_no, sender, amount); };
}

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

/// === 新增功能：不經過市場直接鑄造 (Split) ===
/// 將 USDC 轉換為等量的 YES 和 NO (1:1:1)
/// 這增加了 Vault 中的 YES 和 NO 餘額
public fun mint_complete_set(
    market: &mut Market,
    payment: Coin<USDC>,
    amount: u64, // 新增：指定金額
    ctx: &mut TxContext,
) {
    let sender = tx_context::sender(ctx);
    let input_value = coin::value(&payment);

    // 1. 檢查餘額是否足夠
    assert!(input_value >= amount, EInsufficientBalance);

    // 2. 將 Coin 轉換為 Balance 以便進行切分
    let mut input_balance = coin::into_balance(payment);

    // 3. 從輸入的資金中切分出指定 amount
    let mint_balance = balance::split(&mut input_balance, amount);

    // 4. 將切分出的資金存入市場資金池
    balance::join(&mut market.balance, mint_balance);

    // 5. 處理找零：如果還有剩餘資金，轉回給使用者
    if (balance::value(&input_balance) > 0) {
        let change = coin::from_balance(input_balance, ctx);
        transfer::public_transfer(change, sender);
    } else {
        balance::destroy_zero(input_balance);
    };

    // 6. 在 Vault 中增加 YES 和 NO 的餘額
    increase_balance(market, sender, ASSET_YES, amount);
    increase_balance(market, sender, ASSET_NO, amount);

    event::emit(SetMinted {
        user: sender,
        amount,
    });
}

/// === 新增功能：不經過市場直接合併 (Merge) ===
/// 將等量的 YES 和 NO 銷毀，換回 USDC
public fun merge_complete_set(market: &mut Market, amount: u64, ctx: &mut TxContext) {
    let sender = tx_context::sender(ctx);

    // 1. 扣除 Vault 中的 YES 和 NO (必須兩者都有足夠餘額)
    decrease_balance(market, sender, ASSET_YES, amount);
    decrease_balance(market, sender, ASSET_NO, amount);

    // 2. 從資金池提取 USDC 並發送給用戶
    let payout = coin::take(&mut market.balance, amount, ctx);
    transfer::public_transfer(payout, sender);

    event::emit(SetMerged {
        user: sender,
        amount,
    });
}

public fun post_order(market: &mut Market, order: Order, ctx: &mut TxContext) {
    let sender = tx_context::sender(ctx);
    assert!(order.maker == sender, ENotOwner);
    if (order.maker_role == SIDE_BUY) {
        let bal = if (table::contains(&market.vault_usdc, sender)) {
            *table::borrow(&market.vault_usdc, sender)
        } else { 0 };
        assert!(bal >= order.maker_amount, EInsufficientBalance);
    } else {
        let bal = if (order.token_id == ASSET_YES) {
            if (table::contains(&market.vault_yes, sender)) {
                *table::borrow(&market.vault_yes, sender)
            } else { 0 }
        } else {
            if (table::contains(&market.vault_no, sender)) {
                *table::borrow(&market.vault_no, sender)
            } else { 0 }
        };
        assert!(bal >= order.maker_amount, EInsufficientBalance);
    };
    let order_hash = hash_order(&order);
    if (!linked_table::contains(&market.active_orders, order_hash)) {
        linked_table::push_back(&mut market.active_orders, order_hash, order);
        event::emit(OrderPosted {
            order_hash,
            maker: sender,
            maker_amount: order.maker_amount,
            taker_amount: order.taker_amount,
            token_id: order.token_id,
        });
    };
}

public fun cancel_posted_order(market: &mut Market, order: Order, ctx: &mut TxContext) {
    let sender = tx_context::sender(ctx);
    assert!(order.maker == sender, ENotOwner);
    let order_hash = hash_order(&order);
    if (!table::contains(&market.order_statuses, order_hash)) {
        table::add(
            &mut market.order_statuses,
            order_hash,
            OrderStatus { remaining: order.maker_amount, is_cancelled: true },
        );
    } else {
        let status = table::borrow_mut(&mut market.order_statuses, order_hash);
        status.is_cancelled = true;
    };
    if (linked_table::contains(&market.active_orders, order_hash)) {
        linked_table::remove(&mut market.active_orders, order_hash);
    };
    event::emit(OrderCancelled { order_hash, maker: sender });
}

public fun get_active_orders(market: &Market): vector<Order> {
    let mut orders = vector::empty<Order>();
    let mut node_opt = linked_table::front(&market.active_orders);
    while (option::is_some(node_opt)) {
        let order_hash = *option::borrow(node_opt);
        let order = *linked_table::borrow(&market.active_orders, order_hash);
        vector::push_back(&mut orders, order);
        node_opt = linked_table::next(&market.active_orders, order_hash);
    };
    orders
}

public fun get_market_price(market: &Market): u64 {
    market.last_yes_price
}

/// === CTF Trading Logic (Core) ===

public fun match_orders(
    market: &mut Market,
    taker_order: Order,
    maker_order: Order,
    fill_amount_making: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    // 1. 驗證
    verify_order_validity(market, &maker_order, clock);
    verify_order_validity(market, &taker_order, clock);

    // 2. 更新 Maker 的訂單狀態
    let maker_hash = hash_order(&maker_order);
    update_order_status(market, maker_hash, &maker_order, fill_amount_making);

    // 3. 判斷撮合類型
    let match_type = derive_match_type(&taker_order, &maker_order);

    // 4. 驗證價格
    validate_crossing(&taker_order, &maker_order, match_type);

    // 5. 計算 Taker 數量
    let fill_amount_taking =
        (fill_amount_making as u128) * (maker_order.taker_amount as u128) / (maker_order.maker_amount as u128);
    let fill_amount_taking = fill_amount_taking as u64;

    // === 更新市場價格 ===
    update_market_price(market, &maker_order);

    // 6. 執行資金轉移
    execute_trade(
        market,
        taker_order.maker,
        maker_order.maker,
        fill_amount_taking,
        fill_amount_making,
        &taker_order,
        &maker_order,
        match_type,
    );

    event::emit(OrderFilled {
        order_hash: maker_hash,
        maker: maker_order.maker,
        taker: taker_order.maker,
        maker_amount: fill_amount_making,
        taker_amount: fill_amount_taking,
        match_type,
        price: market.last_yes_price,
    });
}

/// === 修改：更新市場價格 (加入 1~99 限制) ===
fun update_market_price(market: &mut Market, maker_order: &Order) {
    let (usdc_amount, share_amount) = if (maker_order.maker_role == SIDE_BUY) {
        (maker_order.maker_amount, maker_order.taker_amount)
    } else {
        (maker_order.taker_amount, maker_order.maker_amount)
    };

    if (share_amount == 0) return;

    let price_u128 = (usdc_amount as u128) * (PRICE_SCALE as u128) / (share_amount as u128);
    let raw_price = price_u128 as u64;

    // 計算目標 YES 價格
    let mut target_yes_price = if (maker_order.token_id == ASSET_YES) {
        raw_price
    } else {
        if (raw_price <= PRICE_SCALE) {
            PRICE_SCALE - raw_price
        } else {
            0
        }
    };

    // === 實施價格限制 (Clamping) ===
    // 確保價格在 MIN_PRICE (1%) 和 MAX_PRICE (99%) 之間
    if (target_yes_price < MIN_PRICE) {
        target_yes_price = MIN_PRICE;
    };
    if (target_yes_price > MAX_PRICE) {
        target_yes_price = MAX_PRICE;
    };

    market.last_yes_price = target_yes_price;
}

fun execute_trade(
    market: &mut Market,
    taker: address,
    maker: address,
    taker_gives: u64,
    maker_gives: u64,
    taker_order: &Order,
    maker_order: &Order,
    match_type: u8,
) {
    if (match_type == MATCH_COMPLEMENTARY) {
        if (maker_order.maker_role == SIDE_BUY) {
            transfer_internal(market, maker, taker, maker_gives, 2);
            transfer_internal(market, taker, maker, taker_gives, maker_order.token_id);
        } else {
            transfer_internal(market, maker, taker, maker_gives, maker_order.token_id);
            transfer_internal(market, taker, maker, taker_gives, 2);
        };
    } else if (match_type == MATCH_MINT) {
        let total_shares = taker_gives;
        let maker_usdc = maker_gives;
        assert!(total_shares >= maker_usdc, EInvalidPrice);
        let taker_usdc = total_shares - maker_usdc;

        decrease_balance(market, maker, 2, maker_usdc);
        decrease_balance(market, taker, 2, taker_usdc);
        increase_balance(market, maker, maker_order.token_id, total_shares);
        increase_balance(market, taker, taker_order.token_id, total_shares);
    } else if (match_type == MATCH_MERGE) {
        let total_shares_burned = maker_gives;
        let maker_usdc_received = taker_gives;
        assert!(total_shares_burned >= maker_usdc_received, EInvalidPrice);
        let taker_usdc_received = total_shares_burned - maker_usdc_received;

        decrease_balance(market, maker, maker_order.token_id, total_shares_burned);
        decrease_balance(market, taker, taker_order.token_id, total_shares_burned);
        increase_balance(market, maker, 2, maker_usdc_received);
        increase_balance(market, taker, 2, taker_usdc_received);
    }
}

/// === 新增：進階查詢功能 ===

/// 取得買單 (Bids)
/// @param token_id: 想要篩選的代幣 (Some(ASSET_YES) 或 Some(ASSET_NO))，傳入 None 表示不篩選
/// @param cursor: 上一次查詢的最後一個 order_hash (第一頁傳 None)
/// @param limit: 限制回傳數量
/// @return (訂單列表, 下一頁的 Cursor)
public fun get_bids(
    market: &Market,
    token_id: Option<u8>,
    cursor: Option<vector<u8>>,
    limit: u64,
): (vector<Order>, Option<vector<u8>>) {
    // Role 0 = Buy
    get_orders_iterator(market, option::some(SIDE_BUY), token_id, cursor, limit)
}

/// 取得賣單 (Asks)
public fun get_asks(
    market: &Market,
    token_id: Option<u8>,
    cursor: Option<vector<u8>>,
    limit: u64,
): (vector<Order>, Option<vector<u8>>) {
    // Role 1 = Sell
    get_orders_iterator(market, option::some(SIDE_SELL), token_id, cursor, limit)
}

/// 底層迭代器 (Iterator)
/// 負責遍歷 LinkedTable 並篩選資料
fun get_orders_iterator(
    market: &Market,
    filter_role: Option<u8>,
    filter_token: Option<u8>,
    cursor: Option<vector<u8>>,
    limit: u64,
): (vector<Order>, Option<vector<u8>>) {
    let mut res = vector::empty<Order>();
    let mut count = 0;

    // 決定起始點
    // 如果有 cursor，從 cursor 的下一個開始；否則從頭開始
    let mut current_opt = if (option::is_some(&cursor)) {
        linked_table::next(&market.active_orders, *option::borrow(&cursor))
    } else {
        linked_table::front(&market.active_orders)
    };

    // 用來記錄最後遍歷到的位置，作為下一次的 cursor
    let mut last_scanned_hash = cursor;

    // 開始遍歷
    while (option::is_some(current_opt) && count < limit) {
        let order_hash = *option::borrow(current_opt);
        let order = *linked_table::borrow(&market.active_orders, order_hash);

        // 更新最後掃描到的 Hash
        last_scanned_hash = option::some(order_hash);

        // 檢查過濾條件
        let role_match = if (option::is_some(&filter_role)) {
            order.maker_role == *option::borrow(&filter_role)
        } else { true };

        let token_match = if (option::is_some(&filter_token)) {
            order.token_id == *option::borrow(&filter_token)
        } else { true };

        // 如果符合條件，加入結果
        if (role_match && token_match) {
            vector::push_back(&mut res, order);
            count = count + 1;
        };

        // 移動到下一個節點
        current_opt = linked_table::next(&market.active_orders, order_hash);
    };

    // 如果 current_opt 還有值，代表還有下一頁，回傳 last_scanned_hash
    // 如果 current_opt 是 None，代表已經到底了，回傳 None
    let next_cursor = if (option::is_some(current_opt)) {
        last_scanned_hash
    } else {
        // 這裡有個邊緣情況：如果剛好掃到底且 count == limit，next 會是 None
        // 但為了讓前端知道是否還有資料，最精確的做法是回傳最後掃描的 hash
        // 只要前端再次請求時收到空列表，就知道結束了。
        // 簡單起見：如果迴圈結束時 current_opt 是 None，就回傳 None
        option::none()
    };

    (res, next_cursor)
}

// ... (Helper functions: transfer_internal, decrease/increase_balance 等保持不變) ...
fun transfer_internal(
    market: &mut Market,
    from: address,
    to: address,
    amount: u64,
    asset_type: u8,
) {
    decrease_balance(market, from, asset_type, amount);
    increase_balance(market, to, asset_type, amount);
}

fun decrease_balance(market: &mut Market, user: address, asset_type: u8, amount: u64) {
    let table_ref = if (asset_type == ASSET_YES) { &mut market.vault_yes } else if (
        asset_type == ASSET_NO
    ) { &mut market.vault_no } else { &mut market.vault_usdc };
    assert!(table::contains(table_ref, user), EInsufficientBalance);
    let bal = table::borrow_mut(table_ref, user);
    assert!(*bal >= amount, EInsufficientBalance);
    *bal = *bal - amount;
}

fun increase_balance(market: &mut Market, user: address, asset_type: u8, amount: u64) {
    let table_ref = if (asset_type == ASSET_YES) { &mut market.vault_yes } else if (
        asset_type == ASSET_NO
    ) { &mut market.vault_no } else { &mut market.vault_usdc };
    if (!table::contains(table_ref, user)) { table::add(table_ref, user, 0); };
    let bal = table::borrow_mut(table_ref, user);
    *bal = *bal + amount;
}

fun verify_order_validity(market: &Market, order: &Order, clock: &Clock) {
    let now = clock::timestamp_ms(clock);
    if (order.expiration > 0 && order.expiration < now) { abort EOrderExpired };
}

fun update_order_status(market: &mut Market, hash: vector<u8>, order: &Order, fill_amount: u64) {
    if (!table::contains(&market.order_statuses, hash)) {
        table::add(
            &mut market.order_statuses,
            hash,
            OrderStatus { remaining: order.maker_amount, is_cancelled: false },
        );
    };
    let status = table::borrow_mut(&mut market.order_statuses, hash);
    assert!(!status.is_cancelled, EOrderFilledOrCancelled);
    assert!(status.remaining >= fill_amount, EInsufficientBalance);
    status.remaining = status.remaining - fill_amount;
    if (status.remaining == 0) {
        status.is_cancelled = true;
        if (linked_table::contains(&market.active_orders, hash)) {
            linked_table::remove(&mut market.active_orders, hash);
        };
    }
}

fun derive_match_type(taker: &Order, maker: &Order): u8 {
    if (taker.maker_role == SIDE_BUY && maker.maker_role == SIDE_BUY) { MATCH_MINT } else if (
        taker.maker_role == SIDE_SELL && maker.maker_role == SIDE_SELL
    ) { MATCH_MERGE } else { MATCH_COMPLEMENTARY }
}

fun validate_crossing(taker: &Order, maker: &Order, match_type: u8) {
    if (match_type == MATCH_COMPLEMENTARY) {
        assert!(taker.token_id == maker.token_id, EMismatchedTokenIds);
    } else { assert!(taker.token_id != maker.token_id, EMismatchedTokenIds); }
}

public fun hash_order(order: &Order): vector<u8> {
    let mut data = bcs::to_bytes(order);
    blake2b256(&data)
}

public fun redeem_yes(
    market: &mut Market,
    truth: &TruthOracleHolder,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    verify_oracle(market, truth, clock, true);
    let sender = tx_context::sender(ctx);
    let amount = *table::borrow(&market.vault_yes, sender);
    decrease_balance(market, sender, ASSET_YES, amount);
    let payout = coin::take(&mut market.balance, amount, ctx);
    transfer::public_transfer(payout, sender);
}

public fun redeem_no(
    market: &mut Market,
    truth: &TruthOracleHolder,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    verify_oracle(market, truth, clock, false);
    let sender = tx_context::sender(ctx);
    let amount = *table::borrow(&market.vault_no, sender);
    decrease_balance(market, sender, ASSET_NO, amount);
    let payout = coin::take(&mut market.balance, amount, ctx);
    transfer::public_transfer(payout, sender);
}

fun verify_oracle(
    market: &Market,
    truth: &TruthOracleHolder,
    clock: &Clock,
    expected_outcome: bool,
) {
    assert!(market.oracle_config_id == object::id(truth), EWrongMarket);
    assert!(clock::timestamp_ms(clock) >= market.end_time, EWrongTime);
    assert!(truth_oracle::get_outcome(truth) == expected_outcome, EWrongTruth);
}

public fun create_order(
    maker: address,
    maker_amount: u64,
    taker_amount: u64,
    maker_role: u8,
    token_id: u8,
    expiration: u64,
    salt: u64,
): Order {
    Order { maker, maker_amount, taker_amount, maker_role, token_id, expiration, salt }
}

public fun yes_balance(yes: &Yes): u64 { yes.amount }

public fun no_balance(no: &No): u64 { no.amount }
