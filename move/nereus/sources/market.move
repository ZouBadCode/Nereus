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
const EInvalidMatch: u64 = 11;

/// === Constants ===
const PRICE_SCALE: u64 = 1_000_000_000; // 1.0 = 10^9

/// 價格限制常數 (1% ~ 99%)
const MIN_PRICE: u64 = 10_000_000; // 1% (0.01)
const MAX_PRICE: u64 = 990_000_000; // 99% (0.99)

// Side definition
const SIDE_BUY: u8 = 0;
const SIDE_SELL: u8 = 1;

// Asset IDs
const ASSET_YES: u8 = 1;
const ASSET_NO: u8 = 0;
const ASSET_USDC: u8 = 2; // 內部標記 2 代表 USDC

// Match Types
const MATCH_COMPLEMENTARY: u8 = 0; // 一般買賣
const MATCH_MINT: u8 = 1; // 自動鑄造 (買YES + 買NO)
const MATCH_MERGE: u8 = 2; // 自動合併 (賣YES + 賣NO)

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
        last_yes_price: PRICE_SCALE / 2, // 0.5
    };
    transfer::share_object(market);
}

/// === Internal Helpers ===

fun check_balance(market: &Market, user: address, asset_type: u8, amount: u64) {
    let table_ref = if (asset_type == ASSET_YES) { &market.vault_yes } else if (
        asset_type == ASSET_NO
    ) { &market.vault_no } else { &market.vault_usdc };

    let bal = if (table::contains(table_ref, user)) { *table::borrow(table_ref, user) } else { 0 };
    assert!(bal >= amount, EInsufficientBalance);
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

fun get_order_remaining(market: &Market, hash: vector<u8>): u64 {
    if (table::contains(&market.order_statuses, hash)) {
        let status = table::borrow(&market.order_statuses, hash);
        status.remaining
    } else {
        0
    }
}

fun get_order_and_next(market: &Market, hash: vector<u8>): (Option<vector<u8>>, Order) {
    (
        *linked_table::next(&market.active_orders, hash),
        *linked_table::borrow(&market.active_orders, hash),
    )
}

fun get_front_order_hash(market: &Market): Option<vector<u8>> {
    *linked_table::front(&market.active_orders)
}

/// === View Functions (新增功能) ===

/// 讀取使用者在 Market 內部的資產餘額
/// asset_type: 0 (NO), 1 (YES), 2 (USDC)
public fun get_all_balances(market: &Market, user: address): (u64, u64, u64) {
    let yes_bal = if (table::contains(&market.vault_yes, user)) {
        *table::borrow(&market.vault_yes, user)
    } else { 0 };

    let no_bal = if (table::contains(&market.vault_no, user)) {
        *table::borrow(&market.vault_no, user)
    } else { 0 };

    let usdc_bal = if (table::contains(&market.vault_usdc, user)) {
        *table::borrow(&market.vault_usdc, user)
    } else { 0 };

    (yes_bal, no_bal, usdc_bal)
}

/// === Basic Operations ===

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
    increase_balance(market, sender, ASSET_USDC, amount);
}

public fun withdraw_usdc(market: &mut Market, amount: u64, ctx: &mut TxContext) {
    let sender = tx_context::sender(ctx);
    decrease_balance(market, sender, ASSET_USDC, amount);
    let withdraw_coin = coin::take(&mut market.balance, amount, ctx);
    transfer::public_transfer(withdraw_coin, sender);
}

public fun deposit_yes_position(market: &mut Market, yes_pos: Yes, ctx: &mut TxContext) {
    assert!(yes_pos.market_id == object::id(market), EWrongMarket);
    let sender = tx_context::sender(ctx);
    let amount = yes_pos.amount;
    let Yes { id, amount: _, market_id: _ } = yes_pos;
    object::delete(id);
    increase_balance(market, sender, ASSET_YES, amount);
}

public fun deposit_no_position(market: &mut Market, no_pos: No, ctx: &mut TxContext) {
    assert!(no_pos.market_id == object::id(market), EWrongMarket);
    let sender = tx_context::sender(ctx);
    let amount = no_pos.amount;
    let No { id, amount: _, market_id: _ } = no_pos;
    object::delete(id);
    increase_balance(market, sender, ASSET_NO, amount);
}

public fun withdraw_yes(market: &mut Market, amount: u64, ctx: &mut TxContext) {
    let sender = tx_context::sender(ctx);
    decrease_balance(market, sender, ASSET_YES, amount);
    let yes_obj = Yes { id: object::new(ctx), amount, market_id: object::id(market) };
    transfer::public_transfer(yes_obj, sender);
}

