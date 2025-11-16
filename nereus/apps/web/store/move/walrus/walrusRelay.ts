// Copyright (c) Mysten Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { getFaucetHost, requestSuiFromFaucetV2 } from '@mysten/sui/faucet';
import { WalrusFile } from '@mysten/walrus';
import type { Signer } from '@mysten/sui/cryptography';

import { client } from './client';

// Create a keypair using environment variable for secure key management
async function getKeypair(): Promise<Ed25519Keypair> {

	try {
		return Ed25519Keypair.fromSecretKey("suiprivkey1qrqp6xtphngqg9nh488v6hyvev229wl6w964nuukl9l95c090pkskvuznyd");
	} catch {
		throw new Error('Invalid WALRUS_SECRET_KEY format. Please ensure it is a valid base64 encoded secret key.');
	}
};

export async function uploadFile(text: string) {
	const keypair = await getKeypair()

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
