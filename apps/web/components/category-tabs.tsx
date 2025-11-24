"use client"
import { useMemo, useState } from "react";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@workspace/ui/components/tabs"
// Assuming storeStore is the hook returned by create(...)
import { storeStore } from "@/store/storeStore"; 

export function CategoryTabs({ children }: { children: (active: string) => React.ReactNode }) {
  const [active, setActive] = useState("All")
  const marketList = storeStore((state) => state.marketList);
  const CATEGORIES = useMemo(() => {
    // Define static items
    const all = "All";
    const ended = "Ended";

    if (!marketList || marketList.length === 0) return [all, ended];
    const uniqueCats = [...new Set(marketList.map((m) => m.category).filter(Boolean))];
    
    return [all, ...uniqueCats, ended];
  }, [marketList]); 

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