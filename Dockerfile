# Papermark — multi-stage production build for self-hosted deployment.
#
# Build:
#   docker buildx build --tag papermark:latest .

# ---------------------------------------------------------------------------
# Stage 1: Install dependencies
# ---------------------------------------------------------------------------
FROM node:22-alpine AS deps

RUN apk add --no-cache libc6-compat openssl

WORKDIR /app

COPY package.json package-lock.json* yarn.lock* pnpm-lock.yaml* ./
COPY prisma ./prisma/

# Detect package manager and install dependencies.
RUN \
    if [ -f yarn.lock ]; then yarn --frozen-lockfile; \
    elif [ -f package-lock.json ]; then npm ci; \
    elif [ -f pnpm-lock.yaml ]; then corepack enable pnpm && pnpm install --frozen-lockfile; \
    else echo "No lockfile found" && exit 1; \
    fi

# ---------------------------------------------------------------------------
# Stage 2: Build the Next.js application
# ---------------------------------------------------------------------------
FROM node:22-alpine AS builder

RUN apk add --no-cache libc6-compat openssl

WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Replace upstream next.config with Docker-optimised version that sets
# output: 'standalone' and removes Vercel-specific logic.
COPY next.config.docker.js ./next.config.js
# Remove the original .mjs config so Next.js uses our .js version.
RUN rm -f next.config.mjs

# Disable Next.js telemetry during build.
ENV NEXT_TELEMETRY_DISABLED=1
ENV NODE_ENV=production

# Generate Prisma client.
RUN npx prisma generate

# Next.js requires certain env vars at build time for static page generation.
# Papermark eagerly initializes SDK clients at module scope during page data
# collection.  All integration env vars must be set to non-empty dummy values
# to prevent crashes.  Runtime env vars override these.
ENV NEXT_PUBLIC_BASE_URL=https://dataroom.sakuraindustries.net \
    NEXTAUTH_URL=https://dataroom.sakuraindustries.net \
    NEXTAUTH_SECRET=build-time-dummy-secret-not-used-at-runtime \
    NEXT_PUBLIC_APP_BASE_HOST=localhost:3000 \
    NEXT_PUBLIC_WEBHOOK_BASE_HOST=localhost:3000 \
    NEXT_PUBLIC_MARKETING_URL=https://dataroom.sakuraindustries.net \
    DATABASE_URL=postgresql://dummy:dummy@localhost:5432/dummy \
    OPENAI_API_KEY=sk-dummy-build-time-key-012345678901234567890123456789 \
    HANKO_API_KEY=dummy-hanko-api-key \
    NEXT_PUBLIC_HANKO_TENANT_ID=dummy-hanko-tenant-id \
    SLACK_CLIENT_ID=dummy-slack-client-id \
    SLACK_CLIENT_SECRET=dummy-slack-client-secret \
    SLACK_SIGNING_SECRET=dummy-slack-signing-secret \
    UPSTASH_REDIS_REST_URL=https://dummy.upstash.io \
    UPSTASH_REDIS_REST_TOKEN=dummy-redis-token \
    QSTASH_TOKEN=dummy-qstash-token \
    QSTASH_CURRENT_SIGNING_KEY=dummy-qstash-signing-key \
    QSTASH_NEXT_SIGNING_KEY=dummy-qstash-next-signing-key \
    TINYBIRD_TOKEN=dummy-tinybird-token \
    RESEND_API_KEY=re_dummy_build_time_key \
    STRIPE_SECRET_KEY=sk_test_dummy \
    NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY=pk_test_dummy \
    STRIPE_WEBHOOK_SECRET=whsec_dummy \
    NEXT_PRIVATE_UPLOAD_BUCKET=dummy \
    NEXT_PRIVATE_UPLOAD_ACCESS_KEY_ID=dummy \
    NEXT_PRIVATE_UPLOAD_SECRET_ACCESS_KEY=dummy \
    NEXT_PRIVATE_UPLOAD_ENDPOINT=https://dummy.r2.cloudflarestorage.com \
    NEXT_PUBLIC_UPLOAD_TRANSPORT=s3 \
    TRIGGER_SECRET_KEY=tr_dummy_trigger_key \
    NEXT_PRIVATE_UNSUBSCRIBE_JWT_SECRET=dummy-jwt-secret-for-build

# Build the application.
RUN \
    if [ -f yarn.lock ]; then yarn build; \
    elif [ -f package-lock.json ]; then npm run build; \
    elif [ -f pnpm-lock.yaml ]; then corepack enable pnpm && pnpm run build; \
    else echo "No lockfile found" && exit 1; \
    fi

# ---------------------------------------------------------------------------
# Stage 3: Production runtime
# ---------------------------------------------------------------------------
FROM node:22-alpine AS runner

RUN apk add --no-cache libc6-compat openssl curl bash

WORKDIR /app

# Run as non-root.
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV HOSTNAME=0.0.0.0
ENV PORT=3000

# Copy standalone build (includes server.js and minimal node_modules).
COPY --from=builder /app/.next/standalone ./
# Static files and public assets are not included in standalone output.
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/public ./public
COPY --from=builder /app/prisma ./prisma
# Copy Prisma CLI + engines from builder so npx uses the correct version.
COPY --from=builder /app/node_modules/.prisma ./node_modules/.prisma
COPY --from=builder /app/node_modules/prisma ./node_modules/prisma
COPY --from=builder /app/node_modules/@prisma ./node_modules/@prisma

# Copy entrypoint script.
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Set ownership.
RUN chown -R nextjs:nodejs /app

USER nextjs

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:3000/api/health || exit 1

ENTRYPOINT ["docker-entrypoint.sh"]
