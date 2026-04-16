FROM mcr.microsoft.com/devcontainers/javascript-node:1-22-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    TERM=xterm-256color \
    OPENCODE_HOME=/home/node/.local/share/opencode \
    OPENCODE_STATE_HOME=/home/node/.local/state

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        less \
        ripgrep \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g opencode-ai

RUN mkdir -p \
        /workspace \
        /home/node/.config/opencode \
        "${OPENCODE_HOME}" \
        "${OPENCODE_STATE_HOME}" \
    && chown -R node:node \
        /workspace \
        /home/node/.config/opencode \
        /home/node/.local

WORKDIR /workspace
USER node

CMD ["opencode"]
