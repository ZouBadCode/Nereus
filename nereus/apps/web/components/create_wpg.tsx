"use client";

import React, { useState } from "react";
import { Card } from "@workspace/ui/components/card";
import { Button } from "@workspace/ui/components/button";
import { Input } from "@workspace/ui/components/input";
import { Label } from "@workspace/ui/components/label";
import { Textarea } from "@workspace/ui/components/textarea";
import { Badge } from "@workspace/ui/components/badge";
import { Separator } from "@workspace/ui/components/separator";
import { 
    CalendarIcon, 
    Tag, 
    Layers, 
    FileText, 
    Code, 
    Bot, 
    ImageIcon,
    CheckCircle2
} from "lucide-react";
import { WalrusCodeUploader } from "./walrus/walrus-code-uploader";
import { WalrusPromptUploader } from "./walrus/walrus-prompt-uploader";
import type { WalrusUploadResult } from "@/store/move/walrus/walrusRelay";
import { useCurrentAccount, useSignAndExecuteTransaction, useSuiClient } from "@mysten/dapp-kit";
import { createMarketTx } from "@/store/move/create";
import { createMarketTx as createConfigTx } from "@/store/move/create_config";
import { Transaction } from "@mysten/sui/transactions";
import { sealClient } from "@/utils/sealClient";
import { SealApiKeyUploader } from "./walrus/seal-api-uploader";
import { base } from "@/store/move/package";
type Step = 0 | 1 | 2 | 3 | 4;

interface Template {
	id: string;
	title: string;
	description: string;
	category: string;
	rules: string;
	marketRules: string;
	imageUrl?: string;
	tags: string[];
	resolutionType: "ai" | "code";
	aiPrompt?: string;
}

interface FormState {
	selectedTemplate?: Template;
	name: string;
	rules: string;
	marketRules: string;
	imageUrl: string;
	category: string;
	tags: string;
	endDate: string;
	endTime: string;
	resolutionType: "ai" | "code" | "";
	aiPrompt: string;
	aiPromptUploadResult: WalrusUploadResult | null;
	// Store the actual user-entered content as strings for retrieval
	userEnteredPrompt: string; // The actual prompt text the user entered
	userEnteredCode: string; // The actual code text the user entered
	codeUploadResult: WalrusUploadResult | null;
}

const templates: Template[] = [
	{
		id: "market-cap",
		title: "Largest Company by Market Cap",
		description: "#Economy Which company will have the largest market capitalization by December 31, 2025?",
		category: "Business",
		rules: "Resolved by market cap at deadline",
		marketRules: "This market will be resolved based on the publicly traded company with the highest market capitalization at the deadline. Market cap will be determined by the closing stock price multiplied by the number of outstanding shares on the resolution date. Data will be sourced from reliable financial data providers such as Yahoo Finance, Bloomberg, or Reuters.",
		imageUrl: "https://example.com/market-cap.jpg",
		tags: ["stocks", "market-cap", "companies"],
		resolutionType: "ai",
		aiPrompt: "Check the market capitalization of the top 10 publicly traded companies (Apple, Microsoft, Google/Alphabet, Amazon, Tesla, etc.) using reliable financial data sources. Compare their market caps and determine which company has the highest market capitalization at the deadline. Resolve to the company with the largest market cap."
	},
	{
		id: "sui-price",
		title: "Sui Price Range",
		description: "#Crypto Will Sui (SUI) be trading above $2.50 by the deadline?",
		category: "Crypto",
		rules: "Resolved by SUI price at deadline",
		marketRules: "This market will resolve as YES if the price of Sui (SUI) is above $2.50 at the deadline, and NO if it is $2.50 or below. The price will be determined using the closing price from major cryptocurrency exchanges such as Binance, Coinbase, or CoinGecko's aggregated price at the resolution time.",
		imageUrl: "https://example.com/sui.jpg",
		tags: ["sui", "crypto", "price"],
		resolutionType: "ai",
		aiPrompt: "Check the current price of Sui (SUI) cryptocurrency from reliable sources like CoinGecko, CoinMarketCap, or major exchanges (Binance, Coinbase). If the price is above $2.50, resolve as YES. If the price is $2.50 or below, resolve as NO."
	},
	{
		id: "premier-league",
		title: "Premier League Match",
		description: "#Sports Who will win the next Tottenham vs Manchester United match?",
		category: "Sports",
		rules: "Resolved by official match result",
		marketRules: "This market will be resolved based on the official result of the next Premier League match between Tottenham Hotspur and Manchester United. The result will be determined by the final score after 90 minutes plus injury time (regular time only, not including extra time or penalties). Options: Tottenham Win, Manchester United Win, or Draw.",
		imageUrl: "https://example.com/premier-league.jpg",
		tags: ["football", "premier-league", "tottenham", "manchester-united"],
		resolutionType: "ai",
		aiPrompt: "Check the official result of the most recent Premier League match between Tottenham Hotspur and Manchester United from reliable sports sources like BBC Sport, Sky Sports, or the official Premier League website. Determine the winner based on the final score after 90 minutes plus injury time. Resolve accordingly: Tottenham Win, Manchester United Win, or Draw."
	}
];

