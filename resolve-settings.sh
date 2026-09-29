#!/usr/bin/bash
# Find omarchy-ai-settings and exec it.
#
# Marketplace `omarchy plugin add` installs this bar widget only. It does
# not run install.sh, so Panel.qml has no install-time path to rewrite.
# This script is the lookup. It never downloads or installs the assistant.
#
# Order:
#   1. OMARCHY_AI_SETTINGS, when that is an executable file
#   2. The user unit install.sh wrote (~/.config/systemd/user/omarchy-ai.service)
#   3. omarchy-ai-settings on PATH
#   4. Newest fast-install tree under $XDG_DATA_HOME/omachy-ai-releases
#   5. Newest self-update tree under $XDG_DATA_HOME/omarchy-ai/releases
#
# When none of those exist, print one JSON object and exit 0. The panel
# reads assistant_installed=false and explains how to install Omarchy-AI.
set -euo pipefail

accept() {
  local found="${1:-}"
  case "$found" in
    ""|*$'\n'*|*$'\r'*) return 1 ;;
  esac
  if [[ "$found" =~ @[A-Z0-9_]+@ ]]; then
    return 1
  fi
  if [ -x "$found" ] && [ ! -d "$found" ]; then
    printf '%s\n' "$found"
    return 0
  fi
  return 1
}

env_settings() {
  if [ -n "${OMARCHY_AI_SETTINGS:-}" ] && accept "$OMARCHY_AI_SETTINGS"; then
    return 0
  fi
  return 1
}

config_home() {
  if [ -n "${XDG_CONFIG_HOME:-}" ]; then
    printf '%s\n' "$XDG_CONFIG_HOME"
    return 0
  fi
  if [ -n "${HOME:-}" ]; then
    printf '%s\n' "$HOME/.config"
    return 0
  fi
  return 1
}

data_home() {
  if [ -n "${XDG_DATA_HOME:-}" ]; then
    printf '%s\n' "$XDG_DATA_HOME"
    return 0
  fi
  if [ -n "${HOME:-}" ]; then
    printf '%s\n' "$HOME/.local/share"
    return 0
  fi
  return 1
}

from_execstart() {
  local line="${1:-}"
  line=${line#ExecStart=}
  line=${line%$'\r'}
  local prefix=""
  case "$line" in
    *"/.venv/bin/python "*)
      prefix=${line%%/.venv/bin/python *}
      ;;
    *"/.venv/bin/python")
      prefix=${line%%/.venv/bin/python}
      ;;
    *)
      return 1
      ;;
  esac
  case "$prefix" in
    /*) ;;
    *) return 1 ;;
  esac
  if accept "$prefix/.venv/bin/omarchy-ai-settings"; then
    return 0
  fi
  return 1
}

unit_settings() {
  local home unit line workdir
  if ! home=$(config_home); then
    return 1
  fi
  unit="$home/systemd/user/omarchy-ai.service"
  [ -f "$unit" ] || return 1
  line=$(/usr/bin/grep -m1 '^WorkingDirectory=' "$unit" || true)
  if [ -n "$line" ]; then
    workdir=${line#WorkingDirectory=}
    workdir=${workdir%$'\r'}
    case "$workdir" in
      /*)
        if accept "$workdir/.venv/bin/omarchy-ai-settings"; then
          return 0
        fi
        ;;
    esac
  fi
  line=$(/usr/bin/grep -m1 '^ExecStart=' "$unit" || true)
  if [ -n "$line" ] && from_execstart "$line"; then
    return 0
  fi
  return 1
}

path_settings() {
  local found
  found=$(command -v omarchy-ai-settings 2>/dev/null || true)
  if [ -n "$found" ] && accept "$found"; then
    return 0
  fi
  return 1
}

release_version() {
  # .../omarchy-ai-0.11.3-linux-x86_64/.venv/bin/omarchy-ai-settings
  # Parameter expansion only: a marketplace shell may have a tiny PATH.
  local path="$1" dir
  path=${path%/omarchy-ai-settings}
  path=${path%/bin}
  path=${path%/.venv}
  dir=${path##*/}
  case "$dir" in
    omarchy-ai-*-linux-x86_64)
      dir=${dir#omarchy-ai-}
      dir=${dir%-linux-x86_64}
      ;;
    *)
      return 1
      ;;
  esac
  case "$dir" in
    *.*.*) printf '%s\n' "$dir" ;;
    *) return 1 ;;
  esac
}

newest_executable() {
  # Sort the bundle version, not the whole path. A fast-install directory
  # and a self-update directory do not share a prefix, so sorting the path
  # would let the directory name beat a newer release.
  local path best="" version line
  local -a rows=()
  if [ "$#" -eq 0 ]; then
    return 1
  fi
  for path in "$@"; do
    if [ ! -x "$path" ] || [ -d "$path" ] || [[ "$path" =~ @[A-Z0-9_]+@ ]]; then
      continue
    fi
    if ! version=$(release_version "$path"); then
      continue
    fi
    rows+=("$version"$'\t'"$path")
  done
  if [ "${#rows[@]}" -eq 0 ]; then
    return 1
  fi
  line=$(printf '%s\n' "${rows[@]}" | /usr/bin/sort -V | /usr/bin/tail -n 1)
  best=${line#*$'\t'}
  if [ -n "$best" ]; then
    printf '%s\n' "$best"
    return 0
  fi
  return 1
}

release_settings() {
  local home
  if ! home=$(data_home); then
    return 1
  fi
  shopt -s nullglob
  local fast=("$home"/omachy-ai-releases/omarchy-ai-*-linux-x86_64/.venv/bin/omarchy-ai-settings)
  local updated=("$home"/omarchy-ai/releases/*/omarchy-ai-*-linux-x86_64/.venv/bin/omarchy-ai-settings)
  shopt -u nullglob
  local candidates=()
  if [ "${#fast[@]}" -gt 0 ]; then
    candidates+=("${fast[@]}")
  fi
  if [ "${#updated[@]}" -gt 0 ]; then
    candidates+=("${updated[@]}")
  fi
  if [ "${#candidates[@]}" -eq 0 ]; then
    return 1
  fi
  newest_executable "${candidates[@]}"
}

locate() {
  local found
  if found=$(env_settings); then
    printf '%s\n' "$found"
    return 0
  fi
  if found=$(unit_settings); then
    printf '%s\n' "$found"
    return 0
  fi
  if found=$(path_settings); then
    printf '%s\n' "$found"
    return 0
  fi
  if found=$(release_settings); then
    printf '%s\n' "$found"
    return 0
  fi
  return 1
}

not_installed() {
  printf '%s\n' '{"assistant_installed":false,"error":"Omarchy-AI is not installed. Install the full assistant from GitHub Releases or with install.sh, then reopen this panel."}'
  exit 0
}

target=""
# Discovery must not consume the helper's stdin. API keys and passwords
# are waiting there for the real omarchy-ai-settings process.
if ! target=$(locate </dev/null); then
  not_installed
fi
exec "$target" "$@"
