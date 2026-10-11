# syntax=docker/dockerfile:1
#
# The website image. Multi-stage so the runtime layer carries no compiler, no
# devDependencies and no build cache.
#
# node:22-slim, NOT alpine. mysql2 3.24.5 ships no prebuilt binaries (verified:
# no prebuilds/ directory in the package), so `npm ci` compiles the native
# binding. On alpine that means building against musl with a different
# toolchain; on slim the build-essential packages below are the whole story.
# The images are bigger and the build is slower, but the thing being built is
# the same one that runs locally.

# ---- deps -------------------------------------------------------------------
FROM node:22-slim AS deps
WORKDIR /app

# Build tools for mysql2's native binding. Removed from every later stage.
RUN apt-get update \
  && apt-get install -y --no-install-recommends python3 make g++ ca-certificates \
  && rm -rf /var/lib/apt/lists/*

COPY package.json package-lock.json ./
RUN npm ci

# ---- builder ----------------------------------------------------------------
FROM node:22-slim AS builder
WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY . .

# NEXT_PHASE is set by `next build` itself; these are here so the image builds
# even if someone runs it by hand with a bare `next build`. See config.ts: a
# missing runtime variable must not abort a build.
ENV NEXT_TELEMETRY_DISABLED=1

# The build step died on the deploy host with exit 255 and no output at all,
# right after "Creating an optimized production build ...". A process that
# vanishes without a line of diagnostics was killed, not refused: the build ran
# out of memory and the kernel took it. A V8 heap limit turns that silent kill
# into a build that either completes or says exactly why it could not.
#
# Set this to roughly 60% of the RAM actually free on the host WHILE the build
# runs. Too high and the kernel kills it again; too low and this build fails
# with "JavaScript heap out of memory", which is at least an answer.
ARG NODE_BUILD_MEMORY_MB=2048
ENV NODE_OPTIONS=--max-old-space-size=${NODE_BUILD_MEMORY_MB}

RUN npm run build

# ---- runner -----------------------------------------------------------------
FROM node:22-slim AS runner
WORKDIR /app

ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    PORT=3000 \
    HOSTNAME=0.0.0.0

# A non-root user. The application writes nothing to disk, so the filesystem can
# stay read-only apart from /tmp, which Next needs for image optimisation.
RUN groupadd --system --gid 1001 nodejs \
  && useradd --system --uid 1001 --gid nodejs nextjs

# There is deliberately NO `COPY --from=builder /app/public ./public` here.
# This project has no public/ directory and no local static assets — every image
# it renders comes from the Discord CDN. A copy of a directory that does not
# exist fails the whole build, so this line is omitted rather than guarded.
# If a public/ folder is ever added, put this back in the runner stage:
#     COPY --from=builder /app/public ./public

# `output: 'standalone'` produced this. server.js is the entrypoint.
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs
EXPOSE 3000

CMD ["node", "server.js"]