const initialState: FormState = {
	name: "",
	rules: "",
	marketRules: "",
	imageUrl: "",
	category: "",
	tags: "",
	endDate: "",
	endTime: "",
	resolutionType: "",
	aiPrompt: "",
	aiPromptUploadResult: null,
	userEnteredPrompt: "",
	userEnteredCode: "",
	codeUploadResult: null,
};

import { useRouter } from "next/navigation";

export function CreateWizard() {
	const client = useSuiClient();
	const router = useRouter();
	const { mutate: signAndExecuteTransaction } = useSignAndExecuteTransaction({
		execute: async ({ bytes, signature }) =>
			await client.executeTransactionBlock({
				transactionBlock: bytes,
				signature,
				options: {
					// Raw effects are required so the effects can be reported back to the wallet
					showRawEffects: true,
					// Select additional data to return
					showObjectChanges: true,
				},
			}),
	});
	const [step, setStep] = useState<Step>(0);
	const [form, setForm] = useState<FormState>(initialState);
	const [submitting, setSubmitting] = useState(false);

	const next = () => setStep((s) => (s < 4 ? ((s + 1) as Step) : s));
	const prev = () => setStep((s) => (s > 0 ? ((s - 1) as Step) : s));

	const update = (field: keyof FormState) => (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>) => {
		setForm((f) => ({ ...f, [field]: e.target.value }));
	};

	const selectTemplate = (template: Template) => {
		// Calculate date exactly 1 day later
		const tomorrow = new Date();
		tomorrow.setDate(tomorrow.getDate() + 1);
		const endDate = tomorrow.toISOString().split('T')[0] || tomorrow.toLocaleDateString('en-CA'); // Format as YYYY-MM-DD
		const endTime = "23:59"; // Set to end of day
		
		setForm({
			...initialState,
			selectedTemplate: template,
			name: template.description,
			rules: template.rules,
			marketRules: template.marketRules,
			category: template.category,
			tags: template.tags.join(", "),
			imageUrl: template.imageUrl || "",
			endDate,
			endTime,
			resolutionType: template.resolutionType,
			aiPrompt: template.aiPrompt || "",
		});
		next();
	};

	const createFromScratch = () => {
		setForm({ ...initialState, selectedTemplate: undefined });
		next();
	};

	const selectResolutionType = (type: "ai" | "code" | "") => {
		setForm({ ...form, resolutionType: type });
		
	};

	const handleWalrusUpload = (result: WalrusUploadResult, userCode: string) => {
		setForm({ ...form, codeUploadResult: result, userEnteredCode: userCode });
	};

	const handleAIPromptUpload = (result: WalrusUploadResult, userPrompt: string) => {
		setForm({ ...form, aiPromptUploadResult: result, userEnteredPrompt: userPrompt });
	};

	const canProceed = (() => {
		if (step === 0) return false; // Templates page handles navigation
		if (step === 1) return form.name.trim().length > 0 && form.rules.trim().length > 0;
		if (step === 2) return form.category.trim().length > 0 && form.endDate.trim().length > 0;
		if (step === 3) return form.resolutionType !== "";
		return true;
	})();

	const onSubmit = async () => {
		setSubmitting(true);
		try {
			// Create end time as timestamp
			const endDateTime = new Date(`${form.endDate}T${form.endTime}`);
			const endTimeTimestamp = endDateTime.getTime(); // Convert to seconds
			const startTimeTimestamp = Date.now(); // Current time in seconds
			console.log(form)

			// Create the market transaction
			const tx = new Transaction();
						// Add resolution configuration if we have uploaded content
			let list: any[];			
			// console.log(form.codeUploadResult?.blobId)
			if (form.resolutionType === "ai" && form.aiPromptUploadResult && form.userEnteredPrompt) {
				console.log("ai")
				list = createConfigTx(
					tx,
					form.userEnteredPrompt, // Use the original user-entered prompt as code_hash
					form.aiPromptUploadResult.blobId
				);
			} else if (form.resolutionType === "code" && form.codeUploadResult && form.userEnteredCode) {
					console.log("code")
					list = createConfigTx(
					tx,
					form.userEnteredCode, // Use the original user-entered code as code_hash
					form.codeUploadResult.blobId
				);
			}
			createMarketTx(
				tx,
				list,
				form.name,
				form.marketRules || form.rules,
				startTimeTimestamp,
				endTimeTimestamp
			);

			signAndExecuteTransaction({ transaction: tx },{
										onSuccess: (result) => {
											console.log('object changes', result.objectChanges);										},
									},);
			
								} catch (error) {
									console.error("Error creating market:", error);
								} finally {
									setSubmitting(false);
								}
			router.push("/main")
	};
	return (
		<div className="w-full flex justify-center">
			<Card className="w-3/4 p-6 space-y-6">
				<Stepper step={step} />
				{step === 0 && <TemplatesPage onSelectTemplate={selectTemplate} onCreateFromScratch={createFromScratch} />}
				{step === 1 && <MarketDetailsPage form={form} update={update} />}
				{step === 2 && <CategoryAndEndDatePage form={form} update={update} />}
				{step === 3 && <ResolutionTypePage form={form} onSelectType={selectResolutionType} onWalrusUpload={handleWalrusUpload} onAIPromptUpload={handleAIPromptUpload} />}
				{step === 4 && <ReviewPage form={form} />}
				<div className="flex justify-between pt-2">
					<Button variant="outline" onClick={prev} disabled={step === 0 || submitting}>
						{step === 1 ? "Previous" : "Back"}
					</Button>
					{step > 0 && step < 4 && (
						<Button onClick={next} disabled={!canProceed}>
							{step === 3 ? "Review" : "Next"}
						</Button>
					)}
					{step === 4 && (
						<Button onClick={onSubmit} disabled={submitting}>
							{submitting ? "Creating..." : "Create Market"}
						</Button>
					)}
					{step === 0 && <div></div> /* Spacer */}
				</div>
			</Card>
		</div>
	);
}

