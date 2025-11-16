import { Navbar } from "@/components/navbar"
import { MarketGrid } from "@/components/market-grid"
import { storeStore } from "@/store/storeStore";
const { queryMarkets } = storeStore.getState();
export default function Page() {
  queryMarkets();
  return (
    <main className="min-h-svh">
      <Navbar />
      <div className="mx-auto grid max-w-7xl gap-6 pt-6">
        <MarketGrid />
      </div>
    </main>
  )
}
