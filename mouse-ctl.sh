#!/bin/bash

# mouse-ctl.sh — read/apply mouse & pointer settings for the oxhenri.mouse
# plugin panel. Two modes:
#   get                      print current values as key=value lines
#   apply <s> <a> <n> <f> <t> <z>
#                            apply + persist input settings and cursor theme/size
#
# Persistence uses the same mechanism as omarchy-hyprland-toggle: a lua file
# in the toggles dir that is sourced last by default.hypr.toggles, so it
# wins over the user's own input.lua and survives reloads.

TOGGLES_DIR="$HOME/.local/state/omarchy/toggles/hypr"
FILE="$TOGGLES_DIR/oxhenri-mouse.lua"

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

apply() {
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

  hyprctl eval "hl.config({ input = { sensitivity = $sensitivity, accel_profile = \"$accel\", touchpad = { natural_scroll = $natural, scroll_factor = $scroll_factor } } })" >/dev/null 2>&1
  hyprctl setcursor "$theme" "$size" >/dev/null 2>&1
  hyprctl reload >/dev/null 2>&1
}

case "${1:-get}" in
  get) get ;;
  apply)
    if (($# < 7)); then
      echo "usage: mouse-ctl.sh apply <sensitivity> <accel> <natural> <scroll_factor> <theme> <size>" >&2
      exit 1
    fi
    apply "$2" "$3" "$4" "$5" "$6" "$7"
    ;;
  *) echo "usage: mouse-ctl.sh [get|apply ...]" >&2; exit 1 ;;
esac