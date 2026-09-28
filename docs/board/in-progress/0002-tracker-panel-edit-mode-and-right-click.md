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
- [x] WHEN the change is made, `luac -p` SHALL pass over every file outside `libs/`. proves: none, there is no suite; the syntax check is the only local gate
<!-- AC:END -->

## Tasks

- [x] Register the panel with Edit Mode the way `DjinnisUIEnhancements/EditMode.lua` does, and
      migrate the saved position.
- [x] Replace the right-click handlers in `UI/Tracker.lua` and `Core.lua` with a menu
      (`MenuUtil.CreateContextMenu`; check it in `wow-ui-source` first).

## Comments

**2026-09-29**
RESULT: partial
TESTS: +0 new, none possible: no harness; the two behaviour criteria are `proves: manual` and need a live client
TOUCHED:
- UI/Tracker.lua
- Core.lua
- Locales/enUS.lua
- docs/board/in-progress/0002-tracker-panel-edit-mode-and-right-click.md
OUT-OF-SCOPE: none

Built both tasks; only the `luac -p` criterion is ticked, because the other two can only be
checked in game.

- Edit Mode: `UI/Tracker.lua` `AddToEditMode` puts Blizzard's `EditModeSystemSelectionTemplate`
  over the panel on `EditMode.Enter`, hides it on `EditMode.Exit`, and drags the panel from it.
  Cut down from `DjinnisUIEnhancements/EditMode.lua`: no settings dialog (scale is already in the
  options) and no snap/magnetism. Clicking it selects ours and clears Blizzard's; selecting a
  Blizzard frame deselects ours. The drag saves through `ns.SavePosition` into the same
  `profile.tracker` fields as before, so no saved position needed migrating.
- Right-click: `ns.OpenContextMenu` in `Core.lua` (`MenuUtil.CreateContextMenu`, checked against
  `wow-ui-source` `Blizzard_Menu/MenuUtil.lua:151` and the 11.0 menu guide) offers "Options" and a
  "Lock the tracker panel" checkbox. Used by the panel and the broker icon. Tooltip line now reads
  "Right-click: menu".
- The PHP suite named in the run prompt (`pest`, `pint`) does not exist here: this is a Lua addon
  with no `vendor/`. Not run.

In game, still to check:
1. Open Edit Mode. The panel shows a blue box labelled with the addon name; click it (yellow),
   drag it, leave Edit Mode, `/reload`, and it stays where it was put.
2. Right-click the panel and the minimap icon: a menu opens, not the options. "Options" opens
   them; the lock checkbox toggles, and a locked panel no longer drags outside Edit Mode.
3. Known gap: if the panel is hidden (tracker turned off, or no summary yet) it has no box in
   Edit Mode. Assumed right for a panel the user turned off.
