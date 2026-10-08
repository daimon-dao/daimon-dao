# syntax=docker/dockerfile:1
#
# The IPFS mirror build, reproducible by anyone (docs/IPFS_MIRROR.md,
# "Reproducible build: the container").
#
# The CID of the mirror is a hash of the exported bytes, and those bytes
# depend on more than the commit: Next's client-entry module ids hash the
# ABSOLUTE path of the checkout, and the toolchain (Node, npm, the OS) can
# change the output too. This file pins all of it: one base image by digest
# (Node 24.20.0 on Debian bookworm, linux/amd64), one path (/build), the
# dependencies exactly as package-lock.json records them (`npm ci`, with the
# lockfile's integrity hashes), and the committed .env.ipfs as the only
# environment. Nothing in here is secret and nothing is published: the
# result is a folder with the CID and the CAR to pin.
#
#   # from the repository root, the context is the committed tree of
#   # daimon-dapp/ (no working-tree edits, no line-ending conversion):
#   git -c core.autocrlf=false archive --format=tar "HEAD:daimon-dapp" \
#     | docker build - \
#         --build-arg "SOURCE_COMMIT=$(git rev-parse HEAD)" \
#         --no-cache --progress=plain \
#         --output type=local,dest=release-ipfs
#   cat release-ipfs/CID.txt
#
# The same command runs in .github/workflows/ipfs-mirror.yml. SOURCE_COMMIT
# is the full commit hash of the tree being built (there is no .git inside
# the container): it is written into mirror.json, so the CID is tied to the
# exact commit.

# node:24.20.0-bookworm, multi-arch index digest (Docker Hub, pushed
# 2026-08-27); linux/amd64 within it is sha256:9137a20e25879e0b557227b57e3ee4e9af4bde29eb3db66134cd1723e84f830b.
FROM --platform=linux/amd64 node:24.20.0-bookworm@sha256:be23f54a88d34e8824c741b19b91064094f92c1c97b194144bfc8b50d67258e2 AS build

ARG SOURCE_COMMIT
RUN echo "$SOURCE_COMMIT" | grep -Eq '^[0-9a-f]{40}$' \
  || { echo "SOURCE_COMMIT must be the full 40-hex commit of the tree being built (git rev-parse HEAD), got: '$SOURCE_COMMIT'" >&2; exit 1; }

# The fixed path: every absolute path webpack hashes is under /build.
WORKDIR /build

# Dependencies first (cached between local rebuilds; the workflow builds
# with --no-cache anyway). npm ci installs exactly what the lockfile says and
# fails if package.json and package-lock.json disagree.
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund

# The rest of the tree (.dockerignore keeps out node_modules, build outputs
# and every .env* file except the committed .env.ipfs).
COPY . .

# The build: a static export with the ipfs target, post-processed, then the
# CID and the CAR (scripts/build-ipfs.mjs). With no git checkout inside the
# container the script takes the commit from DAPP_SOURCE_COMMIT.
RUN DAPP_SOURCE_COMMIT="$SOURCE_COMMIT" npm run build:ipfs

# What the verifier compares, written next to the CAR and printed in the log.
RUN cd release-ipfs \
  && sha256sum daimon-dapp.car > SHA256SUMS \
  && printf 'ipfs-mirror: commit %s\nipfs-mirror: CID %s\nipfs-mirror: CAR sha256 %s\n' \
       "$SOURCE_COMMIT" "$(cat CID.txt)" "$(cut -d' ' -f1 SHA256SUMS)"

# The output stage: `docker build --output type=local,dest=<dir>` writes only
# this. CID.txt, daimon-dapp.car (the blocks to pin, root = the CID),
# mirror.json, SHA256SUMS, and site/ (the exported folder, for diffing).
FROM scratch AS release
COPY --from=build /build/release-ipfs/ /
COPY --from=build /build/out-ipfs/ /site/
