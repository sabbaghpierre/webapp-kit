#!/usr/bin/env bash
# webapp-kit installer — isolated webapps (Omarchy-style) for any distro/DE.
#
# From a clone:            ./install.sh [--prefix DIR] [--no-path]
# Fresh machine (curl):    curl -fsSL https://raw.githubusercontent.com/sabbaghpierre/webapp-kit/main/install.sh | bash
#                          curl -fsSL .../install.sh | bash -s -- --prefix ~/.local/share/webapps
# Pin a release:           WEBAPP_REF=v0.0.1 curl ... | bash
# Uninstall (keeps data):  ./install.sh --uninstall   (or: webapp-uninstall)
# Full wipe (code+apps):   webapp-uninstall --purge   (after installing)
#
# Never uses sudo. PATH wiring is idempotent single lines. Re-running upgrades.
set -euo pipefail

# Harden against hostile inherited shell state (notably IFS without space,
# which silently disables word splitting, and GLOBIGNORE, which empties
# globs — both observed in the wild breaking this installer with zero output).
unset IFS GLOBIGNORE

REPO="${WEBAPP_REPO:-sabbaghpierre/webapp-kit}"
REF="${WEBAPP_REF:-main}"
# WEBAPP_TARBALL_URL overrides the download location entirely (mirrors/tests).
TARBALL_URL="${WEBAPP_TARBALL_URL:-}"
PREFIX="${HOME}/.local/share/webapps"
NO_PATH=false
UNINSTALL=false

usage() {
  echo "Usage: install.sh [--prefix DIR] [--no-path] [--uninstall]"
  echo "Env:   WEBAPP_REPO=owner/repo  WEBAPP_REF=branch-or-tag  (default: $REPO@$REF)"
}

while (($# > 0)); do
  case "$1" in
    --prefix) PREFIX="${2:?--prefix needs a directory}"; shift 2 ;;
    --prefix=*) PREFIX="${1#--prefix=}"; shift ;;
    --no-path) NO_PATH=true; shift ;;
    --uninstall) UNINSTALL=true; shift ;;
    -h | --help) usage; exit 0 ;;
    *) echo "install.sh: unknown flag: $1" >&2; usage >&2; exit 1 ;;
  esac
done

# Resolve the source tree: local clone if present, else download tarball.
SCRIPT_SRC="${BASH_SOURCE[0]:-}"
SCRIPT_DIR=""
if [[ -n "$SCRIPT_SRC" && "$SCRIPT_SRC" != "bash" && "$SCRIPT_SRC" != "/dev/stdin" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SRC")" && pwd)"
fi
TMPDIR_WK=""
cleanup() { [[ -n "${TMPDIR_WK:-}" ]] && rm -rf "$TMPDIR_WK" || true; }
trap cleanup EXIT

# ---- preflights: fail fast with actionable errors ----
command -v curl >/dev/null 2>&1 || {
  echo "install.sh: curl is required to download webapp-kit." >&2
  echo "Install curl with your distro package manager, then re-run." >&2
  exit 1
}
command -v tar >/dev/null 2>&1 || {
  echo "install.sh: tar is required to unpack webapp-kit." >&2
  echo "Install tar with your distro package manager, then re-run." >&2
  exit 1
}
if ! TMPDIR_PROBE="$(mktemp -d 2>/dev/null)"; then
  echo "install.sh: cannot create temp dirs (check TMPDIR='$TMPDIR' and disk space)." >&2
  exit 1
fi
rm -rf "$TMPDIR_PROBE"
CA_OK=false
for caf in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/cert.pem; do
  [[ -f "$caf" ]] && CA_OK=true
done
if [[ "$CA_OK" != "true" ]]; then
  echo "install.sh: warning: no TLS CA bundle found; HTTPS downloads may fail." >&2
  echo "  Install your distro's ca-certificates package, then re-run if downloads fail." >&2
fi

# ---- download helpers (curl errors are surfaced, never swallowed) ----
FETCH_ERR=""
classify_curl_error() { # $1=exit code, $2=stderr tail, $3=url
  local host
  host="$(printf '%s' "$3" | sed -n 's|^[A-Za-z][A-Za-z0-9+.-]*://\([^/]*\).*|\1|p')"
  [[ -z "$host" ]] && host="$3"
  case "$1" in
    6) printf 'DNS failure resolving %s (offline? broken resolver?)' "$host" ;;
    7) printf 'cannot connect to %s (offline? firewall/proxy?)' "$host" ;;
    28) printf 'connection to %s timed out' "$host" ;;
    35 | 60 | 77) printf 'TLS/CA failure for %s (install ca-certificates; corp proxy?)' "$host" ;;
    22) printf 'HTTP error from %s (captive portal? blocked host?)' "$host" ;;
    5 | 9) printf 'FTP/access issue (unexpected for %s)' "$host" ;;
    *) printf 'curl exit %s for %s: %s' "$1" "$host" "$(printf '%s' "$2" | head -n2 | tr '\n' ' ')" ;;
  esac
}

