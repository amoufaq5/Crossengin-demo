/**
 * Minimal Next.js config for the CrossEngin Vercel proxy.
 *
 * The App Router is the default in Next 14; we keep this file lean and
 * push the only deployment-shape concerns -- function runtime and max
 * duration -- into vercel.json where Vercel actually consumes them.
 */
/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // The /api/chat route streams an upstream response body; nothing to
  // statically optimise here. Leave defaults on for the chat UI page.
};

module.exports = nextConfig;
