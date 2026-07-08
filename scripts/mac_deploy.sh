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
echo "Branch: $(git branch --show-current)"
echo "Before pull: $(git log -1 --oneline)"

if [[ -n "$(git status --short)" ]]; then
  echo
  echo "Local changes detected on the Mac:"
  git status --short
  echo
  echo "Commit, stash, or ask Codex before pulling so local work is not overwritten."
  exit 1
fi

git pull --ff-only

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

echo "After pull: $(git log -1 --oneline)"
echo "Build identity: version $app_version_name ($app_build_number), commit $git_commit"
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