fetch_file() { # $1=url $2=dest — sets FETCH_ERR on failure
  local url="$1" dest="$2" err rc
  err="$(curl -fsSL --retry 3 --retry-delay 2 --max-time 120 "$url" -o "$dest" 2>&1)" && return 0
  rc=$?
  FETCH_ERR="$(classify_curl_error "$rc" "$err" "$url")"
  return 1
}

if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/bin/webapp-create" ]]; then
  SRC="$SCRIPT_DIR"
else
  SRC=""
  ERRORS=""
  # Tier 1: release tarballs (array iteration: immune to IFS).
  URLS=()
  if [[ -n "$TARBALL_URL" ]]; then
    URLS+=("$TARBALL_URL")
  else
    URLS+=("https://github.com/$REPO/archive/refs/heads/$REF.tar.gz")
    URLS+=("https://github.com/$REPO/archive/refs/tags/$REF.tar.gz")
  fi
  for url in "${URLS[@]}"; do
    TMPDIR_WK="$(mktemp -d)"
    if fetch_file "$url" "$TMPDIR_WK/kit.tar.gz"; then
      if tar -xzf "$TMPDIR_WK/kit.tar.gz" -C "$TMPDIR_WK" 2>"$TMPDIR_WK/tar.err"; then
        # find-based scan (immune to GLOBIGNORE/nullglob): accept whatever
        # subtree holds bin/ (GitHub: <repo>-<ref>/).
        while IFS= read -r f; do
          SRC="$(dirname "$(dirname "$f")")"
          break
        done < <(find "$TMPDIR_WK" -maxdepth 4 -path '*/bin/webapp-create' -type f 2>/dev/null || true)
        if [[ -n "$SRC" ]]; then break; fi
        ERRORS="${ERRORS}tarball from $url unpacked but holds no bin/webapp-create; "
      else
        ERRORS="${ERRORS}tarball from $url failed to unpack ($(head -n1 "$TMPDIR_WK/tar.err" 2>/dev/null)); "
      fi
    else
      ERRORS="${ERRORS}${FETCH_ERR}; "
    fi
    rm -rf "$TMPDIR_WK"
    TMPDIR_WK=""
  done
  # Tier 2: shallow git clone (different protocol path, same host family).
  if [[ -z "$SRC" ]] && command -v git >/dev/null 2>&1; then
    TMPDIR_WK="$(mktemp -d)"
    if git clone --depth 1 --branch "$REF" "https://github.com/$REPO.git" "$TMPDIR_WK/git" >"$TMPDIR_WK/git.log" 2>&1 &&
      [[ -f "$TMPDIR_WK/git/bin/webapp-create" ]]; then
      SRC="$TMPDIR_WK/git"
    else
      ERRORS="${ERRORS}git clone failed ($(tail -n1 "$TMPDIR_WK/git.log" 2>/dev/null)); "
      rm -rf "$TMPDIR_WK"
      TMPDIR_WK=""
    fi
  fi
  # Tier 3: per-file fetch via the trees API (raw.githubusercontent.com —
  # independent host; survives codeload-only outages/blocks).
  if [[ -z "$SRC" ]]; then
    TMPDIR_WK="$(mktemp -d)"
    if fetch_file "https://api.github.com/repos/$REPO/git/trees/$REF?recursive=1" "$TMPDIR_WK/tree.json"; then
      TREE_OK=true
      while IFS= read -r p; do
        [[ -z "$p" ]] && continue
        mkdir -p "$TMPDIR_WK/raw/$(dirname "$p")"
        if ! fetch_file "https://raw.githubusercontent.com/$REPO/$REF/$p" "$TMPDIR_WK/raw/$p"; then
          TREE_OK=false
          ERRORS="${ERRORS}${FETCH_ERR}; "
          break
        fi
      done < <(grep -o '"path": *"[^"]*"' "$TMPDIR_WK/tree.json" 2>/dev/null |
        sed 's/"path": *"//;s/"$//' |
        grep -E '^(bin/webapp-[^"]+|VERSION)$' || true)
      if [[ "$TREE_OK" == "true" && -f "$TMPDIR_WK/raw/bin/webapp-create" ]]; then
        SRC="$TMPDIR_WK/raw"
      else
        rm -rf "$TMPDIR_WK"
        TMPDIR_WK=""
      fi
    else
      ERRORS="${ERRORS}${FETCH_ERR}; "
      rm -rf "$TMPDIR_WK"
      TMPDIR_WK=""
    fi
  fi
  if [[ -z "${SRC:-}" || ! -f "$SRC/bin/webapp-create" ]]; then
    echo "install.sh: could not fetch webapp-kit ($REPO@$REF)." >&2
    echo "Details: $ERRORS" >&2
    echo "Hints: check network/DNS, proxy env (env | grep -i proxy), and that" >&2
    echo "  github.com + codeload.github.com + raw.githubusercontent.com resolve." >&2
    exit 1
  fi
