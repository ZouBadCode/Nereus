// components/market/ChatRoom.tsx
"use client";

import React, { useEffect, useRef, useState } from "react";
import { useCurrentAccount } from "@mysten/dapp-kit";
import {
	Card,
	CardHeader,
	CardTitle,
	CardDescription,
	CardContent,
	CardFooter,
} from "@workspace/ui/components/card";
import { ScrollArea } from "@workspace/ui/components/scroll-area";
import { Input } from "@workspace/ui/components/input";
import { Button } from "@workspace/ui/components/button";
import { Avatar, AvatarFallback } from "@workspace/ui/components/avatar";
import { Badge } from "@workspace/ui/components/badge";

type ChatMessage = {
	address: string;
	message: string;
	timestamp: string;
};

type MarketChatRoomProps = {
	marketId: string;
};

export default function MarketChatRoom({ marketId }: MarketChatRoomProps) {
	const account = useCurrentAccount();
	const address = account?.address ?? "";

	const [messages, setMessages] = useState<ChatMessage[]>([]);
	const [input, setInput] = useState("");
	const [isSending, setIsSending] = useState(false);
	const [isLoading, setIsLoading] = useState(true);
	const bottomRef = useRef<HTMLDivElement | null>(null);

	const fetchMessages = async () => {
		try {
			const res = await fetch(`/api/market/${marketId}/chat`, {
				method: "GET",
				cache: "no-store",
			});
			if (!res.ok) return;
			const data = (await res.json()) as { messages: ChatMessage[] };
			setMessages(data.messages ?? []);
		} catch (error) {
			console.error("Failed to fetch chat messages", error);
		} finally {
			setIsLoading(false);
		}
	};

	useEffect(() => {
		fetchMessages();
		const id = setInterval(fetchMessages, 30000);
		return () => clearInterval(id);
	}, [marketId]);

	useEffect(() => {
		if (bottomRef.current) {
			bottomRef.current.scrollIntoView({ behavior: "smooth" });
		}
	}, [messages.length]);

	const handleSend = async () => {
		const trimmed = input.trim();
		if (!trimmed || !address) return;

		setIsSending(true);
		try {
			const res = await fetch(`/api/market/${marketId}/chat`, {
				method: "POST",
				headers: {
					"Content-Type": "application/json",
				},
				body: JSON.stringify({
					address,
					message: trimmed,
				}),
			});

			if (!res.ok) {
				console.error("Failed to send message");
				return;
			}

			const saved = (await res.json()) as ChatMessage;
			setMessages((prev) => [...prev, saved]);
			setInput("");
		} catch (error) {
			console.error("Error sending chat message", error);
		} finally {
			setIsSending(false);
		}
	};

	const handleKeyDown: React.KeyboardEventHandler<HTMLInputElement> = (e) => {
		if (e.key === "Enter" && !e.shiftKey) {
			e.preventDefault();
			handleSend();
		}
	};

	const formatTime = (iso: string) =>
		new Date(iso).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });

	return (
		<Card className="h-full flex flex-col border shadow-sm">
			<CardHeader className="pb-3">
				<div className="flex items-center justify-between gap-2">
					<div>
						<CardTitle className="text-sm font-semibold">
							Market Chat
						</CardTitle>
						<CardDescription className="text-xs">
							Discuss this market with other traders.
						</CardDescription>
					</div>
					<Badge variant="outline" className="text-[10px] font-mono">
						{marketId.slice(0, 4)}...{marketId.slice(-4)}
					</Badge>
				</div>
				<div className="mt-1 text-[11px] text-muted-foreground truncate">
					{address ? (
						<>
							You:{" "}
							<span className="font-mono">
								{address.slice(0, 6)}...{address.slice(-4)}
							</span>
						</>
					) : (
						"Connect Sui wallet to send messages."
					)}
				</div>
			</CardHeader>

			<CardContent className="flex-1 px-0 pt-0 pb-0">
				<ScrollArea className="h-[360px] px-4 py-3">
					{isLoading ? (
						<p className="text-xs text-muted-foreground">
							Loading messages...
						</p>
					) : messages.length === 0 ? (
						<div className="h-full flex flex-col items-center justify-center text-center text-xs text-muted-foreground">
							<p className="mb-1">No messages yet.</p>
							<p>Be the first one to start the discussion.</p>
						</div>
					) : (
						messages.map((msg, idx) => {
							const isSelf = msg.address === address;
							const short = `${msg.address.slice(0, 4)}...${msg.address.slice(
								-4,
							)}`;

							return (
								<div
									key={`${msg.timestamp}-${idx}`}
									className={`mb-3 flex gap-2 ${
										isSelf ? "flex-row-reverse" : "flex-row"
									}`}
								>
									<Avatar className="h-7 w-7">
										<AvatarFallback className="text-[10px]">
											{short.slice(0, 2).toUpperCase()}
										</AvatarFallback>
									</Avatar>
									<div
										className={`max-w-[75%] rounded-2xl px-3 py-2 text-xs shadow-sm ${
											isSelf
												? "bg-primary text-primary-foreground"
												: "bg-muted"
										}`}
									>
										<div className="flex items-center justify-between gap-2 mb-1">
											<span className="font-mono text-[10px] opacity-80">
												{short}
											</span>
											<span className="text-[10px] opacity-70">
												{formatTime(msg.timestamp)}
											</span>
										</div>
										<p className="whitespace-pre-wrap break-words leading-snug">
											{msg.message}
										</p>
									</div>
								</div>
							);
						})
					)}
					<div ref={bottomRef} />
				</ScrollArea>
			</CardContent>

			<CardFooter className="border-t pt-3">
				<div className="flex w-full items-center gap-2">
					<Input
						className="text-xs"
						placeholder={
							address ? "Type a message and press Enter..." : "Connect wallet to chat"
						}
						value={input}
						onChange={(e) => setInput(e.target.value)}
						onKeyDown={handleKeyDown}
						disabled={!address || isSending}
					/>
					<Button
						size="sm"
						className="text-xs px-3"
						onClick={handleSend}
						disabled={!address || !input.trim() || isSending}
					>
						Send
					</Button>
				</div>
			</CardFooter>
		</Card>
	);
}
