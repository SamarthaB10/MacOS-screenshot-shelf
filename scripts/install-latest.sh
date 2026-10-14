#!/bin/bash
set -euo pipefail

repo_api="https://api.github.com/repos/SamarthaB10/MacOS-screenshot-shelf"
api_headers=(
  -H "Accept: application/vnd.github+json"
  -H "X-GitHub-Api-Version: 2022-11-28"
)

if [ "$(/usr/bin/uname -m)" != "arm64" ]; then
  echo "Screenshot Shelf requires an Apple silicon Mac." >&2
  exit 1
fi

os_major="$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d. -f1)"
if [ "$os_major" -lt 26 ]; then
  echo "Screenshot Shelf requires macOS 26 or newer." >&2
  exit 1
fi

echo "Finding the latest successful Screenshot Shelf build..."
runs_json="$(/usr/bin/curl -fsSL --retry 2 "${api_headers[@]}" \
  "$repo_api/actions/workflows/build.yml/runs?branch=main&status=success&per_page=1")"
run_id="$(printf '%s\n' "$runs_json" | /usr/bin/awk '
  /"workflow_runs"[[:space:]]*:[[:space:]]*\[/ { in_runs=1; next }
  in_runs && /"id"[[:space:]]*:[[:space:]]*[0-9]+/ {
    line=$0
    sub(/^.*"id"[[:space:]]*:[[:space:]]*/, "", line)
    sub(/[^0-9].*$/, "", line)
    print line
    exit
  }
')"

if [ -z "$run_id" ]; then
  echo "No successful build was found. Ask the app owner to run the Build macOS app workflow." >&2
  exit 1
fi

artifacts_json="$(/usr/bin/curl -fsSL --retry 2 "${api_headers[@]}" \
  "$repo_api/actions/runs/$run_id/artifacts")"
artifact_id="$(printf '%s\n' "$artifacts_json" | /usr/bin/awk '
  BEGIN { RS="}" }
  /"name"[[:space:]]*:[[:space:]]*"Screenshot-Shelf-macos-arm64"/ &&
  /"expired"[[:space:]]*:[[:space:]]*false/ {
    line=$0
    if (match(line, /"id"[[:space:]]*:[[:space:]]*[0-9]+/)) {
      line=substr(line, RSTART, RLENGTH)
      sub(/^.*:[[:space:]]*/, "", line)
      print line
      exit
    }
  }
')"

if [ -z "$artifact_id" ]; then
  echo "The latest build has no available app download. Ask the app owner to run the Build macOS app workflow." >&2
  exit 1
fi

work_dir="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/screenshot-shelf-install.XXXXXX")"
app_parent="$HOME/Applications"
target_app="$app_parent/Screenshot Shelf.app"
staged_app="$app_parent/.Screenshot Shelf.new.$$.app"
backup_app="$app_parent/.Screenshot Shelf.old.$$.app"

cleanup() {
  /bin/rm -rf "$work_dir"
  if [ -d "$staged_app" ]; then /bin/rm -rf "$staged_app"; fi
}
trap cleanup EXIT

mkdir -p "$work_dir/artifact" "$work_dir/app" "$app_parent"
echo "Downloading the app..."
/usr/bin/curl -fsSL --retry 2 "${api_headers[@]}" \
  "$repo_api/actions/artifacts/$artifact_id/zip" \
  -o "$work_dir/artifact.zip"

/usr/bin/ditto -x -k "$work_dir/artifact.zip" "$work_dir/artifact"
app_zip="$(/usr/bin/find "$work_dir/artifact" -type f \
  -name "Screenshot-Shelf-macos-arm64.zip" -print -quit)"
if [ -z "$app_zip" ]; then
  echo "The build download did not contain the app archive." >&2
  exit 1
fi

/usr/bin/ditto -x -k "$app_zip" "$work_dir/app"
if [ ! -d "$work_dir/app/Screenshot Shelf.app" ]; then
  echo "The build download did not contain Screenshot Shelf.app." >&2
  exit 1
fi

/usr/bin/osascript -e 'tell application id "com.samarthab.screenshot-shelf" to quit' \
  >/dev/null 2>&1 || true
/usr/bin/ditto "$work_dir/app/Screenshot Shelf.app" "$staged_app"

if [ -e "$target_app" ]; then
  /bin/mv "$target_app" "$backup_app"
fi
if /bin/mv "$staged_app" "$target_app"; then
  if [ -e "$backup_app" ]; then /bin/rm -rf "$backup_app"; fi
else
  if [ -e "$backup_app" ]; then /bin/mv "$backup_app" "$target_app"; fi
  echo "Could not install Screenshot Shelf in $app_parent." >&2
  exit 1
fi

echo "Installed Screenshot Shelf in $app_parent. Opening it now..."
/usr/bin/open -a "$target_app" --args --request-permissions
