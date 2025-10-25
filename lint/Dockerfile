# ---------- builder: build Java jar ----------
FROM maven:3.8.5-openjdk-17 AS builder
WORKDIR /build
COPY lint/regex-checker/ ./lint/regex-checker/
WORKDIR /build/lint/regex-checker
RUN mvn -q -B package -DskipTests

# ---------- final runtime image: use official Rakudo image ----------
# 使用官方 rakudo 镜像，避免在构建时运行不稳定的安装脚本
FROM rakudo-star:latest

# 安装 JRE-runtime 与必要工具
RUN apk update && \
    # try common OpenJDK package names used in Alpine repos (order matters)
    apk add --no-cache openjdk17-jre || \
    apk add --no-cache openjdk17 || \
    apk add --no-cache openjdk11-jre || \
    apk add --no-cache openjdk11 || \
    (echo "Failed to install OpenJDK via apk; image may still work if JRE exists in base image" && true)

RUN apk add --no-cache wget ca-certificates unzip curl bash || true

WORKDIR /workspace

# 把构建好的 jar 复制到镜像
COPY --from=builder /build/lint/regex-checker/target/regex-checker-0.1.0-jar-with-dependencies.jar /opt/regex-checker.jar

# 把 linter 脚本复制到镜像
COPY lint/ /workspace/lint/

ENV PATH="/usr/local/bin:/usr/bin:/bin:${PATH}"

WORKDIR /workspace

ENTRYPOINT ["/bin/bash", "-lc"]
