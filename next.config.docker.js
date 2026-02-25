// next.config.docker.js — override for self-hosted Docker builds.
// Replaces upstream next.config.mjs to add standalone output and remove
// Vercel-specific logic.  Based on avnox-com/papermark-self-host.
const nextConfig = {
  output: "standalone",
  reactStrictMode: true,
  images: {
    minimumCacheTTL: 2592000, // 30 days
    remotePatterns: [
      { protocol: "https", hostname: "**" },
    ],
  },
  webpack: (config, { isServer, webpack }) => {
    if (!isServer) {
      config.resolve.fallback = {
        ...config.resolve.fallback,
        fs: false,
        net: false,
        tls: false,
      };
    }
    // Ignore optional Google Cloud modules that @libpdf/core tries to import.
    // These are peer deps that are not installed and not needed for our use case.
    config.plugins.push(
      new webpack.IgnorePlugin({
        resourceRegExp: /^@google-cloud\/(kms|secret-manager)$/,
      }),
    );
    return config;
  },
  async headers() {
    return [
      {
        source: "/(.*)",
        headers: [
          { key: "X-Frame-Options", value: "SAMEORIGIN" },
          { key: "X-Content-Type-Options", value: "nosniff" },
          { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
        ],
      },
    ];
  },
};

module.exports = nextConfig;
