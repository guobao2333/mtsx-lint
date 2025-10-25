# Multi-stage: build the Java jar, then assemble runtime image with OpenJDK + Rakudo + jar

# ---------- builder: build Java jar ----------
FROM maven:3.8.5-openjdk-17 AS builder

WORKDIR /build
# copy only the regex-checker module to speed layer caching
COPY lint/regex-checker/ ./lint/regex-checker/
WORKDIR /build/lint/regex-checker

# build jar (assembly plugin produces jar-with-dependencies)
RUN mvn -q -B package -DskipTests

# ---------- final runtime image ----------
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install JDK runtime and required tools
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
     openjdk-17-jre-headless wget ca-certificates unzip curl git \
     build-essential libssl-dev zlib1g-dev \
  && rm -rf /var/lib/apt/lists/*

# Install Rakudo (Rakudo installer script)
# Using the official installer script; installs to /opt/rakudo
RUN wget -qO /tmp/rakudo-install.sh https://rakudo.org/install.sh \
  && chmod +x /tmp/rakudo-install.sh \
  && /tmp/rakudo-install.sh --prefix=/opt/rakudo --quiet \
  && ln -s /opt/rakudo/bin/raku /usr/local/bin/raku \
  && ln -s /opt/rakudo/bin/perl6 /usr/local/bin/perl6

# Create app directory
WORKDIR /workspace

# Copy built jar from builder stage
COPY --from=builder /build/lint/regex-checker/target/regex-checker-0.1.0-jar-with-dependencies.jar /opt/regex-checker.jar

# Copy linter scripts so container can run them
COPY lint/ /workspace/lint/

# Ensure raku is on PATH (symlink already created). Also expose a simple entrypoint.
ENV PATH="/opt/rakudo/bin:${PATH}"

# Default workdir is /workspace
WORKDIR /workspace

# Entrypoint is bash to make it easy to run test commands; container is intended to be run with docker run ... <cmd>
ENTRYPOINT ["/bin/bash", "-lc"]
