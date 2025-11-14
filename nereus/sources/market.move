module nereus::market;

use sui::balance::{Self, Balance};
use sui::coin::{Self, Coin};
use sui::object::{Self, UID, ID};
use sui::transfer;
use sui::tx_context::TxContext;
use nereus::usdc::{Self, USDC};
use std::string::String;
use sui::clock::{Self, Clock};

/// === Error codes ===
const WrongMarket: u64 = 1;
const WrongTime: u64 = 2;
const InvalidAmount: u64 = 3;
const InsufficientPoolBalance: u64 = 4;
const InsufficientPosition: u64 = 5;

/// === Fixed-point parameters ===
/// All FP values are scaled by FP_SCALE (1e9)
const FP_SCALE: u128 = 1_000_000_000;
/// Price is reported with the same scale but in u64
const PRICE_SCALE: u64 = 1_000_000_000;

/// Liquidity parameter b (controls how fast prices move)
const B: u64 = 1_000_000;

/// Max x (= q/b) we allow for exp(x) before clamping (x <= 10)
const MAX_X_FP: u128 = 10 * FP_SCALE;

public struct Yes has key, store {
    id: UID,
    /// Position size in YES shares
    amount: u64,
    market_id: ID
}

public struct No has key, store {
    id: UID,
    /// Position size in NO shares
    amount: u64,
    market_id: ID
}

public struct Market has key {
    id: UID,
    /// AMM pool balance in USDC
    balance: Balance<USDC>,
    topic: String,
    /// Total outstanding YES / NO shares
    yes: u64,
    no: u64,
    description: String,
    start_time: u64,
    end_time: u64
}

/// Create a new prediction market
public fun create_market(
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
        yes: 0,
        no: 0,
        description,
        start_time,
        end_time
    };
    transfer::share_object(market);
}

/// Create an empty YES position object for a market
public fun zero_yes(
    market: &mut Market,
    ctx: &mut TxContext
): Yes {
    Yes {
        id: object::new(ctx),
        amount: 0,
        market_id: object::id(market)
    }
}

/// Create an empty NO position object for a market
public fun zero_no(
    market: &mut Market,
    ctx: &mut TxContext
): No {
    No {
        id: object::new(ctx),
        amount: 0,
        market_id: object::id(market)
    }
}

/// === Public trading APIs ===

/// Buy YES shares with USDC
/// - `amount`: USDC to spend (must equal `coin` value)
public fun bet_yes(
    yes_bet: &mut Yes,
    market: &mut Market,
    amount: u64,
    coin: Coin<USDC>,
    clock: &Clock,
    ctx: &mut TxContext
) {
    assert!(object::id(market) == yes_bet.market_id, WrongMarket);

    let now = clock::timestamp_ms(clock);
    assert!(now >= market.start_time && now < market.end_time, WrongTime);

    let value = coin::value(&coin);
    assert!(value == amount && amount > 0, InvalidAmount);

    // Add USDC to the AMM pool
    let bal = coin::into_balance(coin);
    balance::join(&mut market.balance, bal);

    // Mint YES shares based on LMSR-style marginal price
    let minted_shares = mint_yes_shares(market, value);
    yes_bet.amount = yes_bet.amount + minted_shares;
    market.yes = market.yes + minted_shares;
}

/// Buy NO shares with USDC
public fun bet_no(
    no_bet: &mut No,
    market: &mut Market,
    amount: u64,
    coin: Coin<USDC>,
    clock: &Clock,
    ctx: &mut TxContext
) {
    assert!(object::id(market) == no_bet.market_id, WrongMarket);

    let now = clock::timestamp_ms(clock);
    assert!(now >= market.start_time && now < market.end_time, WrongTime);

    let value = coin::value(&coin);
    assert!(value == amount && amount > 0, InvalidAmount);

    let bal = coin::into_balance(coin);
    balance::join(&mut market.balance, bal);

    let minted_shares = mint_no_shares(market, value);
    no_bet.amount = no_bet.amount + minted_shares;
    market.no = market.no + minted_shares;
}

/// Sell YES shares back to the pool, receive USDC
public fun sell_yes(
    yes_bet: &mut Yes,
    market: &mut Market,
    sell_amount: u64,
    clock: &Clock,
    ctx: &mut TxContext
): Coin<USDC> {
    assert!(object::id(market) == yes_bet.market_id, WrongMarket);

    let now = clock::timestamp_ms(clock);
    // If you want to allow cash-out after expiry, relax this condition
    assert!(now >= market.start_time && now < market.end_time, WrongTime);

    assert!(sell_amount > 0 && sell_amount <= yes_bet.amount, InsufficientPosition);

    // Quote payout in USDC using current LMSR-style marginal price
    let payout = quote_yes_sell(market, sell_amount);
    assert!(payout > 0, InvalidAmount);

    let pool_value = balance::value(&market.balance);
    assert!(pool_value >= payout, InsufficientPoolBalance);

    // Withdraw from pool
    let payout_bal = balance::split(&mut market.balance, payout);
    let payout_coin = coin::from_balance(payout_bal, ctx);

    yes_bet.amount = yes_bet.amount - sell_amount;
    market.yes = market.yes - sell_amount;

    payout_coin
}

