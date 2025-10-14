# Find eligible builder and runner images on Docker Hub
# Elixir: https://hub.docker.com/_/elixir
# Debian: https://hub.docker.com/_/debian

ARG ELIXIR_VERSION=1.17.3
ARG OTP_VERSION=27
ARG DEBIAN_VERSION=bookworm-20240926-slim

ARG BUILDER_IMAGE="elixir:${ELIXIR_VERSION}-otp-${OTP_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

# Install build dependencies including Node.js
RUN apt-get update -y && apt-get install -y build-essential git curl \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set build ENV
ENV MIX_ENV="prod"

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Prepare build directory
WORKDIR /app

# Install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mkdir config

# Copy compile-time config files before we compile dependencies
COPY config/config.exs config/prod.exs config/
RUN mix deps.compile

# Copy application code
COPY priv priv
COPY lib lib
COPY assets assets

# Install npm dependencies for frontend assets
RUN cd assets && npm install

# Compile assets (if using esbuild/tailwind)
RUN mix assets.deploy

# Compile the release
RUN mix compile

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

# Compile the release
RUN mix release

# Start a new build stage for a lean runtime container
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
  apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates curl \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR /app
RUN chown nobody /app

# Set runner ENV
ENV MIX_ENV="prod"

# Copy built application from builder
# Note: The path matches your app name in mix.exs (app: :life_org)
COPY --from=builder --chown=nobody:root /app/_build/prod/rel/life_org ./

USER nobody

# Health check endpoint (adjust if your route is different)
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:4000/health || exit 1

# Start the Phoenix server
CMD ["/app/bin/life_org", "start"]
