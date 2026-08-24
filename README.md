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

## License

MIT — see [LICENSE](LICENSE).