// Template Selection Page
function TemplatesPage({ 
	onSelectTemplate, 
	onCreateFromScratch 
}: { 
	onSelectTemplate: (template: Template) => void;
	onCreateFromScratch: () => void;
}) {
	return (
		<div className="space-y-6">
			<div className="text-center space-y-2">
				<h2 className="text-2xl font-bold">Templates</h2>
				<p className="text-muted-foreground">Start with a pre-filled template or create from scratch</p>
			</div>
			
			<div className="grid gap-4">
				{templates.map((template) => (
					<Card 
						key={template.id}
						className="p-4 cursor-pointer hover:bg-accent transition-colors"
						onClick={() => onSelectTemplate(template)}
					>
						<div className="space-y-2">
							<h3 className="font-semibold text-lg">{template.title}</h3>
							<p className="text-muted-foreground">{template.description}</p>
							<div className="flex gap-2">
								<span className="text-xs bg-secondary px-2 py-1 rounded-full">{template.category}</span>
								{template.tags.slice(0, 2).map(tag => (
									<span key={tag} className="text-xs bg-secondary px-2 py-1 rounded-full">{tag}</span>
								))}
							</div>
						</div>
					</Card>
				))}
			</div>

			<div className="text-center">
				<Button variant="outline" onClick={onCreateFromScratch}>
					Create from scratch
				</Button>
			</div>
		</div>
	);
}

