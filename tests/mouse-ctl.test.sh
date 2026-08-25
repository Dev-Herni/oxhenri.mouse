#!/usr/bin/env bash
# Security and validation tests for mouse-ctl.sh.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CTL="$ROOT/mouse-ctl.sh"
n_pass=0
n_fail=0

pass() {
  n_pass=$((n_pass + 1))
  printf 'PASS  %s\n' "$1"
}

fail() {
  n_fail=$((n_fail + 1))
  printf 'FAIL  %s\n' "$1"
}

MAIN_TMP="$(mktemp -d)"
trap 'rm -rf "$MAIN_TMP"' EXIT

begin() {
  TEST_HOME="$(mktemp -d "$MAIN_TMP/home.XXXXXX")"
  export HOME="$TEST_HOME"
  mkdir -p "$TEST_HOME/bin"
  cat >"$TEST_HOME/bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${HOME}/hyprctl.log"
case "$1" in
  getoption)
    case "$2" in
      input:sensitivity) printf 'float: -0.25\nset: true\n' ;;
      input:accel_profile) printf 'str: flat\nset: true\n' ;;
      input:touchpad:natural_scroll) printf 'bool: false\nset: true\n' ;;
      input:touchpad:scroll_factor) printf 'float: 0.4\nset: true\n' ;;
    esac
    ;;
esac
exit 0
EOF
  cat >"$TEST_HOME/bin/gsettings" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$TEST_HOME/bin/hyprctl" "$TEST_HOME/bin/gsettings"
  export PATH="$TEST_HOME/bin:$PATH"
  FILE="$HOME/.local/state/omarchy/toggles/hypr/oxhenri-mouse.lua"
}

seed_valid() {
  bash "$CTL" apply-cursor Adwaita 24 >/dev/null
}

# --- injection: theme names must not reach generated Lua unescaped -----------

begin
seed_valid
cp "$FILE" "$FILE.bak"
if bash "$CTL" apply-cursor 'evil"; os.execute("id") --' 24 >/dev/null 2>&1; then
  fail "apply-cursor rejects a theme name containing a double quote"
else
  if cmp -s "$FILE" "$FILE.bak"; then
    pass "apply-cursor rejects a theme name containing a double quote"
  else
    fail "apply-cursor rejects a theme name containing a double quote (state file changed)"
  fi
fi
if grep -q 'os.execute' "$FILE" 2>/dev/null; then
  fail "poisoned theme is not written into Lua"
else
  pass "poisoned theme is not written into Lua"
fi

begin
seed_valid
cp "$FILE" "$FILE.bak"
nl_theme=$'evil\nid'
if bash "$CTL" apply-cursor "$nl_theme" 24 >/dev/null 2>&1; then
  fail "apply-cursor rejects a theme name containing a newline"
else
  if cmp -s "$FILE" "$FILE.bak"; then
    pass "apply-cursor rejects a theme name containing a newline"
  else
    fail "apply-cursor rejects a theme name containing a newline (state file changed)"
  fi
fi

begin
seed_valid
cp "$FILE" "$FILE.bak"
if bash "$CTL" apply-cursor '$(touch pwned)' 24 >/dev/null 2>&1; then
  fail "apply-cursor rejects a theme name with shell metacharacters"
else
  pass "apply-cursor rejects a theme name with shell metacharacters"
fi
if [[ -e "$HOME/pwned" ]] || grep -q 'touch pwned' "$FILE" 2>/dev/null; then
  fail "shell-metacharacter theme is not interpolated into Lua"
else
  pass "shell-metacharacter theme is not interpolated into Lua"
fi

# --- injection: numeric / accel Lua literals --------------------------------

begin
seed_valid
cp "$FILE" "$FILE.bak"
if bash "$CTL" apply-input '1); os.execute("id") --' flat false 0.4 >/dev/null 2>&1; then
  fail "apply-input rejects a sensitivity value that is not a number"
else
  if cmp -s "$FILE" "$FILE.bak"; then
    pass "apply-input rejects a sensitivity value that is not a number"
  else
    fail "apply-input rejects a sensitivity value that is not a number (state file changed)"
  fi
fi

begin
seed_valid
cp "$FILE" "$FILE.bak"
if bash "$CTL" apply-input -0.25 'flat"; os.execute("id") --' false 0.4 >/dev/null 2>&1; then
  fail "apply-input rejects an accel profile outside the allowlist"
