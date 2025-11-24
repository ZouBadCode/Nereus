import { NextRequest, NextResponse } from "next/server";

type ChatMessage = {
  address: string;
  message: string;
  timestamp: string;
};

type MarketChatStore = Record<string, ChatMessage[]>;

// Demo in-memory store (NOT for production, Vercel 會重置)
const marketChats: MarketChatStore = {};

function getMessagesForMarket(marketId: string): ChatMessage[] {
  if (!marketChats[marketId]) {
    marketChats[marketId] = [];
  }
  return marketChats[marketId];
}

export async function GET(
  _req: NextRequest,
  context: { params: Promise<{ marketId: string }> },
) {
  const { marketId } = await context.params; // ⭐ 必須 await
  const messages = getMessagesForMarket(marketId);
  return NextResponse.json({ messages });
}

export async function POST(
  req: NextRequest,
  context: { params: Promise<{ marketId: string }> },
) {
  const { marketId } = await context.params; // ⭐ 必須 await

  const body = await req.json();

  const address = typeof body.address === "string" ? body.address : "";
  const message = typeof body.message === "string" ? body.message : "";

  if (!address || !message) {
    return NextResponse.json(
      { error: "address and message are required" },
      { status: 400 },
    );
  }

  const msg: ChatMessage = {
    address,
    message,
    timestamp: new Date().toISOString(),
  };

  const list = getMessagesForMarket(marketId);
  list.push(msg);

  return NextResponse.json(msg, { status: 201 });
}
