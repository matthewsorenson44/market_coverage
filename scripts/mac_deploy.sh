#!/usr/bin/env bash
set -euo pipefail

device_id="${1:-}"
mode_arg="${2:---release}"

if [[ "$device_id" == "--debug" || "$device_id" == "--release" ]]; then
  mode_arg="$device_id"
  device_id=""
fi

if [[ "$mode_arg" != "--debug" && "$mode_arg" != "--release" ]]; then
  echo "Unknown mode: $mode_arg"
  echo "Usage: ./scripts/mac_deploy.sh [DEVICE_ID] [--release|--debug]"
  exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

echo "Market Coverage OS Mac deploy"
echo "Repo: $repo_root"
branch="$(git branch --show-current)"
if [[ -z "$branch" ]]; then
  echo "This deploy helper requires a checked-out branch. Detached HEAD is not supported."
  exit 1
fi

origin_ref="origin/$branch"

echo "Branch: $branch"
echo "Before update: $(git log -1 --oneline)"
echo "Fetching origin..."
git fetch origin

if ! git rev-parse --verify --quiet "$origin_ref" >/dev/null; then
  echo
  echo "Could not find $origin_ref after fetching origin."
  echo "Check that this branch exists on GitHub before running the deploy helper."
  exit 1
fi

status_output="$(git status --short)"
local_commits="$(git log --oneline "$origin_ref..HEAD")"

if [[ -n "$status_output" || -n "$local_commits" ]]; then
  echo
  echo "============================================================"
  echo "STOP: Local Mac work detected. The Mac clone is deploy-only."
  echo "============================================================"

  if [[ -n "$status_output" ]]; then
    echo
    echo "Uncommitted or untracked files:"
    echo "$status_output"
  fi

  if [[ -n "$local_commits" ]]; then
    echo
    echo "Local commits not on $origin_ref:"
    echo "$local_commits"
  fi

  echo
  echo "Review this output before discarding anything."
  echo "git reset --hard $origin_ref discards them."
  echo
  exit 1
fi

echo "Updating deploy mirror to $origin_ref..."
git reset --hard "$origin_ref"
updated_commit="$(git rev-parse --short=12 HEAD)"
echo "Updated to commit: $updated_commit"

app_version="$(awk '/^version:/ {print $2; exit}' pubspec.yaml)"
app_version_name="${app_version%%+*}"
if [[ "$app_version" == *"+"* ]]; then
  app_build_number="${app_version#*+}"
else
  app_build_number="dev"
fi
git_commit="$(git rev-parse --short=12 HEAD)"
git_branch="$(git branch --show-current)"
if [[ -z "$git_branch" ]]; then
  git_branch="detached"
fi
build_time="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

echo "After update: $(git log -1 --oneline)"
echo "Build identity: version $app_version_name ($app_build_number), commit $git_commit"
echo "Compare commit $git_commit to Settings > Build Identity after launch."
echo

flutter pub get

echo
echo "Available Flutter devices:"
flutter devices
echo

if [[ "$mode_arg" == "--debug" ]]; then
  run_mode=()
else
  run_mode=("--release")
fi

dart_defines=(
  "--dart-define=APP_VERSION=$app_version_name"
  "--dart-define=APP_BUILD_NUMBER=$app_build_number"
  "--dart-define=GIT_COMMIT=$git_commit"
  "--dart-define=GIT_BRANCH=$git_branch"
  "--dart-define=BUILD_TIME=$build_time"
)

if [[ -n "$device_id" ]]; then
  flutter run "${run_mode[@]}" "${dart_defines[@]}" -d "$device_id"
else
  flutter run "${run_mode[@]}" "${dart_defines[@]}"
fi
