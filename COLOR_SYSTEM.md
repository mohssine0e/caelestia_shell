# Dark green color system

The active **Dark Green / Hard Dark** palette is defined in [`themes/darkgreen-hard-dark.txt`](themes/darkgreen-hard-dark.txt). Caelestia CLI loads it into `~/.local/state/caelestia/scheme.json`; `Colours.palette` exposes the same Material 3 roles to every QML layout. The defaults in [`services/Colours.qml`](services/Colours.qml) mirror that palette for startup before the state file loads.

## Palette and use

| Role | Color | Use |
|---|---|---|
| Background / surface | `#0B120D` / `#0E1711` | Desktop chrome and large panels |
| Containers | `#111D15` → `#26392B` | Cards and layered controls, increasing in emphasis |
| Primary | `#5A916C` | Focus, selected states, lyrics, and active controls |
| Primary container | `#1A3825` | Subtle primary tint and Cava fade base |
| Inverse primary | `#3C7452` | Cava bar tips, with opacity |
| On surface / variant | `#DCE8DE` / `#A1B3A4` | Main and supporting text |
| Secondary | `#88AD92` | Quiet green accent |
| Tertiary | `#D2B477` | Stars, pins, and other positive highlights |
| Error | `#DD8588` | Urgent or high intensity status |

This combines a dark, green-tinted neutral scale with a restrained jade accent. Warm gold and dusty rose distinguish highlights and urgent states from the primary green. It is a custom palette, inspired by the [Radix Sage and Jade dark scales](https://www.radix-ui.com/colors/docs/palette-composition/scales) and their [palette composition guidance](https://www.radix-ui.com/colors/docs/palette-composition/composing-a-palette), rather than a copy of either scale.

[Material 3 color roles](https://m3.material.io/m3/pages/color-roles?s=m3) guide the component mapping: surfaces hold layouts, `onSurface` holds text, primary marks focus or selection, and tertiary/error carry distinct meaning. In code, use `Colours.palette` rather than a literal hex value. `Colours.streakColour()` and `Colours.favouriteColour` centralize the task-specific roles. Lyrics and the desktop visualizer also use these palette roles, so switching themes changes them with the rest of the shell.

The active palette has checked contrast ratios of **14.48:1** for on-surface text on surface, **5.58:1** for on-surface-variant text on the highest container, **4.96:1** for primary on surface, and **5.15:1** for on-primary on primary. These meet the [WebAIM guidance](https://webaim.org/resources/contrastchecker/) of 4.5:1 for normal text. Opacity, wallpaper images, and translucent overlays can lower effective contrast; review those against their actual backgrounds.

## Rule for future layouts

- Use `m3surface` and the container roles for layout layers.
- Use the matching `on` role for text and icons on filled controls.
- Use `m3primary` for focus, selection, and the active lyric; `m3onSurfaceVariant` for quiet text.
- Use `m3tertiary` for favorites and `m3error` for urgent status. Avoid encoding meaning with green alone.
- Keep hex values in the theme and the `Colours.qml` startup defaults, not individual QML views. Alpha values may be applied to a palette role when needed.
