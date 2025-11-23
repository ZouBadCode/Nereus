import { Card, CardContent, CardHeader, CardTitle } from "@workspace/ui/components/card"
import { Separator } from "@workspace/ui/components/separator"
import { Button } from "@workspace/ui/components/button"
import { PricePill } from "./price-pill"
import { Sparkline } from "./sparkline"
import { Stat } from "./stat"
import { Market } from "@/store/storeStore"
import { useBuyYes } from "@/hooks/useBuyYes"
import { useBuyNo } from "@/hooks/useBuyNo"
import { FlipBuyButton } from "./flip-buy-button"
import Link from "next/link"
import { useState } from "react"
import { cn } from "@workspace/ui/lib/utils"

// Utility function to format countdown from timestamp
function formatCountdown(endTime: number): string {
  const now = Math.floor(Date.now())
  const timeLeft = endTime - now

  if (timeLeft <= 0) {
    return "Ended"
  }

  const days = Math.floor(timeLeft / (24 * 60 * 60 * 1000))
  const hours = Math.floor((timeLeft % (24 * 60 * 60 * 1000)) / (60 * 60 * 1000))
  const minutes = Math.floor((timeLeft % (60 * 60 * 1000)) / (60 * 1000))

  if (days > 0) {
    return `${days}d ${hours}h`
  } else if (hours > 0) {
    return `${hours}h ${minutes}m`
  } else {
    return `${minutes}m`
  }
}

// Helper function to calculate percentage
function calculatePercentage(value: number, total: number): number {
  if (total === 0) return 0
  return Math.round((value / total) * 100)
}

interface MarketCardProps {
  m: Market
  onMarketClick?: (market: Market) => void
}

