# Dockerfile: OpenJDK 17 + Rakudo
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-17-jdk-headless wget ca-certificates unzip maven build-essential libssl-dev zlib1g-dev \
  && rm -rf /var/lib/apt/lists/*
RUN wget -qO /tmp/rakudo-install.sh https://rakudo.org/install.sh && chmod +x /tmp/rakudo-install.sh && /tmp/rakudo-install.sh --prefix=/opt/rakudo --quiet && ln -s /opt/rakudo/bin/raku /usr/local/bin/raku
WORKDIR /workspace
ENTRYPOINT ["/bin/bash", "-lc"]
