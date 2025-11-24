import React from "react";
import { X, ExternalLink, Clock, Database, Wallet } from "lucide-react"; // 假設你有 lucide-react 圖標
import { Button } from "@workspace/ui/components/button";
import { Separator } from "@workspace/ui/components/separator";
import { PricePill } from "../market/price-pill";
import { Sparkline } from "../market/sparkline";
import { storeStore } from "@/store/storeStore";
import { useBuyYes } from "@/hooks/useBuyYes";
import { useBuyNo } from "@/hooks/useBuyNo";
import { FlipBuyButton } from "../market/flip-buy-button";

// 輔助：計算百分比
function calculatePercentage(value: number, total: number): number {
  if (total === 0) return 0;
  return Math.round((value / total) * 100);
}

// 輔助：格式化時間 (如果沒有 date-fns，可以用這個簡單版)
const formatDate = (ts: number) => new Date(ts ).toLocaleString();

export function MarketDetailSidebar() {

  const { selectedMarket, setSelectedMarket } = storeStore();
  const { handleBuyYes } = useBuyYes();
  const { handleBuyNo } = useBuyNo();
  const [amount, setAmount] = React.useState("");
  const [selectedSide, setSelectedSide] = React.useState<'YES' | 'NO' | null>(null);

  // 當沒有選中時，我們不 render null，而是透過 CSS class 把它移出畫面
  // 這樣可以保有 transition 動畫效果
  const isOpen = !!selectedMarket;
  const m = selectedMarket;

  // 關閉 Sidebar 的函式
  const handleClose = () => setSelectedMarket(null);

  // 如果尚未選取任何東西且是第一次渲染，可能會報錯，所以做個安全檢查
  if (!m && !isOpen) return null;

  const total = m ? m.yes + m.no : 0;
  const yesPercentage = m ? calculatePercentage(m.yes, total) : 0;
  const noPercentage = m ? calculatePercentage(m.no, total) : 0;
  const yesFee = m?.yesprice ? Number(m.yesprice) / 1e9 : 0;
  const noFee = m?.noprice ? Number(m.noprice) / 1e9 : 0;

  const now = Math.floor(Date.now() / 1000);
  const isEnded = m ? m.end_time <= now : false;

  // 計算區塊
  const currentFee = selectedSide === 'YES' ? yesFee : selectedSide === 'NO' ? noFee : 0;
  const parsedAmount = parseFloat(amount);
  const isValidAmount = !isNaN(parsedAmount) && parsedAmount > 0;
  const currentTotal = (currentFee && isValidAmount)
    ? (currentFee * parsedAmount).toFixed(4)
    : "0.0000";

  // 確認購買
  const handleConfirm = () => {
    if (!m || !selectedSide || !isValidAmount) return;
    const val = BigInt(Math.floor(parsedAmount * 1e9));
    if (selectedSide === 'YES') handleBuyYes(m, val);
    else handleBuyNo(m, val);
    setAmount("");
    setSelectedSide(null);
  };

  return (
    <>
      {/* 1. 背景遮罩 (Backdrop) */}
      {/* 點擊背景區域會關閉 Sidebar */}
      <div
        className={`fixed inset-0 z-40 bg-black/50 transition-opacity duration-300 backdrop-blur-sm ${
          isOpen ? "opacity-100 pointer-events-auto" : "opacity-0 pointer-events-none"
        }`}
        onClick={handleClose}
      />

      {/* 2. 滑出式面板 (Sidebar) */}
      <div
        className={`fixed top-0 right-0 z-50 h-full w-full md:w-1/2 bg-background shadow-2xl transition-transform duration-300 ease-in-out border-l ${
          isOpen ? "translate-x-0" : "translate-x-full"
        }`}
        onClick={(e) => e.stopPropagation()} // 防止點擊面板內部時觸發背景的關閉事件
      >
        {m && (
          <div className="flex flex-col h-full">
            {/* Header */}
            <div className="flex items-start justify-between p-6 border-b">
              <div className="space-y-1">
                <h2 className="text-2xl font-bold leading-tight">{m.topic}</h2>
                <div className="flex items-center gap-2 text-sm text-muted-foreground">
                   <span className="bg-muted px-2 py-0.5 rounded text-xs font-mono">ID: {m.address.slice(0, 6)}...{m.address.slice(-4)}</span>
                </div>
              </div>
              <Button variant="ghost" size="icon" onClick={handleClose}>
                <X className="h-5 w-5" />
              </Button>
            </div>

            {/* Scrollable Content */}
            <div className="flex-1 overflow-y-auto p-6 space-y-6">
              {/* 主要圖表區 - 比 Card 更大 */}
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

              {/* 詳細描述 */}
              <div className="space-y-2">
                <h3 className="font-semibold text-lg">Description</h3>
                <p className="text-muted-foreground leading-relaxed">
                  {m.description}
                </p>
              </div>

              <Separator />

              {/* 詳細數據 Grid */}
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div className="space-y-1">
                  <div className="flex items-center gap-2 text-sm text-muted-foreground">
                    <Clock className="h-4 w-4" /> Start Time
                  </div>
                  <p className="font-medium">{formatDate(m.start_time)}</p>
                </div>
                <div className="space-y-1">
                  <div className="flex items-center gap-2 text-sm text-muted-foreground">
                    <Clock className="h-4 w-4" /> End Time
                  </div>
                  <p className="font-medium">{formatDate(m.end_time)}</p>
                </div>
                
                <div className="space-y-1">
                   <div className="flex items-center gap-2 text-sm text-muted-foreground">
                    <Wallet className="h-4 w-4" /> Pool Balance
                  </div>
                  <p className="font-medium">{m.balance/1e9} USDC</p>
                </div>

                <div className="space-y-1">
                   <div className="flex items-center gap-2 text-sm text-muted-foreground">
                    <Database className="h-4 w-4" /> Oracle Config
                  </div>
                  <p className="font-medium truncate" title={m.oracle_config}>
                    {m.oracle_config}
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
            </div>


            {/* Footer Actions + Estimate Cost */}
            <div className="p-6 border-t bg-muted/10 mt-auto">
              {!isEnded && (
                <>
                  {/* Estimate Cost Block */}
                  <div
                    className={`rounded-xl border-2 p-4 text-center transition-all duration-300 relative overflow-hidden min-h-[100px] flex flex-col justify-center items-center shadow-inner mb-4
                      ${!selectedSide ? "bg-muted/20 border-dashed border-muted-foreground/20 text-muted-foreground" : ""}
                      ${selectedSide === 'YES' ? "bg-emerald-50/80 border-emerald-500/30 text-emerald-900 dark:bg-emerald-950/20 dark:text-emerald-100" : ""}
                      ${selectedSide === 'NO' ? "bg-rose-50/80 border-rose-500/30 text-rose-900 dark:bg-rose-950/20 dark:text-rose-100" : ""}
                    `}
                  >
                    {!selectedSide ? (
                      <div className="flex flex-col items-center gap-1 animate-in fade-in duration-300">
                        <span className="text-sm font-medium">Estimate Cost</span>
                        <span className="text-xs opacity-70">Select YES or NO to calculate</span>
                      </div>
                    ) : (
                      <div className="w-full animate-in slide-in-from-bottom-2 fade-in duration-200">
                        <div className="flex items-center justify-center gap-2 mb-1 opacity-70">
                          <span className="text-[10px] uppercase tracking-wider font-bold">
                            Estimated Cost ({selectedSide})
                          </span>
                        </div>
                        <div className="text-3xl font-bold tracking-tight leading-none mb-1">
                          {currentTotal}
                          <span className="text-sm font-normal opacity-70 ml-1">USDC</span>
                        </div>
                        <div className="text-xs opacity-60 font-mono flex justify-center items-center gap-1">
                          <span>{currentFee.toFixed(4)}</span>
                          <span>×</span>
                          <span>{isValidAmount ? parsedAmount : 0}</span>
                        </div>
                      </div>
                    )}
                  </div>

                  {/* Input & Buttons Row */}
                  <div className="flex gap-2 mb-2">
                    <input
                      type="number"
                      min="0"
                      step="any"
                      value={amount}
                      onChange={e => setAmount(e.target.value)}
                      placeholder="Enter amount"
                      className="flex-1 px-3 py-2 border rounded focus:outline-none focus:ring text-base font-mono"
                      disabled={isEnded}
                    />
                    <Button
                      variant={selectedSide === 'YES' ? "default" : "outline"}
                      className="flex-1 h-12"
                      onClick={() => setSelectedSide('YES')}
                      disabled={isEnded}
                    >YES</Button>
                    <Button
                      variant={selectedSide === 'NO' ? "default" : "outline"}
                      className="flex-1 h-12"
                      onClick={() => setSelectedSide('NO')}
                      disabled={isEnded}
                    >NO</Button>
                  </div>

                  <Button
                    className="w-full h-12 mt-2"
                    onClick={handleConfirm}
                    disabled={!selectedSide || !isValidAmount || isEnded}
                  >Confirm</Button>
                </>
              )}
            </div>
            
          </div>
        )}
      </div>
    </>
  );
}