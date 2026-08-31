---
type: ADR
title: Co-locate the project-local runtime under .living-docs
description: Project-local installs package the executable, hooks, and derived state under .living-docs while leaving global installation unchanged.
owner: Project maintainers
status: Accepted
timestamp: 2026-08-31T05:35:02Z
---

# 0046. Co-locate the project-local runtime under .living-docs

<!-- Status lives in frontmatter (`status`), not a body line. Settable values are
     exactly Proposed | Accepted | Deprecated. When superseding a prior ADR, set
     `supersedes` here; `living-docs supersede` sets Superseded on the old record
     -- never set it by hand. -->

## Context

Living Docs supports global CLI installation on PATH, while project hooks and the derived SQLite index already live under .living-docs/. A project-local trial previously placed the executable under tools/living-docs, splitting one runtime package across two directories and forcing PATH configuration. Windows Git Bash also requires a platform-specific .exe name. [ADR 0028](/adr/0028-the-release-binary-is-the-unit-of-distribution-install-sh-only-bootstraps-it-and-every-placement-becomes-a-cli-verb.md) establishes the release binary as the distribution unit; [ADR 0041](/adr/0041-make-cli-install-fetches-the-released-binary-and-install-sh-resolves-the-latest-release-by-default.md) keeps global installation unchanged.

## Decision

We will package a project-local Living Docs runtime under .living-docs/: living-docs on Unix or living-docs.exe on Windows, hooks under .living-docs/hooks/, and derived state such as index.db alongside them. install.sh cli --project selects that destination and adds a marker-delimited .gitignore block that ignores runtime artifacts while explicitly leaving hooks trackable. Hooks resolve the CLI from PATH first, then from the project-local .living-docs executable, and finally from target/release/living-docs[.exe] so the Living Docs source checkout can enforce its own contract during CLI development. tools/living-docs is not a runtime lookup location. An explicit --dir remains an unmanaged custom destination.

## Consequences

**Easier / gained:**
- A project is self-contained and needs no PATH mutation for hooks or skill-driven CLI use.
- The executable, hook scripts, and derived index have one runtime home.
- Windows source builds install the correct living-docs.exe filename.
- The Living Docs source repository can recursively support its own development using its release build.

**Harder / accepted trade-offs:**
- The project installer modifies .gitignore inside a marker-delimited block.
- The local binary is platform-specific and intentionally untracked; each machine must install or build its own copy.
- A custom --dir destination does not receive automatic ignore management.

**Follow-ups:**
- Add Windows release assets separately if source-build fallback becomes too costly.

## Verification

**Implementation impact:** install.sh, skills/living-docs/hooks/, skills/living-docs/SKILL.md, CLI hook embedding/tests, installer fixtures, and installation documentation.

**Verification criteria:**
- install.sh cli --project --from-source writes .living-docs/living-docs[.exe], preserves unrelated .gitignore content, and leaves .living-docs/hooks/** trackable.
- The embedded pre-commit hook invokes a project-local binary when living-docs is absent from PATH and falls back to target/release/living-docs[.exe] in a source checkout.
- Fitness functions: scripts/tests/install/run.sh and the CLI hooks_install, skill, and skill_install test suites.

# References

[1] [ADR 0028](/adr/0028-the-release-binary-is-the-unit-of-distribution-install-sh-only-bootstraps-it-and-every-placement-becomes-a-cli-verb.md)
[2] [ADR 0041](/adr/0041-make-cli-install-fetches-the-released-binary-and-install-sh-resolves-the-latest-release-by-default.md)
