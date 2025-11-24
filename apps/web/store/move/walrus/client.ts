import { getFullnodeUrl, SuiClient } from '@mysten/sui/client';
import { walrus } from '@mysten/walrus';

export const client = new SuiClient({
	url: getFullnodeUrl('testnet'),
	// Setting network on your client is required for walrus to work correctly
	network: 'testnet',
}).$extend(
	walrus({
		uploadRelay: {
			host: 'https://upload-relay.testnet.walrus.space', // Walrus upload relay endpoint
			sendTip: { max: 1000 }, // Maximum tip amount in MIST
		},
	}),
);