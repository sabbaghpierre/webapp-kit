#!/usr/bin/env bash
# webapp-kwin.sh — shared KDE/KWin helpers for the webapp-* scripts.
# Sourced (not executed) by webapp-create / webapp-remove.
#
# Background: Chromium ignores --class when --app= is set, so --app windows
# report Chromium's derived identity (chrome-<host>__-Default style) instead
# of our slug. Plasma's task manager then can't match the window to our
# .desktop file and shows the generic Chrome icon. We fix it two ways:
#   1. StartupWMClass = predicted Chromium id (best effort).
#   2. A KWin window rule forcing desktopfile association via a regex that
#      matches both the slug (--class, if honored) and the derived id.
# Mirrors the user's own working nativefier rule already in kwinrulesrc.

KWIN_RULES_FILE="${HOME}/.config/kwinrulesrc"

# webapp_chrome_id <url> — predict Chromium's window id for a --app window.
# e.g. https://strafe.com/ -> chrome-strafe.com__-Default
webapp_chrome_id() {
  local host="${1#*://}"
  host="${host%%/*}"
  host="${host%%:*}" # strip port
  host="$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')"
  [[ -z "$host" ]] && host="webapp"
  printf 'chrome-%s__-Default' "$host"
}

# webapp_regex_escape <string> — escape for KWin regexp match (wmclassmatch=3).
webapp_regex_escape() {
  printf '%s' "$1" | sed 's/[][\.*^$()+?{}|\\]/\\&/g'
}

# kwin_reconfigure — ask KWin to reload config. Best effort, never fails.
kwin_reconfigure() {
  if command -v qdbus6 >/dev/null 2>&1; then
    qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1 || true
  elif command -v qdbus >/dev/null 2>&1; then
    qdbus org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1 || true
  elif command -v dbus-send >/dev/null 2>&1; then
    dbus-send --session --type=method_call --dest=org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1 || true
  fi
  return 0
}

_kwin_backup() {
  if [[ -f "$KWIN_RULES_FILE" ]]; then
    cp -f "$KWIN_RULES_FILE" "$KWIN_RULES_FILE.webapp-bak" || true
  fi
}

# kwin_rule_exists <desktop-id> <pattern> — true if OUR identical rule exists.
# (kwriteconfig6 escapes backslashes on write, so compare escaped form.)
kwin_rule_exists() {
  local target="$1" pattern="$2"
  [[ -f "$KWIN_RULES_FILE" ]] || return 1
  local pattern_esc="${pattern//\\/\\\\}"
  # NOTE: via ENVIRON, not -v: awk -v unescapes backslashes, ENVIRON doesn't.
  KWEX_T="$target" KWEX_P="$pattern_esc" awk '
    /^\[.*\]$/ { g = substr($0, 2, length($0) - 2); desc[g] = ""; df[g] = ""; wm[g] = ""; next }
    /^Description=webapp: / { desc[g] = $0; next }
    /^desktopfile=/ { df[g] = substr($0, 13); next }
    /^wmclass=/ { wm[g] = substr($0, 9); next }
    END {
      for (k in df)
        if (df[k] == ENVIRON["KWEX_T"] && desc[k] != "" && wm[k] == ENVIRON["KWEX_P"]) { found = 1 }
      exit !found
    }
  ' "$KWIN_RULES_FILE"
}

# kwin_rule_add <desktop-id> <app-name> <regex-pattern>
# desktop-id: .desktop basename WITHOUT extension (matches `desktopfile=`).
kwin_rule_add() {
  local desktop_id="$1" app_name="$2" pattern="$3"
  command -v kwriteconfig6 >/dev/null 2>&1 || {
    echo "webapp: warning: kwriteconfig6 not found; skipping KWin rule" >&2
    return 0
  }
  if kwin_rule_exists "$desktop_id" "$pattern"; then
    echo "  KWin rule already present for '$app_name'"
    return 0
  fi
  _kwin_backup
  local uuid
  uuid="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "webapp-$RANDOM-$RANDOM")"
  kwriteconfig6 --file kwinrulesrc --group "$uuid" --key Description "webapp: $app_name" || return 0
  kwriteconfig6 --file kwinrulesrc --group "$uuid" --key desktopfile "$desktop_id"
  kwriteconfig6 --file kwinrulesrc --group "$uuid" --key desktopfilerule 4
  kwriteconfig6 --file kwinrulesrc --group "$uuid" --key wmclass "$pattern"
  kwriteconfig6 --file kwinrulesrc --group "$uuid" --key wmclassmatch 3
  # Register in [General].
  local rules="" count=""
  if command -v kreadconfig6 >/dev/null 2>&1; then
    rules="$(kreadconfig6 --file kwinrulesrc --group General --key rules 2>/dev/null || true)"
    count="$(kreadconfig6 --file kwinrulesrc --group General --key count 2>/dev/null || true)"
  fi
  [[ -z "$count" ]] && count=0
  [[ "$count" =~ ^[0-9]+$ ]] || count=0
  if [[ -z "$rules" ]]; then
    rules="$uuid"
  elif [[ ",$rules," != *",$uuid,"* ]]; then
    rules="$rules,$uuid"
  fi
  count=$((count + 1))
  kwriteconfig6 --file kwinrulesrc --group General --key rules "$rules"
  kwriteconfig6 --file kwinrulesrc --group General --key count "$count"
  echo "  KWin rule added for '$app_name' (match: $pattern)"
}

