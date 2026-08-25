#!/bin/bash

# mouse-ctl.sh — read/apply mouse & pointer settings for the oxhenri.mouse
# plugin panel.
#   get
#   apply-input <sensitivity> <accel> <natural> <scroll_factor>
#   apply-cursor <theme> <size>
#   apply <sensitivity> <accel> <natural> <scroll_factor> <theme> <size>
#
# Persistence uses the same mechanism as omarchy-hyprland-toggle: a lua file
# in the toggles dir that is sourced last by default.hypr.toggles, so it
# wins over the user's own input.lua and survives reloads.
# Input and cursor can be applied independently; both halves are always
# written so a half-apply cannot clobber the other.
#
# Every value interpolated into Lua is allowlisted, and Lua strings are
# escaped. The state file is replaced atomically (mktemp + rename) so a
# replaceable symlink is not followed.

TOGGLES_DIR="$HOME/.local/state/omarchy/toggles/hypr"
FILE="$TOGGLES_DIR/oxhenri-mouse.lua"

USAGE="usage: mouse-ctl.sh [get|apply-input ...|apply-cursor ...|apply ...]"

die() {
  echo "$1" >&2
  exit 1
}

# Escape a value for a Lua double-quoted string. Allowlisting is the
# primary defense; this remains so a later charset change cannot inject.
lua_string() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

