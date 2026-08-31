#!/usr/bin/env bash
#
# session-context.sh — SessionStart hook for the living-docs authoring contract
# (ADR 0021 layer 2: deterministic point-of-use teaching).
#
# Emits one context line stating the body-only rule and the resolved CLI binary,
# so every session receives the rule at t=0 instead of behind a skill trigger.
# Also points core.hooksPath at .githooks/ when the repo ships one, arming the
# pre-commit doc-gate. Always exits 0.

set -u

ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

resolve_bin() {
  if command -v living-docs >/dev/null 2>&1; then
    command -v living-docs
  elif [ -x "$ROOT/.living-docs/living-docs" ]; then
    printf '%s' "$ROOT/.living-docs/living-docs"
  elif [ -x "$ROOT/.living-docs/living-docs.exe" ]; then
    printf '%s' "$ROOT/.living-docs/living-docs.exe"
  elif [ -x "$ROOT/target/release/living-docs" ]; then
    printf '%s' "$ROOT/target/release/living-docs"
  elif [ -x "$ROOT/target/release/living-docs.exe" ]; then
    printf '%s' "$ROOT/target/release/living-docs.exe"
  fi
}

arm_githooks() {
  [ -d "$ROOT/.githooks" ] || return 0
  git -C "$ROOT" config core.hooksPath .githooks 2>/dev/null || true
}

arm_githooks

BIN="$(resolve_bin)"
if [ -n "$BIN" ]; then
  BIN_NOTE="CLI: $BIN"
else
  BIN_NOTE="CLI not found — install it on PATH or at .living-docs/living-docs[.exe], or build target/release/living-docs[.exe]"
fi

printf 'living-docs: %s. Docs authoring contract: write ONLY the body below the closing --- of a record. Numbering, frontmatter, supersede links, and index rows are CLI-owned — `living-docs new <type> "<title>"`, `living-docs status <NNNN> <Status>`, `living-docs supersede <old> <new>`, `living-docs index`, `living-docs fmt`. Hand-writes to those are blocked by a PreToolUse hook.\n' "$BIN_NOTE"

exit 0
