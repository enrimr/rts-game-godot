# Setup Instructions for Heroines Feature

## After Pulling Latest Changes

The hero gender selection feature has been added, but you need to **reload the project in Godot** for the translations to take effect.

### Steps:

1. **Close Godot completely** (if open)
2. **Delete the `.godot/` cache** (optional but recommended):
   ```bash
   rm -rf project/.godot/global_script_class_cache.cfg
   ```
3. **Reopen the project** in Godot
4. **Wait for reimport** to complete (watch the progress bar at the bottom)
5. **Run the game** and check the lobby

### What to Expect:

In the lobby, you should now see a new dropdown after "Victory Mode":

```
Victory Mode
○ Conquest  ○ Regicide  ○ Wonder

Hero Gender              ⬇️
○ Random (50/50)
  Male
  Female
```

### If the Dropdown Still Doesn't Appear:

1. Check that `project/assets/translations/translations.csv` has the new entries:
   ```bash
   grep "LOBBY_HERO" project/assets/translations/translations.csv
   ```

2. Force reimport the translations:
   - In Godot, right-click on `assets/translations/translations.csv` in the FileSystem dock
   - Select **"Reimport"**
   - Click **"Reimport"** in the dialog

3. Restart Godot completely

### Verification:

The feature is working if you can:
- ✅ See "Hero Gender" dropdown in the lobby
- ✅ Select Random/Male/Female
- ✅ Hero info in the right panel updates based on selection
- ✅ Start a match and get the correct hero

### Files Changed:

- `project/scripts/core/match_config.gd` - Added HeroGender enum
- `project/scripts/game/game_world.gd` - Updated spawn logic
- `project/scripts/ui/lobby_screen.gd` - Added UI dropdown
- `project/assets/translations/translations.csv` - Added 23 new translation keys

---

If issues persist, check the Godot console for errors related to translation keys.
