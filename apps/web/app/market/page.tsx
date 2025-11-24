"use client";
import * as React from "react";
import { Suspense } from "react";
import { useSearchParams } from "next/navigation";
import { storeStore } from "@/store/storeStore";
import { PricePill } from "../../components/market/price-pill";
import { Sparkline } from "../../components/market/sparkline";
import { Separator } from "@workspace/ui/components/separator";
import { Button } from "@workspace/ui/components/button";
import { FlipBuyButton } from "../../components/market/flip-buy-button";
import {
  Clock,
  Database,
  Wallet,
  Info,
  RefreshCw,
  ChevronDown,
} from "lucide-react";
import MarketChatRoom from "@/components/market/ChatRoom";
import BuyerRankTabs from "@/components/market/buyerRank";
import { useBuyYes } from "@/hooks/useBuyYes";
import { useBuyNo } from "@/hooks/useBuyNo";
import { Navbar } from "@/components/navbar";
import { Transaction } from "@mysten/sui/transactions";
import { useCurrentAccount } from "@mysten/dapp-kit";
import { provideLPtx } from "@/store/move/orderbook/addliquidity";
import { orderCreateTx } from "@/store/move/orderbook/orderCreate";
import { useSignAndExecuteTransaction, useSuiClient } from "@mysten/dapp-kit";

function calculatePercentage(value: number, total: number): number {
  if (total === 0) return 0;
  return Math.round((value / total) * 100);
}

const formatDate = (ts: number) => new Date(ts).toLocaleString();

// NEW: order type union
type OrderType = "MARKET" | "LIMIT";

type OrderLevel = {
  price: number;   // 價格（cents）
  shares: number;  // 股數
  total: number;   // 總金額（USDC）
};

const mockOrderBook: Record<
  "YES" | "NO",
  { asks: OrderLevel[]; bids: OrderLevel[] }
> = {
  YES: {
    asks: [
      { price: 18, shares: 49375.6, total: 112220.1 },
      { price: 17, shares: 128698.21, total: 103332.49 },
      { price: 16, shares: 196494.86, total: 81453.79 },
      { price: 15, shares: 245533.96, total: 50014.61 },
      { price: 14, shares: 94175.14, total: 13184.52 },
    ],
    bids: [
      { price: 13, shares: 33857.25, total: 4401.44 },
      { price: 12, shares: 220154.23, total: 30819.95 },
      { price: 11, shares: 200509.39, total: 52875.98 },
      { price: 10, shares: 85210.14, total: 61396.99 },
      { price: 9, shares: 44498.85, total: 65401.89 },
    ],
  },
  NO: {
    asks: [
      { price: 78, shares: 30000, total: 23400 },
      { price: 77, shares: 150000, total: 115500 },
      { price: 76, shares: 90000, total: 68400 },
    ],
    bids: [
      { price: 75, shares: 45000, total: 33750 },
      { price: 74, shares: 120000, total: 88800 },
      { price: 73, shares: 80000, total: 58400 },
    ],
  },
};

const formatCents = (p: number) => `${p}¢`;

const formatNumber = (n: number) =>
  n.toLocaleString(undefined, {
    maximumFractionDigits: 2,
  });

