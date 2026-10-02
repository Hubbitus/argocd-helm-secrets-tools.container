# syntax=docker/dockerfile:1.7
# Minimal busybox image bundling helm-secrets (sops backend), sops, and age
# for the ArgoCD repo-server helm-secrets plugin init-container.
# Every base image, binary, and checksum is pinned exactly; bump via Renovate / manual PR.

ARG DEBIAN_BASE=docker.io/library/debian:bookworm-slim@sha256:3783cc01769c7b2b1b83a5c5ad96c815348e28ed7da68e2e3687004faa906251
ARG BUSYBOX_BASE=docker.io/library/busybox:1.37.0@sha256:bdf57e528e45e4433820e045b29b4597825a1c9e38353532d90a01445013f82e

# ---------- Stage 1: download and verify tools ----------
FROM ${DEBIAN_BASE} AS builder

ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# helm-secrets plugin packaged as a Helm plugin chart.
# Provenance (.prov) is verified in CI; here we pin the chart SHA-256.
ARG HELM_SECRETS_VERSION=4.7.8
ARG HELM_SECRETS_TARBALL_SHA256=d0132dded2644d2e7cfea0b7ce11a8bbedb67af303a9b6e6b7f5a3230c825230
RUN curl -fsSL -o helm-secrets.tgz \
        "https://github.com/jkroepke/helm-secrets/releases/download/v${HELM_SECRETS_VERSION}/secrets-${HELM_SECRETS_VERSION}.tgz" \
    && echo "${HELM_SECRETS_TARBALL_SHA256}  helm-secrets.tgz" | sha256sum -c - \
    && mkdir -p /tools/secrets \
    && tar -xzf helm-secrets.tgz -C /tools/secrets --strip-components=1 \
    && rm helm-secrets.tgz

# sops
ARG SOPS_VERSION=3.13.3
ARG SOPS_AMD64_SHA256=e5bec3346a873ae91d871550f3e698c1aad962aff462a080e40f25fde17fef6b
ARG SOPS_ARM64_SHA256=53b0abacd38ef1b12a66d6c100956691b9cefce018d91f81e73ddf7438b94d77
RUN mkdir -p /tools/bin \
    && case "${TARGETARCH}" in \
        amd64) SOPS_SHA256=${SOPS_AMD64_SHA256}; SOPS_BINARY="sops-v${SOPS_VERSION}.linux.amd64" ;; \
        arm64) SOPS_SHA256=${SOPS_ARM64_SHA256}; SOPS_BINARY="sops-v${SOPS_VERSION}.linux.arm64" ;; \
        *) echo "unsupported architecture: ${TARGETARCH}"; exit 1 ;; \
       esac \
    && curl -fsSL -o sops \
        "https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/${SOPS_BINARY}" \
    && echo "${SOPS_SHA256}  sops" | sha256sum -c - \
    && install -m 0755 sops /tools/bin/sops \
    && rm sops

# age
ARG AGE_VERSION=1.3.2
ARG AGE_AMD64_SHA256=cbe24006683f8eb669266162894b9a522a1af52f2665fbc63a4bb032ed26ac10
ARG AGE_ARM64_SHA256=6b8dc4333c53a5a57c9e5834e3a48f92605d7154014cd07269ff3327db5d37f4
RUN case "${TARGETARCH}" in \
        amd64) AGE_SHA256=${AGE_AMD64_SHA256}; AGE_TARBALL="age-v${AGE_VERSION}-linux-amd64.tar.gz" ;; \
        arm64) AGE_SHA256=${AGE_ARM64_SHA256}; AGE_TARBALL="age-v${AGE_VERSION}-linux-arm64.tar.gz" ;; \
        *) echo "unsupported architecture: ${TARGETARCH}"; exit 1 ;; \
       esac \
    && curl -fsSL -o age.tar.gz \
        "https://github.com/FiloSottile/age/releases/download/v${AGE_VERSION}/${AGE_TARBALL}" \
    && echo "${AGE_SHA256}  age.tar.gz" | sha256sum -c - \
    && mkdir -p /tmp/age-extract \
    && tar -xzf age.tar.gz -C /tmp/age-extract \
    && install -m 0755 /tmp/age-extract/age/age /tools/bin/age \
    && install -m 0755 /tmp/age-extract/age/age-keygen /tools/bin/age-keygen \
    && rm -rf /tmp/age-extract age.tar.gz

# Helm wrapper must shadow the real helm binary in PATH.
# Relative symlink so it stays valid after copying /tools to another mount path.
RUN ln -s ../secrets/scripts/wrapper/helm.sh /tools/bin/helm

# ---------- Stage 2: final runtime image ----------
FROM ${BUSYBOX_BASE}

COPY --from=builder /tools /tools

# Default behaviour: copy everything under /tools into the caller-supplied directory.
# ArgoCD repo-server mounts the emptyDir at the same path this container writes to.
ENTRYPOINT ["/bin/sh", "-c", "cp -a /tools/* \"${TARGET_DIR:-/out}/\""]

LABEL org.opencontainers.image.title="argocd-helm-secrets-tools" \
      org.opencontainers.image.description="Busybox image with helm-secrets plugin, sops, and age for ArgoCD repo-server init-containers" \
      org.opencontainers.image.source="https://github.com/Hubbitus/argocd-helm-secrets-tools.container" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="Hubbitus"