/// Sell NO shares back to the pool, receive USDC
public fun sell_no(
    no_bet: &mut No,
    market: &mut Market,
    sell_amount: u64,
    clock: &Clock,
    ctx: &mut TxContext
): Coin<USDC> {
    assert!(object::id(market) == no_bet.market_id, WrongMarket);

    let now = clock::timestamp_ms(clock);
    assert!(now >= market.start_time && now < market.end_time, WrongTime);

    assert!(sell_amount > 0 && sell_amount <= no_bet.amount, InsufficientPosition);

    let payout = quote_no_sell(market, sell_amount);
    assert!(payout > 0, InvalidAmount);

    let pool_value = balance::value(&market.balance);
    assert!(pool_value >= payout, InsufficientPoolBalance);

    let payout_bal = balance::split(&mut market.balance, payout);
    let payout_coin = coin::from_balance(payout_bal, ctx);

    no_bet.amount = no_bet.amount - sell_amount;
    market.no = market.no - sell_amount;

    payout_coin
}

/// === View / helper APIs ===

/// Returns current YES / NO prices as fixed-point values
/// scaled by PRICE_SCALE (1e9). For example:
///  - 400_000_000 => 0.4
///  - 600_000_000 => 0.6
public fun get_prices(market: &Market): (u64, u64) {
    (price_yes(market), price_no(market))
}

/// LMSR-style marginal price for YES:
/// p_yes = exp(q_yes/b) / (exp(q_yes/b) + exp(q_no/b))
fun price_yes(market: &Market): u64 {
    let (e_yes, e_no) = lmsr_exps(market);
    let denom = e_yes + e_no;

    if (denom == 0) {
        // No liquidity yet: 0.5 / 0.5
        return PRICE_SCALE / 2;
    };

    let num = e_yes * (FP_SCALE);
    // num / denom => fixed-point in FP_SCALE, need to convert to PRICE_SCALE
    let p_fp = num / denom;

    // p_fp is scaled by FP_SCALE (1e9). We choose PRICE_SCALE == FP_SCALE,
    // so we can cast directly.
    (p_fp as u64)
}

/// LMSR-style marginal price for NO
fun price_no(market: &Market): u64 {
    let (e_yes, e_no) = lmsr_exps(market);
    let denom = e_yes + e_no;

    if (denom == 0) {
        return PRICE_SCALE / 2;
    };

    let num = e_no * (FP_SCALE);
    let p_fp = num / denom;

    (p_fp as u64)
}

/// Compute exp(q_yes/b) and exp(q_no/b) in fixed point
fun lmsr_exps(market: &Market): (u128, u128) {
    let qy = market.yes;
    let qn = market.no;

    let x_yes = fp_div_u64(qy, B);
    let x_no = fp_div_u64(qn, B);

    let e_yes = exp_fp(x_yes);
    let e_no = exp_fp(x_no);

    (e_yes, e_no)
}

/// Convert q (u64) / b (u64) into fixed-point x scaled by FP_SCALE
fun fp_div_u64(q: u64, b: u64): u128 {
    // Ensure b > 0
    let b_u128 = (b as u128);
    let q_u128 = (q as u128);
    let x = q_u128 * FP_SCALE / b_u128;

    // Clamp x to avoid explosion in exp approximation
    if (x > MAX_X_FP) {
        MAX_X_FP
    } else {
        x
    }
}

/// Fixed-point exponential approximation:
/// exp(x) ≈ 1 + x + x^2/2 + x^3/6
/// where x is scaled by FP_SCALE (1e9).
/// Returns exp(x) also scaled by FP_SCALE.
fun exp_fp(x: u128): u128 {
    let one = FP_SCALE;

    // x^2 / SCALE
    let x2 = x * x / FP_SCALE;
    // x^3 / SCALE
    let x3 = x2 * x / FP_SCALE;

    // 1 + x + x^2/2 + x^3/6
    let term2 = x2 / 2;
    let term3 = x3 / 6;

    one + x + term2 + term3
}

/// Mint YES shares given `budget` USDC using current marginal price.
/// price_yes is p in [0, PRICE_SCALE], interpreted as USDC per share.
/// shares = budget / p.
fun mint_yes_shares(market: &Market, budget: u64): u64 {
    let p = price_yes(market);
    if (p == 0) {
        // Fallback: 1:1 mapping
        return budget;
    };

    let budget_u128 = (budget as u128);
    let p_u128 = (p as u128);
    let scale_u128 = (PRICE_SCALE as u128);

    let shares_u128 = budget_u128 * scale_u128 / p_u128;
    (shares_u128 as u64)
}

/// Mint NO shares given `budget` USDC using current marginal price.
fun mint_no_shares(market: &Market, budget: u64): u64 {
    let p = price_no(market);
    if (p == 0) {
        return budget;
    };

    let budget_u128 = (budget as u128);
    let p_u128 = (p as u128);
    let scale_u128 = (PRICE_SCALE as u128);

    let shares_u128 = budget_u128 * scale_u128 / p_u128;
    (shares_u128 as u64)
}

/// Quote USDC payout for selling `shares` YES at current price:
/// payout = shares * p_yes
fun quote_yes_sell(market: &Market, shares: u64): u64 {
    let p = price_yes(market);

    let shares_u128 = (shares as u128);
    let p_u128 = (p as u128);
    let scale_u128 = (PRICE_SCALE as u128);

    let payout_u128 = shares_u128 * p_u128 / scale_u128;
    (payout_u128 as u64)
}

/// Quote USDC payout for selling `shares` NO at current price.
fun quote_no_sell(market: &Market, shares: u64): u64 {
    let p = price_no(market);

    let shares_u128 = (shares as u128);
    let p_u128 = (p as u128);
    let scale_u128 = (PRICE_SCALE as u128);

    let payout_u128 = shares_u128 * p_u128 / scale_u128;
    (payout_u128 as u64)
}
