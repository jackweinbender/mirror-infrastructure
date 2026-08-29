FROM debian:trixie-slim AS base

ARG TARGETARCH=amd64

LABEL org.opencontainers.image.title="CI base"
LABEL org.opencontainers.image.description="Small Debian CI image with 1Password CLI and Tailscale"

RUN apt-get update && apt-get install --no-install-recommends --yes \
    bash \
    ca-certificates \
    curl \
    git \
    gnupg \
    jq \
    openssh-client \
    python3-pip \
    python3-venv \
    rsync \
    ruby \
    unzip

RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) vendor_arch=amd64 ;; \
        *) echo "This CI image currently supports amd64 only" >&2; exit 1 ;; \
    esac; \
    install -d -m 0755 /etc/apt/keyrings; \
    curl --fail --silent --show-error --location https://downloads.1password.com/linux/keys/1password.asc \
        | gpg --dearmor --output /etc/apt/keyrings/1password.gpg; \
    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/1password.gpg] https://downloads.1password.com/linux/debian/%s stable main\n' \
        "${vendor_arch}" "${vendor_arch}" > /etc/apt/sources.list.d/1password.list; \
    curl --fail --silent --show-error --location https://apt.releases.hashicorp.com/gpg \
        | gpg --dearmor --output /etc/apt/keyrings/hashicorp.gpg; \
    printf 'deb [signed-by=/etc/apt/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com trixie main\n' \
        > /etc/apt/sources.list.d/hashicorp.list; \
    curl --fail --silent --show-error --location https://packages.cloud.google.com/apt/doc/apt-key.gpg \
        | gpg --dearmor --output /etc/apt/keyrings/google-cloud.gpg; \
    printf 'deb [signed-by=/etc/apt/keyrings/google-cloud.gpg] https://packages.cloud.google.com/apt cloud-sdk main\n' \
        > /etc/apt/sources.list.d/google-cloud-sdk.list; \
    curl --fail --silent --show-error --location https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg \
        --output /usr/share/keyrings/tailscale-archive-keyring.gpg; \
    curl --fail --silent --show-error --location https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list \
        --output /etc/apt/sources.list.d/tailscale.list; \
    curl --fail --silent --show-error --location https://download.docker.com/linux/debian/gpg \
        | gpg --dearmor --output /etc/apt/keyrings/docker.gpg; \
    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian trixie stable\n' \
        "${vendor_arch}" > /etc/apt/sources.list.d/docker.list

RUN apt-get update && apt-get install --no-install-recommends --yes \
    1password-cli \
    docker-ce-cli \
    docker-compose-plugin \
    google-cloud-cli \
    tailscale \
    terraform

RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) aws_arch=x86_64 ;; \
        *) echo "This CI image currently supports amd64 only" >&2; exit 1 ;; \
    esac; \
    curl --fail --silent --show-error --location \
        "https://awscli.amazonaws.com/awscli-exe-linux-${aws_arch}.zip" \
        --output /tmp/awscliv2.zip; \
    unzip -q /tmp/awscliv2.zip -d /tmp; \
    /tmp/aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update

FROM base AS ansible

COPY ansible/requirements.txt /tmp/ansible-requirements.txt
RUN pip install --break-system-packages --no-cache-dir -r /tmp/ansible-requirements.txt \
    && rm /tmp/ansible-requirements.txt

COPY ansible/ansible-requirements.yaml /tmp/ansible-galaxy-requirements.yaml
RUN ansible-galaxy collection install -r /tmp/ansible-galaxy-requirements.yaml \
    && rm /tmp/ansible-galaxy-requirements.yaml

WORKDIR /workspace

CMD ["bash"]
