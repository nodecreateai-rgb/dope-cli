#!/usr/bin/env bash
set -euo pipefail

REPO="${DOPE_CLI_REPO:-nodecreateai-rgb/dope-cli}"
BRANCH="${DOPE_CLI_BRANCH:-main}"
ARCHIVE_URL="${DOPE_CLI_ARCHIVE_URL:-https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz}"
INSTALL_ROOT="${HOME}/.local/share/dope-cli"
BIN_DIR="${HOME}/.local/bin"
LAUNCHER="${BIN_DIR}/dope"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

append_path_hint() {
  local rc
  for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    if [[ -f "$rc" ]] || [[ "$rc" == "$HOME/.profile" ]]; then
      if ! grep -Fq 'export PATH="$HOME/.local/bin:$PATH"' "$rc" 2>/dev/null; then
        printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc"
      fi
    fi
  done
}

main() {
  need_cmd curl
  need_cmd tar
  need_cmd python3
  mkdir -p "$INSTALL_ROOT" "$BIN_DIR"
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  echo "Downloading dope-cli bundle from ${ARCHIVE_URL} ..."
  curl -fsSL "$ARCHIVE_URL" -o "$tmpdir/dope-cli.tar.gz"
  tar -xzf "$tmpdir/dope-cli.tar.gz" -C "$tmpdir"
  src="$(find "$tmpdir" -maxdepth 1 -mindepth 1 -type d -name 'dope-cli-*' | head -n 1)"
  [[ -n "$src" ]] || { echo "failed to unpack dope-cli bundle" >&2; exit 1; }

  rm -rf "$INSTALL_ROOT"
  mkdir -p "$INSTALL_ROOT"
  cp -R "$src"/. "$INSTALL_ROOT"/
  chmod +x "$INSTALL_ROOT/dope"

  cat > "$LAUNCHER" <<EOF
#!/usr/bin/env bash
exec python3 "$INSTALL_ROOT/dope" "\$@"
EOF
  chmod +x "$LAUNCHER"

  append_path_hint

  echo
  echo "Installed dope to: $INSTALL_ROOT"
  echo "Launcher: $LAUNCHER"
  echo
  if command -v dope >/dev/null 2>&1; then
    dope --help >/dev/null 2>&1 || true
  fi
  echo "If your shell cannot find 'dope' yet, run:"
  echo "  export PATH=\"$HOME/.local/bin:\$PATH\""
}

main "$@"