function OrderBook() {
  const [side, setSide] = React.useState<"YES" | "NO">("YES");
  const [isOpen, setIsOpen] = React.useState(false); // 🔹 控制伸縮
  const data = mockOrderBook[side];

  const bestAsk = data.asks[0]?.price ?? null;
  const bestBid = data.bids[0]?.price ?? null;
  const last = bestBid ?? bestAsk ?? null;
  const spread =
    bestAsk != null && bestBid != null ? bestAsk - bestBid : null;

  return (
    <div className="rounded-lg border bg-card p-4 shadow-sm">
      {/* Header：點這裡伸縮 */}
      <button
        type="button"
        className="flex w-full items-center justify-between mb-2"
        onClick={() => setIsOpen((v) => !v)}
      >
        <div className="flex items-center gap-2">
          <span className="font-semibold text-sm">Order Book</span>
          <Info className="h-3 w-3 text-muted-foreground" />
        </div>

        <div className="flex items-center gap-3">
          {/* Last / Spread 縮合時仍顯示在 header */}
          <div className="hidden sm:flex flex-col items-end text-[11px] text-muted-foreground">
            <span>
              Last:{" "}
              <span className="text-foreground font-medium">
                {last != null ? formatCents(last) : "--"}
              </span>
            </span>
            <span>
              Spread:{" "}
              <span className="text-foreground font-medium">
                {spread != null ? `${spread}¢` : "--"}
              </span>
            </span>
          </div>

          <RefreshCw className="h-3 w-3 text-muted-foreground" />

          <ChevronDown
            className={`h-4 w-4 text-muted-foreground transition-transform ${
              isOpen ? "rotate-180" : ""
            }`}
          />
        </div>
      </button>

      {/* 收合內容區塊 */}
      <div
        className={`transition-[max-height,opacity] duration-200 ease-in-out ${
          isOpen ? "max-h-[600px] opacity-100" : "max-h-0 opacity-0 overflow-hidden"
        }`}
      >
        {/* tabs */}
        <div className="flex items-center justify-between mb-3">
          <div className="inline-flex items-center rounded-full border bg-muted/40 p-0.5 text-xs">
            <button
              type="button"
              onClick={() => setSide("YES")}
              className={`px-3 py-1 rounded-full transition ${
                side === "YES"
                  ? "bg-primary text-primary-foreground shadow-sm"
                  : "text-muted-foreground hover:text-foreground"
              }`}
            >
              Trade Yes
            </button>
            <button
              type="button"
              onClick={() => setSide("NO")}
              className={`px-3 py-1 rounded-full transition ${
                side === "NO"
                  ? "bg-primary text-primary-foreground shadow-sm"
                  : "text-muted-foreground hover:text-foreground"
              }`}
            >
              Trade No
            </button>
          </div>
        </div>

        {/* 表頭 */}
        <div className="grid grid-cols-[1.5fr,1fr,1fr] text-[11px] text-muted-foreground mb-1 px-1">
          <span className="uppercase tracking-wide">Price</span>
          <span className="uppercase tracking-wide text-right">Shares</span>
          <span className="uppercase tracking-wide text-right">Total</span>
        </div>

        {/* Asks */}
        <div className="mb-2 rounded-md bg-red-950/10 pb-2">
          <div className="flex items-center justify-between px-1 pt-1 pb-1">
            <span className="text-[11px] uppercase tracking-wide text-red-400">
              Asks
            </span>
          </div>
          <div className="space-y-0.5">
            {data.asks.map((level, idx) => (
              <div
                key={`ask-${level.price}-${idx}`}
                className="relative overflow-hidden"
              >
                <div className="absolute inset-y-0 left-0 w-full origin-left bg-red-900/20" />
                <div className="relative grid grid-cols-[1.5fr,1fr,1fr] text-xs px-1 py-0.5">
                  <span className="text-red-400 font-medium">
                    {formatCents(level.price)}
                  </span>
                  <span className="text-right text-muted-foreground">
                    {formatNumber(level.shares)}
                  </span>
                  <span className="text-right text-muted-foreground">
                    ${formatNumber(level.total)}
                  </span>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Last / Spread（小螢幕在內容區顯示） */}
        <div className="flex sm:hidden items-center justify-between text-[11px] text-muted-foreground mb-2 px-1">
          <span>
            Last:{" "}
            <span className="text-foreground font-medium">
              {last != null ? formatCents(last) : "--"}
            </span>
          </span>
          <span>
            Spread:{" "}
            <span className="text-foreground font-medium">
              {spread != null ? `${spread}¢` : "--"}
            </span>
          </span>
        </div>

        {/* Bids */}
        <div className="rounded-md bg-emerald-950/10 pt-1 pb-1">
          <div className="flex items-center justify-between px-1 pb-1">
            <span className="text-[11px] uppercase tracking-wide text-emerald-400">
              Bids
            </span>
          </div>
          <div className="space-y-0.5">
            {data.bids.map((level, idx) => (
              <div
                key={`bid-${level.price}-${idx}`}
                className="relative overflow-hidden"
              >
                <div className="absolute inset-y-0 left-0 w-full origin-left bg-emerald-900/20" />
                <div className="relative grid grid-cols-[1.5fr,1fr,1fr] text-xs px-1 py-0.5">
                  <span className="text-emerald-400 font-medium">
                    {formatCents(level.price)}
                  </span>
                  <span className="text-right text-muted-foreground">
                    {formatNumber(level.shares)}
                  </span>
                  <span className="text-right text-muted-foreground">
                    ${formatNumber(level.total)}
                  </span>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}


function MarketContent() {
  const client = useSuiClient();
  const { mutate: signAndExecuteTransaction } = useSignAndExecuteTransaction({
    execute: async ({ bytes, signature }) =>
      await client.executeTransactionBlock({
        transactionBlock: bytes,
        signature,
        options: {
          showRawEffects: true,
          showObjectChanges: true,
        },
      }),
  });

  const { handleBuyYes } = useBuyYes();
  const { handleBuyNo } = useBuyNo();
  const searchParams = useSearchParams();
  const marketId = searchParams.get("id");
  const { marketList, queryMarkets, fetchUser, user } = storeStore();

  React.useEffect(() => {
    queryMarkets();
  }, [queryMarkets]);

  const market = marketList.find((m) => m.address === marketId);

  // hooks must be before early return
  const [amount, setAmount] = React.useState("");
  const [selectedSide, setSelectedSide] = React.useState<"YES" | "NO" | null>(
    null,
  );

  // NEW: order type & limit price
  const [orderType, setOrderType] = React.useState<OrderType>("MARKET");
  const [limitPrice, setLimitPrice] = React.useState("");

  const currentAccount = useCurrentAccount();
  const addr = currentAccount?.address;

  if (!market) {
    return <div className="p-8 text-center">Market not found.</div>;
  }

  const total = market.yes + market.no;
  const yesPercentage = calculatePercentage(market.yes, total);
  const noPercentage = calculatePercentage(market.no, total);
  const yesFee = market.yesprice ? Number(market.yesprice) / 1e9 : "-";
  const noFee = market.noprice ? Number(market.noprice) / 1e9 : "-";
  const now = Math.floor(Date.now() / 1000);
  const isEnded = market.end_time <= now;

  const handleResolve = () => {
    console.log("Resolve button pressed for market:", marketId);
  };

  const handleAddLiquidity = async () => {
    if (!addr) return;
    await fetchUser(addr);
    const tx = new Transaction();

    const usdcIds = user.USDC;
    const primaryCoinId = usdcIds[0];
    if (!primaryCoinId) throw new Error("No USDC found");

    if (usdcIds.length > 1) {
      tx.mergeCoins(
        tx.object(primaryCoinId),
        usdcIds.slice(1).map((id) => tx.object(id)),
      );
    }

    const lpAmount = BigInt(1e9) * 50n;
    const orderAmount1 = BigInt(1e10) * 5n;
    const orderAmount2 = BigInt(1e10) * 5n;

    const [coinForLP] = tx.splitCoins(tx.object(primaryCoinId), [
      tx.pure.u64(lpAmount),
    ]);
    const [coinForOrder1] = tx.splitCoins(tx.object(primaryCoinId), [
      tx.pure.u64(orderAmount1),
    ]);
    const [coinForOrder2] = tx.splitCoins(tx.object(primaryCoinId), [
      tx.pure.u64(orderAmount2),
    ]);

    provideLPtx(tx, coinForLP, market.address, lpAmount);

    orderCreateTx(
      tx,
      addr,
      market.address,
      orderAmount1,
      27500000000,
      1,
      1,
      0,
      Math.floor(Date.now() * Math.random()),
      coinForOrder1,
    );
    orderCreateTx(
      tx,
      addr,
      market.address,
      orderAmount2,
      27500000000,
      1,
      0,
      0,
      Math.floor(Date.now() * Math.random()),
      coinForOrder2,
    );

    signAndExecuteTransaction({
      transaction: tx,
    });
  };

  // price/amount parsing
  const currentFee =
    selectedSide === "YES"
      ? typeof yesFee === "number"
        ? yesFee
        : 0
      : selectedSide === "NO"
        ? typeof noFee === "number"
          ? noFee
          : 0
        : 0;

  const parsedAmount = parseFloat(amount);
  const isValidAmount = !isNaN(parsedAmount) && parsedAmount > 0;

  const parsedLimitPrice = parseFloat(limitPrice);
  const hasValidLimitPrice =
    !isNaN(parsedLimitPrice) && parsedLimitPrice > 0;

  // NEW: decide which price to use based on order type
  const effectivePricePerShare =
    orderType === "MARKET"
      ? currentFee
      : hasValidLimitPrice
        ? parsedLimitPrice
        : 0;

  const currentTotal =
    effectivePricePerShare && isValidAmount
      ? (effectivePricePerShare * parsedAmount).toFixed(4)
      : "0.0000";

  // NEW: example limit order creator (you可以換成自己的邏輯)
  const createLimitOrder = async (side: "YES" | "NO") => {
    if (!addr) return;
    if (!hasValidLimitPrice || !isValidAmount) return;

    // TODO: 這裡改成你實際的 limit order tx
    console.log("Create limit order", {
      market: market.address,
      side,
      amount: parsedAmount,
      price: parsedLimitPrice,
    });

    // Example skeleton (註解掉，避免編譯錯誤):
    /*
    await fetchUser(addr);
    const tx = new Transaction();
    const usdcIds = user.USDC;
    const primaryCoinId = usdcIds[0];
    if (!primaryCoinId) throw new Error("No USDC found");

    if (usdcIds.length > 1) {
      tx.mergeCoins(
        tx.object(primaryCoinId),
        usdcIds.slice(1).map((id) => tx.object(id)),
      );
    }

    const orderAmount = BigInt(Math.floor(parsedAmount * 1e9));
    const [coinForOrder] = tx.splitCoins(tx.object(primaryCoinId), [
      tx.pure.u64(orderAmount),
    ]);

    orderCreateTx(
      tx,
      addr,
      market.address,
      orderAmount,
      BigInt(Math.floor(parsedLimitPrice * 1e9)),
      1,
      side === "YES" ? 1 : 0,
      0,
      Math.floor(Date.now() * Math.random()),
      coinForOrder,
    );

    signAndExecuteTransaction({ transaction: tx });
    */
  };

  return (
    <div className="max-w-6xl mx-auto px-4 py-8">
      <Navbar />
      <div className="mt-8 grid gap-8 md:grid-cols-[minmax(0,2fr)_minmax(0,1.4fr)] items-start">
        {/* left column */}
        <div className="space-y-6">
          <div className="flex items-start justify-between">
            <div>
              <h2 className="text-2xl font-bold leading-tight">
                {market.topic}
              </h2>
              <div className="flex items-center gap-2 text-sm text-muted-foreground">
                <span className="bg-muted px-2 py-0.5 rounded text-xs font-mono">
                  ID: {market.address.slice(0, 6)}...
                  {market.address.slice(-4)}
                </span>
              </div>
            </div>
          </div>

          <div className="rounded-lg border bg-card p-4 shadow-sm">
            <div className="mb-4 flex justify-between items-center">
              <span className="text-sm font-medium">Price History</span>
              <div className="flex gap-2">
                <PricePill side="Yes" price={yesPercentage} />
                <PricePill side="No" price={noPercentage} />
              </div>
            </div>
            <Sparkline width={600} height={200} className="w-full" />
          </div>

		  <OrderBook />

          <div className="space-y-2">
            <h3 className="font-semibold text-lg">Description</h3>
            <p className="text-muted-foreground leading-relaxed">
              {market.description}
            </p>
          </div>

          <Separator />

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="space-y-1">
              <div className="flex items-center gap-2 text-sm text-muted-foreground">
                <Clock className="h-4 w-4" /> Start Time
              </div>
              <p className="font-medium">{formatDate(market.start_time)}</p>
            </div>
            <div className="space-y-1">
              <div className="flex items-center gap-2 text-sm text-muted-foreground">
                <Clock className="h-4 w-4" /> End Time
              </div>
              <p className="font-medium">{formatDate(market.end_time)}</p>
            </div>
            <div className="space-y-1">
              <div className="flex items-center gap-2 text-sm text-muted-foreground">
                <Wallet className="h-4 w-4" /> Pool Balance
              </div>
              <p className="font-medium">{market.balance / 1e9} USDC</p>
            </div>
            <div className="space-y-1">
              <div className="flex items-center gap-2 text-sm text-muted-foreground">
                <Database className="h-4 w-4" /> Oracle Config
              </div>
              <p
                className="font-medium truncate"
                title={market.oracle_config}
              >
                {market.oracle_config}
              </p>
            </div>
          </div>

          <div className="bg-muted/30 p-4 rounded-lg border space-y-2">
            <h4 className="font-semibold text-sm">Fee Structure</h4>
            <div className="flex justify-between text-sm">
              <span>Yes Position Fee:</span>
              <span className="font-mono">{yesFee} USDC</span>
            </div>
            <div className="flex justify-between text-sm">
              <span>No Position Fee:</span>
              <span className="font-mono">{noFee} USDC</span>
            </div>
          </div>

          {/* order area */}
          <div className="border-t pt-6 flex flex-col gap-4">
            {!isEnded && (
              <>
                {/* NEW: market / limit toggle */}
                <div className="flex justify-center mb-2">
                  <div className="inline-flex items-center rounded-full border bg-muted/40 p-1 text-xs font-medium">
                    <button
                      type="button"
                      className={`px-3 py-1 rounded-full transition ${
                        orderType === "MARKET"
                          ? "bg-primary text-primary-foreground shadow-sm"
                          : "text-muted-foreground hover:text-foreground"
                      }`}
                      onClick={() => setOrderType("MARKET")}
                    >
                      Market
                    </button>
                    <button
                      type="button"
                      className={`px-3 py-1 rounded-full transition ${
                        orderType === "LIMIT"
                          ? "bg-primary text-primary-foreground shadow-sm"
                          : "text-muted-foreground hover:text-foreground"
                      }`}
                      onClick={() => setOrderType("LIMIT")}
                    >
                      Limit
                    </button>
                  </div>
                </div>

                {/* limit price input */}
                {orderType === "LIMIT" && (
                  <div className="flex flex-col gap-1">
                    <label className="text-xs font-medium text-muted-foreground">
                      Limit price (USDC)
                    </label>
                    <input
                      type="number"
                      step="0.0001"
                      min="0"
                      value={limitPrice}
                      onChange={(e) => setLimitPrice(e.target.value)}
                      className="w-full rounded-md border bg-background px-3 py-2 text-sm outline-none focus-visible:ring-2 focus-visible:ring-primary"
                      placeholder="Enter limit price per share"
                    />
                    {!hasValidLimitPrice && limitPrice !== "" && (
                      <span className="text-[10px] text-red-500">
                        Please enter a valid limit price.
                      </span>
                    )}
                  </div>
                )}

                {/* buy buttons */}
                <div className="flex gap-2 mb-2">
                  <FlipBuyButton
                    side="YES"
                    price={typeof yesFee === "number" ? yesFee : 0}
                    amount={amount}
                    setAmount={setAmount}
                    selectedSide={selectedSide}
                    setSelectedSide={setSelectedSide}
                    onConfirm={async () => {
                      if (orderType === "MARKET") {
                        handleBuyYes(market, BigInt(amount));
                      } else {
                        await createLimitOrder("YES");
                      }
                      setAmount("");
                      setSelectedSide(null);
                    }}
                    className="flex-1 h-12"
                    disabled={isEnded}
                  />
                  <FlipBuyButton
                    side="NO"
                    price={typeof noFee === "number" ? noFee : 0}
                    amount={amount}
                    setAmount={setAmount}
                    selectedSide={selectedSide}
                    setSelectedSide={setSelectedSide}
                    onConfirm={async () => {
                      if (orderType === "MARKET") {
                        handleBuyNo(market, BigInt(amount));
                      } else {
                        await createLimitOrder("NO");
                      }
                      setAmount("");
                      setSelectedSide(null);
                    }}
                    className="flex-1 h-12"
                    disabled={isEnded}
                  />
                </div>

                {/* estimate block */}
                {selectedSide && (
                  <div
                    className={`
                      mt-2 rounded-xl border-2 p-4 text-center relative overflow-hidden
                      min-h-[100px] flex flex-col justify-center items-center shadow-inner
                      animate-in slide-in-from-bottom-2 fade-in duration-300
                      ${
                        selectedSide === "YES"
                          ? "bg-emerald-50/80 border-emerald-500/30 text-emerald-900 dark:bg-emerald-950/20 dark:text-emerald-100"
                          : "bg-rose-50/80 border-rose-500/30 text-rose-900 dark:bg-rose-950/20 dark:text-rose-100"
                      }
                    `}
                  >
                    <div className="w-full">
                      <div className="flex items-center justify-center gap-2 mb-1 opacity-70">
                        <span className="text-[10px] uppercase tracking-wider font-bold">
                          Estimated Cost ({orderType} {selectedSide})
                        </span>
                      </div>
                      <div className="text-3xl font-bold tracking-tight leading-none mb-1">
                        {currentTotal}
                        <span className="text-sm font-normal opacity-70 ml-1">
                          USDC
                        </span>
                      </div>
                      <div className="text-xs opacity-60 font-mono flex justify-center items-center gap-1">
                        <span>{effectivePricePerShare.toFixed(4)}</span>
                        <span>×</span>
                        <span>{isValidAmount ? parsedAmount : 0}</span>
                      </div>
                    </div>
                  </div>
                )}
              </>
            )}

            <Button
              className="mt-4 w-full"
              onClick={handleAddLiquidity}
              variant="default"
            >
              Add Liquidity
            </Button>
            <Button
              className="mt-2 w-full"
              onClick={handleResolve}
              variant="default"
            >
              Resolve
            </Button>
          </div>
        </div>

        {/* right column */}
        {market != undefined && (
          <div className="h-full flex flex-col gap-4">
            <MarketChatRoom marketId={market.address} />
            <BuyerRankTabs marketAddress={market.address} />
          </div>
        )}
      </div>
    </div>
  );
}

export default function MarketPage() {
  return (
    <Suspense fallback={<div>Loading...</div>}>
      <MarketContent />
    </Suspense>
  );
}
