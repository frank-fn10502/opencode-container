# opencode-dev profile Dockerfile guide

This directory stores opencode-dev profiles. A profile is a Dockerfile named:

```text
Dockerfile.<profile>
```

Examples:

```text
Dockerfile.python
Dockerfile.node
Dockerfile.rhel10
```

Use this document as the instruction source when asking AI to create or edit a profile Dockerfile.

## Required base image

Always start from the stable local base alias:

```dockerfile
FROM localhost/opencode-dev-yuta:base
```

Do not pin `localhost/opencode-dev-yuta:<version>` in profile Dockerfiles. The `base` alias is updated by `./init.sh`, so profiles do not need to change when opencode-dev is upgraded.

## User model

The base image has an `opencode` user and uses `/workspace` at runtime.

Use `USER root` only for system installation, then switch back to:

```dockerfile
USER opencode
```

The final instruction should normally be `USER opencode`.

## Build context

The Docker build context is this `.opencode-dev-yuta/` directory, not the project root.

Allowed:

```dockerfile
COPY ./some-config-file /some/path
```

Only if `some-config-file` is inside `.opencode-dev-yuta/`.

Do not assume these are available during image build:

```dockerfile
COPY ../package.json /tmp/package.json
COPY /workspace/package.json /tmp/package.json
RUN cd /workspace && npm install
```

`/workspace` is mounted only when `opencode-dev` starts the container. It is not available while building the profile image.

## What belongs in a profile

A profile should install reusable tools and configuration needed by this user or project, for example:

- OS packages such as compilers, libraries, database clients, or CLIs.
- Language runtimes or package managers.
- Global npm/pip/pipx tools.
- Company CA files or package manager config that can safely be stored in this directory.
- Shell or tool config that should exist before OpenCode starts.

Project dependencies that change frequently should usually stay in the project and be installed at runtime inside `/workspace`, not baked into the profile image.

## Secrets

Do not put secrets in Dockerfiles or files copied by Dockerfiles.

Avoid:

```dockerfile
ENV TOKEN=...
RUN npm config set //registry.example.com/:_authToken ...
```

Use runtime login flows, Docker volumes, or host-side secret handling instead.

## apt pattern

Use noninteractive apt installs, keep package lists clean, and avoid unnecessary recommended packages:

```dockerfile
FROM localhost/opencode-dev-yuta:base

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        <package-name> \
    && rm -rf /var/lib/apt/lists/*

USER opencode
```

## npm pattern

For global npm tools:

```dockerfile
FROM localhost/opencode-dev-yuta:base

USER root

RUN npm install -g <tool-name>

USER opencode
```

If the tool can be installed under the `opencode` user without root, prefer that.

## Python pattern

The base image puts a writable virtual environment at the front of `PATH`:

```text
/opt/opencode-python
```

Normal commands such as `python`, `python3`, `pip`, and `pip3` use that virtual
environment by default, so `pip install <package>` does not write into Debian's
externally managed system Python.

Prefer `pipx` for Python command-line tools:

```dockerfile
FROM localhost/opencode-dev-yuta:base

USER opencode

RUN pipx install <tool-name>
```

For Python packages that need native OS headers or clients, install only the OS
dependencies with `apt`, then install the Python package with `pip`, `pipx`, or
the project's own dependency manager:

```dockerfile
FROM localhost/opencode-dev-yuta:base

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        <system-package> \
    && rm -rf /var/lib/apt/lists/*

USER opencode

RUN pip install <python-package>
```

## Copying files

If a profile needs config files, place them beside the Dockerfile inside `.opencode-dev-yuta/`:

```text
.opencode-dev-yuta/
  Dockerfile.python
  pip.conf
  certs/company-ca.crt
```

Then copy them with paths relative to this directory:

```dockerfile
COPY ./pip.conf /etc/pip.conf
COPY ./certs/company-ca.crt /usr/local/share/ca-certificates/company-ca.crt
```

Use `USER root` before copying into system locations.

## Good minimal examples

Python tools:

```dockerfile
FROM localhost/opencode-dev-yuta:base

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libpq-dev \
    && rm -rf /var/lib/apt/lists/*

USER opencode

RUN pipx install poetry
```

Node tools:

```dockerfile
FROM localhost/opencode-dev-yuta:base

USER root

RUN npm install -g pnpm turbo

USER opencode
```

Mixed native build tools:

```dockerfile
FROM localhost/opencode-dev-yuta:base

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        pkg-config \
        libssl-dev \
    && rm -rf /var/lib/apt/lists/*

USER opencode
```

## Validation checklist

Before saving a Dockerfile, check:

- The filename is `Dockerfile.<profile>`.
- The first `FROM` is `localhost/opencode-dev-yuta:base`.
- Any root operation is followed by `USER opencode`.
- No secrets are embedded.
- No build step depends on `/workspace` or files outside `.opencode-dev-yuta/`.
- apt package lists are cleaned after installation.
- The Dockerfile installs reusable environment tools, not frequently changing project dependencies.
