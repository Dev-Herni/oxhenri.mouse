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

TOGGLES_DIR="$HOME/.local/state/omarchy/toggles/hypr"
FILE="$TOGGLES_DIR/oxhenri-mouse.lua"

USAGE="usage: mouse-ctl.sh [get|apply-input ...|apply-cursor ...|apply ...]"

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
  if [[ -f "$FILE" ]]; then
    theme=$(sed -n 's/.*HYPRCURSOR_THEME", "\([^"]*\)".*/\1/p' "$FILE" | head -1)
    size=$(sed -n 's/.*HYPRCURSOR_SIZE", "\([^"]*\)".*/\1/p' "$FILE" | head -1)
  fi
  [[ -z "$theme" ]] && theme=$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null | tr -d "'")
  [[ -z "$theme" ]] && theme="default"
  [[ -z "$size" ]] && size=$(gsettings get org.gnome.desktop.interface cursor-size 2>/dev/null | tr -d '\r')
  [[ -z "$size" ]] && size="24"

  # Enumerate both cursor formats: hyprcursor themes (a hyprcursors/ subdir,
  # which hyprctl setcursor accepts) and legacy XCursor themes (cursors/).
  local themes
  themes=$(for d in "$HOME/.local/share/icons"/*/ "$HOME/.icons"/*/ /usr/share/icons/*/; do
    if [[ -d "$d/hyprcursors" || -d "$d/cursors" ]]; then basename "$d"; fi
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

  mkdir -p "$TOGGLES_DIR"
  cat > "$FILE" <<EOF
-- Written by the oxhenri.mouse plugin panel.
hl.config({
  input = {
    sensitivity = $sensitivity,
    accel_profile = "$accel",
    touchpad = {
      natural_scroll = $natural,
      scroll_factor = $scroll_factor,
    },
  },
})
hl.env("HYPRCURSOR_THEME", "$theme")
hl.env("HYPRCURSOR_SIZE", "$size")
hl.env("XCURSOR_THEME", "$theme")
hl.env("XCURSOR_SIZE", "$size")
EOF
}

apply_input_live() {
  local sensitivity="$1"
  local accel="$2"
  local natural="$3"
  local scroll_factor="$4"
  hyprctl eval "hl.config({ input = { sensitivity = $sensitivity, accel_profile = \"$accel\", touchpad = { natural_scroll = $natural, scroll_factor = $scroll_factor } } })" >/dev/null 2>&1
}

apply_cursor_live() {
  hyprctl setcursor "$1" "$2" >/dev/null 2>&1
}

# Cursor theme/size from the lua file, else gsettings, else defaults.
read_cursor() {
  local theme="" size=""
  if [[ -f "$FILE" ]]; then
    theme=$(sed -n 's/.*HYPRCURSOR_THEME", "\([^"]*\)".*/\1/p' "$FILE" | head -1)
    size=$(sed -n 's/.*HYPRCURSOR_SIZE", "\([^"]*\)".*/\1/p' "$FILE" | head -1)
  fi
  [[ -z "$theme" ]] && theme=$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null | tr -d "'")
  [[ -z "$theme" ]] && theme="default"
  [[ -z "$size" ]] && size=$(gsettings get org.gnome.desktop.interface cursor-size 2>/dev/null | tr -d '\r')
  [[ -z "$size" ]] && size="24"
  CURSOR_THEME="$theme"
  CURSOR_SIZE="$size"
}

# Input values from the lua file, else hyprctl getoption, else defaults.
read_input() {
  local sensitivity="" accel="" natural="" scroll_factor=""
  if [[ -f "$FILE" ]]; then
    sensitivity=$(sed -n 's/.*sensitivity = \([^,]*\),.*/\1/p' "$FILE" | head -1)
    accel=$(sed -n 's/.*accel_profile = "\([^"]*\)".*/\1/p' "$FILE" | head -1)
    natural=$(sed -n 's/.*natural_scroll = \([^,]*\),.*/\1/p' "$FILE" | head -1)
    scroll_factor=$(sed -n 's/.*scroll_factor = \([^,]*\),.*/\1/p' "$FILE" | head -1)
  fi
  [[ -z "$sensitivity" ]] && sensitivity=$(hyprctl getoption input:sensitivity | awk '/^float:/{print $2}' | tr -d '\r')
  [[ -z "$accel" ]] && accel=$(hyprctl getoption input:accel_profile | awk '/^str:/{print $2}' | tr -d '\r')
  [[ -z "$natural" ]] && natural=$(hyprctl getoption input:touchpad:natural_scroll | awk '/^bool:/{print $2}' | tr -d '\r')
  [[ -z "$scroll_factor" ]] && scroll_factor=$(hyprctl getoption input:touchpad:scroll_factor | awk '/^float:/{print $2}' | tr -d '\r')
  [[ -z "$sensitivity" ]] && sensitivity="-0.25"
  [[ -z "$accel" ]] && accel="flat"
  [[ -z "$natural" ]] && natural="false"
  [[ -z "$scroll_factor" ]] && scroll_factor="0.4"
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

  read_cursor
  apply_input_live "$sensitivity" "$accel" "$natural" "$scroll_factor"
  write_lua "$sensitivity" "$accel" "$natural" "$scroll_factor" "$CURSOR_THEME" "$CURSOR_SIZE"
  hyprctl reload >/dev/null 2>&1
}

apply_cursor() {
  local theme="$1"
  local size="$2"

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
