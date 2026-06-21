# Dart Frog backend production image for Xene.
#
# BUILD CONTEXT = monorepo root (xene_dart/), NOT this folder, because the
# backend has a path dependency on ../xene_domain which must be inside the
# build context. From the repo root:
#
#   docker build -f packages/xene_backend/Dockerfile -t xene-backend .
#
# Two-stage build: compile to a self-contained native executable on the Dart
# SDK image, then ship only that exe + minimal runtime libs on `scratch`.

# ---------------------------------------------------------------------------
# Stage 1 — build & AOT-compile
# ---------------------------------------------------------------------------
FROM dart:stable AS build

# Dart Frog CLI, pinned to the version this repo was developed against.
RUN dart pub global activate dart_frog_cli 1.2.14

WORKDIR /app

# Flutter-free workspace root (see deploy/pubspec.workspace.yaml for the why).
COPY packages/xene_backend/deploy/pubspec.workspace.yaml ./pubspec.yaml

# The two pure-Dart workspace members. xene_domain ships committed *.g.dart /
# *.freezed.dart, so no build_runner step is needed in the image.
COPY packages/xene_domain ./packages/xene_domain
COPY packages/xene_backend ./packages/xene_backend

# Belt-and-suspenders: strip any host-generated artifacts that slipped past
# .dockerignore. A stale build/pubspec_overrides.yaml carries an absolute
# Windows path to xene_domain; stale .dart_tool dirs point at host paths.
RUN rm -rf packages/xene_backend/build \
           packages/xene_backend/.dart_tool \
           packages/xene_backend/pubspec_overrides.yaml \
           packages/xene_domain/.dart_tool

# Resolve the trimmed workspace.
RUN dart pub get

# Produce the Dart Frog production bundle. dart_frog regenerates
# build/pubspec_overrides.yaml with xene_domain pointing at the in-container
# absolute path (/app/packages/xene_domain) — Linux-correct, unlike the
# host-generated override.
WORKDIR /app/packages/xene_backend
RUN dart pub global run dart_frog_cli:dart_frog build

# AOT-compile the bundled server into a single native executable.
WORKDIR /app/packages/xene_backend/build
RUN dart pub get
RUN dart compile exe bin/server.dart -o /server

# ---------------------------------------------------------------------------
# Stage 2 — minimal runtime image
# ---------------------------------------------------------------------------
FROM scratch

# /runtime/ (shared libs + CA certs needed to run an AOT exe on scratch) is
# shipped by the official dart:stable image — the documented minimal-image path.
COPY --from=build /runtime/ /
COPY --from=build /server /app/bin/server

# Dart Frog binds InternetAddress.anyIPv6 on $PORT (default 8080). Azure
# Container Apps / App Service inject PORT; this default covers local runs.
ENV PORT=8080
EXPOSE 8080

CMD ["/app/bin/server"]
