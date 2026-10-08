#!/usr/bin/env bash
#
# install.sh — bootstrap the living-docs CLI binary.
#
# Packaging is the CLI (ADR 0028): the release binary is the unit of
# distribution and this script's only job is to place that binary. Skill
# placement is a CLI verb (`living-docs install skills --harness
# <claude|opencode|codex|pi> [--project] [--dir]`) and enforcement is another
# (`living-docs install hooks`) — see README.md → Installation.
#
# Usage:
#   ./install.sh [cli] [options]
#
# Target (default and only supported target: cli):
#   cli   download the living-docs binary (release asset, sha256-verified,
#         cargo-build fallback) to --dir (default ~/.local/bin), or to
#         ./.living-docs/ with --project
#
# Options:
#   --dir <path>     override the destination directory (default ~/.local/bin)
#   --project        install into ./.living-docs/ (living-docs or living-docs.exe)
#   --uninstall      remove a previous living-docs CLI install
#   --from-source    skip the release asset, build with `cargo build --release`
#   -n, --dry-run    print what would happen, change nothing
#   -h, --help       show this help
#
# Environment:
#   LIVING_DOCS_VERSION   pin an exact release tag instead of resolving latest
#
# Examples:
#   ./install.sh                       # download the CLI to ~/.local/bin
#   ./install.sh --dir /usr/local/bin  # install to a custom directory
#   ./install.sh --from-source         # build the CLI with cargo instead
#   ./install.sh --project --from-source
#                                  # build into ./.living-docs/living-docs[.exe]
#   ./install.sh --uninstall           # remove a previous install

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROJECT=0
UNINSTALL=0
DRYRUN=0
FROM_SOURCE=0
OVERRIDE_DIR=""
TARGET=""

CLI_REPO="ejklock/living-docs-skill"
GITIGNORE_BEGIN="# >>> living-docs managed runtime >>>"
GITIGNORE_END="# <<< living-docs managed runtime <<<"

log()  { printf '%s\n' "$*"; }
run()  { if [[ $DRYRUN -eq 1 ]]; then log "  [dry-run] $*"; else eval "$*"; fi; }
note() { if [[ $DRYRUN -eq 1 ]]; then log "  [dry-run] would install: $*"; else log "installed: $*"; fi; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

usage() { sed -n '2,36p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    cli) TARGET="cli" ;;
    --project) PROJECT=1 ;;
    --uninstall) UNINSTALL=1 ;;
    -n|--dry-run) DRYRUN=1 ;;
    --from-source) FROM_SOURCE=1 ;;
    --dir) shift; OVERRIDE_DIR="${1:-}"; [[ -n "$OVERRIDE_DIR" ]] || die "--dir needs a path" ;;
    -h|--help) usage; exit 0 ;;
    --*) die "unknown option: $1 (try --help)" ;;
    *) die "unsupported target: $1 (cli is the only target; try --help)" ;;
  esac
  shift
done
TARGET="${TARGET:-cli}"

cli_target_triple() {
  local os="$1" arch="$2" os_part arch_part
  case "$os" in
    Darwin) os_part="apple-darwin" ;;
    Linux)  os_part="unknown-linux-gnu" ;;
    *) return 1 ;;
  esac
  case "$arch" in
    arm64|aarch64) arch_part="aarch64" ;;
    x86_64|amd64)  arch_part="x86_64" ;;
    *) return 1 ;;
  esac
  printf '%s-%s\n' "$arch_part" "$os_part"
}

cli_verify_sha256() {
  local file="$1" sumfile="$2" expected actual
  expected="$(awk '{print $1}' "$sumfile")"
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$file" | awk '{print $1}')"
  else
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  fi
  [[ -n "$expected" && "$expected" == "$actual" ]]
}

cli_binary_name() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) printf '%s\n' "living-docs.exe" ;;
    *)                    printf '%s\n' "living-docs" ;;
  esac
}

build_cli_from_source() {
  local dest="$1" bin_name="$2"
  command -v cargo >/dev/null 2>&1 \
    || die "cargo not found; install Rust or drop --from-source once a release asset exists"
  run "cargo build --release --manifest-path '$SCRIPT_DIR/cli/Cargo.toml'"
  run "mkdir -p '$dest'"
  run "install -m 755 '$SCRIPT_DIR/target/release/$bin_name' '$dest/$bin_name'"
  note "living-docs (built from source) -> $dest/$bin_name"
}

ensure_project_gitignore() {
  local file=".gitignore"
  if [[ -f "$file" ]] && grep -qxF "$GITIGNORE_BEGIN" "$file"; then
    log "gitignore already configured: $file"
    return
  fi
  if [[ $DRYRUN -eq 1 ]]; then
    log "  [dry-run] append Living Docs runtime block to $file"
    return
  fi
  if [[ -s "$file" ]]; then printf '\n' >>"$file"; fi
  {
    printf '%s\n' "$GITIGNORE_BEGIN"
    printf '%s\n' '!/.living-docs/'
    printf '%s\n' '/.living-docs/*'
    printf '%s\n' '!/.living-docs/hooks/'
    printf '%s\n' '!/.living-docs/hooks/**'
    printf '%s\n' "$GITIGNORE_END"
  } >>"$file"
  log "configured: $file (runtime ignored; hooks trackable)"
}