// Market Details Page
function MarketDetailsPage({ 
	form, 
	update 
}: { 
	form: FormState;
	update: (field: keyof FormState) => (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => void;
}) {
	return (
		<div className="space-y-6">
			<div className="space-y-4">
				<div className="space-y-2">
					<Label htmlFor="name">Market Name</Label>
					<p className="text-sm text-muted-foreground">Provide a concise, descriptive market name</p>
					<Input 
						id="name" 
						placeholder="Will Bitcoin reach $100,000 by December 31, 2025?" 
						value={form.name} 
						onChange={update("name")} 
					/>
				</div>
				
				<div className="space-y-2">
					<Label htmlFor="rules">Rules (short)</Label>
					<p className="text-sm text-muted-foreground">Short resolution summary (required)</p>
					<Input 
						id="rules" 
						placeholder="Market Rules" 
						value={form.rules} 
						onChange={update("rules")} 
					/>
				</div>
				
				<div className="space-y-2">
					<Label htmlFor="marketRules">Market Rules</Label>
					<p className="text-sm text-muted-foreground">Short resolution summary, e.g., Resolved by BTC price at deadline</p>
					<Textarea 
						id="marketRules" 
						placeholder="Enter detailed market rules..."
						value={form.marketRules} 
						onChange={update("marketRules")} 
					/>
				</div>
				
				<div className="space-y-2">
					<Label htmlFor="imageUrl">Image URL</Label>
					<p className="text-sm text-muted-foreground">Optional cover image for the market</p>
					<Input 
						id="imageUrl" 
						placeholder="https://..." 
						value={form.imageUrl} 
						onChange={update("imageUrl")} 
					/>
				</div>
			</div>
		</div>
	);
}

// Category and End Date Page
function CategoryAndEndDatePage({ 
	form, 
	update 
}: { 
	form: FormState;
	update: (field: keyof FormState) => (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => void;
}) {
	return (
		<div className="space-y-6">
			<div className="space-y-4">
				<div className="space-y-2">
					<Label>Category & Tags</Label>
					<p className="text-sm text-muted-foreground">Categorize and tag for discovery</p>
					
					<div className="space-y-2">
						<Label htmlFor="category">Category</Label>
						<Input 
							id="category" 
							placeholder="e.g., Crypto" 
							value={form.category} 
							onChange={update("category")} 
						/>
					</div>
					
					<div className="space-y-2">
						<Label htmlFor="tags">Tags (comma-separated)</Label>
						<Input 
							id="tags" 
							placeholder="bitcoin, price, 2025" 
							value={form.tags} 
							onChange={update("tags")} 
						/>
					</div>
				</div>
				
				<div className="space-y-2">
					<Label>End Date</Label>
					<p className="text-sm text-muted-foreground">Choose an end date in the future</p>
					
					<div className="grid grid-cols-2 gap-4">
						<div className="space-y-2">
							<Label htmlFor="endDate">End Date</Label>
							<Input 
								id="endDate" 
								type="date"
								value={form.endDate} 
								onChange={update("endDate")} 
							/>
						</div>
						
						<div className="space-y-2">
							<Label htmlFor="endTime">End Time</Label>
							<Input 
								id="endTime" 
								type="time"
								value={form.endTime} 
								onChange={update("endTime")} 
							/>
						</div>
					</div>
				</div>
			</div>
		</div>
	);
}

// Resolution Type Page
function ResolutionTypePage({ 
	form, 
	onSelectType,
	onWalrusUpload,
	onAIPromptUpload,
}: { 
	form: FormState;
	onSelectType: (type: "ai" | "code" | "") => void;
	onWalrusUpload: (result: WalrusUploadResult, userCode: string) => void;
	onAIPromptUpload: (result: WalrusUploadResult, userPrompt: string) => void;
}) {
    const curacc = useCurrentAccount();
	if (form.resolutionType === "") {
		return (
			<div className="space-y-6">
				<div className="text-center space-y-2">
					<h2 className="text-2xl font-bold">Resolution Method</h2>
					<p className="text-muted-foreground">Choose how your market will be resolved</p>
				</div>
				
				<div className="grid gap-4">
					<Card 
						className="p-6 cursor-pointer hover:bg-accent transition-colors"
						onClick={() => onSelectType("ai")}
					>
						<div className="space-y-2">
							<h3 className="font-semibold text-lg">AI Resolution</h3>
							<p className="text-muted-foreground">Use AI to resolve the market based on your custom prompt</p>
							<div className="flex gap-2">
								<span className="text-xs bg-blue-100 text-blue-800 px-2 py-1 rounded-full">Automated</span>
								<span className="text-xs bg-purple-100 text-purple-800 px-2 py-1 rounded-full">AI-Powered</span>
							</div>
						</div>
					</Card>
					
					<Card 
						className="p-6 cursor-pointer hover:bg-accent transition-colors"
						onClick={() => onSelectType("code")}
					>
						<div className="space-y-2">
							<h3 className="font-semibold text-lg">Code Resolution</h3>
							<p className="text-muted-foreground">Upload custom code to Walrus for programmatic resolution</p>
							<div className="flex gap-2">
								<span className="text-xs bg-green-100 text-green-800 px-2 py-1 rounded-full">Custom Code</span>
								<span className="text-xs bg-orange-100 text-orange-800 px-2 py-1 rounded-full">Walrus Storage</span>
							</div>
						</div>
					</Card>
				</div>
			</div>
		);
	}

	if (form.resolutionType === "ai") {
		return (
            
			<div className="space-y-6">
				<div className="space-y-2">
					<h2 className="text-2xl font-bold">AI Resolution Setup</h2>
					<p className="text-muted-foreground">Configure how AI should resolve your market</p>
					<Button variant="outline" size="sm" onClick={() => onSelectType("")}>
						Change Resolution Type
					</Button>
				</div>
				
				<WalrusPromptUploader 
					signer={curacc || null} 
					defaultPrompt={form.aiPrompt}
					initialTitle={form.name}
					onUploaded={onAIPromptUpload}
				/>
				<SealApiKeyUploader
				signer={curacc || null}
				sealClient={sealClient}
				packageId={base}
				policyId="0x3789869361a511e35a0c0bd6d579951991539a46638283fb53f9dcfbca9dd221"
				threshold={2}
				/>
				
			</div>
		);
	}

	if (form.resolutionType === "code") {
		return (
			<div className="space-y-6">
				<div className="space-y-2">
					<h2 className="text-2xl font-bold">Code Resolution Setup</h2>
					<p className="text-muted-foreground">Upload your resolution code to Walrus</p>
					<Button variant="outline" size="sm" onClick={() => onSelectType("")}>
						Change Resolution Type
					</Button>
				</div>
				
				<WalrusCodeUploader 
					signer={curacc || null} 
					defaultFilename="resolution.ts"
					onUploaded={onWalrusUpload}
				/>
				<SealApiKeyUploader
					signer={curacc || null}
					sealClient={sealClient}
					packageId={base}
					policyId="0x3789869361a511e35a0c0bd6d579951991539a46638283fb53f9dcfbca9dd221"
					threshold={2}
				/>
				
				
			</div>
		);
	}

	return null;
}

// Review Page
function ReviewPage({ form }: { form: FormState }) {
    // 格式化日期顯示
    const formattedEndDate = new Date(form.endDate).toLocaleDateString('en-US', {
        weekday: 'long',
        year: 'numeric',
        month: 'long',
        day: 'numeric',
    });

    return (
        <div className="space-y-8 animate-in fade-in duration-500">
            {/* Header Section: 標題與基礎資訊 */}
            <div className="flex flex-col md:flex-row gap-6 items-start">
                {/* 圖片預覽 (如果有的話) */}
                <div className="shrink-0 w-full md:w-32 h-32 bg-muted rounded-lg flex items-center justify-center overflow-hidden border">
                    {form.imageUrl ? (
                        <img src={form.imageUrl} alt="Market Cover" className="w-full h-full object-cover" />
                    ) : (
                        <ImageIcon className="w-8 h-8 text-muted-foreground/50" />
                    )}
                </div>

                <div className="space-y-3 flex-1">
                    <div>
                        <h3 className="text-2xl font-bold tracking-tight">{form.name || "Untitled Market"}</h3>
                        <p className="text-muted-foreground flex items-center gap-2 mt-1">
                            <Layers className="w-4 h-4" />
                            {form.category || "Uncategorized"}
                        </p>
                    </div>

                    <div className="flex flex-wrap gap-2">
                        {form.tags.split(',').map((tag) => tag.trim()).filter(t => t).map((tag) => (
                            <span key={tag} className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-secondary text-secondary-foreground hover:bg-secondary/80">
                                <Tag className="w-3 h-3 mr-1" />
                                {tag}
                            </span>
                        ))}
                    </div>
                </div>
            </div>

            <Separator className="my-6" />

            <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
                {/* Left Column: 市場規則與時間 */}
                <div className="space-y-6">
                    <div>
                        <h4 className="text-sm font-semibold uppercase text-muted-foreground mb-3 flex items-center gap-2">
                            <FileText className="w-4 h-4" /> Market Details
                        </h4>
                        <div className="bg-accent/30 rounded-lg p-4 space-y-4 border">
                            <div>
                                <label className="text-xs font-medium text-muted-foreground">Short Rules</label>
                                <p className="font-medium text-sm">{form.rules || "—"}</p>
                            </div>
                            
                            {form.rules !== form.marketRules && (
                                <div>
                                    <label className="text-xs font-medium text-muted-foreground">Detailed Rules</label>
                                    <p className="text-sm text-foreground/90 whitespace-pre-wrap mt-1">
                                        {form.marketRules || "Same as short rules"}
                                    </p>
                                </div>
                            )}
                        </div>
                    </div>

                    <div>
                        <h4 className="text-sm font-semibold uppercase text-muted-foreground mb-3 flex items-center gap-2">
                            <CalendarIcon className="w-4 h-4" /> Timeline
                        </h4>
                        <div className="flex items-center gap-4 bg-accent/30 p-4 rounded-lg border">
                            <div className="flex-1">
                                <label className="text-xs font-medium text-muted-foreground">Resolution Date</label>
                                <div className="font-semibold">{formattedEndDate}</div>
                            </div>
                            <div className="h-8 w-[1px] bg-border"></div>
                            <div className="flex-1 text-right">
                                <label className="text-xs font-medium text-muted-foreground">Time</label>
                                <div className="font-semibold">{form.endTime || "23:59"}</div>
                            </div>
                        </div>
                    </div>
                </div>

                {/* Right Column: 技術解析與 Walrus 數據 */}
                <div className="space-y-6">
                    <h4 className="text-sm font-semibold uppercase text-muted-foreground mb-3 flex items-center gap-2">
                        {form.resolutionType === 'ai' ? <Bot className="w-4 h-4" /> : <Code className="w-4 h-4" />}
                        Resolution Mechanism
                    </h4>

                    <div className="border rounded-xl overflow-hidden shadow-sm">
                        <div className="bg-muted px-4 py-3 border-b flex justify-between items-center">
                            <span className="font-semibold text-sm flex items-center gap-2">
                                {form.resolutionType === "ai" ? "AI Resolution" : "Code Resolution"}
                            </span>
                            {(form.aiPromptUploadResult || form.codeUploadResult) && (
                                <span className="text-xs bg-green-100 text-green-700 px-2 py-0.5 rounded-full flex items-center gap-1">
                                    <CheckCircle2 className="w-3 h-3" /> Uploaded to Walrus
                                </span>
                            )}
                        </div>

                        <div className="p-4 space-y-4 bg-card">
                            {/* Blob ID Section */}
                            <div>
                                <label className="text-xs font-medium text-muted-foreground">Walrus Blob ID</label>
                                <div className="font-mono text-xs bg-muted p-2 rounded border mt-1 truncate">
                                    {form.resolutionType === "ai" 
                                        ? form.aiPromptUploadResult?.blobId || "Pending..."
                                        : form.codeUploadResult?.blobId || "Pending..."
                                    }
                                </div>
                            </div>

                            {/* Content Preview Section */}
                            <div>
                                <label className="text-xs font-medium text-muted-foreground">
                                    {form.resolutionType === "ai" ? "Prompt Content" : "Source Code"}
                                </label>
                                <div className="mt-1 relative">
                                    <div className="absolute top-0 left-0 w-full h-full pointer-events-none rounded border shadow-inner inset-0"></div>
                                    <div className="max-h-[200px] overflow-y-auto p-3 text-xs font-mono bg-zinc-950 text-zinc-100 rounded">
                                        <pre className="whitespace-pre-wrap break-all">
                                            {form.resolutionType === "ai" 
                                                ? (form.userEnteredPrompt || form.aiPrompt) 
                                                : form.userEnteredCode}
                                        </pre>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    );
}

function Stepper({ step }: { step: Step }) {
	const steps = ["Templates", "Market Details", "Category & Date", "Resolution", "Review"];
	return (
		<ol className="flex items-center justify-between text-sm">
			{steps.map((label, i) => {
				const active = i === step;
				const complete = i < step;
				return (
					<li key={label} className="flex-1 flex flex-col items-center">
						<div
							className={
								"h-8 w-8 flex items-center justify-center rounded-full border text-xs font-medium " +
								(active
									? "bg-primary text-primary-foreground border-primary"
									: complete
									? "bg-green-500 text-white border-green-500"
									: "bg-muted text-foreground/60 border-border")
							}
						>
							{i + 1}
						</div>
						<span className={"mt-1 " + (active ? "font-semibold" : "text-muted-foreground")}>{label}</span>
					</li>
				);
			})}
		</ol>
	);
}

export default CreateWizard;
