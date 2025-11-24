/** @type {import('next').NextConfig} */
const nextConfig = {
  transpilePackages: ["@workspace/ui"],
  experimental: {
    serverExternalPackages: ["@mysten/walrus", "@mysten/walrus-wasm"],
  },
}

export default nextConfig
