import { ApolloClient, InMemoryCache, HttpLink, gql, DocumentNode, OperationVariables } from '@apollo/client';

// Create the HTTP link
const httpLink = new HttpLink({
  uri: "https://graphql.testnet.sui.io/graphql",
});

// Create the Apollo Client instance
export const gqlClient = new ApolloClient({
  link: httpLink,
  cache: new InMemoryCache(),
  defaultOptions: {
    watchQuery: {
      fetchPolicy: 'cache-and-network',
    },
    query: {
      fetchPolicy: 'network-only',
      errorPolicy: 'all',
    },
    mutate: {
      errorPolicy: 'all',
    },
  },
});

/**
 * Execute a GraphQL query
 * @param query - GraphQL query string or DocumentNode
 * @param variables - Optional variables for the query
 * @returns Promise with the query result
 */
export async function gqlQuery<TData = unknown, TVariables extends OperationVariables = OperationVariables>(
  query: string | DocumentNode,
  variables?: TVariables
) {
  const queryDoc = typeof query === 'string' ? gql(query) : query;
  
  return gqlClient.query<TData, TVariables>({
    query: queryDoc,
    variables: variables as TVariables,
  });
}

/**
 * Execute a GraphQL mutation
 * @param mutation - GraphQL mutation string or DocumentNode
 * @param variables - Optional variables for the mutation
 * @returns Promise with the mutation result
 */
export async function gqlMutate<TData = unknown, TVariables extends OperationVariables = OperationVariables>(
  mutation: string | DocumentNode,
  variables?: TVariables
) {
  const mutationDoc = typeof mutation === 'string' ? gql(mutation) : mutation;
  
  return gqlClient.mutate<TData, TVariables>({
    mutation: mutationDoc,
    variables: variables as TVariables,
  });
}

export default gqlClient;
