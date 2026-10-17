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

**2026-09-29** The loop moved this card from in-progress/ to human-review/ WITHOUT trying it. All 2 of its open acceptance criteria say proves: manual, so there is nothing left an unattended session could close and starting one would change nothing. Each open criterion names what to look at and what a pass is: tick what passes and move the card on, or say what failed and move it back to todo/.

### 2026-10-04 manager (m20261004153633-f962)

**outcome: rob**

The code looks complete, and the two open checks need a person in the live game.

**what the session said**

I read the code that the build note talks about. The code does what the card asks.

- **Edit Mode:** In `UI/Tracker.lua`, `AddToEditMode` puts Blizzard's selection box over the panel. The box shows when Edit Mode opens and hides when it closes. When you drag the box, it saves the position through `ns.SavePosition` in `Core.lua`, into the same saved fields as before.
- **Right-click:** In `Core.lua`, `ns.OpenContextMenu` uses `MenuUtil.CreateContextMenu`. The menu has "Options" and a lock checkbox. The panel's `OnMouseUp` in `Build` (in `UI/Tracker.lua`) uses it, and so does the broker `OnClick` in `BuildBroker` (in `Core.lua`). Neither one opens the options directly now.

No review finding disproves the ticked criterion. The two open criteria can only be checked in a live game client, so a builder cannot close them.

What Rob must do: deploy, then do the in-game checks 1 and 2 from the card's build note.

WHY: The code looks complete, and the two open checks need a person in the live game.

OUTCOME: rob

**2026-10-11** Clear-down (attended, agent). The game folder was older than `0c30a34`: today's dry run showed `Core.lua`, `Locales\enUS.lua` and `UI\Tracker.lua` changed. Deployed with `bin\deploy.ps1 -Only DjinnisDelveTracker`; the next dry run showed 75 unchanged, so the build is now in the game. The two open criteria are the in-game looks (checks 1 and 2 in the 2026-09-29 build note). Per the board README rule "A look waits on the product", moved to `ai-review/`: the 2026-10-04 pass was a manager pass, not an adversarial review.

### 2026-10-17 review (v20261017044143-77f9)

**suite**

No suite this job could find in WoWAddons:DjinnisDelveTracker, so none ran. That is not a pass.

**acceptance: sound**

I reviewed card 0002 against its three acceptance criteria, using only the code. I could not break it. Nothing was edited.

**#1 Edit Mode box (manual, open).** This is in `UI/Tracker.lua`, function `AddToEditMode`.
- It puts Blizzard's selection box over the panel.
- I checked Blizzard's template in `wow-ui-source` (`Blizzard_EditMode/Shared/EditModeSystemTemplates.xml`). The template already takes the mouse and left-button drag, so the replaced drag code will run.
- The box drags the panel even when the panel is locked. That is correct, because Edit Mode must always move it.
- The position saves through `ns.SavePosition` (`Core.lua`). `Build` reads it back with `ns.RestorePosition` after `/reload`.
- Nothing stops this check from passing.

**#2 Right-click menu (manual, open).** This is `ns.OpenContextMenu` in `Core.lua`.
- It makes a menu with a title, "Options" and the lock checkbox.
- The panel calls it from `OnMouseUp` in `Build` (`UI/Tracker.lua`). The broker icon calls it from `OnClick` in `BuildBroker` (`Core.lua`).
- Neither one opens the options directly now.
- `ns.OpenOptions` exists in `Options.lua`. `L["OPT_LOCK_TRACKER"]` exists in `Locales/enUS.lua`.
- Nothing stops this check from passing.

**#3 Syntax check (ticked).** No code proves it wrong.

The two open boxes are in-game checks for you. They are not findings.

**What you do now:** the card can go to `done/`. Later, in game, do checks 1 and 2 from the card's 2026-09-29 build note.

VERDICT: sound

**scope: sound**

**Scope review of card 0002**

**What the card asked for, and what was built:**
- Edit Mode box over the panel: built, in `UI/Tracker.lua` `AddToEditMode`.
- Right-click menu on the panel and the broker icon: built, in `Core.lua` `ns.OpenContextMenu`. The panel uses it in `Build`, and the broker uses it in `BuildBroker`.
- The lock checkbox works at once. The panel's `OnDragStart` reads `tracker.locked` on every drag.
- "Migrate the saved position": nothing needs to move. The Edit Mode drag saves through `ns.SavePosition` into the same `profile.tracker` fields.
- Left-click did not change. `MainWindow.lua` did not change. Both fences hold.

**Extra things in the range:**
- A root `LICENSE` and `libs/CallbackHandler-1.0/LICENSE.txt`. The card did not ask for these. They are legal files, not code. They change no behaviour.
- The rewrite of card 0001 and its move to `done/`. That is board work from the 2026-10-11 clear-down. It is not part of this card's build.

These extras are outside the card, but they break no criterion. They do not touch the tracker or the menu.

**Half done:** If the panel is hidden, it gets no Edit Mode box. The builder wrote this down as a known gap. It only matters for a panel the user turned off, so criterion #1 can still pass in game.

I found nothing that disproves a criterion.

VERDICT: sound

**breakage: sound**

I tried to find something this change breaks. I found nothing.

- **Callers:** Both right-click paths now call `ns.OpenContextMenu`: the panel's `OnMouseUp` in `Build` (`UI/Tracker.lua`) and the broker `OnClick` in `BuildBroker` (`Core.lua`). Nothing else opens the options on a right-click.
- **Blizzard API:** I checked each call against `wow-ui-source`. `ClearSelectedSystem`, `SelectSystem` and `IsEditModeActive` exist in `EditModeManager.lua`. `ShowSelected` and `ShowHighlighted` exist in `EditModeSystemTemplates.lua`. The selection box's own `OnMouseDown` and drag scripts are replaced, so Blizzard's manager never receives our frame.
- **Lock rule:** Outside Edit Mode, the panel's own `OnDragStart` still checks `tracker.locked`. Inside Edit Mode, the selection box drags the panel even when it is locked. That is correct, because Edit Mode must always be able to move it.
- **Saved position:** Both drag paths save through `ns.SavePosition` into the same `profile.tracker` fields. Old saved positions still load.
- **Comments:** The file header says "drag to move it while it is unlocked". That is still true.
- **Edge case:** A hidden panel gets no box in Edit Mode, because the box is a child of the panel. The build note already says this. A panel that is turned off does not need to be placed, so criterion #1 is not broken.

The two open criteria need a check in the game. That is not a finding.

VERDICT: sound

