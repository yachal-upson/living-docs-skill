#!/usr/bin/env bash
#
# run.sh — fixture tests for install.sh's CLI install path (ADR 0041 version
# resolution), driven entirely by a stub `curl` placed first on PATH, plus a
# stub `cargo` (source-build fallback) and, for the unknown-platform case, a
# stub `uname`. No network access and no real GitHub release are involved.
#
# The curl stub logs every invocation to $CURL_LOG, serves the
# `releases/latest` endpoint from a fixture JSON file, serves an `-o <file>
# <asset_url>` download by writing a deterministic payload, and serves an
# `-o <file> <asset_url>.sha256` download by writing a matching checksum
# (or a deliberately wrong one when CURL_FORCE_MISMATCH=1). The cargo stub
# writes a dummy binary to the manifest's target/release dir instead of
# compiling, so the source-build fallback completes without a real build.
#
# Exit: 0 = all cases pass, 1 = at least one failed.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
SCRIPT="$REPO_ROOT/install.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/living-docs-install-tests.XXXXXX")"

TARGET_BIN="$REPO_ROOT/target/release/living-docs"
TARGET_BIN_BACKUP="$TMP/living-docs.orig"
[[ -f "$TARGET_BIN" ]] && cp "$TARGET_BIN" "$TARGET_BIN_BACKUP"

restore_target_bin() {
  if [[ -f "$TARGET_BIN_BACKUP" ]]; then
    mkdir -p "$(dirname "$TARGET_BIN")"
    cp "$TARGET_BIN_BACKUP" "$TARGET_BIN"
  else
    rm -f "$TARGET_BIN"
  fi
}
trap 'restore_target_bin; rm -rf "$TMP"' EXIT

TAG="v9.9.9"
CURL_LOG="$TMP/curl.log"
CARGO_LOG="$TMP/cargo.log"
LATEST_JSON="$TMP/latest.json"
STUB_BIN="$TMP/bin"
mkdir -p "$STUB_BIN"

cat >"$LATEST_JSON" <<JSON
{
  "url": "https://api.github.com/repos/ejklock/living-docs-skill/releases/latest",
  "tag_name": "$TAG",
  "name": "$TAG",
  "draft": false,
  "prerelease": false
}
JSON

cat >"$STUB_BIN/curl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

log_call() { printf '%s\n' "$*" >>"$CURL_LOG"; }

sha256_of_payload() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf 'payload:%s' "$1" | sha256sum | awk '{print $1}'
  else
    printf 'payload:%s' "$1" | shasum -a 256 | awk '{print $1}'
  fi
}

log_call "$@"

output="" url=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) output="$2"; shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done

case "$url" in
  */releases/latest)
    cat "$CURL_LATEST_JSON"
    ;;
  *.sha256)
    base="$(basename "$url" .sha256)"
    if [[ "${CURL_FORCE_MISMATCH:-0}" == "1" ]]; then
      hash="$(printf '%064d' 0)"
    else
      hash="$(sha256_of_payload "$base")"
    fi
    printf '%s  %s\n' "$hash" "$base" >"$output"
    ;;
  *)
    printf 'payload:%s' "$(basename "$url")" >"$output"
    ;;
esac
STUB
chmod +x "$STUB_BIN/curl"

cat >"$STUB_BIN/cargo" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

log_call() { printf '%s\n' "$*" >>"$CARGO_LOG"; }
log_call "$@"

manifest=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest-path) manifest="$2"; shift 2 ;;
    *) shift ;;
  esac
done

[[ -n "$manifest" ]] || exit 0
repo_root="$(dirname "$(dirname "$manifest")")"
mkdir -p "$repo_root/target/release"
printf '#!/bin/sh\nexit 0\n' >"$repo_root/target/release/living-docs"
printf '#!/bin/sh\nexit 0\n' >"$repo_root/target/release/living-docs.exe"
chmod +x "$repo_root/target/release/living-docs" "$repo_root/target/release/living-docs.exe"
STUB
chmod +x "$STUB_BIN/cargo"

REAL_UNAME="$(command -v uname)"
export REAL_UNAME

cat >"$STUB_BIN/uname" <<'STUB'
#!/usr/bin/env bash
if [[ "${UNAME_UNSUPPORTED:-0}" == "1" ]]; then
  case "$1" in
    -s) echo "SunOS" ;;
    -m) echo "sparc64" ;;
  esac
  exit 0
