// components/walrus-code-uploader.tsx
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
import { vscodeDark } from '@uiw/codemirror-theme-vscode';

import { Loader2, CheckCircle2, AlertCircle, UploadCloud } from 'lucide-react';

// 🔥 CodeMirror (Syntax Highlight Editor)
import CodeMirror from '@uiw/react-codemirror';
import { javascript } from '@codemirror/lang-javascript';
import { python } from '@codemirror/lang-python';

interface WalrusCodeUploaderProps {
	// eslint-disable-next-line @typescript-eslint/no-explicit-any
	signer: any; // Signer type from Sui - accepting any to work with WalletAccount
	defaultFilename?: string;
	onUploaded?: (result: WalrusUploadResult, userCode: string) => void;
}

export function WalrusCodeUploader(props: WalrusCodeUploaderProps) {
	const { signer, defaultFilename = 'snippet.ts', onUploaded } = props;

	const [filename, setFilename] = useState(defaultFilename);
	const [code, setCode] = useState<string>(
		`// Paste or write your code here\n// This snippet will be stored on Walrus testnet\n`,
	);
	const [uploading, setUploading] = useState(false);
	const [error, setError] = useState<string | null>(null);
	const [result, setResult] = useState<WalrusUploadResult | null>(null);

	// 🔥 根據檔名推測語言，決定 CodeMirror 語法高亮
	const languageExtension = (() => {
		if (filename.endsWith('.ts') || filename.endsWith('.tsx'))
			return javascript({ typescript: true });

		if (filename.endsWith('.js') || filename.endsWith('.jsx'))
			return javascript();

		if (filename.endsWith('.py')) return python();

		return javascript();
	})();

	async function handleUpload() {
		if (!signer) {
			setError('Signer is not available. Please connect a wallet or provide a Signer instance.');
			return;
		}

		if (!code.trim()) {
			setError('Code is empty. Please write something before uploading.');
			return;
		}

		setUploading(true);
		setError(null);

		try {
			// Create a structured code file with metadata
			const codeData = {
				filename: filename || 'snippet.ts',
				code: code,
				timestamp: new Date().toISOString(),
				type: 'code-snippet'
			};

			const formattedCode = JSON.stringify(codeData, null, 2);

			const res = await uploadFile(formattedCode);

			setResult(res);
			onUploaded?.(res, code);
		} catch (err: unknown) {
			console.error(err);
			setError(err instanceof Error ? err.message : 'Failed to upload code to Walrus.');
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
							<UploadCloud className="h-5 w-5" />
							<span>Walrus Code Uploader</span>
						</CardTitle>
						<CardDescription>
							Edit your code and store it as a Walrus blob on Sui testnet.
						</CardDescription>
					</div>
					<Badge variant={signer ? 'default' : 'outline'}>
						{signer ? 'Signer ready' : 'No signer'}
					</Badge>
				</div>
			</CardHeader>

			<CardContent className="space-y-4">
				<div className="space-y-2">
					<Label htmlFor="filename">File name</Label>
					<Input
						id="filename"
						value={filename}
						onChange={(e) => setFilename(e.target.value)}
						placeholder="snippet.ts"
					/>
				</div>

				{/* 🔥 直接把 Textarea 換成 CodeMirror Editor */}
				<div className="space-y-2">
					<Label>Code</Label>
					<div className="border border-border rounded-md overflow-hidden">
						<CodeMirror
							value={code}
							height="300px"
							theme={vscodeDark}
							extensions={[languageExtension]}
							onChange={(value) => setCode(value)}
						/>
					</div>
					<p className="text-xs text-muted-foreground text-right">
						{code.length} characters
					</p>
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
							<span className="font-medium text-emerald-500">Upload succeeded</span>
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
					disabled={uploading || !signer}
					className="gap-2 transition-transform active:scale-[0.97]"
				>
					{uploading && <Loader2 className="h-4 w-4 animate-spin" />}
					<span>{uploading ? 'Uploading to Walrus…' : 'Upload to Walrus'}</span>
				</Button>
			</CardFooter>
		</Card>
	);
}
