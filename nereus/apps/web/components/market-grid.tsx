"use client"

import { CategoryTabs } from "./category-tabs"
import { Market, MarketCardLarge, MarketCardMedium, MarketCardSmall } from "./market/market-card"

const MOCK: Market[] = [
  {
    id: "1",
    title: "Will GDP growth be negative in Q3 2025?",
    category: "Economy",
    volume: "$310,434",
    yes: 12,
    no: 88,
  },
  {
    id: "2",
    title: "Fed decision in December? 25bps decrease",
    category: "Economy",
    volume: "$91m",
    yes: 54,
    no: 46,
  },
  {
    id: "3",
    title: "$SOL above $150 by month end?",
    category: "Crypto",
    volume: "$15,679",
    yes: 42,
    no: 58,
  },
  {
    id: "4",
    title: "Super Bowl Champion 2026: Los Angeles?",
    category: "Sports",
    volume: "$529m",
    yes: 11,
    no: 89,
  },
  {
    id: "5",
    title: "House passes disclosure resolution in November?",
    category: "Politics",
    volume: "$268k",
    yes: 91,
    no: 9,
  },
  {
    id: "6",
    title: "Will US gov shutdown happen in 2025?",
    category: "Politics",
    volume: "$12k",
    yes: 26,
    no: 74,
  },
]

export function MarketGrid() {
  return (
    <section className="mx-auto w-full max-w-7xl px-4">
      <CategoryTabs>
        {(active) => (
          <div className="grid grid-cols-1 gap-4 md:grid-cols-12">
            <div className="md:col-span-6">
              <MarketCardLarge m={MOCK[0]} />
            </div>
            <div className="md:col-span-3">
              <MarketCardMedium m={MOCK[1]} />
            </div>
            <div className="md:col-span-3">
              <MarketCardMedium m={MOCK[2]} />
            </div>
            <div className="md:col-span-3">
              <MarketCardSmall m={MOCK[3]} />
            </div>
            <div className="md:col-span-3">
              <MarketCardSmall m={MOCK[4]} />
            </div>
            <div className="md:col-span-3">
              <MarketCardSmall m={MOCK[5]} />
            </div>
            <div className="md:col-span-12">
              {/* Footer bar placeholder matching figma */}
              <div className="rounded-md bg-primary/20 p-3" />
            </div>
          </div>
        )}
      </CategoryTabs>
    </section>
  )
}