# kwin_rule_remove <desktop-id> — delete OUR rule groups for a desktop id.
# Only touches groups whose Description starts with "webapp: ".
kwin_rule_remove() {
  local target="$1"
  [[ -f "$KWIN_RULES_FILE" ]] || return 0
  local doomed
  doomed="$(awk -v target="$target" '
    /^\[.*\]$/ {
      g = substr($0, 2, length($0) - 2)
      desc[g] = ""; df[g] = ""
      next
    }
    g == "" { next }
    /^Description=webapp: / { desc[g] = $0; next }
    /^desktopfile=/ { df[g] = substr($0, 13); next }
    END {
      n = 0
      for (k in df) {
        if (df[k] == target && desc[k] != "") {
          printf "%s%s", (n++ ? " " : ""), k
        }
      }
    }
  ' "$KWIN_RULES_FILE")"
  [[ -z "$doomed" ]] && return 0
  _kwin_backup
  local n_removed=0
  n_removed="$(printf '%s' "$doomed" | wc -w)"
  # Snapshot General list from the ORIGINAL file before filtering.
  local rules="" count=""
  rules="$(sed -n 's/^rules=//p' "$KWIN_RULES_FILE" | head -n1)"
  count="$(sed -n 's/^count=//p' "$KWIN_RULES_FILE" | head -n1)"
  # Rebuild General rules list minus doomed uuids; fix count.
  # (Computed up front so awk can substitute in place, preserving key order.)
  local new_rules="" entry
  if [[ -n "$rules" ]]; then
    IFS=',' read -ra entries <<<"$rules"
    for entry in "${entries[@]}"; do
      [[ -z "$entry" ]] && continue
      if [[ " $doomed " != *" $entry "* ]]; then
        [[ -z "$new_rules" ]] && new_rules="$entry" || new_rules="$new_rules,$entry"
      fi
    done
  fi
  [[ -z "$count" ]] && count=0
  [[ "$count" =~ ^[0-9]+$ ]] || count=0
  count=$((count - n_removed))
  ((count < 0)) && count=0
  NEW_RULES="$new_rules" NEW_COUNT="$count" DOOMED="$doomed" awk '
    function flush_pending() {
      if (!skip) {
        for (k = 0; k < pending; k++) print ""
      }
      pending = 0
    }
    BEGIN {
      n = split(ENVIRON["DOOMED"], d, /[ \t]+/)
      for (i = 1; i <= n; i++) dead[d[i]] = 1
      group = ""; skip = 0; pending = 0
      saw_general = 0; saw_rules = 0; saw_count = 0
    }
    /^\[.*\]$/ {
      if (group == "General") {
        if (!saw_rules) print "rules=" ENVIRON["NEW_RULES"]
        if (!saw_count) print "count=" ENVIRON["NEW_COUNT"]
        saw_rules = 1; saw_count = 1
      }
      # Blank lines after a removed group die with it; after a kept
      # group they are layout and survive. (This is what keeps
      # add/remove round-trips byte-identical.)
      flush_pending()
      group = substr($0, 2, length($0) - 2)
      if (group == "General") saw_general = 1
      skip = (group in dead)
      if (!skip) print
      next
    }
    /^$/ { pending++; next }
    group == "General" && /^rules=/ && !saw_rules {
      flush_pending()
      print "rules=" ENVIRON["NEW_RULES"]; saw_rules = 1; next
    }
    group == "General" && /^count=/ && !saw_count {
      flush_pending()
      print "count=" ENVIRON["NEW_COUNT"]; saw_count = 1; next
    }
    {
      if (skip) { pending = 0; next }
      flush_pending()
      print
    }
    END {
      if (!skip && group == "General") {
        if (!saw_rules) print "rules=" ENVIRON["NEW_RULES"]
        if (!saw_count) print "count=" ENVIRON["NEW_COUNT"]
      } else if (!skip && !saw_general) {
        print ""
        print "[General]"
        print "rules=" ENVIRON["NEW_RULES"]
        print "count=" ENVIRON["NEW_COUNT"]
      }
      flush_pending()
    }
  ' "$KWIN_RULES_FILE" >"$KWIN_RULES_FILE.webapp-tmp" || return 0
  cat "$KWIN_RULES_FILE.webapp-tmp" >"$KWIN_RULES_FILE"
  rm -f "$KWIN_RULES_FILE.webapp-tmp"
  echo "  KWin rule removed for '$target'"
}
