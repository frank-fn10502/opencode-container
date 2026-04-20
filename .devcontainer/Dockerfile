FROM mcr.microsoft.com/devcontainers/javascript-node:1-22-bookworm

ARG OPENCODE_VERSION="latest"
ARG COMPANY_CA_CERT_B64=""

ENV DEBIAN_FRONTEND=noninteractive \
    TERM=xterm-256color \
    OPENCODE_USER=opencode \
    OPENCODE_HOME=/home/opencode/.local/share/opencode \
    OPENCODE_STATE_HOME=/home/opencode/.local/state

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        wget \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        sudo \
        less \
        ripgrep \
        build-essential \
        cmake \
        git \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev \
        python3-setuptools \
        python3-wheel \
        pipx \
    && rm -rf /var/lib/apt/lists/*

RUN if [ -n "${COMPANY_CA_CERT_B64}" ]; then \
      printf '%s' "${COMPANY_CA_CERT_B64}" | base64 -d > /usr/local/share/ca-certificates/company-ca.crt; \
      update-ca-certificates; \
    fi

RUN npm config set cafile /etc/ssl/certs/ca-certificates.crt \
    && npm config set fetch-retries 5 \
    && npm config set fetch-retry-mintimeout 20000 \
    && npm config set fetch-retry-maxtimeout 120000

RUN pip3 config --global set global.cert /etc/ssl/certs/ca-certificates.crt \
    && pip3 config --global set global.timeout 120 \
    && pip3 config --global set global.disable-pip-version-check true

RUN if ! getent group "${OPENCODE_USER}" >/dev/null; then \
            groupadd "${OPENCODE_USER}"; \
        fi \
        && if ! id -u "${OPENCODE_USER}" >/dev/null 2>&1; then \
            useradd --create-home --gid "${OPENCODE_USER}" --shell /bin/bash "${OPENCODE_USER}"; \
        fi

RUN usermod -aG sudo "${OPENCODE_USER}" \
    && echo "${OPENCODE_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${OPENCODE_USER}" \
    && chmod 0440 "/etc/sudoers.d/${OPENCODE_USER}"

RUN npm install -g "opencode-ai@${OPENCODE_VERSION}"

RUN mkdir -p \
        /workspace \
        /home/opencode/.config/opencode \
        "${OPENCODE_HOME}" \
        "${OPENCODE_STATE_HOME}" \
    && chown -R "${OPENCODE_USER}:${OPENCODE_USER}" \
        /workspace \
        /home/opencode/.config/opencode \
        /home/opencode/.local

COPY scripts/runtime/entrypoint-opencode.sh /usr/local/bin/entrypoint-opencode.sh

RUN chmod 755 /usr/local/bin/entrypoint-opencode.sh

WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/entrypoint-opencode.sh"]

CMD ["opencode"]
