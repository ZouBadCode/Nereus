"use client";
import React, { Suspense } from "react";
import { useSearchParams } from "next/navigation";
import { storeStore } from "@/store/storeStore";
import { PricePill } from "../../components/market/price-pill";
import { Sparkline } from "../../components/market/sparkline";
import { Separator } from "@workspace/ui/components/separator";
import { Button } from "@workspace/ui/components/button";
import { FlipBuyButton } from "../../components/market/flip-buy-button";
import { Clock, Database, Wallet } from "lucide-react";
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

function MarketContent() {
	const client = useSuiClient();
	const { mutate: signAndExecuteTransaction } = useSignAndExecuteTransaction({
		execute: async ({ bytes, signature }) =>
			await client.executeTransactionBlock({
				transactionBlock: bytes,
				signature,
				options: {
					// Raw effects are required so the effects can be reported back to the wallet
					showRawEffects: true,
					// Select additional data to return
					showObjectChanges: true,
				},
			}),
	});

	const { handleBuyYes } = useBuyYes()
	const { handleBuyNo } = useBuyNo()
	const searchParams = useSearchParams();
	const marketId = searchParams.get("id");
	const { marketList, queryMarkets, fetchUser, user } = storeStore();
	React.useEffect(() => {
		queryMarkets();
	}, [queryMarkets]);
	const market = marketList.find((m) => m.address === marketId);

	// ✅ hooks 一定要在條件 return 之前宣告
	const [amount, setAmount] = React.useState("");
	const [selectedSide, setSelectedSide] = React.useState<"YES" | "NO" | null>(
		null,
	);
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
		await fetchUser(addr!);
		const tx = new Transaction();
		// 1. 取得所有 USDC ID
		const usdcIds = user.USDC;
		const primaryCoinId = usdcIds[0];
		if (!primaryCoinId) throw new Error("No USDC found");
		// 2. 先將所有零錢合併到第一顆 Coin
		if (usdcIds.length > 1) {
			tx.mergeCoins(
				tx.object(primaryCoinId),
				usdcIds.slice(1).map(id => tx.object(id))
			);
		}
		// 3. 定義金額
		const lpAmount = BigInt(1e9) * 50n;
		const orderAmount1 = BigInt(1e10) * 5n;
		const orderAmount2 = BigInt(1e10) * 5n;
		// 4. 從主 Coin 切分出專款專用的 Coin
		const [coinForLP] = tx.splitCoins(tx.object(primaryCoinId), [tx.pure.u64(lpAmount)]);
		const [coinForOrder1] = tx.splitCoins(tx.object(primaryCoinId), [tx.pure.u64(orderAmount1)]);
		const [coinForOrder2] = tx.splitCoins(tx.object(primaryCoinId), [tx.pure.u64(orderAmount2)]);
		// 5. 呼叫功能函數
		provideLPtx(tx, coinForLP, market.address, lpAmount);
		orderCreateTx(
			tx,
			addr!,
			market.address,
			orderAmount1,
			27500000000,
			1, 1, 0,
			Math.floor((Date.now() * Math.random())),
			coinForOrder1
		);
		orderCreateTx(
			tx,
			addr!,
			market.address,
			orderAmount2,
			27500000000,
			1, 0, 0,
			Math.floor((Date.now() * Math.random())),
			coinForOrder2
		);
		signAndExecuteTransaction({
			transaction: tx,
		});
	}
	// 計算區塊
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
	const currentTotal =
		currentFee && isValidAmount
			? (currentFee * parsedAmount).toFixed(4)
			: "0.0000";

	return (
		<div className="max-w-6xl mx-auto px-4 py-8">
			<Navbar />
			{/* 🔹 左右兩欄：左邊 market、右邊 chat；小螢幕時會上下堆疊 */}
			<div className="mt-8 grid gap-8 md:grid-cols-[minmax(0,2fr)_minmax(0,1.4fr)] items-start">
				{/* 左側：原本的 market 內容 */}
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
							<p className="font-medium">
								{formatDate(market.start_time)}
							</p>
						</div>
						<div className="space-y-1">
							<div className="flex items-center gap-2 text-sm text-muted-foreground">
								<Clock className="h-4 w-4" /> End Time
							</div>
							<p className="font-medium">
								{formatDate(market.end_time)}
							</p>
						</div>
						<div className="space-y-1">
							<div className="flex items-center gap-2 text-sm text-muted-foreground">
								<Wallet className="h-4 w-4" /> Pool Balance
							</div>
							<p className="font-medium">
								{market.balance / 1e9} USDC
							</p>
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

					{/* Calculation Area */}
					<div className="border-t pt-6 flex flex-col gap-4">
						{!isEnded && (
							<>
								{/* 先讓使用者選 YES / NO */}
								<div className="flex gap-2 mb-2">
									<FlipBuyButton
										side="YES"
										price={typeof yesFee === "number" ? yesFee : 0}
										amount={amount}
										setAmount={setAmount}
										selectedSide={selectedSide}
										setSelectedSide={setSelectedSide}
										onConfirm={() => {
											handleBuyYes(market, BigInt(amount));
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
										onConfirm={() => {
											handleBuyNo(market, BigInt(amount));
											setAmount("");
											setSelectedSide(null);
										}}
										className="flex-1 h-12"
										disabled={isEnded}
									/>
								</div>

								{/* 只有在點了 YES / NO 之後才出現 Estimate Cost 區塊 */}
								{selectedSide && (
									<div
										className={`
            mt-2 rounded-xl border-2 p-4 text-center relative overflow-hidden
            min-h-[100px] flex flex-col justify-center items-center shadow-inner
            animate-in slide-in-from-bottom-2 fade-in duration-300
            ${selectedSide === "YES"
												? "bg-emerald-50/80 border-emerald-500/30 text-emerald-900 dark:bg-emerald-950/20 dark:text-emerald-100"
												: "bg-rose-50/80 border-rose-500/30 text-rose-900 dark:bg-rose-950/20 dark:text-rose-100"
											}
          `}
									>
										<div className="w-full">
											<div className="flex items-center justify-center gap-2 mb-1 opacity-70">
												<span className="text-[10px] uppercase tracking-wider font-bold">
													Estimated Cost ({selectedSide})
												</span>
											</div>
											<div className="text-3xl font-bold tracking-tight leading-none mb-1">
												{currentTotal}
												<span className="text-sm font-normal opacity-70 ml-1">
													USDC
												</span>
											</div>
											<div className="text-xs opacity-60 font-mono flex justify-center items-center gap-1">
												<span>{currentFee.toFixed(4)}</span>
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

				{/* 右側：對應這個 market 的聊天室 */}
				{market != undefined && (<div className="h-full flex flex-col gap-4">
					<MarketChatRoom marketId={market.address} />
					<BuyerRankTabs
						marketAddress={market.address}
					/>
				</div>)}
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
