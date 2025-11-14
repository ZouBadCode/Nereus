module no::no;

use sui::coin::{Self, TreasuryCap, Coin};
use sui::url;
use nereus::pool::{Self, PoolConfig};

public struct NO has drop {}

fun init(witness: NO, pool_config: PoolConfig, ctx: &mut TxContext) {
    let (mut treasury_cap, coin_metadata) = coin::create_currency(
        witness,
        9,
        b"NO",
        b"NO",
        b"NO token",
        option::some(url::new_unsafe_from_bytes(b"https://www.google.com/url?sa=i&url=https%3A%2F%2Fwww.svgrepo.com%2Fsvg%2F327405%2Flogo-usd&psig=AOvVaw2A4ktX0YSLyC0Ntnfhe6Vh&ust=1761913741050000&source=images&cd=vfe&opi=89978449&ved=0CBUQjRxqFwoTCOC3osuPzJADFQAAAAAdAAAAABAE")),
        ctx
    );
    let treasury_cap_manager = TreasuryCapManager {
        id: object::new(ctx),
        treasury_cap: treasury_cap
    };
    transfer::public_freeze_object(coin_metadata);
    pool_config.no_treasury_cap = treasury_cap;
}