fi

BIN_DST="$PREFIX/bin"
PATH_LINE="export PATH=\"\$HOME/.local/share/webapps/bin:\$PATH\""
if [[ "$PREFIX" != "$HOME/.local/share/webapps" ]]; then
  # Keep PATH wiring pointed at the real install location.
  PATH_LINE="export PATH=\"$BIN_DST:\$PATH\""
fi

if [[ "$UNINSTALL" == "true" ]]; then
  rm -rf "$BIN_DST"
  rm -f "$PREFIX/VERSION"
  # Remove exactly our PATH lines (current prefix or default location).
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [[ -f "$rc" ]] || continue
    grep -v -F -e "$BIN_DST:" -e ".local/share/webapps/bin:" "$rc" >"$rc.webapp-tmp" || true
    cat "$rc.webapp-tmp" >"$rc"
    rm -f "$rc.webapp-tmp"
  done
  rm -f "$HOME/.config/plasma-workspace/env/local-bin-path.sh"
  echo "Uninstalled webapp-kit code ($BIN_DST)."
  echo "Kept your data: profiles/desktops/icons/rules. For a full wipe:"
  echo "  webapp-uninstall --purge   (before uninstalling, while bin/ exists)"
  exit 0
fi

mkdir -p "$BIN_DST"
cp -f "$SRC"/bin/webapp-* "$BIN_DST/"
chmod +x "$BIN_DST"/webapp-*
if [[ -f "$SRC/VERSION" ]]; then
  cp -f "$SRC/VERSION" "$PREFIX/VERSION"
fi

# Compiled TUI (nocterm AOT binary, linux-x64) from release assets.
# Warns (never fails) when no release exists yet.
TUI_URL="https://github.com/$REPO/releases/latest/download/webapp-tui"
if curl -fsSL "$TUI_URL" -o "$BIN_DST/webapp-tui" 2>/dev/null; then
  chmod +x "$BIN_DST/webapp-tui"
  echo "Installed webapp-tui to $BIN_DST/webapp-tui"
else
  echo "install.sh: note: no webapp-tui release asset at $TUI_URL yet (scripts work fine without it)." >&2
fi

if [[ "$NO_PATH" != "true" ]]; then
  # Shell rc files: append once (exact-line match = idempotent).
  touch "$HOME/.bashrc"
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [[ -f "$rc" ]] || continue
    if ! grep -q -F "webapps/bin:" "$rc"; then
      printf '\n# webapp-kit\n%s\n' "$PATH_LINE" >>"$rc"
    fi
  done
  # Plasma graphical sessions don't source rc files; wire PATH there too,
  # but only when Plasma is actually present.
  if [[ "${XDG_CURRENT_DESKTOP:-}" == *KDE* || "${XDG_CURRENT_DESKTOP:-}" == *lasma* ]] ||
    command -v plasmashell >/dev/null 2>&1 || command -v kwriteconfig6 >/dev/null 2>&1; then
    mkdir -p "$HOME/.config/plasma-workspace/env"
    cat >"$HOME/.config/plasma-workspace/env/local-bin-path.sh" <<EOF
# webapp-kit: ensure toolkit on PATH in Plasma sessions (managed by install.sh).
if [[ ":\$PATH:" != *":$BIN_DST:"* ]]; then
  export PATH="$BIN_DST:\$PATH"
fi
EOF
  fi
  export PATH="$BIN_DST:$PATH"
fi

echo "Installed webapp-kit to $BIN_DST"
if command -v "$BIN_DST/webapp-doctor" >/dev/null 2>&1; then
  "$BIN_DST/webapp-doctor" --deps || true
fi
echo ""
echo "Quickstart:  webapp-create \"ChatGPT\" https://chatgpt.com chrome"
echo "Overview:    webapp-help"
echo "(Open a new terminal so the PATH update takes effect.)"
