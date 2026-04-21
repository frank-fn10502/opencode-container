---
description: Create or update an opencode-dev project profile Dockerfile
---

Create or update an opencode-dev project profile for the current workspace.

User request and optional arguments:

```text
$ARGUMENTS
```

Treat the first argument as the preferred profile name only if it is a safe
profile name matching `^[A-Za-z0-9_.-]+$`. If no safe profile name is supplied,
use `project`.

Your task:

1. Inspect the project from `/workspace` and infer reusable environment tools
   needed by this project. Prefer concrete evidence from files such as
   `package.json`, `pyproject.toml`, `requirements.txt`, `go.mod`, `Cargo.toml`,
   `*.csproj`, `CMakeLists.txt`, build scripts, lockfiles, and error messages
   already present in the conversation.
2. Create or update only files under `/workspace/.opencode-dev-yuta/`.
3. Write the profile Dockerfile to:

   ```text
   /workspace/.opencode-dev-yuta/Dockerfile.<profile>
   ```

4. Select the profile for the project by writing:

   ```text
   /workspace/.opencode-dev-yuta/config.env
   ```

   with exactly:

   ```text
   SELECTED_PROFILE=<profile>
   ```

5. Explain that the current container will not change in-place. The user must
   exit and run `opencode-dev` again so the launcher can build and start the new
   profile image.

Profile Dockerfile rules:

- The first instruction must be:

  ```dockerfile
  FROM localhost/opencode-dev-yuta:base
  ```

- Install reusable system tools, language runtimes, global CLIs, package manager
  configuration, and stable environment setup.
- Do not bake frequently changing project dependencies into the image.
- Do not run commands that depend on `/workspace`; it is available only at
  runtime, not during Docker image build.
- Do not copy files from outside `/workspace/.opencode-dev-yuta/`.
- Do not store secrets, tokens, private keys, or credentials in the Dockerfile or
  copied files.
- Do not set `USER` in normal project profiles. Profile Dockerfiles are build
  recipes that run as root. opencode-dev owns the runtime user switch: its
  entrypoint starts as root, syncs UID/GID and volume ownership, then runs
  OpenCode as `opencode`.
- For apt installs, use `--no-install-recommends` and clean package lists:

  ```dockerfile
  RUN apt-get update \
      && apt-get install -y --no-install-recommends \
          <package-name> \
      && rm -rf /var/lib/apt/lists/*
  ```

- For Python command-line tools, install reusable tools into the shared base
  venv with `pip install <tool>`. The base image puts `/opt/opencode-python` at
  the front of `PATH`.
- For Node command-line tools, install stable global CLIs only. Do not run
  project-level `npm install` or equivalent in the image.

Before finishing, validate:

- `/workspace/.opencode-dev-yuta/Dockerfile.<profile>` exists.
- The Dockerfile starts from `localhost/opencode-dev-yuta:base`.
- The Dockerfile does not set `USER` unless the user explicitly asked for an
  advanced custom image contract.
- `/workspace/.opencode-dev-yuta/config.env` selects the same profile.
- Your final answer names the profile and lists the files changed.