// 1. Large List Card (Detailed View)
export function MarketCard({ m, onMarketClick }: MarketCardProps) {
  const { handleBuyYes } = useBuyYes()
  const { handleBuyNo } = useBuyNo()

  // Lifted state for controlled inputs and instant calculation
  const [amount, setAmount] = useState("");
  const [selectedSide, setSelectedSide] = useState<'YES' | 'NO' | null>(null);

  const total = m.yes + m.no
  const yesPercentage = calculatePercentage(m.yes, total)
  const noPercentage = calculatePercentage(m.no, total)
  const countdown = formatCountdown(m.end_time)
  const isEnded = countdown === "Ended"

  // Parse fees, default to 0 if undefined
  const yesFee = m.yesprice ? Number(m.yesprice) / 1e9 : 0
  const noFee = m.noprice ? Number(m.noprice) / 1e9 : 0

  // Calculation Logic
  const currentFee = selectedSide === 'YES' ? yesFee : selectedSide === 'NO' ? noFee : 0;

  const parsedAmount = parseFloat(amount);
  const isValidAmount = !isNaN(parsedAmount) && parsedAmount > 0;
  const currentTotal = (currentFee && isValidAmount)
    ? (currentFee * parsedAmount).toFixed(4)
    : "0.0000";

  // Reset handler
  const handleConfirm = (side: 'YES' | 'NO', val: bigint) => {
    if (side === 'YES') handleBuyYes(m, val);
    else handleBuyNo(m, val);

    setAmount("");
    setSelectedSide(null);
  };

  return (
    <Card className="overflow-hidden h-full flex flex-col shadow-sm hover:shadow-md transition-all">
      <CardHeader className="p-4 pb-2">
        <div className="flex justify-between items-start gap-4">
          <CardTitle
            className="text-lg cursor-pointer hover:text-primary transition-colors break-words hyphens-auto leading-tight"
            onClick={() => onMarketClick?.(m)}
          >
            {m.topic}
          </CardTitle>
        </div>
        <p className="text-sm text-gray-400 line-clamp-2 break-words mt-1">
          {m.description}
        </p>
      </CardHeader>

      <CardContent className="grid gap-4 p-4 pt-2 md:grid-cols-5 flex-1">
        {/* Chart Section */}
        <div className="col-span-3 rounded-lg bg-muted/30 border p-3 min-w-0 flex items-center justify-center">
          <div className="w-full">
            <Sparkline width={520} height={140} className="w-full h-auto" />
          </div>
        </div>

        {/* Stats & Action Section */}
        <div className="col-span-2 flex flex-col justify-between min-w-0 gap-2">
          <div className="space-y-3">
            <div className="flex items-center gap-2 flex-wrap">
              <PricePill side="Yes" price={yesPercentage} />
              <PricePill side="No" price={noPercentage} />
            </div>
            <Separator />
            <div className="grid grid-cols-2 gap-x-2 gap-y-1">
              <Stat label="Ends in" value={countdown} />
              <Stat label="Pool" value={`${(m.balance / 1e9).toFixed(2)} U`} />
              <div className="col-span-2">
                <Stat
                  label="Current Price"
                  value={`Y: ${yesFee.toFixed(3)} | N: ${noFee.toFixed(3)}`}
                />
              </div>
            </div>
          </div>

          <div className="mt-auto pt-2 space-y-3">
            {/* Buttons Row */}
            <div className="flex gap-2">
              <FlipBuyButton
                side="YES"
                price={yesFee}
                amount={amount}
                setAmount={setAmount}
                selectedSide={selectedSide}
                setSelectedSide={setSelectedSide}
                onConfirm={(val) => handleConfirm('YES', val)}
                className={`flex-1 min-w-[80px] ${isEnded ? "hidden" : ""}`}
              />
              <FlipBuyButton
                side="NO"
                price={noFee}
                amount={amount}
                setAmount={setAmount}
                selectedSide={selectedSide}
                setSelectedSide={setSelectedSide}
                onConfirm={(val) => handleConfirm('NO', val)}
                className={`flex-1 min-w-[80px] ${isEnded ? "hidden" : ""}`}
              />
            </div>

            {/* ⬇️ 點 YES / NO 後才出現的 Estimate Cost 區塊 */}
            {!isEnded && (
              <div
                className="relative overflow-hidden h-[120px] rounded-xl border-2 shadow-inner"
                // base bg
                style={{
                  background:
                    selectedSide === "YES"
                      ? "rgba(16, 185, 129, 0.08)"       // emerald-500/20
                      : selectedSide === "NO"
                        ? "rgba(244, 63, 94, 0.08)"        // rose-500/20
                        : "rgba(255,255,255,0.05)",        // muted
                  borderColor:
                    selectedSide === "YES"
                      ? "rgba(16, 185, 129, 0.3)"
                      : selectedSide === "NO"
                        ? "rgba(244, 63, 94, 0.3)"
                        : "rgba(255,255,255,0.1)",
                }}
              >
                {/* 內容滑入層 */}
                <div
                  className={cn(
                    "absolute inset-0 flex flex-col items-center justify-center transition-transform duration-300",
                    selectedSide
                      ? "translate-y-0 opacity-100"
                      : "translate-y-full opacity-0"
                  )}
                >
                  {selectedSide && (
                    <>
                      <span className="text-[10px] uppercase tracking-wider font-bold opacity-70">
                        Estimated Cost ({selectedSide})
                      </span>
                      <div className="text-3xl font-bold leading-none">
                        {currentTotal}
                        <span className="text-sm ml-1 opacity-70">USDC</span>
                      </div>
                      <div className="text-xs opacity-60 font-mono">
                        {currentFee.toFixed(4)} × {isValidAmount ? parsedAmount : 0}
                      </div>
                    </>
                  )}
                </div>

                {/* 🔹 Placeholder 層，避免初次出現位置跳動 */}
                {!selectedSide && (
                  <div className="absolute inset-0 flex flex-col items-center justify-center text-muted-foreground text-sm opacity-75">
                    <span>Estimate Cost</span>
                    <span className="text-xs opacity-60">Select YES or NO</span>
                  </div>
                )}
              </div>
            )}

            <Link href={`/market?id=${m.address}`}>
              <Button variant="outline" className="w-full" size="sm">
                View Details
              </Button>
            </Link>
          </div>
        </div>
      </CardContent>
    </Card>
  )
}

/* 下面兩個元件維持原本的邏輯 */

