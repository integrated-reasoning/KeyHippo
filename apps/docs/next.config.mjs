import nextra from "nextra";

const withNextra = nextra({
  theme: "nextra-theme-docs",
  themeConfig: "./src/theme.config.jsx",
  latex: true,
  titleSuffix: "KeyHippo Documentation",
});

/** @type {import('next').NextConfig} */
const nextConfig = {
  experimental: {
    turbo: {
      resolveExtensions: [
        '.mdx',
        '.tsx',
        '.ts',
        '.jsx',
        '.js',
        '.mjs',
        '.json',
      ],
    },
  },
  //assetPrefix: process.env.DISABLE_ASSET_PREFIX ? undefined : "https://keyhippo.com",
  //transpilePackages: ["@repo/ui"],
};

let config = withNextra(nextConfig);

export default config;
