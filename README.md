# webapp-kit

Omarchy-style isolated webapps for any Linux distro and desktop: turn any website into a native-feeling app with its own icon, window, and isolated browser profile — no browser tabs, no shared logins.

Two engines per app, your choice at creation time:

- **chrome** — Chromium `--app` SSB window in an isolated `--user-data-dir`
- **firefox** — self-contained profile (ice-ssb style), tab strip removed, only minimize/maximize/close remain

## Requirements

Hard: `bash`, `curl`, `setsid` (util-linux) + one browser (`firefox`, or a Chromium-family build for the chrome engine). Everything else degrades gracefully. Run `webapp-doctor --deps` after installing for a full check with install commands for your distro.

## Install

Fresh machine, one line:

```sh
curl -fsSL https://raw.githubusercontent.com/sabbaghpierre/webapp-kit/main/install.sh | bash
```

Options:

```sh
curl -fsSL .../install.sh | bash -s -- --prefix ~/.local/share/webapps  # custom location
WEBAPP_REF=v0.0.1 curl -fsSL .../install.sh | bash                      # pin a release
./install.sh --no-path        # skip shell PATH wiring (from a clone)
./install.sh --uninstall      # remove code, keep your profiles and data
```

Re-running the installer upgrades in place; your apps, profiles, and logins are untouched. The installer never uses `sudo`. Every install includes the prebuilt terminal UI (`webapp-tui`, fetched from GitHub releases).

## Usage

```sh
webapp-create "Strafe" https://strafe.com firefox   # interactive if args omitted
webapp-create "ChatGPT" https://chatgpt.com chrome
webapp-list                                          # installed apps
webapp-doctor Strafe                                 # health check (icon, profile, CSS, rules…)
webapp-doctor --probe Strafe                         # live window identity (icon debugging)
webapp-remove --purge Strafe                         # delete app (+ isolated data)
webapp-update --check                                # is a newer toolkit out?
webapp-update                                        # upgrade in place (data untouched)
webapp-uninstall --purge                             # remove toolkit AND every webapp
webapp-help                                          # full overview
```

Apps appear in any freedesktop app launcher (Kickoff/KRunner, fuzzel, wofi, …) with the site's favicon. `webapp-launch-*` are called by the generated `.desktop` files, not by hand.

## How it works

- `webapp-create` fetches the favicon, installs it into the hicolor icon theme, and writes `~/.local/share/applications/<Name>.desktop` with an absolute `Exec=` (immune to session-PATH issues), a matching `StartupWMClass`, and — on Plasma — a KWin window rule forcing the association.
- Chrome apps get `--user-data-dir=~/.local/share/webapps/chrome-<slug>` + `--ozone-platform-hint=auto`.
- Firefox apps get `--profile ~/.local/share/webapps/firefox-<slug> --no-remote`, native Wayland forced, `--name` app_id, and a `userChrome.css` that strips everything but window controls.

## Portability

No package-manager calls, no hardcoded paths or usernames, no distro-specific assumptions. Icon matching uses `app_id` + `StartupWMClass` everywhere (KWin rule added automatically on Plasma only). `webapp-doctor --probe` auto-detects KWin, niri, Hyprland, Sway (GNOME: prints Looking-Glass steps).

## Layout

```
VERSION     install.sh  README.md  LICENSE
bin/        webapp-{create,launch-chrome,launch-firefox,remove,list,doctor,help}
            webapp-{update,uninstall}  (lifecycle)
            webapp-kwin.sh webapp-env.sh  (sourced helpers, not run directly)
tool/       version.sh  (single entry point for versioning)
tui/        nocterm terminal UI (shipped prebuilt; needs Dart SDK only to build)
```

Per-user state (never in this repo): `~/.local/share/webapps/` (profiles, data, run logs), `~/.local/share/applications/*.desktop`, `~/.local/share/icons/hicolor/…`, `~/.config/kwinrulesrc` entries.

## Troubleshooting

**Installer fails with `could not fetch webapp-kit`.** Recent versions print
per-tier details — read them first. If it still fails, run this diagnostic
and compare hosts (a common real case: the archive host blocked/slow while
everything else works):

```sh
for u in https://raw.githubusercontent.com/sabbaghpierre/webapp-kit/main/VERSION "https://github.com/sabbaghpierre/webapp-kit/archive/refs/heads/main.tar.gz"; do echo "== $u"; curl -sSL -o /dev/null -w "http=%{http_code} time=%{time_total}s\n" --max-time 30 "$u" || echo "CURL FAILED rc=$?"; done
ls /etc/ssl/certs/ca-certificates.crt || echo "NO CA BUNDLE (install ca-certificates)"
```

Other usual suspects: no network/DNS on a fresh install, a proxy that needs
`http_proxy`/`https_proxy`, or an inherited `IFS` without space / `GLOBIGNORE`
(which used to break downloads silently — current releases sanitize both;
`webapp-doctor --deps` reports them under “shell environment sanity”).

## License

MIT — see [LICENSE](LICENSE).
