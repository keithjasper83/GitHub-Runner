#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Bootstrap or remove a GitHub Actions self-hosted runner for a single repository.

Usage:
  scripts/bootstrap_runner.sh register --repo owner/repo [options]
  scripts/bootstrap_runner.sh register-and-run-once --repo owner/repo [options]
  scripts/bootstrap_runner.sh remove --repo owner/repo [options]

Options:
  --repo <owner/repo>     Required target repository.
  --name <runner-name>    Runner name. Default: <hostname>-<label-os>
  --labels <csv>          Labels. Default: self-hosted,<label-os>,<arch>
  --dir <path>            Runner install directory.
  --work <path>           Runner work directory. Default: _work
  --version <version>     Runner release version. Default: latest
  --service               Install and start as a service.
  --no-service            Configure but do not install service.
  --prompt-service        Ask interactively whether to install service.
  --force-download        Re-download runner package.

Examples:
  scripts/bootstrap_runner.sh register --repo owner/repo --service
  scripts/bootstrap_runner.sh register-and-run-once --repo owner/repo
  scripts/bootstrap_runner.sh remove --repo owner/repo

Requirements:
  gh auth login (with repo admin rights), curl, tar
EOF
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

runner_os() {
  case "${1:-}" in
    Darwin) echo "osx" ;;
    Linux) echo "linux" ;;
    *)
      echo "Unsupported OS: ${1:-unknown}. Use bootstrap_runner.ps1 on Windows." >&2
      exit 1
      ;;
  esac
}

label_os() {
  case "${1:-}" in
    osx) echo "macOS" ;;
    linux) echo "linux" ;;
    *) echo "${1:-unknown}" ;;
  esac
}

runner_arch() {
  case "${1:-}" in
    x86_64|amd64) echo "x64" ;;
    arm64|aarch64) echo "arm64" ;;
    *)
      echo "Unsupported CPU architecture: ${1:-unknown}" >&2
      exit 1
      ;;
  esac
}

action="${1:-}"
if [[ -z "$action" || "$action" == "-h" || "$action" == "--help" ]]; then
  usage
  exit 0
fi
shift

repo=""
name=""
labels=""
install_dir=""
work_dir="_work"
version="latest"
force_download="false"
service_mode="unset"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      repo="$2"
      shift 2
      ;;
    --name)
      name="$2"
      shift 2
      ;;
    --labels)
      labels="$2"
      shift 2
      ;;
    --dir)
      install_dir="$2"
      shift 2
      ;;
    --work)
      work_dir="$2"
      shift 2
      ;;
    --version)
      version="$2"
      shift 2
      ;;
    --service)
      service_mode="yes"
      shift
      ;;
    --no-service)
      service_mode="no"
      shift
      ;;
    --prompt-service)
      service_mode="prompt"
      shift
      ;;
    --force-download)
      force_download="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ "$action" != "register" && "$action" != "register-and-run-once" && "$action" != "remove" ]]; then
  echo "Action must be register, register-and-run-once, or remove." >&2
  usage
  exit 1
fi

if [[ -z "$repo" ]]; then
  echo "--repo is required." >&2
  usage
  exit 1
fi

need_cmd gh
need_cmd curl
need_cmd tar

os_download="$(runner_os "$(uname -s)")"
os_label="$(label_os "$os_download")"
arch_name="$(runner_arch "$(uname -m)")"

if [[ -z "$name" ]]; then
  host="$(hostname -s 2>/dev/null || hostname)"
  name="${host}-${os_label}"
fi

if [[ -z "$labels" ]]; then
  labels="self-hosted,${os_label},${arch_name}"
fi

repo_slug="${repo//\//_}"
if [[ -z "$install_dir" ]]; then
  install_dir="$HOME/.local/share/gh-runners/${repo_slug}/${name}"
fi

if [[ "$version" == "latest" ]]; then
  version="$(gh api repos/actions/runner/releases/latest --jq .tag_name | sed 's/^v//')"
fi

archive="actions-runner-${os_download}-${arch_name}-${version}.tar.gz"
download_url="https://github.com/actions/runner/releases/download/v${version}/${archive}"

mkdir -p "$install_dir"
cd "$install_dir"

if [[ "$action" == "remove" ]]; then
  if [[ ! -x "./config.sh" ]]; then
    echo "No runner config found in ${install_dir}. Nothing to remove."
    exit 0
  fi
  remove_token="$(gh api -X POST "repos/${repo}/actions/runners/remove-token" --jq .token)"
  ./config.sh remove --unattended --token "$remove_token"
  echo "Runner removed from ${repo}."
  exit 0
fi

if [[ "$force_download" == "true" || ! -x "./config.sh" ]]; then
  rm -f ./*.tar.gz
  curl -fsSL "$download_url" -o "$archive"
  tar xzf "$archive"
fi

registration_token="$(gh api -X POST "repos/${repo}/actions/runners/registration-token" --jq .token)"

config_args=(
  --url "https://github.com/${repo}"
  --token "$registration_token"
  --name "$name"
  --labels "$labels"
  --work "$work_dir"
  --unattended
  --replace
)

if [[ "$action" == "register-and-run-once" ]]; then
  config_args+=(--ephemeral)
  service_mode="no"
fi

./config.sh "${config_args[@]}"

if [[ "$service_mode" == "prompt" ]]; then
  if [[ -t 0 ]]; then
    read -r -p "Install and start as service on this machine? [y/N] " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      service_mode="yes"
    else
      service_mode="no"
    fi
  else
    service_mode="no"
  fi
fi

if [[ "$service_mode" == "yes" ]]; then
  if [[ -x "./svc.sh" ]]; then
    ./svc.sh install
    ./svc.sh start
    echo "Runner service installed and started."
  else
    echo "svc.sh is not available on this platform."
  fi
else
  if [[ "$action" == "register-and-run-once" ]]; then
    echo "Starting ephemeral runner for one job..."
    ./run.sh
  else
    echo "Runner configured. Start with:"
    echo "  cd \"$install_dir\" && ./run.sh"
  fi
fi

echo "Done. Runner '${name}' registered for ${repo} with labels: ${labels}"
