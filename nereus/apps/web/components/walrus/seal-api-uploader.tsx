// components/seal-api-key-uploader.tsx
'use client';

import { useCallback, useMemo, useState } from 'react';
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

import {
  Loader2,
  CheckCircle2,
  AlertCircle,
  Plus,
  UploadCloud,
  KeyRound,
} from 'lucide-react';

import type { SealClient } from '@mysten/seal';
import { fromHex } from '@mysten/sui/utils';
type ApiKeyEntry = {
  name: string;
  value: string;
  uploading: boolean;
  error: string | null;
  result: WalrusUploadResult | null;
};

interface SealApiKeyUploaderProps {
  signer: any;
  sealClient: SealClient;

  packageId: string;
  policyId: string;

  threshold?: number;
  initialEntries?: Array<{ name?: string; value?: string }>;

  onUploaded?: (result: WalrusUploadResult, entry: { name: string; value: string }) => void;
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = '';
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
  }
  return btoa(binary);
}

export function SealApiKeyUploader(props: SealApiKeyUploaderProps) {
  const {
    signer,
    sealClient,
    packageId,
    policyId,
    threshold = 2,
    initialEntries = [{ name: '', value: '' }],
    onUploaded,
  } = props;
  console.log(packageId, policyId);
  const [entries, setEntries] = useState<ApiKeyEntry[]>(
    initialEntries.map((e) => ({
      name: e.name ?? '',
      value: e.value ?? '',
      uploading: false,
      error: null,
      result: null,
    })),
  );

  const addRow = useCallback(() => {
    setEntries((prev) => [
      ...prev,
      { name: '', value: '', uploading: false, error: null, result: null },
    ]);
  }, []);

  const updateEntry = useCallback(
    (index: number, patch: Partial<ApiKeyEntry>) => {
      setEntries((prev) =>
        prev.map((it, i) => (i === index ? { ...it, ...patch } : it)),
      );
    },
    [],
  );

  const handleUpload = useCallback(
    async (index: number) => {
      if (!signer) {
        updateEntry(index, { error: 'Signer is not available.' });
        return;
      }

      const entry = entries[index];
      if (!entry?.value.trim()) {
        updateEntry(index, { error: 'API key is empty.' });
        return;
      }

      updateEntry(index, { uploading: true, error: null });

      try {
        const payload = {
          name: entry.name || `API Key #${index + 1}`,
          apiKey: entry.value,
          createdAt: new Date().toISOString(),
          type: 'api-key',
          version: 1,
        };

        const plainText = JSON.stringify(payload);
        const data = new TextEncoder().encode(plainText);

        const { encryptedObject } = await sealClient.encrypt({
          threshold,
          packageId: fromHex(packageId),
          id: fromHex(policyId),
          data,
        });

        const encryptedBase64 = bytesToBase64(encryptedObject);

        const res = await uploadFile(encryptedBase64);

        updateEntry(index, { result: res });
        onUploaded?.(res, { name: payload.name, value: entry.value });
      } catch (err: unknown) {
        console.error(err);
        updateEntry(index, {
          error: err instanceof Error ? err.message : 'Failed to encrypt/upload.',
        });
      } finally {
        updateEntry(index, { uploading: false });
      }
    },
    [entries, onUploaded, packageId, policyId, sealClient, signer, threshold, updateEntry],
  );

  const anyUploading = useMemo(
    () => entries.some((e) => e.uploading),
    [entries],
  );

  return (
    <Card className="w-full max-w-3xl mx-auto shadow-lg border border-border/60 bg-gradient-to-b from-background/70 to-background/40 backdrop-blur-md">
      <CardHeader>
        <div className="flex items-center justify-between gap-2">
          <div>
            <CardTitle className="flex items-center gap-2">
              <KeyRound className="h-5 w-5 text-purple-500" />
              <span>API Key Uploader (Seal + Walrus)</span>
            </CardTitle>
            <CardDescription>
              Add one or more API keys, encrypt with Seal, then upload encrypted blobs to Walrus.
            </CardDescription>
          </div>
          <Badge variant={signer ? 'default' : 'outline'}>
            {signer ? 'Signer ready' : 'No signer'}
          </Badge>
        </div>
      </CardHeader>

      <CardContent className="space-y-4">
        {entries.map((entry, i) => {
          const isLast = i === entries.length - 1;
          const uploaded = !!entry.result;

          const walrusExplorerUrl =
            entry.result?.blobId
              ? `https://walruscan.com/testnet/blob/${entry.result.blobId}`
              : null;

          return (
            <div
              key={i}
              className="rounded-xl border border-border/60 p-4 space-y-3 bg-background/40"
            >
              <div className="grid grid-cols-1 md:grid-cols-5 gap-3 items-end">
                <div className="md:col-span-2 space-y-2">
                  <Label htmlFor={`name-${i}`}>Key Name (Optional)</Label>
                  <Input
                    id={`name-${i}`}
                    value={entry.name}
                    onChange={(e) =>
                      updateEntry(i, { name: e.target.value })
                    }
                    placeholder="e.g., OpenAI / CoinGecko"
                    disabled={entry.uploading || uploaded}
                  />
                </div>

                <div className="md:col-span-2 space-y-2">
                  <Label htmlFor={`value-${i}`}>API Key</Label>
                  <Input
                    id={`value-${i}`}
                    type="password"
                    value={entry.value}
                    onChange={(e) =>
                      updateEntry(i, { value: e.target.value })
                    }
                    placeholder="sk-... / api_..."
                    disabled={entry.uploading || uploaded}
                  />
                </div>

                <div className="md:col-span-1">
                  {isLast ? (
                    <Button
                      type="button"
                      variant="outline"
                      className="w-full gap-2"
                      onClick={addRow}
                      disabled={anyUploading}
                    >
                      <Plus className="h-4 w-4" />
                      <span>Add</span>
                    </Button>
                  ) : (
                    <Button
                      type="button"
                      className="w-full gap-2"
                      onClick={() => handleUpload(i)}
                      disabled={entry.uploading || uploaded || !entry.value.trim()}
                    >
                      {entry.uploading ? (
                        <Loader2 className="h-4 w-4 animate-spin" />
                      ) : uploaded ? (
                        <CheckCircle2 className="h-4 w-4" />
                      ) : (
                        <UploadCloud className="h-4 w-4" />
                      )}
                      <span>
                        {entry.uploading
                          ? 'Uploading...'
                          : uploaded
                            ? 'Uploaded'
                            : 'Upload'}
                      </span>
                    </Button>
                  )}
                </div>
              </div>

              {entry.error && (
                <div className="flex items-start gap-2 rounded-md border border-destructive/40 bg-destructive/10 px-3 py-2 text-sm text-destructive">
                  <AlertCircle className="h-4 w-4 mt-0.5" />
                  <p>{entry.error}</p>
                </div>
              )}

              {entry.result && (
                <div className="space-y-2 rounded-md border border-emerald-500/40 bg-emerald-500/5 px-3 py-3 text-sm">
                  <div className="flex items-center gap-2 mb-1">
                    <CheckCircle2 className="h-4 w-4 text-emerald-500" />
                    <span className="font-medium text-emerald-500">
                      Encrypted key uploaded successfully
                    </span>
                  </div>
                  <div className="space-y-1 text-xs md:text-sm">
                    <div>
                      <span className="font-semibold">Quilt ID:&nbsp;</span>
                      <code className="break-all">{entry.result.id}</code>
                    </div>
                    <div>
                      <span className="font-semibold">Blob ID:&nbsp;</span>
                      <code className="break-all">{entry.result.blobId}</code>
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
            </div>
          );
        })}
      </CardContent>

      <CardFooter className="flex justify-between items-center gap-3">
        <p className="text-xs text-muted-foreground">
          Keys are encrypted with Seal (threshold {threshold}) and stored as Walrus blobs.
        </p>
      </CardFooter>
    </Card>
  );
}
