# extension-saveprogress

Automatic progress saving for Haxe/Lime games. Set values or track your game objects once, and the library saves them for you: shortly after changes, on a timer, when the app loses focus or goes to background, when it closes, and on Flixel state switches.

## Features

- Automatic saving: on change (debounced), on interval, on focus loss/minimize/background, on exit and on `FlxState` switch
- Tracked values: bind getters/setters or object fields once, they are captured on every save and restored on load
- Multiple save slots, slot listing, copying and deletion
- Crash-safe writes: data is written to a temporary file first, then swapped in, keeping the previous save as a backup
- Corruption detection with CRC32 and automatic recovery from the temp/backup file
- Skips disk writes when nothing changed
- Export/import of slots as strings
- Works on Android, iOS, Windows, Linux, macOS (files) and HTML5 (localStorage)
- No required dependencies; Lime and Flixel integrations activate automatically when present

## Installation

```
haxelib git extension-saveprogress https://github.com/BrenninhoTools/extension-saveprogress
```

`Project.xml`:

```xml
<haxelib name="extension-saveprogress" />
```

## Usage

```haxe
import saveprogress.SaveProgress;

SaveProgress.init("MyGame");

var coins:Int = SaveProgress.get("coins", 0);
SaveProgress.set("coins", coins + 10);
```

That's it: the change is written automatically about 1.5 seconds later, and again whenever the game is minimized, loses focus or closes.

### Tracking values

```haxe
SaveProgress.track("volume", () -> FlxG.sound.volume, value -> FlxG.sound.volume = value);

SaveProgress.trackFields("player", player, ["x", "y", "health", "level"]);
```

Tracked values are restored immediately if a save exists, and captured automatically on every save.

### Options

```haxe
SaveProgress.init("MyGame", {
	slot: "default",
	directory: null,
	interval: 60,
	saveOnChange: true,
	changeDelay: 1.5,
	saveOnFocusLost: true,
	saveOnExit: true,
	saveOnStateSwitch: true
});
```

All options can also be changed later through the static fields of `SaveProgress`. Set `interval` to `0` to disable periodic saving, and `SaveProgress.enabled = false` to pause all automatic saving.

### Slots

```haxe
SaveProgress.useSlot("slot2");
SaveProgress.listSlots();
SaveProgress.copySlot("slot2", "slot3");
SaveProgress.deleteSlot("slot3");

var other = SaveProgress.getSlot("settings");
other.set("language", "en");
```

### Manual control

```haxe
SaveProgress.flush();
SaveProgress.flushAll(true);

var data = SaveProgress.slot.export();
SaveProgress.slot.importData(data);
```

Without Lime, call `SaveProgress.tick()` from your own update loop if `haxe.Timer` events are not processed on your target.

### Events

```haxe
SaveProgress.onSave.add(slot -> showSaveIcon());
SaveProgress.onLoad.add(slot -> if (slot.recovered) showRecoveredMessage());
SaveProgress.onError.add(message -> Sys.println(message));
```

## Storage location

| Target | Location |
| --- | --- |
| Native (Lime) | `System.applicationStorageDirectory/saveprogress/` |
| Native (no Lime) | `<cwd>/saves/` |
| HTML5 | `localStorage`, keys prefixed with `saveprogress/` |

Use the `directory` option or `SaveStorage.directory` to change it.

## License

MIT
