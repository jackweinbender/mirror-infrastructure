# CI images

Reusable container images for repository automation live here. They are not
Compose stacks and are not deployed to infrastructure hosts.

## `ci-base`

`ci-base` is intentionally small while remaining useful for shell-based CI. It
is based on `debian:bookworm-slim` and includes:

- Bash, Git, curl, jq, Ruby, Python/pip, rsync, and OpenSSH client
- Docker CLI and Compose plugin from Docker's official APT repository
- 1Password CLI from the official 1Password APT repository
- Tailscale CLI from the official Tailscale APT repository
- The latest Terraform, Google Cloud CLI, and AWS CLI v2

The image is currently built for `linux/amd64`, matching the vendor packages and
AWS CLI installer used by the image. Terraform, Google Cloud CLI, and Docker are installed from their official APT
repositories; AWS CLI v2 is installed from its official installer archive. The
image includes the Docker client and Compose plugin only; it does not include a
Docker daemon. The package repositories are intentionally used rather
than downloading unverified binaries during the build; their APT signatures are
validated using the vendor keyrings.

Build locally with:

```bash
docker build --platform linux/amd64 -t ci-base:local ci-images/ci-base
```

The image does not connect to Tailscale or require credentials at build time. At runtime, provide a 1Password service-account token through `OP_SERVICE_ACCOUNT_TOKEN`; the 1Password CLI reads this variable automatically:

```bash
docker run --rm \
  --env OP_SERVICE_ACCOUNT_TOKEN \
  git.weinbender.io/labs/ci-base:latest \
  op vault list
```

For CI, configure `OP_SERVICE_ACCOUNT_TOKEN` as a masked repository or
organization secret and pass it through the job environment. Tailscale OAuth
credentials use the corresponding runtime variables already used by this
repository:

```yaml
env:
  OP_SERVICE_ACCOUNT_TOKEN: ${{ secrets.OP_SERVICE_ACCOUNT_TOKEN }}
  TS_OAUTH_CLIENT_ID: ${{ secrets.TS_OAUTH_CLIENT_ID }}
  TS_OAUTH_CLIENT_SECRET: ${{ secrets.TS_OAUTH_CLIENT_SECRET }}
```

The Tailscale GitHub Action consumes the OAuth client ID and secret to create a
short-lived connection. For direct CLI use, Tailscale supports using the OAuth
client secret as the auth key; the OAuth client must have the `auth_keys` scope
and the requested tag:

```bash
tailscale up \
  --auth-key="$TS_OAUTH_CLIENT_SECRET" \
  --advertise-tags="tag:ci"
```

The OAuth client ID is not needed by `tailscale up` in this mode. The image does
not make a token-exchange request at startup. Never add credentials to the
Dockerfile, image build arguments, repository, or shell command output.
