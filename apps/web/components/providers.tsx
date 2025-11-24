"use client"
import '@mysten/dapp-kit/dist/index.css';
import * as React from "react"
import { ThemeProvider as NextThemesProvider } from "next-themes"
import { createNetworkConfig, SuiClientProvider, WalletProvider } from '@mysten/dapp-kit';
import { getFullnodeUrl } from '@mysten/sui/client';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { ApolloProvider as ApolloClientProvider } from '@apollo/client/react';
import { gqlClient } from '@/utils/gql';

// Config options for the networks you want to connect to
const { networkConfig } = createNetworkConfig({
  localnet: { url: getFullnodeUrl('localnet') },
  testnet: { url: getFullnodeUrl('testnet') },
  mainnet: { url: getFullnodeUrl('mainnet') },
});

const queryClient = new QueryClient();

export function Providers({ children }: { children: React.ReactNode }) {
  return (
    <QueryClientProvider client={queryClient}>
      <SuiClientProvider networks={networkConfig} defaultNetwork="testnet">
        <WalletProvider autoConnect>
          <ApolloClientProvider client={gqlClient}>
            <NextThemesProvider
              attribute="class"
              defaultTheme="system"
              enableSystem
              disableTransitionOnChange
              enableColorScheme
            >
              {children}
            </NextThemesProvider>
          </ApolloClientProvider>
        </WalletProvider>
      </SuiClientProvider>
    </QueryClientProvider>
  )
}