fi
if [[ -n "${UNAME_S:-}" ]]; then
  case "$1" in
    -s) echo "$UNAME_S" ;;
    -m) echo "${UNAME_M:-x86_64}" ;;
  esac
  exit 0
fi
exec "$REAL_UNAME" "$@"
STUB
chmod +x "$STUB_BIN/uname"

expected_triple() {
  local os arch os_part arch_part
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os" in
    Darwin) os_part="apple-darwin" ;;
    Linux)  os_part="unknown-linux-gnu" ;;
    *)      os_part="unsupported" ;;
  esac
  case "$arch" in
    arm64|aarch64) arch_part="aarch64" ;;
    x86_64|amd64)  arch_part="x86_64" ;;
    *)             arch_part="unsupported" ;;
  esac
  printf '%s-%s\n' "$arch_part" "$os_part"
}
TRIPLE="$(expected_triple)"

fail=0

reset_state() { : >"$CURL_LOG"; : >"$CARGO_LOG"; }

invoke() { # invoke <ENV=val>... -- <script args...>
  invoke_in "$TMP" "$@"
}

invoke_in() { # invoke_in <dir> <ENV=val>... -- <script args...>
  local dir="$1"
  shift
  local envs=()
  while [[ "$1" != "--" ]]; do
    envs+=("$1")
    shift
  done
  shift
  reset_state
  OUT="$(cd "$dir" && env "${envs[@]}" PATH="$STUB_BIN:$PATH" CURL_LOG="$CURL_LOG" \
    CARGO_LOG="$CARGO_LOG" CURL_LATEST_JSON="$LATEST_JSON" REAL_UNAME="$REAL_UNAME" \
    bash "$SCRIPT" "$@" 2>&1)"
  RC=$?
  CURLLOG=""
  [[ -f "$CURL_LOG" ]] && CURLLOG="$(cat "$CURL_LOG")"
}

project_bin_name() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) printf '%s\n' "living-docs.exe" ;;
    *)                    printf '%s\n' "living-docs" ;;
  esac
}

check() { # check <name> <ok:0|1>
  if [[ "$2" == 1 ]]; then
    printf '  ok    %s\n' "$1"
  else
    printf '  FAIL  %s\n' "$1"
    printf '        exit=%s\n%s\n' "$RC" "$OUT" | sed 's/^/        out | /'
    printf '%s\n' "$CURLLOG" | sed 's/^/        curl | /'
    fail=1
  fi
}

assert_exit() { # assert_exit <name> <expected>
  local ok=0
  [[ "$RC" == "$2" ]] && ok=1
  check "$1" "$ok"
}

assert_out_has() { # assert_out_has <name> <substring>
  local ok=0
  grep -qF -- "$2" <<<"$OUT" && ok=1
  check "$1" "$ok"
}

assert_log_has() { # assert_log_has <name> <substring>
  local ok=0
  grep -qF -- "$2" <<<"$CURLLOG" && ok=1
  check "$1" "$ok"
}

assert_log_lacks() { # assert_log_lacks <name> <substring>
  local ok=1
  grep -qF -- "$2" <<<"$CURLLOG" && ok=0
  check "$1" "$ok"
}

assert_out_lacks() { # assert_out_lacks <name> <substring>
  local ok=1
  grep -qF -- "$2" <<<"$OUT" && ok=0
  check "$1" "$ok"
}

assert_file_exists() { # assert_file_exists <name> <path>
  local ok=0
  [[ -f "$2" ]] && ok=1
  check "$1" "$ok"
}

echo "install.sh fixtures (ADR 0041)"
echo

echo "case 1: LIVING_DOCS_VERSION unset resolves the latest release tag"
DEST="$TMP/dest-1"
mkdir -p "$DEST"
invoke "UNAME_S=Linux" "UNAME_M=x86_64" -- cli --dir "$DEST"
assert_exit    "1-exit-0"             0
assert_log_has "1-queries-latest"     "releases/latest"
assert_log_has "1-downloads-resolved" "/download/$TAG/"
assert_file_exists "1-installed"      "$DEST/living-docs"

