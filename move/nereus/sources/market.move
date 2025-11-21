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
    const EInsufficientShares: u64 = 7;

    /// === Constants ===
    const PRICE_SCALE: u64 = 1_000_000_000; 
    const MIN_PRICE: u64 = 10_000_000;      
    const MAX_PRICE: u64 = 990_000_000;     

    /// === Structs ===

    /// Limit Order in the Order Book
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
        is_bid_for_yes: bool 
    }

    public struct Market has key {
        id: UID,
        /// Escrow/Pool Balance: Holds USDC for open orders AND matched positions.
        balance: Balance<USDC>,
        
        topic: String,
        description: String,
        start_time: u64,
        end_time: u64,
        oracle_config_id: ID,
        
        /// Order Book (Bids)
        /// yes_bids: Offers to BUY YES (Paying `p` USDC)
        yes_bids: Table<u64, LinkedTable<ID, Order>>,
        
        /// no_bids: Offers to BUY NO (Paying `1-p` USDC)
        /// Note: Buying NO is equivalent to Selling YES.
        no_bids: Table<u64, LinkedTable<ID, Order>>,

        /// Price Discovery
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

    /// === Manual Split / Merge Functions ===

    /// **Split**: Manually convert USDC into YES + NO shares (1:1 ratio).
    /// This allows users to mint shares without trading, effectively providing liquidity
    /// or hedging. 
    /// 1 USDC -> 1 YES + 1 NO.
    public fun split_usdc(
        market: &mut Market,
        yes_pos: &mut Yes,
        no_pos: &mut No,
        coin: Coin<USDC>,
        ctx: &mut TxContext
    ) {
        // Check market ID
        let market_id = object::id(market);
        assert!(market_id == yes_pos.market_id, EWrongMarket);
        assert!(market_id == no_pos.market_id, EWrongMarket);

        let amount = coin::value(&coin);
        assert!(amount > 0, EInvalidAmount);

        // Lock USDC into the market balance
        let bal = coin::into_balance(coin);
        balance::join(&mut market.balance, bal);

        // Mint YES and NO shares
        yes_pos.amount = yes_pos.amount + amount;
        no_pos.amount = no_pos.amount + amount;

        // Note: Splitting does not affect `last_traded_price_yes` 
        // because no trade occurred on the order book.
    }

    /// **Merge**: Manually combine YES + NO shares back into USDC.
    /// 1 YES + 1 NO -> 1 USDC.
    /// This can be done at any time, even before market resolution.
    public fun merge_shares(
        market: &mut Market,
        yes_pos: &mut Yes,
        no_pos: &mut No,
        amount_shares: u64,
        ctx: &mut TxContext
    ) {
        assert!(object::id(market) == yes_pos.market_id, EWrongMarket);
        assert!(object::id(market) == no_pos.market_id, EWrongMarket);
        
        assert!(yes_pos.amount >= amount_shares, EInsufficientShares);
        assert!(no_pos.amount >= amount_shares, EInsufficientShares);
        assert!(amount_shares > 0, EInvalidAmount);

        // Burn shares
        yes_pos.amount = yes_pos.amount - amount_shares;
        no_pos.amount = no_pos.amount - amount_shares;

        // Unlock USDC
        let usdc = coin::take(&mut market.balance, amount_shares, ctx);
        transfer::public_transfer(usdc, tx_context::sender(ctx));
    }

    /// === Order Book Trading (CLOB) ===

    /// **Place Limit Order**
    /// 
    /// This function handles both **Maker** (adding liquidity) and **Taker** (removing liquidity) logic.
    /// 
    /// - **Taker Flow (Matching)**: 
    ///   If a counter-order exists, the system performs an implicit **Split**.
    ///   Taker's USDC + Maker's USDC = 1 Unit -> Converted to YES/NO shares.
    ///   `last_traded_price_yes` is updated.
    /// 
    /// - **Maker Flow (Queueing)**:
    ///   If no match is found, the Taker becomes a Maker, and their order is added to the book.
    /// 
    /// @param is_bid_for_yes: true = Buy YES, false = Buy NO
    public fun place_limit_order(
        market: &mut Market,
        my_yes_pos: &mut Yes, // Needed if I buy YES
        my_no_pos: &mut No,   // Needed if I buy NO
        is_bid_for_yes: bool,
        price: u64,
        coin: Coin<USDC>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        // Capture Market ID early to avoid borrow checker issues
        let market_id = object::id(market);

        // Basic Validations
        if (is_bid_for_yes) {
            assert!(market_id == my_yes_pos.market_id, EWrongMarket);
        } else {
            assert!(market_id == my_no_pos.market_id, EWrongMarket);
        };
        assert!(price >= MIN_PRICE && price <= MAX_PRICE, EInvalidPrice);
        let now = clock::timestamp_ms(clock);
        assert!(now >= market.start_time && now < market.end_time, EWrongTime);

        let mut input_value = coin::value(&coin);
        let mut input_balance = coin::into_balance(coin);

        // Calculate Counter-Party Price
        // If I buy YES at 0.6 (p), I need someone buying NO at 0.4 (1-p).
        let counter_price = PRICE_SCALE - price;

        // --- Taker Logic (Matching Engine) ---
        
        // Determine which order book to look at
        let has_liquidity = if (is_bid_for_yes) {
            table::contains(&market.no_bids, counter_price)
        } else {
            table::contains(&market.yes_bids, counter_price)
        };

        if (has_liquidity) {
            // Borrow the correct order book mutably
            let orders = if (is_bid_for_yes) {
                table::borrow_mut(&mut market.no_bids, counter_price)
            } else {
                table::borrow_mut(&mut market.yes_bids, counter_price)
            };
            
            while (input_value > 0 && !linked_table::is_empty(orders)) {
                let order_id = *option::borrow(linked_table::front(orders));
                let order = linked_table::borrow_mut(orders, order_id);
                
                // Calculate Shares
                // Taker Shares (Potential)
                let taker_shares_u128 = (input_value as u128) * (PRICE_SCALE as u128) / (price as u128);
                // Maker Shares (Potential)
                // Note: Maker's price is `counter_price`
                let maker_shares_u128 = (order.amount_usdc as u128) * (PRICE_SCALE as u128) / (counter_price as u128);
                
                // Matched Shares = min(Taker, Maker)
                let matched_shares = if (taker_shares_u128 < maker_shares_u128) { 
                    taker_shares_u128 as u64 
                } else { 
                    maker_shares_u128 as u64 
                };

                if (matched_shares == 0) { break; };

                // Calculate USDC Cost
                let taker_cost = ((matched_shares as u128) * (price as u128) / (PRICE_SCALE as u128)) as u64;
                let maker_cost = ((matched_shares as u128) * (counter_price as u128) / (PRICE_SCALE as u128)) as u64;

                // === EXECUTE SPLIT / TRADE ===
                
                // 1. Lock Taker Funds
                let matched_bal = balance::split(&mut input_balance, taker_cost);
                balance::join(&mut market.balance, matched_bal);
                input_value = input_value - taker_cost;

                // 2. Update Maker Order (Funds already locked)
                order.amount_usdc = order.amount_usdc - maker_cost;

                // 3. Distribute Shares (Implicit Split)
                if (is_bid_for_yes) {
                    // I am Taker (Buying YES), Order is Maker (Buying NO)
                    my_yes_pos.amount = my_yes_pos.amount + matched_shares;
                    
                    // Send NO to Maker
                    let maker_no = No { id: object::new(ctx), amount: matched_shares, market_id };
                    transfer::public_transfer(maker_no, order.owner);
                    
                    // Update Price (YES Price)
                    market.last_traded_price_yes = price;
                } else {
                    // I am Taker (Buying NO), Order is Maker (Buying YES)
                    my_no_pos.amount = my_no_pos.amount + matched_shares;

                    // Send YES to Maker
                    let maker_yes = Yes { id: object::new(ctx), amount: matched_shares, market_id };
                    transfer::public_transfer(maker_yes, order.owner);

                    // Update Price (YES Price = Maker's Price)
                    // If I buy NO at 0.4, Maker bought YES at 0.6.
                    market.last_traded_price_yes = counter_price;
                };

                // 4. Cleanup Order
                if (order.amount_usdc < MIN_PRICE) { 
                   let finished_order = linked_table::remove(orders, order_id);
                   let Order { id: _, owner: _, amount_usdc: _ } = finished_order;
                };
            };
        };

        // --- Maker Logic (Resting Order) ---
        // If funds remain, place a limit order
        if (input_value > 0) {
             balance::join(&mut market.balance, input_balance);
             
             let target_table = if (is_bid_for_yes) { &mut market.yes_bids } else { &mut market.no_bids };

             if (!table::contains(target_table, price)) {
                 table::add(target_table, price, linked_table::new(ctx));
             };
             let queue = table::borrow_mut(target_table, price);
             
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

    /// Redeem YES shares after Oracle resolution (Winner)
    public fun redeem_yes(
        yes_bet: &Yes,
        market: &mut Market,
        truth: &TruthOracleHolder,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(object::id(market) == yes_bet.market_id, EWrongMarket);
        // Verify that the provided Oracle matches the Market's config
        assert!(market.oracle_config_id == object::id(truth), EWrongMarket);
        
        assert!(clock::timestamp_ms(clock) >= market.end_time, EWrongTime);
        assert!(truth_oracle::get_outcome(truth) == true, EWrongTruth);

        let payout_amount = yes_bet.amount; 
        let reward = coin::take<USDC>(&mut market.balance, payout_amount, ctx);
        transfer::public_transfer(reward, ctx.sender());
    }

    /// Redeem NO shares after Oracle resolution (Winner)
    public fun redeem_no(
        no_bet: &No,
        market: &mut Market,
        truth: &TruthOracleHolder,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(object::id(market) == no_bet.market_id, EWrongMarket);
        assert!(market.oracle_config_id == object::id(truth), EWrongMarket);
        
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
        is_bid_for_yes: bool
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
                is_bid_for_yes
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

    public fun yes_amount(yes: &Yes): u64 {
        yes.amount
    }

    public fun no_amount(no: &No): u64 {
        no.amount
    }
}