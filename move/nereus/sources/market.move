module nereus::market {
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use std::string::String;
    use sui::clock::{Self, Clock};
    use sui::table::{Self, Table};
    use sui::linked_table::{Self, LinkedTable};
    use std::vector;
    use std::option;

    use nereus::usdc::{USDC};
    use nereus::truth_oracle::{Self, TruthOracleHolder};

    /// === Error codes ===
    const EWrongMarket: u64 = 1;
    const EWrongTime: u64 = 2;
    const EInvalidAmount: u64 = 3;
    const EInvalidPrice: u64 = 4;
    const EWrongTruth: u64 = 6;

    /// === Constants ===
    const PRICE_SCALE: u64 = 1_000_000_000; 
    const MIN_PRICE: u64 = 10_000_000;      
    const MAX_PRICE: u64 = 990_000_000;     

    /// === Structs ===

    public struct Order has store, drop {
        id: ID,
        owner: address,
        amount_usdc: u64, 
    }

    public struct Yes has key, store {
        id: UID,
        amount: u64,
        market_id: ID
    }

    public struct No has key, store {
        id: UID,
        amount: u64,
        market_id: ID
    }

    public struct OrderView has copy, drop, store {
        order_id: ID,
        owner: address,
        amount_usdc: u64,
        price: u64,
        is_yes_bid: bool 
    }

    public struct Market has key {
        id: UID,
        balance: Balance<USDC>,
        topic: String,
        description: String,
        start_time: u64,
        end_time: u64,
        oracle_config_id: ID,
        yes_bids: Table<u64, LinkedTable<ID, Order>>,
        no_bids: Table<u64, LinkedTable<ID, Order>>,
        last_traded_price_yes: u64,
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
            yes_bids: table::new(ctx),
            no_bids: table::new(ctx),
            last_traded_price_yes: PRICE_SCALE / 2, 
        };
        transfer::share_object(market);
    }

    public fun zero_yes(market: &mut Market, ctx: &mut TxContext): Yes {
        Yes { id: object::new(ctx), amount: 0, market_id: object::id(market) }
    }

    public fun zero_no(market: &mut Market, ctx: &mut TxContext): No {
        No { id: object::new(ctx), amount: 0, market_id: object::id(market) }
    }

    /// === Trading Logic ===

    public fun bet_yes(
        yes_pos: &mut Yes,
        market: &mut Market,
        price: u64,
        coin: Coin<USDC>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Fix 1: Capture ID early to avoid borrow conflict later
        let market_id = object::id(market);
        
        assert!(market_id == yes_pos.market_id, EWrongMarket);
        assert!(price >= MIN_PRICE && price <= MAX_PRICE, EInvalidPrice);
        
        let now = clock::timestamp_ms(clock);
        assert!(now >= market.start_time && now < market.end_time, EWrongTime);

        let mut input_value = coin::value(&coin);
        let mut input_balance = coin::into_balance(coin);

        let counter_price = PRICE_SCALE - price;

        if (table::contains(&market.no_bids, counter_price)) {
            let orders = table::borrow_mut(&mut market.no_bids, counter_price);
            
            while (input_value > 0 && !linked_table::is_empty(orders)) {
                let order_id = *option::borrow(linked_table::front(orders));
                let order = linked_table::borrow_mut(orders, order_id);
                
                let my_shares = (input_value as u128) * (PRICE_SCALE as u128) / (price as u128);
                let maker_shares = (order.amount_usdc as u128) * (PRICE_SCALE as u128) / (counter_price as u128);
                
                let matched_shares_u128 = if (my_shares < maker_shares) { my_shares } else { maker_shares };
                let matched_shares = (matched_shares_u128 as u64);

                if (matched_shares == 0) {
                    break; 
                };

                let my_cost = (matched_shares as u128) * (price as u128) / (PRICE_SCALE as u128);
                let maker_cost = (matched_shares as u128) * (counter_price as u128) / (PRICE_SCALE as u128);

                let my_cost_u64 = (my_cost as u64);
                let maker_cost_u64 = (maker_cost as u64);

                // Execute Trade
                let matched_bal = balance::split(&mut input_balance, my_cost_u64);
                balance::join(&mut market.balance, matched_bal);
                input_value = input_value - my_cost_u64;

                order.amount_usdc = order.amount_usdc - maker_cost_u64;
                
                // Taker gets YES
                yes_pos.amount = yes_pos.amount + matched_shares;
                
                // Maker gets NO
                let maker_no_pos = No {
                    id: object::new(ctx),
                    amount: matched_shares,
                    // Fix 2: Use the pre-captured market_id
                    market_id: market_id 
                };
                transfer::public_transfer(maker_no_pos, order.owner);
                
                market.last_traded_price_yes = price;

                if (order.amount_usdc < MIN_PRICE) { 
                   let finished_order = linked_table::remove(orders, order_id);
                   let Order { id: _, owner: _, amount_usdc: _ } = finished_order;
                };
            };
        };

        if (input_value > 0) {
             balance::join(&mut market.balance, input_balance);
             
             if (!table::contains(&market.yes_bids, price)) {
                 table::add(&mut market.yes_bids, price, linked_table::new(ctx));
             };
             let queue = table::borrow_mut(&mut market.yes_bids, price);
             
             let order_uid = object::new(ctx);
             let order_id = object::uid_to_inner(&order_uid);
             
             let order = Order {
                 id: order_id,
                 owner: tx_context::sender(ctx),
                 amount_usdc: input_value
             };
             object::delete(order_uid); 
             linked_table::push_back(queue, order_id, order);
        } else {
            balance::destroy_zero(input_balance);
        };
    }

    public fun bet_no(
        no_pos: &mut No,
        market: &mut Market,
        price: u64, 
        coin: Coin<USDC>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Fix 3: Capture ID early here too
        let market_id = object::id(market);

        assert!(market_id == no_pos.market_id, EWrongMarket);
        assert!(price >= MIN_PRICE && price <= MAX_PRICE, EInvalidPrice);
        
        let now = clock::timestamp_ms(clock);
        assert!(now >= market.start_time && now < market.end_time, EWrongTime);

        let mut input_value = coin::value(&coin);
        let mut input_balance = coin::into_balance(coin);

        let target_yes_price = PRICE_SCALE - price;
        
        if (table::contains(&market.yes_bids, target_yes_price)) {
            let orders = table::borrow_mut(&mut market.yes_bids, target_yes_price);

            while (input_value > 0 && !linked_table::is_empty(orders)) {
                let order_id = *option::borrow(linked_table::front(orders));
                let order = linked_table::borrow_mut(orders, order_id);

                let my_shares = (input_value as u128) * (PRICE_SCALE as u128) / (price as u128);
                let maker_shares = (order.amount_usdc as u128) * (PRICE_SCALE as u128) / (target_yes_price as u128);

                let matched_shares_u128 = if (my_shares < maker_shares) { my_shares } else { maker_shares };
                let matched_shares = (matched_shares_u128 as u64);

                if (matched_shares == 0) { break; };

                let my_cost = (matched_shares as u128) * (price as u128) / (PRICE_SCALE as u128);
                let maker_cost = (matched_shares as u128) * (target_yes_price as u128) / (PRICE_SCALE as u128);

                let my_cost_u64 = (my_cost as u64);
                let maker_cost_u64 = (maker_cost as u64);

                let matched_bal = balance::split(&mut input_balance, my_cost_u64);
                balance::join(&mut market.balance, matched_bal);
                input_value = input_value - my_cost_u64;

                order.amount_usdc = order.amount_usdc - maker_cost_u64;

                no_pos.amount = no_pos.amount + matched_shares;

                let maker_yes_pos = Yes {
                    id: object::new(ctx),
                    amount: matched_shares,
                    // Fix 4: Use the pre-captured market_id
                    market_id: market_id 
                };
                transfer::public_transfer(maker_yes_pos, order.owner);

                market.last_traded_price_yes = target_yes_price;

                if (order.amount_usdc < MIN_PRICE) {
                    let finished_order = linked_table::remove(orders, order_id);
                    let Order { id: _, owner: _, amount_usdc: _ } = finished_order;
                };
            }
        };
        
        if (input_value > 0) {
             balance::join(&mut market.balance, input_balance);
             
             if (!table::contains(&market.no_bids, price)) {
                 table::add(&mut market.no_bids, price, linked_table::new(ctx));
             };
             let queue = table::borrow_mut(&mut market.no_bids, price);
             
             let order_uid = object::new(ctx);
             let order_id = object::uid_to_inner(&order_uid);
             let order = Order {
                 id: order_id,
                 owner: tx_context::sender(ctx),
                 amount_usdc: input_value
             };
             object::delete(order_uid); 
             linked_table::push_back(queue, order_id, order);
        } else {
            balance::destroy_zero(input_balance);
        };
    }

    /// === Settlement ===

    public fun redeem_yes(
        yes_bet: &Yes,
        market: &mut Market,
        truth: &TruthOracleHolder,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(object::id(market) == yes_bet.market_id, EWrongMarket);
        assert!(object::id(market) == object::id(truth), EWrongMarket);
        assert!(clock::timestamp_ms(clock) >= market.end_time, EWrongTime);
        assert!(truth_oracle::get_outcome(truth) == true, EWrongTruth);

        let payout_amount = yes_bet.amount; 
        let reward = coin::take<USDC>(&mut market.balance, payout_amount, ctx);
        transfer::public_transfer(reward, ctx.sender());
    }

    public fun redeem_no(
        no_bet: &No,
        market: &mut Market,
        truth: &TruthOracleHolder,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(object::id(market) == no_bet.market_id, EWrongMarket);
        assert!(object::id(market) == object::id(truth), EWrongMarket);
        assert!(clock::timestamp_ms(clock) >= market.end_time, EWrongTime);
        assert!(truth_oracle::get_outcome(truth) == false, EWrongTruth);

        let payout_amount = no_bet.amount; 
        let reward = coin::take<USDC>(&mut market.balance, payout_amount, ctx);
        transfer::public_transfer(reward, ctx.sender());
    }

    /// === View / Helper APIs ===

    public fun get_price(market: &Market): u64 {
        market.last_traded_price_yes
    }

    fun iter_orders(
        queue: &LinkedTable<ID, Order>, 
        price: u64, 
        is_yes_bid: bool
    ): vector<OrderView> {
        let mut views = vector::empty<OrderView>();
        let mut current_opt = linked_table::front(queue);

        while (option::is_some(current_opt)) {
            let id = *option::borrow(current_opt);
            let order = linked_table::borrow(queue, id);
            
            vector::push_back(&mut views, OrderView {
                order_id: id,
                owner: order.owner,
                amount_usdc: order.amount_usdc,
                price,
                is_yes_bid
            });

            current_opt = linked_table::next(queue, id);
        };
        views
    }

    public fun get_yes_orders_at_price(market: &Market, price: u64): vector<OrderView> {
        if (!table::contains(&market.yes_bids, price)) {
            return vector::empty()
        };
        let queue = table::borrow(&market.yes_bids, price);
        iter_orders(queue, price, true)
    }

    public fun get_no_orders_at_price(market: &Market, price: u64): vector<OrderView> {
        if (!table::contains(&market.no_bids, price)) {
            return vector::empty()
        };
        let queue = table::borrow(&market.no_bids, price);
        iter_orders(queue, price, false)
    }

    public fun get_orders_batch(
        market: &Market, 
        prices: vector<u64>, 
        check_yes: bool
    ): vector<OrderView> {
        let mut all_orders = vector::empty<OrderView>();
        let mut i = 0;
        let len = vector::length(&prices);

        while (i < len) {
            let p = *vector::borrow(&prices, i);
            let mut orders_at_p = if (check_yes) {
                get_yes_orders_at_price(market, p)
            } else {
                get_no_orders_at_price(market, p)
            };
            vector::append(&mut all_orders, orders_at_p);
            i = i + 1;
        };

        all_orders
    }
}