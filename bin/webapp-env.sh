#!/usr/bin/env bash
# webapp-env.sh — distro + compositor detection for the webapp-* toolkit.
# Sourced (not executed) by the webapp-* scripts. All functions degrade
# gracefully when detection tools are missing.

# WEBAPP_OS_RELEASE override exists for testing (default: /etc/os-release).
# webapp_compositor — print plasma|niri|hyprland|sway|gnome|unknown.
# Prefers the actually-running compositor; falls back to XDG_CURRENT_DESKTOP.
webapp_compositor() {
  if command -v pgrep >/dev/null 2>&1; then
    pgrep -x kwin_wayland >/dev/null 2>&1 && { printf 'plasma'; return; }
    pgrep -x kwin_x11 >/dev/null 2>&1 && { printf 'plasma'; return; }
    pgrep -x niri >/dev/null 2>&1 && { printf 'niri'; return; }
    pgrep -x Hyprland >/dev/null 2>&1 && { printf 'hyprland'; return; }
    pgrep -x sway >/dev/null 2>&1 && { printf 'sway'; return; }
    pgrep -x gnome-shell >/dev/null 2>&1 && { printf 'gnome'; return; }
  fi
  case "${XDG_CURRENT_DESKTOP:-}" in
    *[Pp]lasma* | *KDE*) printf 'plasma' ;;
    *[Nn]iri*) printf 'niri' ;;
    *[Hh]yprland*) printf 'hyprland' ;;
    *[Ss]way*) printf 'sway' ;;
    *GNOME*) printf 'gnome' ;;
    *) printf 'unknown' ;;
  esac
}

# webapp_distro — print os-release ID (void, arch, fedora, ...) or unknown.
webapp_distro() (
  # subshell: sourcing os-release must not leak variables into callers.
  OS_RELEASE_FILE="${WEBAPP_OS_RELEASE:-/etc/os-release}"
  # shellcheck disable=SC1090
  [[ -f "$OS_RELEASE_FILE" ]] && source "$OS_RELEASE_FILE" 2>/dev/null
  printf '%s' "${ID:-unknown}"
)

# webapp_install_cmd <pkgs...> — print the distro's install command, or empty.
webapp_install_cmd() {
  local pkgs="$*"
  case "$(webapp_distro)" in
    void) printf 'sudo xbps-install -S %s' "$pkgs" ;;
    arch | endeavouros | manjaro | cachyos | artix) printf 'sudo pacman -S %s' "$pkgs" ;;
    fedora | nobara | rhel | centos | rocky | almalinux) printf 'sudo dnf install %s' "$pkgs" ;;
    debian | ubuntu | pop | linuxmint | peppermint | zorin | mx) printf 'sudo apt install %s' "$pkgs" ;;
    opensuse* | suse) printf 'sudo zypper install %s' "$pkgs" ;;
    gentoo) printf 'sudo emerge %s' "$pkgs" ;;
    alpine) printf 'sudo apk add %s' "$pkgs" ;;
    nixos) printf '# NixOS: add %s to environment.systemPackages' "$pkgs" ;;
    *) printf '' ;;
  esac
}
