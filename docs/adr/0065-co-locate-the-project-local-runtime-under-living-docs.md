---
type: ADR
title: Co-locate the project-local runtime under .living-docs
description: Project-local installs package the executable, hooks, and derived state under .living-docs while leaving global installation unchanged.
owner: Project maintainers
status: Accepted
timestamp: 2026-10-08T08:55:16Z
---

# 0065. Co-locate the project-local runtime under .living-docs

## Context

Living Docs supports a global CLI on `PATH`, while project hooks and derived state already live under `.living-docs/`. A project-local trial placed the executable under `tools/living-docs`, splitting one runtime across two directories and forcing a `PATH` change. Windows Git Bash also needs the platform `.exe` name. [ADR 0028](/adr/0028-the-release-binary-is-the-unit-of-distribution-install-sh-only-bootstraps-it-and-every-placement-becomes-a-cli-verb.md) makes the release binary the distribution unit; [ADR 0041](/adr/0041-make-cli-install-fetches-the-released-binary-and-install-sh-resolves-the-latest-release-by-default.md) keeps the global install. Frontmatter and link checks still assumed LF and `/`, so a Windows checkout failed both.

## Decision

We will package a project-local runtime under `.living-docs/`: `living-docs` on Unix or `living-docs.exe` on Windows, hooks under `.living-docs/hooks/`, and derived state beside them. `./install.sh --project` selects that destination and adds a marker-delimited `.gitignore` block that ignores runtime artifacts while leaving `.living-docs/hooks/**` trackable. Hook scripts resolve the CLI from `PATH`, then `.living-docs/living-docs[.exe]`, then `target/release/living-docs[.exe]`, and run `check --plain`. `tools/living-docs` is not a lookup path. An explicit `--dir` stays unmanaged.

Frontmatter fences accept LF and CRLF. Link normalization treats `\` as `/` before resolving a target.

Rejected alternatives:

- **Keep the executable under `tools/living-docs`.** It leaves hooks and the binary in different directories and still needs a `PATH` edit.
- **Require the binary on `PATH` for every project hook.** A checkout cannot run its own doc-gate until the developer installs globally.
- **Treat CRLF and backslashes as authoring errors.** Windows Git checkouts produce both, and the gate would fail records the CLI itself wrote.

## Consequences

**Easier / gained:**
- A project is self-contained and needs no `PATH` change for hooks or skill-driven CLI use.
- The executable, hook scripts, and derived index have one runtime home.
- A Windows source build installs `living-docs.exe`, and check accepts CRLF frontmatter and `\` link paths.

**Harder / accepted trade-offs:**
- The project installer rewrites `.gitignore` inside a marker-delimited block.
- The local binary is platform-specific and untracked; each machine installs or builds its own copy.
- A custom `--dir` destination does not get ignore management.

**Follow-ups:**
- None in this record.

## Verification

**Implementation impact:** `install.sh`, `skills/living-docs/hooks/`, the embedded hook corpus, installer fixtures, frontmatter and link resolution, and the installation section of the README.

**Verification criteria:**
- `./install.sh --project --from-source` writes `.living-docs/living-docs[.exe]`, preserves unrelated `.gitignore` lines, and leaves `.living-docs/hooks/**` trackable.
- The pre-commit hook runs that project-local binary with `check --plain` when `living-docs` is absent from `PATH`, and falls back to `target/release/living-docs[.exe]` in a source checkout.
- A CRLF frontmatter block reads as the same record as LF, and a Windows path resolves to the same logical path as its `/` form.

**Fitness functions:** `scripts/tests/install/run.sh`, `cli/tests/project_local_hook.rs`, and the frontmatter, canonical, graph, and links unit tests.

# References

[1] [ADR 0028](/adr/0028-the-release-binary-is-the-unit-of-distribution-install-sh-only-bootstraps-it-and-every-placement-becomes-a-cli-verb.md)

[2] [ADR 0041](/adr/0041-make-cli-install-fetches-the-released-binary-and-install-sh-resolves-the-latest-release-by-default.md)
