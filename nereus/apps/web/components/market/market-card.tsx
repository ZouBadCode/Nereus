import { Card, CardContent, CardHeader, CardTitle } from "@workspace/ui/components/card"
import { Button } from "@workspace/ui/components/button"
import { Separator } from "@workspace/ui/components/separator"
import { PricePill } from "./price-pill"
import { Sparkline } from "./sparkline"
import { Stat } from "./stat"

export type Market = {
  id: string
  title: string
  category: string
  volume: string
  yes: number
  no: number
}

export type MarketCardProps = {
  m: Market
  onMarketClick?: (market: Market, side?: "yes" | "no") => void
}

export function MarketCardLarge({ m, onMarketClick }: MarketCardProps) {
  return (
    <Card className="overflow-hidden">
      <CardHeader className="p-4">
        <CardTitle 
          className="text-lg cursor-pointer hover:text-primary transition-colors"
          onClick={() => onMarketClick?.(m)}
        >
          {m.title}
        </CardTitle>
      </CardHeader>
      <CardContent className="grid gap-3 p-4 pt-0 md:grid-cols-5">
        <div className="col-span-3 rounded-md bg-muted/40 p-2">
          <Sparkline width={520} height={120} />
        </div>
        <div className="col-span-2 flex flex-col gap-3">
          <div className="flex items-center gap-2">
            <PricePill side="Yes" price={m.yes} />
            <PricePill side="No" price={m.no} />
          </div>
          <Separator />
          <Stat label="Volume" value={m.volume} />
          <Stat label="Category" value={m.category} />
          <div className="mt-auto flex gap-2">
            <Button 
              className="flex-1"
              onClick={() => onMarketClick?.(m, "yes")}
            >
              Buy Yes
            </Button>
            <Button 
              variant="outline" 
              className="flex-1"
              onClick={() => onMarketClick?.(m, "no")}
            >
              Buy No
            </Button>
          </div>
        </div>
      </CardContent>
    </Card>
  )
}

export function MarketCardMedium({ m, onMarketClick }: MarketCardProps) {
  return (
    <Card className="cursor-pointer hover:shadow-md transition-shadow" onClick={() => onMarketClick?.(m)}>
      <CardHeader className="pb-2">
        <CardTitle className="line-clamp-2 text-base">{m.title}</CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        <Sparkline width={300} height={70} />
        <div className="flex items-center justify-between">
          <PricePill side="Yes" price={m.yes} />
          <PricePill side="No" price={m.no} />
        </div>
        <Stat label="Vol" value={m.volume} />
      </CardContent>
    </Card>
  )
}

export function MarketCardSmall({ m, onMarketClick }: MarketCardProps) {
  return (
    <Card className="cursor-pointer hover:shadow-md transition-shadow" onClick={() => onMarketClick?.(m)}>
      <CardHeader className="pb-2">
        <CardTitle className="line-clamp-2 text-sm">{m.title}</CardTitle>
      </CardHeader>
      <CardContent className="space-y-2">
        <div className="flex items-center justify-between">
          <PricePill side="Yes" price={m.yes} />
          <PricePill side="No" price={m.no} />
        </div>
        <Stat label="Vol" value={m.volume} />
      </CardContent>
    </Card>
  )
}