else
  if cmp -s "$FILE" "$FILE.bak"; then
    pass "apply-input rejects an accel profile outside the allowlist"
  else
    fail "apply-input rejects an accel profile outside the allowlist (state file changed)"
  fi
fi

begin
if bash "$CTL" apply-input -0.25 flat maybe 0.4 >/dev/null 2>&1; then
  fail "apply-input rejects a natural-scroll value that is not a boolean"
else
  pass "apply-input rejects a natural-scroll value that is not a boolean"
fi

begin
if bash "$CTL" apply-cursor Adwaita '24"; os.execute("id") --' >/dev/null 2>&1; then
  fail "apply-cursor rejects a size that is not an integer"
else
  pass "apply-cursor rejects a size that is not an integer"
fi

# --- live apply must not hyprctl eval user strings ---------------------------

begin
bash "$CTL" apply-input -0.25 flat false 0.4 >/dev/null 2>&1 || true
if [[ -f "$HOME/hyprctl.log" ]] && grep -q 'eval' "$HOME/hyprctl.log"; then
  fail "apply-input does not call hyprctl eval"
else
  pass "apply-input does not call hyprctl eval"
fi

# --- valid persist -----------------------------------------------------------

begin
if bash "$CTL" apply -0.25 flat false 0.4 Bibata-Modern-Ice 32 >/dev/null 2>&1; then
  if grep -q 'accel_profile = "flat"' "$FILE" \
    && grep -q 'sensitivity = -0.25' "$FILE" \
    && grep -q 'natural_scroll = false' "$FILE" \
    && grep -q 'scroll_factor = 0.4' "$FILE" \
    && grep -q 'HYPRCURSOR_THEME", "Bibata-Modern-Ice"' "$FILE" \
    && grep -q 'HYPRCURSOR_SIZE", "32"' "$FILE"; then
    pass "valid apply writes expected Lua literals"
  else
    fail "valid apply writes expected Lua literals (contents)"
  fi
else
  fail "valid apply writes expected Lua literals (exit status)"
fi

# --- get: skip illegal theme directory names --------------------------------

begin
mkdir -p "$HOME/.local/share/icons/GoodTheme/cursors"
mkdir -p "$HOME/.local/share/icons/bad\"quote/cursors"
mkdir -p "$HOME/.icons/Also-Good/hyprcursors"
out="$(bash "$CTL" get)"
themes="$(printf '%s\n' "$out" | sed -n 's/^themes=//p')"
if printf '%s' "$themes" | grep -qw 'GoodTheme' && printf '%s' "$themes" | grep -qw 'Also-Good'; then
  pass "get lists allowlisted cursor theme directory names"
else
  fail "get lists allowlisted cursor theme directory names ($themes)"
fi
if printf '%s' "$themes" | grep -q 'bad'; then
  fail "get omits theme directory names that fail the allowlist"
else
  pass "get omits theme directory names that fail the allowlist"
fi

# --- atomic replace must not follow a replaceable symlink --------------------

begin
mkdir -p "$(dirname "$FILE")"
printf 'SECRET\n' >"$HOME/victim"
ln -s "$HOME/victim" "$FILE"
if bash "$CTL" apply-cursor Adwaita 24 >/dev/null 2>&1; then
  victim="$(cat "$HOME/victim")"
  if [[ "$victim" == "SECRET" ]]; then
    pass "atomic write does not follow a replaceable symlink (target intact)"
  else
    fail "atomic write does not follow a replaceable symlink (target overwritten)"
  fi
  if [[ -L "$FILE" ]]; then
    fail "atomic write replaces a symlink with a regular file"
  elif grep -q 'HYPRCURSOR_THEME", "Adwaita"' "$FILE"; then
    pass "atomic write replaces a symlink with a regular file"
  else
    fail "atomic write replaces a symlink with a regular file (missing contents)"
  fi
else
  fail "atomic write does not follow a replaceable symlink (apply failed)"
fi

# --- leftover temp files -----------------------------------------------------

begin
bash "$CTL" apply-cursor Adwaita 24 >/dev/null 2>&1 || true
leftovers="$(find "$(dirname "$FILE")" -maxdepth 1 -name 'oxhenri-mouse.*' ! -name 'oxhenri-mouse.lua' 2>/dev/null | wc -l)"
if [[ "$leftovers" -eq 0 ]]; then
  pass "atomic write leaves no temp files behind"
else
  fail "atomic write leaves no temp files behind"
fi

printf '\n%d passed, %d failed\n' "$n_pass" "$n_fail"
[[ "$n_fail" -eq 0 ]]
