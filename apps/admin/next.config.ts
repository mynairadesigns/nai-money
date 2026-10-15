import path from 'node:path';

import type { NextConfig } from 'next';

/**
 * pnpm keeps the real packages in the repo-root `node_modules/.pnpm` store, so
 * both Turbopack's resolver and the standalone output tracer have to treat the
 * monorepo root — not `apps/admin` — as the workspace root. Without this the
 * build fails with "Could not find the Next.js package".
 */
const repoRoot = path.join(__dirname, '..', '..');

/**
 * `output: 'standalone'` keeps the admin panel deployable two ways from the
 * same build: Firebase App Hosting (primary) and a plain container on Cloud
 * Run (fallback, see ../../docs/ADMIN_SETUP.md). It also trims the runtime
 * image to just the files the server actually needs.
 *
 * `firebase-admin` must never be bundled into the client graph — it is
 * server-only and pulls native deps. `serverExternalPackages` keeps it as a
 * real `require` at runtime.
 */
/**
 * Vercel builds and serves Next natively and does its own output tracing, so
 * `standalone` is both unnecessary and unhelpful there. It stays on everywhere
 * else, because the Dockerfile / Cloud Run path depends on the self-contained
 * server it produces.
 */
const onVercel = Boolean(process.env.VERCEL);

const nextConfig: NextConfig = {
  output: onVercel ? undefined : 'standalone',
  // Kept on Vercel too: with the app in a pnpm workspace, tracing has to start
  // at the repo root or server files from other packages are missed.
  outputFileTracingRoot: repoRoot,
  turbopack: { root: repoRoot },
  serverExternalPackages: ['firebase-admin'],
  reactStrictMode: true,
  // Next would otherwise write its own AGENTS.md and CLAUDE.md into this
  // directory on every dev run. The repo already has a hand-maintained
  // CLAUDE.md at the root, and these files would both shadow it and ship to
  // buyers in the distribution zip.
  agentRules: false,
};

export default nextConfig;