remove_project_gitignore() {
  local file=".gitignore" tmp
  [[ -f "$file" ]] || return
  grep -qxF "$GITIGNORE_BEGIN" "$file" || return
  if [[ $DRYRUN -eq 1 ]]; then
    log "  [dry-run] remove Living Docs runtime block from $file"
    return
  fi
  tmp="$(mktemp)"
  awk -v begin="$GITIGNORE_BEGIN" -v end="$GITIGNORE_END" '
    $0 == begin { skipping = 1; next }
    $0 == end   { skipping = 0; next }
    !skipping   { print }
  ' "$file" >"$tmp"
  mv "$tmp" "$file"
  log "removed Living Docs runtime block from $file"
}

cli_resolve_tag() {
  local pinned="${LIVING_DOCS_VERSION:-}"
  if [[ -n "$pinned" ]]; then
    case "$pinned" in
      v*) printf '%s\n' "$pinned" ;;
      *)  printf 'v%s\n' "$pinned" ;;
    esac
    return 0
  fi

  local latest_url="https://api.github.com/repos/$CLI_REPO/releases/latest"
  local tag
  tag="$(curl -fsSL "$latest_url" 2>/dev/null | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]*)".*/\1/')"
  [[ -n "$tag" ]] || return 1
  printf '%s\n' "$tag"
}

install_cli() {
  local dest bin_name bin_path project_managed=0
  bin_name="$(cli_binary_name)"
  if [[ -n "$OVERRIDE_DIR" ]]; then
    dest="$OVERRIDE_DIR"
  elif [[ $PROJECT -eq 1 ]]; then
    dest=".living-docs"
    project_managed=1
  else
    dest="$HOME/.local/bin"
  fi
  bin_path="$dest/$bin_name"

  if [[ $UNINSTALL -eq 1 ]]; then
    run "rm -f '$bin_path'"
    if [[ $project_managed -eq 1 ]]; then remove_project_gitignore; fi
    log "uninstalled: $bin_path"
    return
  fi

  if [[ $FROM_SOURCE -eq 1 ]]; then
    build_cli_from_source "$dest" "$bin_name"
    if [[ $project_managed -eq 1 ]]; then ensure_project_gitignore; fi
    return
  fi

  local triple asset tag base asset_url sha_url tmp
  if ! triple="$(cli_target_triple "$(uname -s)" "$(uname -m)")"; then
    log "unsupported platform ($(uname -s)/$(uname -m)) for a prebuilt binary; building from source"
    build_cli_from_source "$dest" "$bin_name"
    if [[ $project_managed -eq 1 ]]; then ensure_project_gitignore; fi
    return
  fi

  asset="living-docs-$triple"
  if ! tag="$(cli_resolve_tag)"; then
    log "could not resolve a release tag (set LIVING_DOCS_VERSION or check network); building from source"
    build_cli_from_source "$dest" "$bin_name"
    if [[ $project_managed -eq 1 ]]; then ensure_project_gitignore; fi
    return
  fi
  base="https://github.com/$CLI_REPO/releases/download/$tag"
  asset_url="$base/$asset"
  sha_url="$asset_url.sha256"

  if [[ $DRYRUN -eq 1 ]]; then
    log "  [dry-run] would download $asset_url ($tag) -> $bin_path (sha256-verified)"
    if [[ $project_managed -eq 1 ]]; then ensure_project_gitignore; fi
    return
  fi

  tmp="$(mktemp -d)"
  if curl -fsSL -o "$tmp/$asset" "$asset_url" 2>/dev/null \
      && curl -fsSL -o "$tmp/$asset.sha256" "$sha_url" 2>/dev/null \
      && cli_verify_sha256 "$tmp/$asset" "$tmp/$asset.sha256"; then
    run "mkdir -p '$dest'"
    run "install -m 755 '$tmp/$asset' '$bin_path'"
    note "living-docs ($triple) -> $bin_path"
    if [[ $project_managed -eq 1 ]]; then ensure_project_gitignore; fi
    rm -rf "$tmp"
    return
  fi

  rm -rf "$tmp"
  log "release asset unavailable for $triple; falling back to build from source"
  build_cli_from_source "$dest" "$bin_name"
  if [[ $project_managed -eq 1 ]]; then ensure_project_gitignore; fi
}

log "living-docs installer — target: $TARGET$([[ $PROJECT -eq 1 ]] && echo ' (project)')$([[ $UNINSTALL -eq 1 ]] && echo ' [uninstall]')$([[ $DRYRUN -eq 1 ]] && echo ' [dry-run]')"
log ""
install_cli
