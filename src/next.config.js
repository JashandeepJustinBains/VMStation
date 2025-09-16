/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'export',
  trailingSlash: true,
  images: {
    unoptimized: true
  },
  basePath: process.env.NODE_ENV === 'production' ? '/VMStation' : '',
  assetPrefix: process.env.NODE_ENV === 'production' ? '/VMStation/' : '',
  experimental: {
    esmExternals: 'loose'
  }
};

module.exports = nextConfig;