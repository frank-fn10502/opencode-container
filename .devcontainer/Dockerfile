FROM mcr.microsoft.com/devcontainers/javascript-node:1-22-bookworm

ARG OPENCODE_VERSION="latest"
ARG COMPANY_CA_CERT_B64=""

ENV DEBIAN_FRONTEND=noninteractive \
    TERM=xterm-256color \
    OPENCODE_USER=opencode \
    OPENCODE_HOME=/home/opencode/.local/share/opencode \
    OPENCODE_STATE_HOME=/home/opencode/.local/state \
    PYTHON_VENV=/opt/opencode-python \
    PATH=/opt/opencode-python/bin:/home/opencode/.local/bin:${PATH} \
    CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    PIP_CERT=/etc/ssl/certs/ca-certificates.crt

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

RUN if ! getent group "${OPENCODE_USER}" >/dev/null; then \
            groupadd "${OPENCODE_USER}"; \
        fi \
        && if ! id -u "${OPENCODE_USER}" >/dev/null 2>&1; then \
            useradd --create-home --gid "${OPENCODE_USER}" --shell /bin/bash "${OPENCODE_USER}"; \
        fi

# Debian Bookworm marks /usr/bin/python3 as externally managed (PEP 668), so
# normal pip installs must not target the system interpreter. Keep a writable
# default venv and expose wrapper scripts from /usr/local/bin; wrappers are used
# instead of symlinks so `python3 -m pip` keeps sys.prefix inside the venv.
RUN python3 -m venv "${PYTHON_VENV}" \
    && "${PYTHON_VENV}/bin/python" -m pip install --upgrade pip setuptools wheel \
    && printf '#!/bin/sh\nexec "%s/bin/python" "$@"\n' "${PYTHON_VENV}" > /usr/local/bin/python \
    && printf '#!/bin/sh\nexec "%s/bin/python3" "$@"\n' "${PYTHON_VENV}" > /usr/local/bin/python3 \
    && printf '#!/bin/sh\nexec "%s/bin/python" -m pip "$@"\n' "${PYTHON_VENV}" > /usr/local/bin/pip \
    && printf '#!/bin/sh\nexec "%s/bin/python3" -m pip "$@"\n' "${PYTHON_VENV}" > /usr/local/bin/pip3 \
    && chmod 755 /usr/local/bin/python /usr/local/bin/python3 /usr/local/bin/pip /usr/local/bin/pip3 \
    && chown -R "${OPENCODE_USER}:${OPENCODE_USER}" "${PYTHON_VENV}"

RUN if [ -n "${COMPANY_CA_CERT_B64}" ]; then \
      printf '%s' "${COMPANY_CA_CERT_B64}" | base64 -d > /usr/local/share/ca-certificates/company-ca.crt; \
      update-ca-certificates; \
    fi

RUN npm config set --global cafile /etc/ssl/certs/ca-certificates.crt \
    && npm config set --global fetch-retries 5 \
    && npm config set --global fetch-retry-mintimeout 20000 \
    && npm config set --global fetch-retry-maxtimeout 120000

RUN pip3 config --global set global.cert /etc/ssl/certs/ca-certificates.crt \
    && pip3 config --global set global.timeout 120 \
    && pip3 config --global set global.disable-pip-version-check true \
    && pip3 config --site set global.cert /etc/ssl/certs/ca-certificates.crt \
    && pip3 config --site set global.timeout 120 \
    && pip3 config --site set global.disable-pip-version-check true

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
