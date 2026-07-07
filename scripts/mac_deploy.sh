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

echo "After pull: $(git log -1 --oneline)"
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

if [[ -n "$device_id" ]]; then
  flutter run "${run_mode[@]}" -d "$device_id"
else
  flutter run "${run_mode[@]}"
fi

