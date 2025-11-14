"use client"
import * as React from "react"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@workspace/ui/components/tabs"

const CATEGORIES = [
  "All",
  "Politics",
  "Economy",
  "Crypto",
  "Sports",
  "Tech",
]

export function CategoryTabs({ children }: { children: (active: string) => React.ReactNode }) {
  const [active, setActive] = React.useState("All")
  return (
    <Tabs value={active} onValueChange={setActive}>
      <TabsList>
        {CATEGORIES.map((c) => (
          <TabsTrigger key={c} value={c}>
            {c}
          </TabsTrigger>
        ))}
      </TabsList>
      <TabsContent value={active}>{children(active)}</TabsContent>
    </Tabs>
  )
}
