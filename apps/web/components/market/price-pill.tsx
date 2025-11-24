import { Badge } from "@workspace/ui/components/badge"

export function PricePill({ side, price }: { side: "Yes" | "No"; price: number }) {
  const variant = side === "Yes" ? "default" : "secondary" as const
  return (
    <Badge variant={variant} className="min-w-14 justify-center">
      {side} {price}%
    </Badge>
  )
}