export function MarketCardGrid({ m, onMarketClick }: MarketCardProps) {
  const { handleBuyYes } = useBuyYes()
  const { handleBuyNo } = useBuyNo()

  const total = m.yes + m.no
  const yesPercentage = calculatePercentage(m.yes, total)
  const noPercentage = calculatePercentage(m.no, total)
  const countdown = formatCountdown(m.end_time)
  const isEnded = countdown === "Ended"

  const yesFee = m.yesprice ? Number(m.yesprice) / 1e9 : undefined
  const noFee = m.noprice ? Number(m.noprice) / 1e9 : undefined

  return (
    <Card className="cursor-pointer hover:shadow-md transition-shadow flex flex-col h-full">
      <CardHeader className="pb-2">
        <CardTitle
          className="line-clamp-2 text-base break-words hyphens-auto leading-snug"
          onClick={() => onMarketClick?.(m)}
        >
          {m.topic}
        </CardTitle>
      </CardHeader>

      <CardContent className="space-y-3 flex-1 flex flex-col">
        <div className="w-full overflow-hidden">
          <Sparkline width={300} height={70} className="w-full h-auto" />
        </div>

        <div className="grid grid-cols-2 gap-3 mt-auto">
          <div className="flex flex-col gap-2">
            <div className="flex justify-center">
              <PricePill side="Yes" price={yesPercentage} />
            </div>
            {!isEnded && (
              <FlipBuyButton
                side="YES"
                price={yesFee ?? 0}
                onConfirm={(amount) => handleBuyYes(m, amount)}
                className="w-full text-xs h-9"
              />
            )}
          </div>

          <div className="flex flex-col gap-2">
            <div className="flex justify-center">
              <PricePill side="No" price={noPercentage} />
            </div>
            {!isEnded && (
              <FlipBuyButton
                side="NO"
                price={noFee ?? 0}
                onConfirm={(amount) => handleBuyNo(m, amount)}
                className="w-full text-xs h-9"
              />
            )}
          </div>
        </div>

        <div className="flex justify-between items-center pt-2 border-t text-xs">
          <Stat label="Ends" value={countdown} />
          <Stat label="Fee" value={`Y:${yesFee?.toFixed(2) ?? "-"} N:${noFee?.toFixed(2) ?? "-"}`} />
        </div>

        <Link href={`/market?id=${m.address}`}>
          <Button variant="outline" className="w-full" size="sm">
            View Details
          </Button>
        </Link>
      </CardContent>
    </Card>
  )
}

export function MarketCardSmall({ m, onMarketClick }: MarketCardProps) {
  const total = m.yes + m.no
  const yesPercentage = calculatePercentage(m.yes, total)
  const noPercentage = calculatePercentage(m.no, total)
  const countdown = formatCountdown(m.end_time)

  const yesFee = m.yesprice ? Number(m.yesprice) / 1e9 : undefined
  const noFee = m.noprice ? Number(m.noprice) / 1e9 : undefined

  return (
    <Card
      className="cursor-pointer hover:shadow-md transition-shadow w-full"
      onClick={() => onMarketClick?.(m)}
    >
      <CardHeader className="pb-2 p-3">
        <CardTitle className="line-clamp-2 text-sm leading-tight break-words">
          {m.topic}
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-2 p-3 pt-0">
        <div className="flex items-center justify-between gap-2">
          <PricePill side="Yes" price={yesPercentage} />
          <PricePill side="No" price={noPercentage} />
        </div>
        <div className="flex flex-col gap-1 text-xs text-muted-foreground">
          <div className="flex justify-between">
            <span>Ends:</span>
            <span className="font-medium text-foreground">{countdown}</span>
          </div>
          <div className="flex justify-between">
            <span>Fee:</span>
            <span className="font-medium text-foreground truncate ml-2">
              Y:{yesFee?.toFixed(2) ?? "-"} N:{noFee?.toFixed(2) ?? "-"}
            </span>
          </div>
        </div>
        <Link href={`/market?id=${m.address}`}>
          <Button variant="outline" className="w-full mt-2" size="sm">
            View Details
          </Button>
        </Link>
      </CardContent>
    </Card>
  )
}
