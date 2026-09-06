#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$HOME/.local/bin"
if ! command -v jf >/dev/null; then
  case "$(uname -m)" in x86_64) arch=amd64;; aarch64|arm64) arch=arm64;; *) exit 1;; esac
  curl -fsSL "https://releases.jfrog.io/artifactory/jfrog-cli/v2/2.122.0/jfrog-cli-linux-${arch}/jfrog" -o "$HOME/.local/bin/jf"
  chmod +x "$HOME/.local/bin/jf"
fi
export PATH="$HOME/.local/bin:$PATH"
if ! grep -Fq 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc"; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi
node --version
jf --version
python3 --version
command -v jq
echo 'Ready. Follow README.md to configure your workshop.'