echo "case 2: LIVING_DOCS_VERSION pins an exact tag"
DEST="$TMP/dest-2"
mkdir -p "$DEST"
invoke "LIVING_DOCS_VERSION=v1.2.3" "UNAME_S=Linux" "UNAME_M=x86_64" -- cli --dir "$DEST"
assert_exit      "2-exit-0"           0
assert_log_lacks "2-never-latest"     "releases/latest"
assert_log_has   "2-downloads-pinned" "/download/v1.2.3/"
assert_file_exists "2-installed"      "$DEST/living-docs"

echo "case 3: checksum mismatch falls back to build from source"
DEST="$TMP/dest-3"
mkdir -p "$DEST"
invoke "CURL_FORCE_MISMATCH=1" "UNAME_S=Linux" "UNAME_M=x86_64" -- cli --dir "$DEST"
assert_out_has "3-fallback-message" \
  "release asset unavailable for x86_64-unknown-linux-gnu; falling back to build from source"
assert_out_lacks "3-no-release-asset-install-note" "installed: living-docs ($TRIPLE) ->"

echo "case 4: unsupported platform falls back to build from source"
DEST="$TMP/dest-4"
mkdir -p "$DEST"
invoke "UNAME_UNSUPPORTED=1" -- cli --dir "$DEST"
assert_out_has   "4-unsupported-message" \
  "unsupported platform (SunOS/sparc64) for a prebuilt binary; building from source"
assert_log_lacks "4-no-latest-query" "releases/latest"

echo "case 5: any target other than cli exits non-zero with a usage error"
invoke -- claude
assert_exit    "5-exit-1"        1
assert_out_has "5-names-cli"     "cli is the only target"

echo "case 6: --project --from-source writes under .living-docs and keeps hooks trackable"
PROJ="$TMP/project-6"
mkdir -p "$PROJ"
git -C "$PROJ" init -q
printf 'keep-me\n' >"$PROJ/.gitignore"
BIN_NAME="$(project_bin_name)"
invoke_in "$PROJ" -- --project --from-source
assert_exit "6-exit-0" 0
assert_file_exists "6-project-binary" "$PROJ/.living-docs/$BIN_NAME"
assert_out_has "6-keeps-unrelated-gitignore" "configured: .gitignore"
if grep -qxF 'keep-me' "$PROJ/.gitignore"; then check "6-unrelated-gitignore-line" 1; else check "6-unrelated-gitignore-line" 0; fi
if grep -qxF '# >>> living-docs managed runtime >>>' "$PROJ/.gitignore"; then check "6-gitignore-marker" 1; else check "6-gitignore-marker" 0; fi
if git -C "$PROJ" check-ignore -q -- ".living-docs/$BIN_NAME"; then check "6-binary-ignored" 1; else check "6-binary-ignored" 0; fi
mkdir -p "$PROJ/.living-docs/hooks"
printf '#!/bin/sh\n' >"$PROJ/.living-docs/hooks/pre-commit"
if git -C "$PROJ" check-ignore -q -- ".living-docs/hooks/pre-commit"; then check "6-hooks-trackable" 0; else check "6-hooks-trackable" 1; fi
invoke_in "$PROJ" -- --project --from-source
assert_out_has "6-gitignore-idempotent" "gitignore already configured: .gitignore"
MARKERS="$(grep -cF '# >>> living-docs managed runtime >>>' "$PROJ/.gitignore")"
if [[ "$MARKERS" == "1" ]]; then check "6-marker-once" 1; else check "6-marker-once" 0; fi

echo "case 7: --project --uninstall removes the managed block and the binary"
invoke_in "$PROJ" -- --project --uninstall
assert_exit "7-exit-0" 0
if [[ -f "$PROJ/.living-docs/$BIN_NAME" ]]; then check "7-binary-removed" 0; else check "7-binary-removed" 1; fi
if grep -qxF 'keep-me' "$PROJ/.gitignore"; then check "7-unrelated-kept" 1; else check "7-unrelated-kept" 0; fi
if grep -qxF '# >>> living-docs managed runtime >>>' "$PROJ/.gitignore"; then check "7-marker-removed" 0; else check "7-marker-removed" 1; fi

echo
if ((fail == 0)); then
  echo "All install.sh fixtures passed."
  exit 0
else
  echo "install.sh fixture failures."
  exit 1
fi
