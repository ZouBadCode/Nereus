
// BuyerRankTabs.tsx
import React, { useEffect, useState } from "react";
import { Tabs, TabsList, TabsTrigger, TabsContent } from "@workspace/ui/components/tabs";
import { Card, CardHeader, CardTitle, CardContent } from "@workspace/ui/components/card";
import { Avatar, AvatarFallback } from "@workspace/ui/components/avatar";
import { Badge } from "@workspace/ui/components/badge";
import { Skeleton } from "@workspace/ui/components/skeleton";
import { storeStore } from "../../store/storeStore";

type Buyer = {
	address: string;
	buyAmount: number;
	lastBuyTime: string;
	transactionCount: number;
};

interface BuyerRankProps {
	marketAddress: string;
}

// --- 輔助函式 ---
function formatAddress(addr: string) {
	return addr.length > 10 ? `${addr.slice(0, 6)}...${addr.slice(-4)}` : addr;
}

function formatTime(iso: string) {
	const d = new Date(iso);
	return d.toLocaleString([], { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });
}

function formatNumber(num: number) {
	return num/1e9
}

// --- 列表子元件 ---
function BuyerList({ buyers, isLoading, side }: { buyers: Buyer[], isLoading: boolean, side: string }) {
	if (isLoading) {
		return (
			<div className="space-y-3">
				{[1, 2, 3].map((i) => (
					<div key={i} className="flex items-center gap-3">
						<Skeleton className="h-8 w-8 rounded-full" />
						<div className="space-y-1 flex-1">
							<Skeleton className="h-3 w-24" />
							<Skeleton className="h-2 w-16" />
						</div>
					</div>
				))}
			</div>
		);
	}

	if (buyers.length === 0) {
		return <div className="text-center py-6 text-muted-foreground text-sm">No {side} buyers yet.</div>;
	}

	return (
		<div className="flex flex-col gap-2">
			{buyers.slice(0, 10).map((b, idx) => (
				<div key={b.address} className="flex items-center gap-3 rounded-lg border px-3 py-2 bg-card hover:bg-accent/50 transition-colors">
					<span className={`font-mono text-xs w-4 text-center ${idx < 3 ? "text-yellow-500 font-bold" : "text-muted-foreground"}`}>
						{idx + 1}
					</span>
					<Avatar className="size-8 border">
						<AvatarFallback className="text-[10px] bg-muted text-muted-foreground">
							{b.address.slice(2, 4).toUpperCase()}
						</AvatarFallback>
					</Avatar>
					<div className="flex-1 min-w-0">
						<div className="font-mono text-xs font-medium truncate text-foreground">
							{formatAddress(b.address)}
						</div>
						<div className="text-[10px] text-muted-foreground flex items-center gap-1">
							<span>{formatTime(b.lastBuyTime)}</span>
							<span>•</span>
							<span>{b.transactionCount} txns</span>
						</div>
					</div>
					<div className="flex flex-col items-end">
						<Badge variant={side === "Yes" ? "default" : "secondary"} className="font-mono text-[11px] h-5">
							{formatNumber(b.buyAmount)}
						</Badge>
					</div>
				</div>
			))}
		</div>
	);
}

// --- 主元件 ---
export default function BuyerRankTabs({ marketAddress }: BuyerRankProps) {
	const [yesBuyers, setYesBuyers] = useState<Buyer[]>([]);
	const [noBuyers, setNoBuyers] = useState<Buyer[]>([]);
	const [loading, setLoading] = useState(true);

	useEffect(() => {
		console.log("Fetching buyer rankings for market:", marketAddress);
		const loadData = async () => {
			if (!marketAddress) return;
			setLoading(true);
			try {
				const [yesData, noData] = await Promise.all([
					storeStore.getState().fetchRichMan(marketAddress, "Yes"),
					storeStore.getState().fetchRichMan(marketAddress, "No")
				]);
				setYesBuyers(yesData);
				setNoBuyers(noData);
			} catch (error) {
				console.error("Failed to fetch buyer rankings:", error);
			} finally {
				setLoading(false);
			}
		};
		loadData();
	}, [marketAddress]);

	return (
		<Card className="w-full max-w-md mx-auto shadow-sm">
			<CardHeader className="pb-2 pt-4 px-4">
				<CardTitle className="text-sm font-semibold uppercase tracking-wide text-muted-foreground">
					Market Participants
				</CardTitle>
			</CardHeader>
			<CardContent className="px-4 pb-4">
				<Tabs defaultValue="yes" className="w-full">
					<TabsList className="grid w-full grid-cols-2 mb-3 h-9">
						<TabsTrigger value="yes" className="text-xs data-[state=active]:bg-green-100 data-[state=active]:text-green-700 dark:data-[state=active]:bg-green-900/30 dark:data-[state=active]:text-green-400">
							Yes Holders ({yesBuyers.length})
						</TabsTrigger>
						<TabsTrigger value="no" className="text-xs data-[state=active]:bg-red-100 data-[state=active]:text-red-700 dark:data-[state=active]:bg-red-900/30 dark:data-[state=active]:text-red-400">
							No Holders ({noBuyers.length})
						</TabsTrigger>
					</TabsList>
					<TabsContent value="yes" className="mt-0">
						<BuyerList buyers={yesBuyers} isLoading={loading} side="Yes" />
					</TabsContent>
					<TabsContent value="no" className="mt-0">
						<BuyerList buyers={noBuyers} isLoading={loading} side="No" />
					</TabsContent>
				</Tabs>
			</CardContent>
		</Card>
	);
}
