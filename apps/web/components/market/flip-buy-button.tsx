import React, { useRef, useEffect } from 'react';
import { TrendingUp, TrendingDown, Check, X } from 'lucide-react';

interface FlipBuyButtonProps {
  side: "YES" | "NO";
  price: number;
  onConfirm: (amount: bigint) => void;
  className?: string;
  // 新增受控組件所需的 props
  amount?: string;
  setAmount?: (val: string) => void;
  selectedSide?: 'YES' | 'NO' | null;
  setSelectedSide?: (side: 'YES' | 'NO' | null) => void;
}

export const FlipBuyButton = ({ 
  side, 
  price, 
  onConfirm, 
  className,
  amount = "",           // 預設值，防止未傳入時報錯
  setAmount,
  selectedSide,
  setSelectedSide
}: FlipBuyButtonProps) => {
  const inputRef = useRef<HTMLInputElement>(null);

  // 判斷是否翻轉：如果父組件告訴我是這個 side 被選中，我就翻轉
  // 如果沒有傳入 selectedSide (舊用法)，則不翻轉 (或保留內部 state，但這裡為了配合 MarketCard 全改為受控)
  const isFlipped = selectedSide === side;

  // 樣式設定：根據 YES/NO 決定顏色
const isYes = side === "YES";

  const baseColor = isYes ? "bg-teal-600" : "bg-rose-700";
  
  const hoverColor = isYes ? "hover:bg-teal-500" : "hover:bg-rose-600";

  const gradient = isYes 
    ? "from-teal-600 to-cyan-700 shadow-teal-900/20" 
    : "from-rose-700 to-red-900 shadow-rose-900/20";

  // 自動聚焦邏輯
  useEffect(() => {
    if (isFlipped && inputRef.current) {
      // 延遲一點點等待動畫
      setTimeout(() => inputRef.current?.focus(), 300);
    }
  }, [isFlipped]);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!amount || isNaN(Number(amount)) || Number(amount) <= 0) return;

    try {
      const val = BigInt(Math.floor(Number(amount))); 
      onConfirm(val);
      // 注意：重置狀態的邏輯通常由父組件的 onConfirm 處理
    } catch (error) {
      console.error("BigInt Conversion Error", error);
    }
  };

  const handleCancel = (e: React.MouseEvent) => {
    e.stopPropagation();
    // 通知父組件取消選擇
    if (setSelectedSide) setSelectedSide(null);
    if (setAmount) setAmount("");
  };

  const handleFlip = (e: React.MouseEvent) => {
    e.stopPropagation();
    // 通知父組件選擇了我
    if (setSelectedSide) setSelectedSide(side);
  };

  // 處理輸入變更
  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (setAmount) {
        setAmount(e.target.value);
    }
  };

  return (
    <div className={`relative h-10 [perspective:1000px] group ${className}`} onClick={(e) => e.stopPropagation()}>
      <div 
        className={`
          relative w-full h-full transition-all duration-500 
          [transform-style:preserve-3d]
          ${isFlipped ? '[transform:rotateX(180deg)]' : ''}
        `}
      >
        
        {/* --- 正面 (Front): 顯示價格與方向 --- */}
        <div className="absolute inset-0 w-full h-full [backface-visibility:hidden]">
          <button
            onClick={handleFlip}
            className={`
              w-full h-full rounded-md shadow-sm bg-gradient-to-r ${gradient}
              flex items-center justify-between px-3 text-white font-bold text-sm
              hover:scale-[1.02] active:scale-[0.98] transition-all duration-200
            `}
          >
            <div className="flex items-center gap-1">
              {isYes ? <TrendingUp className="w-4 h-4" /> : <TrendingDown className="w-4 h-4" />}
              <span>{side}</span>
            </div>
            <span className="text-white/90 text-xs bg-black/20 px-1.5 py-0.5 rounded">
              ${price}
            </span>
          </button>
        </div>

        {/* --- 背面 (Back): 輸入金額 --- */}
        <div 
          className="absolute inset-0 w-full h-full [transform:rotateX(180deg)] [backface-visibility:hidden]
                     bg-slate-800 rounded-md shadow-xl border border-slate-700 overflow-hidden flex"
        >
          <form onSubmit={handleSubmit} className="flex w-full h-full">
            {/* 取消按鈕 */}
            <button
              type="button"
              onClick={handleCancel}
              className="px-2 text-slate-400 hover:text-white hover:bg-slate-700 transition-colors"
            >
              <X className="w-3 h-3" />
            </button>

            {/* 金額輸入框 */}
            <div className="flex-1 relative flex items-center min-w-0">
              <input
                ref={inputRef}
                type="number"
                step="1"
                min="1"
                value={amount}
                onChange={handleInputChange}
                placeholder="#"
                className="w-full h-full bg-transparent px-1 text-white placeholder-slate-500 outline-none text-xs font-mono text-center"
              />
            </div>

            {/* 確認按鈕 (動態顏色) */}
            <button
              type="submit"
              disabled={!amount}
              className={`
                px-2 text-white font-medium transition-colors flex items-center justify-center
                disabled:opacity-50 disabled:cursor-not-allowed
                ${baseColor} ${hoverColor}
              `}
            >
              <Check className="w-4 h-4" />
            </button>
          </form>
        </div>

      </div>
    </div>
  );
};