valid_theme() {
  local name="$1"
  local LC_ALL=C
  [[ ${#name} -ge 1 && ${#name} -le 128 ]] || return 1
  [[ "$name" =~ ^[A-Za-z0-9_][A-Za-z0-9._+-]*$ ]]
}

valid_size() {
  local n="$1"
  local LC_ALL=C
  [[ "$n" =~ ^[0-9]{1,3}$ ]] || return 1
  ((10#$n >= 1 && 10#$n <= 256))
}

valid_accel() {
  [[ "$1" == "flat" || "$1" == "adaptive" ]]
}

valid_bool() {
  [[ "$1" == "true" || "$1" == "false" ]]
}

valid_number_range() {
  local v="$1" lo="$2" hi="$3"
  awk -v v="$v" -v lo="$lo" -v hi="$hi" 'BEGIN {
    if (v !~ /^-?[0-9]+(\.[0-9]+)?$/) exit 1
    if (v + 0 < lo + 0 || v + 0 > hi + 0) exit 1
    exit 0
  }'
}

valid_sensitivity() { valid_number_range "$1" -1 1; }
valid_scroll() { valid_number_range "$1" 0 10; }

validate_input() {
  valid_sensitivity "$1" || die "invalid sensitivity: $1"
  valid_accel "$2" || die "invalid accel: $2"
  valid_bool "$3" || die "invalid natural: $3"
  valid_scroll "$4" || die "invalid scroll_factor: $4"
}

validate_cursor() {
  valid_theme "$1" || die "invalid theme: $1"
  valid_size "$2" || die "invalid size: $2"
}

# Regular file only — never read through a replaceable symlink.
state_file_readable() {
  [[ -L "$FILE" ]] && return 1
  [[ -f "$FILE" ]]
}

get() {
  local sensitivity
  local accel
  local natural
  local scroll_factor
  sensitivity=$(hyprctl getoption input:sensitivity | awk '/^float:/{print $2}' | tr -d '\r')
  accel=$(hyprctl getoption input:accel_profile | awk '/^str:/{print $2}' | tr -d '\r')
  natural=$(hyprctl getoption input:touchpad:natural_scroll | awk '/^bool:/{print $2}' | tr -d '\r')
  scroll_factor=$(hyprctl getoption input:touchpad:scroll_factor | awk '/^float:/{print $2}' | tr -d '\r')

  local theme="" size=""
  if state_file_readable; then
    theme=$(sed -n 's/.*HYPRCURSOR_THEME", "\([^"]*\)".*/\1/p' "$FILE" | head -1)
    size=$(sed -n 's/.*HYPRCURSOR_SIZE", "\([^"]*\)".*/\1/p' "$FILE" | head -1)
  fi
  valid_theme "$theme" || theme=""
  valid_size "$size" || size=""
  [[ -z "$theme" ]] && theme=$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null | tr -d "'")
  valid_theme "$theme" || theme="default"
  [[ -z "$size" ]] && size=$(gsettings get org.gnome.desktop.interface cursor-size 2>/dev/null | tr -d '\r')
  valid_size "$size" || size="24"

  # Enumerate both cursor formats: hyprcursor themes (a hyprcursors/ subdir,
  # which hyprctl setcursor accepts) and legacy XCursor themes (cursors/).
  # Directory names are user-writable; skip anything outside the allowlist.
  local themes name
  themes=$(for d in "$HOME/.local/share/icons"/*/ "$HOME/.icons"/*/ /usr/share/icons/*/; do
    if [[ -d "$d/hyprcursors" || -d "$d/cursors" ]]; then
      name=$(basename "$d")
      if valid_theme "$name"; then
        printf '%s\n' "$name"
      fi
    fi
  done 2>/dev/null | sort -u | tr '\n' ' ')

  echo "sensitivity=$sensitivity"
  echo "accel=$accel"
  echo "natural=$natural"
  echo "scroll_factor=$scroll_factor"
  echo "theme=$theme"
  echo "size=$size"
  echo "themes=$themes"
}

write_lua() {
  local sensitivity="$1"
  local accel="$2"
  local natural="$3"
  local scroll_factor="$4"
  local theme="$5"
  local size="$6"

  validate_input "$sensitivity" "$accel" "$natural" "$scroll_factor"
  validate_cursor "$theme" "$size"

  mkdir -p "$TOGGLES_DIR" || die "cannot create $TOGGLES_DIR"

  local accel_lua theme_lua size_lua
  accel_lua=$(lua_string "$accel")
  theme_lua=$(lua_string "$theme")
  size_lua=$(lua_string "$size")

  local tmp
  tmp=$(mktemp "${TOGGLES_DIR}/oxhenri-mouse.XXXXXX") || die "cannot create temp state file"
  if ! cat >"$tmp" <<EOF
-- Written by the oxhenri.mouse plugin panel.
hl.config({
  input = {
    sensitivity = $sensitivity,
    accel_profile = "$accel_lua",
    touchpad = {
      natural_scroll = $natural,
      scroll_factor = $scroll_factor,
    },
  },
})
hl.env("HYPRCURSOR_THEME", "$theme_lua")
hl.env("HYPRCURSOR_SIZE", "$size_lua")
hl.env("XCURSOR_THEME", "$theme_lua")
hl.env("XCURSOR_SIZE", "$size_lua")
EOF
  then
    rm -f "$tmp"
    die "failed to write temp state file"
  fi
  chmod 644 "$tmp" 2>/dev/null || true
  if ! mv -f "$tmp" "$FILE"; then
    rm -f "$tmp"
    die "failed to replace state file"
  fi
}

apply_input_live() {
  local sensitivity="$1"
  local accel="$2"
  local natural="$3"
  local scroll_factor="$4"
  hyprctl keyword input:sensitivity "$sensitivity" >/dev/null 2>&1
  hyprctl keyword input:accel_profile "$accel" >/dev/null 2>&1
  hyprctl keyword input:touchpad:natural_scroll "$natural" >/dev/null 2>&1
  hyprctl keyword input:touchpad:scroll_factor "$scroll_factor" >/dev/null 2>&1
}

apply_cursor_live() {
  hyprctl setcursor "$1" "$2" >/dev/null 2>&1
}

# Cursor theme/size from the lua file, else gsettings, else defaults.
read_cursor() {
  local theme="" size=""
  if state_file_readable; then
    theme=$(sed -n 's/.*HYPRCURSOR_THEME", "\([^"]*\)".*/\1/p' "$FILE" | head -1)
    size=$(sed -n 's/.*HYPRCURSOR_SIZE", "\([^"]*\)".*/\1/p' "$FILE" | head -1)
  fi
  valid_theme "$theme" || theme=""
  valid_size "$size" || size=""
  [[ -z "$theme" ]] && theme=$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null | tr -d "'")
  valid_theme "$theme" || theme="default"
  [[ -z "$size" ]] && size=$(gsettings get org.gnome.desktop.interface cursor-size 2>/dev/null | tr -d '\r')
  valid_size "$size" || size="24"
  CURSOR_THEME="$theme"
  CURSOR_SIZE="$size"
}

# Input values from the lua file, else hyprctl getoption, else defaults.
read_input() {
  local sensitivity="" accel="" natural="" scroll_factor=""
  if state_file_readable; then
    sensitivity=$(sed -n 's/.*sensitivity = \([^,]*\),.*/\1/p' "$FILE" | head -1)
    accel=$(sed -n 's/.*accel_profile = "\([^"]*\)".*/\1/p' "$FILE" | head -1)
    natural=$(sed -n 's/.*natural_scroll = \([^,]*\),.*/\1/p' "$FILE" | head -1)
    scroll_factor=$(sed -n 's/.*scroll_factor = \([^,]*\),.*/\1/p' "$FILE" | head -1)
  fi
  valid_sensitivity "$sensitivity" || sensitivity=""
  valid_accel "$accel" || accel=""
  valid_bool "$natural" || natural=""
  valid_scroll "$scroll_factor" || scroll_factor=""
  [[ -z "$sensitivity" ]] && sensitivity=$(hyprctl getoption input:sensitivity | awk '/^float:/{print $2}' | tr -d '\r')
  [[ -z "$accel" ]] && accel=$(hyprctl getoption input:accel_profile | awk '/^str:/{print $2}' | tr -d '\r')
  [[ -z "$natural" ]] && natural=$(hyprctl getoption input:touchpad:natural_scroll | awk '/^bool:/{print $2}' | tr -d '\r')
  [[ -z "$scroll_factor" ]] && scroll_factor=$(hyprctl getoption input:touchpad:scroll_factor | awk '/^float:/{print $2}' | tr -d '\r')
  valid_sensitivity "$sensitivity" || sensitivity="-0.25"
  valid_accel "$accel" || accel="flat"
  valid_bool "$natural" || natural="false"
  valid_scroll "$scroll_factor" || scroll_factor="0.4"
  INPUT_SENSITIVITY="$sensitivity"
  INPUT_ACCEL="$accel"
  INPUT_NATURAL="$natural"
  INPUT_SCROLL_FACTOR="$scroll_factor"
}

apply() {
  local sensitivity="$1"
  local accel="$2"
  local natural="$3"
  local scroll_factor="$4"
  local theme="$5"
  local size="$6"

  validate_input "$sensitivity" "$accel" "$natural" "$scroll_factor"
  validate_cursor "$theme" "$size"
  write_lua "$sensitivity" "$accel" "$natural" "$scroll_factor" "$theme" "$size"
  apply_input_live "$sensitivity" "$accel" "$natural" "$scroll_factor"
  apply_cursor_live "$theme" "$size"
  hyprctl reload >/dev/null 2>&1
}

apply_input() {
  local sensitivity="$1"
  local accel="$2"
  local natural="$3"
  local scroll_factor="$4"

  validate_input "$sensitivity" "$accel" "$natural" "$scroll_factor"
  read_cursor
  apply_input_live "$sensitivity" "$accel" "$natural" "$scroll_factor"
  write_lua "$sensitivity" "$accel" "$natural" "$scroll_factor" "$CURSOR_THEME" "$CURSOR_SIZE"
  hyprctl reload >/dev/null 2>&1
}

apply_cursor() {
  local theme="$1"
  local size="$2"

  validate_cursor "$theme" "$size"
  read_input
  apply_cursor_live "$theme" "$size"
  write_lua "$INPUT_SENSITIVITY" "$INPUT_ACCEL" "$INPUT_NATURAL" "$INPUT_SCROLL_FACTOR" "$theme" "$size"
  hyprctl reload >/dev/null 2>&1
}

case "$1" in
  get) get ;;
  apply-input)
    if (($# < 5)); then
      echo "usage: mouse-ctl.sh apply-input <sensitivity> <accel> <natural> <scroll_factor>" >&2
      exit 1
    fi
    apply_input "$2" "$3" "$4" "$5"
    ;;
  apply-cursor)
    if (($# < 3)); then
      echo "usage: mouse-ctl.sh apply-cursor <theme> <size>" >&2
      exit 1
    fi
    apply_cursor "$2" "$3"
    ;;
  apply)
    if (($# < 7)); then
      echo "usage: mouse-ctl.sh apply <sensitivity> <accel> <natural> <scroll_factor> <theme> <size>" >&2
      exit 1
    fi
    apply "$2" "$3" "$4" "$5" "$6" "$7"
    ;;
  *) echo "$USAGE" >&2; exit 1 ;;
esac
