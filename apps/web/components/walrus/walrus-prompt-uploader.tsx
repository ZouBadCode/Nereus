// components/walrus-prompt-uploader.tsx
'use client';

import { useState } from 'react';
import { uploadFile, WalrusUploadResult } from '@/store/move/walrus/walrusRelay';

import {
	Card,
	CardHeader,
	CardTitle,
	CardDescription,
	CardContent,
	CardFooter,
} from '@workspace/ui/components/card';
import { Button } from '@workspace/ui/components/button';
import { Badge } from '@workspace/ui/components/badge';
import { Input } from '@workspace/ui/components/input';
import { Label } from '@workspace/ui/components/label';
import { Textarea } from '@workspace/ui/components/textarea';

import { Loader2, CheckCircle2, AlertCircle, FileText, Sparkles } from 'lucide-react';

interface WalrusPromptUploaderProps {
	// eslint-disable-next-line @typescript-eslint/no-explicit-any
	signer: any; // Signer type from Sui - accepting any to work with WalletAccount
	defaultPrompt?: string;
	onUploaded?: (result: WalrusUploadResult, userPrompt: string) => void;
	initialTitle?: string;
}

export function WalrusPromptUploader(props: WalrusPromptUploaderProps) {
	const { signer, defaultPrompt = '', onUploaded, initialTitle = '' } = props;

	const [title, setTitle] = useState(initialTitle);
	const [prompt, setPrompt] = useState<string>(
		defaultPrompt || 
		`// Enter your AI resolution prompt here\n// Example: Check the official BTC price on CoinGecko at the deadline.\n// If BTC is $100,000 or higher, resolve as YES. Otherwise, resolve as NO.`
	);
	const [uploading, setUploading] = useState(false);
	const [error, setError] = useState<string | null>(null);
	const [result, setResult] = useState<WalrusUploadResult | null>(null);

	async function handleUpload() {
		if (!signer) {
			setError('Signer is not available. Please connect a wallet or provide a Signer instance.');
			return;
		}

		if (!prompt.trim()) {
			setError('Prompt is empty. Please write an AI resolution prompt before uploading.');
			return;
		}

		setUploading(true);
		setError(null);

		try {
			// Create a structured prompt with metadata
			const promptData = {
				title: title || 'AI Resolution Prompt',
				prompt: prompt,
				timestamp: new Date().toISOString(),
				type: 'ai-resolution'
			};

			const formattedPrompt = JSON.stringify(promptData, null, 2);

			const res = await uploadFile(formattedPrompt);

			setResult(res);
			onUploaded?.(res, prompt);
		} catch (err: unknown) {
			console.error(err);
			setError(err instanceof Error ? err.message : 'Failed to upload prompt to Walrus.');
		} finally {
			setUploading(false);
		}
	}

	const walrusExplorerUrl =
		result?.blobId ? `https://walruscan.com/testnet/blob/${result.blobId}` : null;

	return (
		<Card className="w-full max-w-3xl mx-auto shadow-lg border border-border/60 bg-gradient-to-b from-background/70 to-background/40 backdrop-blur-md">
			<CardHeader>
				<div className="flex items-center justify-between gap-2">
					<div>
						<CardTitle className="flex items-center gap-2">
							<Sparkles className="h-5 w-5 text-purple-500" />
							<span>AI Prompt Uploader</span>
						</CardTitle>
						<CardDescription>
							Create and store your AI resolution prompt as a Walrus blob on Sui testnet.
						</CardDescription>
					</div>
					<Badge variant={signer ? 'default' : 'outline'}>
						{signer ? 'Signer ready' : 'No signer'}
					</Badge>
				</div>
			</CardHeader>

			<CardContent className="space-y-4">
				<div className="space-y-2">
					<Label htmlFor="prompt-title">Prompt Title (Optional)</Label>
					<Input
						id="prompt-title"
						value={title}
						onChange={(e) => setTitle(e.target.value)}
						placeholder="e.g., BTC Price Resolution Prompt"
					/>
				</div>

				<div className="space-y-2">
					<Label htmlFor="ai-prompt">AI Resolution Prompt</Label>
					<p className="text-xs text-muted-foreground">
						Describe how the AI should evaluate and resolve your market. Be specific about data sources, conditions, and expected outcomes.
					</p>
					<Textarea
						id="ai-prompt"
						value={prompt}
						onChange={(e) => setPrompt(e.target.value)}
						placeholder="Enter your AI resolution instructions..."
						rows={12}
						className="font-mono text-sm"
					/>
					<p className="text-xs text-muted-foreground text-right">
						{prompt.length} characters
					</p>
				</div>

				{/* Example Prompts Section */}
				<div className="p-4 bg-muted/50 rounded-lg space-y-2">
					<div className="flex items-center gap-2">
						<FileText className="h-4 w-4 text-muted-foreground" />
						<span className="text-sm font-medium">Example Prompts:</span>
					</div>
					<ul className="text-xs text-muted-foreground space-y-1 list-disc list-inside">
						<li>Check [data source] for [metric] at [time]. If [condition], resolve YES, else NO.</li>
						<li>Compare [entity A] and [entity B] based on [criteria]. Resolve to the winner.</li>
						<li>Verify if [event] occurred by checking [source]. Resolve accordingly.</li>
					</ul>
				</div>

				{error && (
					<div className="flex items-start gap-2 rounded-md border border-destructive/40 bg-destructive/10 px-3 py-2 text-sm text-destructive">
						<AlertCircle className="h-4 w-4 mt-0.5" />
						<p>{error}</p>
					</div>
				)}

				{result && (
					<div className="space-y-2 rounded-md border border-emerald-500/40 bg-emerald-500/5 px-3 py-3 text-sm">
						<div className="flex items-center gap-2 mb-1">
							<CheckCircle2 className="h-4 w-4 text-emerald-500" />
							<span className="font-medium text-emerald-500">Prompt uploaded successfully</span>
						</div>
						<div className="space-y-1 text-xs md:text-sm">
							<div>
								<span className="font-semibold">Quilt ID:&nbsp;</span>
								<code className="break-all">{result.id}</code>
							</div>
							<div>
								<span className="font-semibold">Blob ID:&nbsp;</span>
								<code className="break-all">{result.blobId}</code>
							</div>
							{walrusExplorerUrl && (
								<div className="pt-1">
									<a
										href={walrusExplorerUrl}
										target="_blank"
										rel="noreferrer"
										className="text-xs underline underline-offset-2 text-emerald-500 hover:text-emerald-400"
									>
										View on Walrus explorer
									</a>
								</div>
							)}
						</div>
					</div>
				)}
			</CardContent>

			<CardFooter className="flex justify-between items-center gap-3">
				<p className="text-xs text-muted-foreground">
					Your signer must have enough SUI and WAL on testnet to pay for storage and gas.
				</p>
				<Button
					onClick={handleUpload}
					disabled={uploading || !signer || !prompt.trim()}
					className="gap-2 transition-transform active:scale-[0.97]"
				>
					{uploading && <Loader2 className="h-4 w-4 animate-spin" />}
					<span>{uploading ? 'Uploading to Walrus…' : 'Upload Prompt'}</span>
				</Button>
			</CardFooter>
		</Card>
	);
}
