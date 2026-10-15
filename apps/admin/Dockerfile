# Fallback deploy path for the Moneymind admin panel (Cloud Run, or any
# container host). Firebase App Hosting is the primary target and needs none of
# this — see apphosting.yaml and docs/ADMIN_SETUP.md.
#
# Build from the REPO ROOT so the pnpm workspace resolves:
#   docker build -f apps/admin/Dockerfile -t moneymind-admin .
#
# Or let Cloud Run build it for you, from the repo root:
#   gcloud run deploy moneymind-admin --source . --region asia-southeast1
#
# Credentials come from the runtime service account (Application Default
# Credentials). Never bake a service-account key into this image.

FROM node:22-slim AS base
ENV PNPM_HOME="/pnpm" PATH="/pnpm:$PATH"
RUN corepack enable

# ---- Install workspace dependencies -----------------------------------------
FROM base AS deps
WORKDIR /repo
COPY pnpm-lock.yaml pnpm-workspace.yaml package.json ./
COPY apps/admin/package.json ./apps/admin/
RUN pnpm install --frozen-lockfile --filter admin...

# ---- Build -------------------------------------------------------------------
FROM base AS builder
WORKDIR /repo
COPY --from=deps /repo/node_modules ./node_modules
COPY --from=deps /repo/apps/admin/node_modules ./apps/admin/node_modules
COPY pnpm-lock.yaml pnpm-workspace.yaml package.json ./
COPY apps/admin ./apps/admin
ENV NEXT_TELEMETRY_DISABLED=1
RUN pnpm -F admin build

# ---- Runtime -----------------------------------------------------------------
FROM node:22-slim AS runner
WORKDIR /app
ENV NODE_ENV=production NEXT_TELEMETRY_DISABLED=1 PORT=8080
RUN groupadd --system --gid 1001 nodejs \
  && useradd --system --uid 1001 --gid nodejs nextjs

# `output: 'standalone'` emits a self-contained server plus a trimmed
# node_modules; static assets must be copied alongside it.
#
# Because outputFileTracingRoot is the monorepo root, the standalone tree keeps
# the workspace layout: server.js lands at apps/admin/server.js, and .next/static
# and public/ must sit beside it — not at the image root.
COPY --from=builder --chown=nextjs:nodejs /repo/apps/admin/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /repo/apps/admin/.next/static ./apps/admin/.next/static
COPY --from=builder --chown=nextjs:nodejs /repo/apps/admin/public ./apps/admin/public

USER nextjs
EXPOSE 8080
CMD ["node", "apps/admin/server.js"]
