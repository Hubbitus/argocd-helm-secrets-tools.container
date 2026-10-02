# argocd-helm-secrets-tools

Minimal busybox image bundling the [helm-secrets](https://github.com/jkroepke/helm-secrets)
Helm plugin (sops backend), [sops](https://github.com/getsops/sops), and
[age](https://github.com/FiloSottile/age) for the ArgoCD repo-server
`helm-secrets` plugin init-container.

Published to: `docker.io/hubbitus/argocd-helm-secrets-tools`

## Versions

| Tool            | Version |
|-----------------|---------|
| helm-secrets    | 4.7.8   |
| sops            | 3.13.3  |
| age             | 1.3.2   |
| busybox (base)  | 1.37.0  |

All binaries and base images are pinned by SHA-256. Upstream signatures are
verified in CI before the image build:

- helm-secrets `.prov` file is verified with the publisher's GPG key in `keys/jkroepke.asc`.
- sops `checksums.txt` is verified with the Sigstore bundle via `cosign verify-blob`.

## Usage in ArgoCD

Mount an `emptyDir` volume into both the init-container (this image) and the
repo-server container. The init-container copies `/tools/*` into the volume:

```yaml
initContainers:
  - name: download-tools
    image: docker.io/hubbitus/argocd-helm-secrets-tools:1.0.0
    env:
      - name: TARGET_DIR
        value: /helm-secrets-tools
    volumeMounts:
      - name: helm-secrets-tools
        mountPath: /helm-secrets-tools
containers:
  - name: argocd-repo-server
    env:
      - name: HELM_PLUGINS
        value: /helm-secrets-tools
      - name: PATH
        value: /helm-secrets-tools/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
      - name: HELM_SECRETS_WRAPPER_ENABLED
        value: "true"
      - name: HELM_SECRETS_HELM_PATH
        value: /usr/local/bin/helm
    volumeMounts:
      - name: helm-secrets-tools
        mountPath: /helm-secrets-tools
```

`HELM_SECRETS_WRAPPER_ENABLED=true` makes the wrapper script at
`/helm-secrets-tools/bin/helm` decrypt `secrets://` value files before delegating
to the real Helm binary at `HELM_SECRETS_HELM_PATH`.

## Build locally

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t argocd-helm-secrets-tools:latest .
```

## Secrets

The GitHub Actions workflow expects Docker Hub credentials in repository secrets:

- `DOCKERHUB_USER`
- `DOCKERHUB_TOKEN`

These are not stored in this repository.