public fun withdraw_no(market: &mut Market, amount: u64, ctx: &mut TxContext) {
    let sender = tx_context::sender(ctx);
    decrease_balance(market, sender, ASSET_NO, amount);
    let no_obj = No { id: object::new(ctx), amount, market_id: object::id(market) };
    transfer::public_transfer(no_obj, sender);
}

public fun mint_complete_set(
    market: &mut Market,
    payment: Coin<USDC>,
    amount: u64,
    ctx: &mut TxContext,
) {
    let sender = tx_context::sender(ctx);
    let input_value = coin::value(&payment);
    assert!(input_value >= amount, EInsufficientBalance);

    let mut input_balance = coin::into_balance(payment);
    let mint_balance = balance::split(&mut input_balance, amount);
    balance::join(&mut market.balance, mint_balance);

    if (balance::value(&input_balance) > 0) {
        let change = coin::from_balance(input_balance, ctx);
        transfer::public_transfer(change, sender);
    } else {
        balance::destroy_zero(input_balance);
    };

    increase_balance(market, sender, ASSET_YES, amount);
    increase_balance(market, sender, ASSET_NO, amount);

    event::emit(SetMinted { user: sender, amount });
}

public fun merge_complete_set(market: &mut Market, amount: u64, ctx: &mut TxContext) {
    let sender = tx_context::sender(ctx);
    decrease_balance(market, sender, ASSET_YES, amount);
    decrease_balance(market, sender, ASSET_NO, amount);

    let payout = coin::take(&mut market.balance, amount, ctx);
    transfer::public_transfer(payout, sender);

    event::emit(SetMerged { user: sender, amount });
}

/// === Core Order Logic with Auto-Matching ===

