// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { getFaucetHost, requestSuiFromFaucetV2 } from '@mysten/sui/faucet';
import { WalrusFile } from '@mysten/walrus';
import type { Signer } from '@mysten/sui/cryptography';

import { client } from './client';

// Create a keypair using environment variable for secure key management
const getKeypair = (): Ed25519Keypair => {
	const secretKey = process.env.WALRUS_SECRET_KEY;
	
	if (!secretKey) {
		throw new Error('WALRUS_SECRET_KEY environment variable is required. Please set it in your .env.local file.');
	}
	
	try {
		// Decode the base64 secret key
		const secretKeyBytes = Uint8Array.from(atob(secretKey), c => c.charCodeAt(0));
		return Ed25519Keypair.fromSecretKey(secretKeyBytes);
	} catch {
		throw new Error('Invalid WALRUS_SECRET_KEY format. Please ensure it is a valid base64 encoded secret key.');
	}
};

const keypair = getKeypair();

// Legacy upload function for backward compatibility
export async function uploadFile(text: string) {
	await requestSuiFromFaucetV2({
		host: getFaucetHost('testnet'),
		recipient: keypair.getPublicKey().toSuiAddress(),
	});

	const file = new TextEncoder().encode(text);

	const { blobId, blobObject } = await client.walrus.writeBlob({
		blob: file,
		deletable: true,
		epochs: 3,
		signer: keypair,
	});

	console.log(blobId, blobObject);
}

// Export interface for upload results
export interface WalrusUploadResult {
	id: string; // Quilt ID
	blobId: string; // Blob ID
}

// Parameters for uploading code to Walrus
export interface UploadCodeParams {
	code: string;
	filename: string;
	epochs: number;
	deletable: boolean;
	signer: Signer;
}

// Enhanced upload function using Walrus upload relay and WalrusFile
export async function uploadCodeToWalrus(params: UploadCodeParams): Promise<WalrusUploadResult> {
	const { code, filename, epochs, deletable, signer } = params;

	try {
		// Create WalrusFile instance with the code content
		const file = WalrusFile.from({
			contents: new TextEncoder().encode(code),
			identifier: filename,
		});

		// Upload via the relay using writeFiles (recommended for dapps)
		const results = await client.walrus.writeFiles({
			files: [file],
			epochs,
			deletable,
			signer,
		});

		// Extract the first result (we only upload one file)
		const result = results[0];
		if (!result) {
			throw new Error('No upload result returned from Walrus');
		}

		return {
			id: result.id, // Quilt ID
			blobId: result.blobId, // Blob ID
		};
	} catch (error) {
		console.error('Failed to upload code to Walrus:', error);
		throw new Error(`Upload failed: ${error instanceof Error ? error.message : 'Unknown error'}`);
	}
}

