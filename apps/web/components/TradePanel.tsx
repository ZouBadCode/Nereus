import React, { useState, useEffect } from "react";
import { storeStore } from "../store/storeStore";

const SCALE = 10000; // 假設合約的價格精度是 4位數，請依實際情況調整

export default function TradePanel() {
  const { selectedMarket, selectedSide } = storeStore();
  const [inputAmount, setInputAmount] = useState<string>("");
  const [total, setTotal] = useState<number>(0);

  // 取得當前價格
  const getPrice = () => {
    if (!selectedMarket || !selectedSide) return 0;
    const priceBigInt = selectedSide === "Yes" ? selectedMarket.yesprice : selectedMarket.noprice;
    // 將 BigInt 轉為數字並正規化 (例如 5000 -> 0.5)
    return priceBigInt ? Number(priceBigInt) / SCALE : 0;
  };

  const currentPrice = getPrice();

  // 當輸入改變時計算 Total
  // 公式: Input * Price = Total
  useEffect(() => {
    const amount = parseFloat(inputAmount);
    if (!isNaN(amount)) {
      setTotal(amount * currentPrice);
    } else {
      setTotal(0);
    }
  }, [inputAmount, currentPrice]);

  if (!selectedMarket || !selectedSide) {
    return <div className="p-4 border text-gray-500">Select a market to start trading</div>;
  }

  return (
    <div className="mt-4 border-2 border-black p-4 w-full max-w-md mx-auto bg-white">
      <h3 className="text-lg font-bold mb-2">
        I'm buying: <span className="text-blue-600">{selectedMarket.topic}</span>
      </h3>
      {/* 手繪圖中的框框區域 */}
      <div className="flex items-center justify-between border border-gray-400 p-4 text-xl font-mono">
        {/* Input 區域 */}
        <input
          type="number"
          value={inputAmount}
          onChange={(e) => setInputAmount(e.target.value)}
          placeholder="Input"
          className="w-24 outline-none border-b border-gray-300 focus:border-black text-center"
        />
        {/* X 符號 */}
        <span className="mx-2">x</span>
        {/* Price 顯示 (Yes/No) */}
        <div className="flex flex-col items-center">
          <span className={selectedSide === "Yes" ? "text-green-600" : "text-red-600"}>
            {selectedSide}
          </span>
          <span className="text-sm text-gray-500">
            ({currentPrice.toFixed(2)})
          </span>
        </div>
        {/* = 符號 */}
        <span className="mx-2">=</span>
        {/* Total 結果 */}
        <div className="font-bold">
          {total.toFixed(2)} <span className="text-xs font-normal">USDC</span>
        </div>
      </div>
      <button className="w-full mt-4 bg-black text-white py-2 hover:bg-gray-800 transition">
        Confirm Trade
      </button>
    </div>
  );
}
