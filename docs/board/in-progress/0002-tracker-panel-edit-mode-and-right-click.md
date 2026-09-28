# 0002 The tracker panel is not in Edit Mode, and right-click acts directly

## Why

The small on-screen tracker panel (`UI/Tracker.lua`, `DjinnisDelveTrackerPanel`) is moved by
dragging it, with its own lock setting, so it is the one frame on screen that Blizzard's Edit Mode
cannot place. Right-clicking it (and the broker/minimap button in `Core.lua`) opens the options
panel straight away instead of offering a menu. Both break standing rules for every addon here:
anything on screen is movable from Edit Mode, and a right-click opens a menu, never acts by
itself. It came about because the addon predates both rules. Found 2026-09-29 while reviewing
`0001`.

## Links

**Relates to**
- `DjinnisUIEnhancements/EditMode.lua` - an existing Edit Mode integration in this workspace to
  copy the approach from rather than invent one.

## Not this card

- The main window (`UI/MainWindow.lua`). It is a toggled dialog, not a HUD element.
- Any change to what left-click does.

## Acceptance

<!-- AC:BEGIN -->
- [ ] WHEN Edit Mode is opened, THE ADDON SHALL show the tracker panel as a selectable, movable frame, and its position SHALL persist across `/reload`. proves: manual
- [ ] WHEN the tracker panel or broker icon is right-clicked, THE ADDON SHALL open a context menu (at least "Options" and "Lock/Unlock"), and SHALL NOT open the options panel directly. proves: manual
- [ ] WHEN the change is made, `luac -p` SHALL pass over every file outside `libs/`. proves: none, there is no suite; the syntax check is the only local gate
<!-- AC:END -->

## Tasks

- [ ] Register the panel with Edit Mode the way `DjinnisUIEnhancements/EditMode.lua` does, and
      migrate the saved position.
- [ ] Replace the right-click handlers in `UI/Tracker.lua` and `Core.lua` with a menu
      (`MenuUtil.CreateContextMenu`; check it in `wow-ui-source` first).
