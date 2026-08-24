# oxhenri.mouse

Mouse and pointer settings panel for [Omarchy](https://github.com/basecamp/omarchy) (Quickshell).

- Pointer sensitivity and acceleration profile (`flat` / `adaptive` / custom)
- Touchpad natural scroll and scroll factor
- Cursor theme (hyprcursor and legacy XCursor themes) and cursor size

Changes apply immediately via `hyprctl` and persist through an Omarchy
hyprland-toggles lua file (`~/.local/state/omarchy/toggles/hypr/oxhenri-mouse.lua`)
so they survive reloads, in the same way `omarchy-hyprland-toggle` persists state.

## Install

```sh
git clone https://github.com/Dev-Herni/oxhenri.mouse.git \
  ~/.config/omarchy/plugins/oxhenri.mouse
```

Open the panel with:

```sh
omarchy-shell shell summon oxhenri.mouse '{}'
```

or launch it from the Omarchy plugin drawer.

## Files

- `MousePanel.qml` — settings UI
- `mouse-ctl.sh` — read (`get`) / apply + persist (`apply`) helper

## Requirements

Everything used here ships with Omarchy: `hyprctl`, `jq`, `gsettings`, and a
POSIX shell. No extra packages.

Settings are only written when you press apply in the panel, and they go to
Omarchy's own toggles state dir — your existing Hyprland config files are
never modified.

## Removal

```bash
omarchy plugin remove oxhenri.mouse --yes
```

Persisted settings live in
`~/.local/state/omarchy/toggles/hypr/oxhenri-mouse.lua`; delete that file to
forget them.

## License

MIT — see [LICENSE](LICENSE).