public fun post_order(market: &mut Market, mut order: Order, clock: &Clock, ctx: &mut TxContext) {
    let sender = tx_context::sender(ctx);
    assert!(order.maker == sender, ENotOwner);

    assert!(order.taker_amount > 0, EInvalidPrice);
    assert!(order.maker_amount > 0, EInsufficientBalance);

    // 1. 檢查餘額
    if (order.maker_role == SIDE_BUY) {
        check_balance(market, sender, ASSET_USDC, order.maker_amount);
    } else {
        check_balance(market, sender, order.token_id, order.maker_amount);
    };

    // 2. 嘗試自動撮合
    if (order.maker_amount > 0) {
        try_match_existing_orders(market, &mut order, clock, ctx);
    };

    // 3. 如果還有剩餘，掛入訂單簿
    if (order.maker_amount > 0) {
        let order_hash = hash_order(&order);
        if (!linked_table::contains(&market.active_orders, order_hash)) {
            // === [修復重點] 初始化 OrderStatus ===
            // 必須在這裡初始化，否則後續撮合讀取時 remaining 會是 0
            if (!table::contains(&market.order_statuses, order_hash)) {
                table::add(
                    &mut market.order_statuses,
                    order_hash,
                    OrderStatus {
                        remaining: order.maker_amount,
                        is_cancelled: false,
                    },
                );
            };

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
}

/// 嘗試撮合現有訂單 (包含 Auto-Mint/Merge)
fun try_match_existing_orders(
    market: &mut Market,
    taker_order: &mut Order,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let mut current_opt = get_front_order_hash(market);
    let mut loop_limit = 50;

    while (option::is_some(&current_opt) && taker_order.maker_amount > 0 && loop_limit > 0) {
        let maker_hash = *option::borrow(&current_opt);

        let (next_cursor, maker_order) = get_order_and_next(market, maker_hash);

        // === [新增] 防呆保護：如果是壞訂單(分母為0)，直接跳過 ===
        if (maker_order.taker_amount == 0 || maker_order.maker_amount == 0) {
            current_opt = next_cursor;
            loop_limit = loop_limit - 1;
            continue
        };
        // ====================================================

        if (can_match(taker_order, &maker_order)) {
            let maker_remaining = get_order_remaining(market, maker_hash);

            let required_maker_amount =
                (taker_order.maker_amount as u128) 
                        * (maker_order.maker_amount as u128) 
                        / (maker_order.taker_amount as u128);

            let mut fill_amount_making = maker_remaining;
            if ((required_maker_amount as u64) < maker_remaining) {
                fill_amount_making = (required_maker_amount as u64);
            };

            if (fill_amount_making > 0) {
                let fill_amount_taking =
                    (fill_amount_making as u128) 
                            * (maker_order.taker_amount as u128) 
                            / (maker_order.maker_amount as u128);

                match_orders(
                    market,
                    *taker_order,
                    maker_order,
                    fill_amount_making,
                    clock,
                    ctx,
                );

                taker_order.maker_amount = taker_order.maker_amount - (fill_amount_taking as u64);
                taker_order.taker_amount = taker_order.taker_amount - fill_amount_making;
            };
        };

        current_opt = next_cursor;
        loop_limit = loop_limit - 1;
    };
}

fun can_match(taker: &Order, maker: &Order): bool {
    if (taker.maker == maker.maker) return false;

    if (taker.maker_role == maker.maker_role && taker.token_id == maker.token_id) {
        return false
    };

    if (taker.maker_role != maker.maker_role && taker.token_id != maker.token_id) {
        return false
    };

    let match_type = derive_match_type(taker, maker);
    let maker_p = calculate_price(maker);
    let taker_p = calculate_price(taker);

    if (match_type == MATCH_COMPLEMENTARY) {
        return true
    } else if (match_type == MATCH_MINT) {
        return (maker_p + taker_p >= PRICE_SCALE)
    } else if (match_type == MATCH_MERGE) {
        return (maker_p + taker_p <= PRICE_SCALE)
    };

    false
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

public fun match_orders(
    market: &mut Market,
    taker_order: Order,
    maker_order: Order,
    fill_amount_making: u64,
    clock: &Clock,
    _ctx: &mut TxContext,
) {
    verify_order_validity(market, &maker_order, clock);
    verify_order_validity(market, &taker_order, clock);

    let maker_hash = hash_order(&maker_order);
    update_order_status(market, maker_hash, &maker_order, fill_amount_making);

    let match_type = derive_match_type(&taker_order, &maker_order);
    validate_crossing(&taker_order, &maker_order, match_type);

    let fill_amount_taking =
        (fill_amount_making as u128) * (maker_order.taker_amount as u128) / (maker_order.maker_amount as u128);
    let fill_amount_taking = fill_amount_taking as u64;

    update_market_price(market, &maker_order);

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

fun update_market_price(market: &mut Market, maker_order: &Order) {
    let (usdc_amount, share_amount) = if (maker_order.maker_role == SIDE_BUY) {
        (maker_order.maker_amount, maker_order.taker_amount)
    } else {
        (maker_order.taker_amount, maker_order.maker_amount)
    };

    if (share_amount == 0) return;

    let price_u128 = (usdc_amount as u128) * (PRICE_SCALE as u128) / (share_amount as u128);
    let raw_price = price_u128 as u64;

    let mut target_yes_price = if (maker_order.token_id == ASSET_YES) {
        raw_price
    } else {
        if (raw_price <= PRICE_SCALE) {
            PRICE_SCALE - raw_price
        } else {
            0
        }
    };

    if (target_yes_price < MIN_PRICE) { target_yes_price = MIN_PRICE; };
    if (target_yes_price > MAX_PRICE) { target_yes_price = MAX_PRICE; };

    market.last_yes_price = target_yes_price;
}

fun derive_match_type(taker: &Order, maker: &Order): u8 {
    if (taker.maker_role != maker.maker_role) {
        assert!(taker.token_id == maker.token_id, EMismatchedTokenIds);
        return MATCH_COMPLEMENTARY
    };
    assert!(taker.token_id != maker.token_id, EInvalidMatch);

    if (taker.maker_role == SIDE_BUY) { MATCH_MINT } else { MATCH_MERGE }
}

fun validate_crossing(taker: &Order, maker: &Order, match_type: u8) {
    let maker_p = calculate_price(maker);
    let taker_p = calculate_price(taker);

    if (match_type == MATCH_COMPLEMENTARY) {} else if (match_type == MATCH_MINT) {
        assert!(maker_p + taker_p >= PRICE_SCALE, EInvalidPrice);
    } else if (match_type == MATCH_MERGE) {
        assert!(maker_p + taker_p <= PRICE_SCALE, EInvalidPrice);
    };
}

fun calculate_price(order: &Order): u64 {
    if (order.taker_amount == 0) return 0;
    let (pay, get) = (order.maker_amount as u128, order.taker_amount as u128);
    let p = pay * (PRICE_SCALE as u128) / get;
    p as u64
}

fun execute_trade(
    market: &mut Market,
    taker: address,
    maker: address,
    taker_gets_amount: u64,
    maker_gives_amount: u64,
    taker_order: &Order,
    maker_order: &Order,
    match_type: u8,
) {
    if (match_type == MATCH_COMPLEMENTARY) {
        if (maker_order.maker_role == SIDE_BUY) {
            transfer_internal(market, maker, taker, maker_gives_amount, ASSET_USDC);
            transfer_internal(market, taker, maker, taker_gets_amount, maker_order.token_id);
        } else {
            transfer_internal(market, maker, taker, maker_gives_amount, maker_order.token_id);
            transfer_internal(market, taker, maker, taker_gets_amount, ASSET_USDC);
        };
    } else if (match_type == MATCH_MINT) {
        let total_shares = taker_gets_amount;
        let maker_usdc = maker_gives_amount;
        assert!(total_shares >= maker_usdc, EInvalidPrice);
        let taker_usdc = total_shares - maker_usdc;

        decrease_balance(market, maker, ASSET_USDC, maker_usdc);
        decrease_balance(market, taker, ASSET_USDC, taker_usdc);

        increase_balance(market, maker, maker_order.token_id, total_shares);
        increase_balance(market, taker, taker_order.token_id, total_shares);
    } else if (match_type == MATCH_MERGE) {
        let total_shares_burned = maker_gives_amount;
        let maker_usdc_received = taker_gets_amount;
        assert!(total_shares_burned >= maker_usdc_received, EInvalidPrice);
        let taker_usdc_received = total_shares_burned - maker_usdc_received;

        decrease_balance(market, maker, maker_order.token_id, total_shares_burned);
        decrease_balance(market, taker, taker_order.token_id, total_shares_burned);

        increase_balance(market, maker, ASSET_USDC, maker_usdc_received);
        increase_balance(market, taker, ASSET_USDC, taker_usdc_received);
    }
}

/// === Query Functions ===

public fun get_bids(
    market: &Market,
    token_id: Option<u8>,
    cursor: Option<vector<u8>>,
    limit: u64,
): (vector<Order>, Option<vector<u8>>) {
    get_orders_iterator(market, option::some(SIDE_BUY), token_id, cursor, limit)
}

public fun get_asks(
    market: &Market,
    token_id: Option<u8>,
    cursor: Option<vector<u8>>,
    limit: u64,
): (vector<Order>, Option<vector<u8>>) {
    get_orders_iterator(market, option::some(SIDE_SELL), token_id, cursor, limit)
}

fun get_orders_iterator(
    market: &Market,
    filter_role: Option<u8>,
    filter_token: Option<u8>,
    cursor: Option<vector<u8>>,
    limit: u64,
): (vector<Order>, Option<vector<u8>>) {
    let mut res = vector::empty<Order>();
    let mut count = 0;
    let mut current_opt = if (option::is_some(&cursor)) {
        linked_table::next(&market.active_orders, *option::borrow(&cursor))
    } else {
        linked_table::front(&market.active_orders)
    };
    let mut last_scanned_hash = cursor;

    while (option::is_some(current_opt) && count < limit) {
        let order_hash = *option::borrow(current_opt);
        let order = *linked_table::borrow(&market.active_orders, order_hash);
        last_scanned_hash = option::some(order_hash);

        let role_match = if (option::is_some(&filter_role)) {
            order.maker_role == *option::borrow(&filter_role)
        } else { true };

        let token_match = if (option::is_some(&filter_token)) {
            order.token_id == *option::borrow(&filter_token)
        } else { true };

        if (role_match && token_match) {
            vector::push_back(&mut res, order);
            count = count + 1;
        };
        current_opt = linked_table::next(&market.active_orders, order_hash);
    };

    let next_cursor = if (option::is_some(current_opt)) { last_scanned_hash } else {
        option::none()
    };
    (res, next_cursor)
}

/// === Common Helpers ===

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

public fun get_active_orders(market: &Market): vector<Order> {
    let (orders, _) = get_orders_iterator(
        market,
        option::none(),
        option::none(),
        option::none(),
        1000,
    );
    orders
}

public fun get_market_price(market: &Market): u64 { market.last_yes_price }

public entry fun place_order_entry(
    market: &mut Market,
    maker_amount: u64,
    taker_amount: u64,
    maker_role: u8,
    token_id: u8,
    expiration: u64,
    salt: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let order = create_order(
        tx_context::sender(ctx),
        maker_amount,
        taker_amount,
        maker_role,
        token_id,
        expiration,
        salt,
    );
    post_order(market, order, clock, ctx);
}
