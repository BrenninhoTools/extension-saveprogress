package saveprogress;

import haxe.Timer;

class SaveProgress
{
	public static final onSave:SaveSignal<SaveSlot> = new SaveSignal<SaveSlot>();
	public static final onLoad:SaveSignal<SaveSlot> = new SaveSignal<SaveSlot>();
	public static final onError:SaveSignal<String> = new SaveSignal<String>();
	public static final onManualSave:SaveSignal<SaveSnapshot> = new SaveSignal<SaveSnapshot>();
	public static final onManualLoad:SaveSignal<SaveSnapshot> = new SaveSignal<SaveSnapshot>();

	public static var initialized(default, null):Bool = false;
	public static var id(default, null):String = "game";
	public static var enabled:Bool = true;
	public static var mode:SaveMode = SaveMode.AUTO;
	public static var interval:Float = 60;
	public static var saveOnChange:Bool = true;
	public static var changeDelay:Float = 1.5;
	public static var saveOnFocusLost:Bool = true;
	public static var saveOnExit:Bool = true;
	public static var saveOnStateSwitch:Bool = true;

	public static var slot(get, never):SaveSlot;
	public static var slotName(default, null):String = "default";

	static var slots:Map<String, SaveSlot> = [];
	static var lastTick:Float = -1;
	static var intervalElapsed:Float = 0;
	static var changeElapsed:Float = 0;
	static var changePending:Bool = false;
	static var hooked:Bool = false;

	#if !lime
	static var timer:Null<Timer> = null;
	#end

	public static function init(id:String = "game", ?options:SaveOptions):SaveSlot
	{
		if (initialized)
			return slot;

		SaveProgress.id = SaveStorage.sanitize(id);
		var startSlot = "default";

		if (options != null)
		{
			if (options.mode != null)
				mode = options.mode;
			if (options.directory != null)
				SaveStorage.directory = options.directory;
			if (options.interval != null)
				interval = options.interval;
			if (options.saveOnChange != null)
				saveOnChange = options.saveOnChange;
			if (options.changeDelay != null)
				changeDelay = options.changeDelay;
			if (options.saveOnFocusLost != null)
				saveOnFocusLost = options.saveOnFocusLost;
			if (options.saveOnExit != null)
				saveOnExit = options.saveOnExit;
			if (options.saveOnStateSwitch != null)
				saveOnStateSwitch = options.saveOnStateSwitch;
			if (options.slot != null)
				startSlot = options.slot;
		}

		initialized = true;
		lastTick = Timer.stamp();
		hook();
		return useSlot(startSlot);
	}

	public static function shutdown():Void
	{
		if (!initialized)
			return;
		if (autoActive())
			flushAll();
		unhook();
		slots.clear();
		changePending = false;
		intervalElapsed = 0;
		initialized = false;
	}

	public static function useSlot(name:String):SaveSlot
	{
		ensureInitialized();
		var previous = slots.get(slotName);
		if (previous != null && previous.name != name && previous.dirty && autoActive())
			previous.flush();
		slotName = name;
		return getSlot(name);
	}

	public static function getSlot(name:String):SaveSlot
	{
		ensureInitialized();
		var existing = slots.get(name);
		if (existing != null)
			return existing;
		var created = new SaveSlot(name, keyOf(name));
		slots.set(name, created);
		created.load();
		return created;
	}

	public static function slotExists(name:String):Bool
	{
		return slots.exists(name) || SaveStorage.exists(keyOf(name));
	}

	public static function listSlots():Array<String>
	{
		var prefix = id + "-";
		var names = [for (key in SaveStorage.list(prefix)) if (key.indexOf("@") == -1) key.substr(prefix.length)];
		for (name in slots.keys())
		{
			var key = keyOf(name).substr(prefix.length);
			if (!names.contains(key))
				names.push(key);
		}
		return names;
	}

	public static function deleteSlot(name:String):Void
	{
		var existing = slots.get(name);
		if (existing != null)
			existing.erase();
		else
			SaveStorage.delete(keyOf(name));
		for (file in SaveStorage.list(keyOf(name) + "@"))
			SaveStorage.delete(file);
	}

	public static function copySlot(from:String, to:String):Bool
	{
		var source = getSlot(from);
		return getSlot(to).importData(source.export());
	}

	public static inline function get<T>(field:String, ?fallback:T):T
		return slot.get(field, fallback);

	public static inline function set<T>(field:String, value:T):T
		return slot.set(field, value);

	public static inline function has(field:String):Bool
		return slot.has(field);

	public static inline function remove(field:String):Bool
		return slot.remove(field);

	public static inline function track<T>(field:String, getter:Void->T, setter:T->Void):Void
		slot.track(field, getter, setter);

	public static inline function trackFields(field:String, target:Dynamic, names:Array<String>):Void
		slot.trackFields(field, target, names);

	public static inline function untrack(field:String):Bool
		return slot.untrack(field);

	public static function save():Bool
	{
		return slot.flush(true);
	}

	public static function saveTo(name:String, ?label:String):Null<SaveSnapshot>
	{
		return slot.saveSnapshot(name, label);
	}

	public static function loadFrom(name:String):Bool
	{
		return slot.loadSnapshot(name);
	}

	public static function listSaves():Array<SaveSnapshot>
	{
		return slot.listSnapshots();
	}

	public static function hasSave(name:String):Bool
	{
		return slot.snapshotExists(name);
	}

	public static function getSaveInfo(name:String):Null<SaveSnapshot>
	{
		return slot.snapshotInfo(name);
	}

	public static function deleteSave(name:String):Bool
	{
		return slot.deleteSnapshot(name);
	}

	public static function hasUnsavedChanges():Bool
	{
		return slot.hasChanges();
	}

	public static function discardChanges():Bool
	{
		changePending = false;
		changeElapsed = 0;
		return slot.reload();
	}

	public static function flush(force:Bool = false):Bool
	{
		return slot.flush(force);
	}

	public static function flushAll(force:Bool = false):Bool
	{
		var success = true;
		for (existing in slots)
			if (!existing.flush(force))
				success = false;
		changePending = false;
		changeElapsed = 0;
		return success;
	}

	public static function tick(?elapsed:Float):Void
	{
		if (!initialized)
			return;

		var now = Timer.stamp();
		if (elapsed == null)
			elapsed = lastTick < 0 ? 0 : now - lastTick;
		lastTick = now;

		if (!autoActive())
			return;

		if (changePending)
		{
			changeElapsed += elapsed;
			if (changeElapsed >= changeDelay)
				flushDirty();
		}

		if (interval > 0)
		{
			intervalElapsed += elapsed;
			if (intervalElapsed >= interval)
			{
				intervalElapsed = 0;
				flushAll();
			}
		}
	}

	@:allow(saveprogress.SaveSlot)
	static function notifyChange(changed:SaveSlot):Void
	{
		if (!autoActive() || !saveOnChange)
			return;
		changePending = true;
		changeElapsed = 0;
		if (changeDelay <= 0)
			flushDirty();
	}

	static function flushDirty():Void
	{
		changePending = false;
		changeElapsed = 0;
		for (existing in slots)
			if (existing.dirty)
				existing.flush();
	}

	static inline function autoActive():Bool
	{
		return enabled && mode == SaveMode.AUTO;
	}

	static function keyOf(name:String):String
	{
		return id + "-" + SaveStorage.sanitize(name);
	}

	static function ensureInitialized():Void
	{
		if (!initialized)
			init();
	}

	static function get_slot():SaveSlot
	{
		ensureInitialized();
		return getSlot(slotName);
	}

	static function handleExit(code:Int):Void
	{
		if (autoActive() && saveOnExit)
			flushAll();
	}

	static function handleFocusLost():Void
	{
		if (autoActive() && saveOnFocusLost)
			flushAll();
	}

	#if flixel
	static function handleStateSwitch():Void
	{
		if (autoActive() && saveOnStateSwitch)
			flushAll();
	}
	#end

	#if lime
	static function handleUpdate(delta:Int):Void
	{
		tick();
	}
	#end

	#if js
	static function handleVisibility():Void
	{
		if (js.Browser.document.hidden)
			handleFocusLost();
	}

	static function handleUnload():Void
	{
		handleExit(0);
	}
	#end

	static function hook():Void
	{
		if (hooked)
			return;
		hooked = true;

		#if lime
		var app = lime.app.Application.current;
		if (app != null)
		{
			app.onUpdate.add(handleUpdate);
			app.onExit.add(handleExit, false, 1000);
			var window = app.window;
			if (window != null)
			{
				window.onFocusOut.add(handleFocusLost);
				window.onDeactivate.add(handleFocusLost);
				window.onMinimize.add(handleFocusLost);
				window.onClose.add(handleFocusLost, false, 1000);
			}
		}
		#else
		timer = new Timer(250);
		timer.run = () -> tick();
		#end

		#if js
		js.Browser.document.addEventListener("visibilitychange", handleVisibility);
		js.Browser.window.addEventListener("pagehide", handleUnload);
		js.Browser.window.addEventListener("beforeunload", handleUnload);
		#end

		#if flixel
		flixel.FlxG.signals.preStateSwitch.add(handleStateSwitch);
		#end
	}

	static function unhook():Void
	{
		if (!hooked)
			return;
		hooked = false;

		#if lime
		var app = lime.app.Application.current;
		if (app != null)
		{
			app.onUpdate.remove(handleUpdate);
			app.onExit.remove(handleExit);
			var window = app.window;
			if (window != null)
			{
				window.onFocusOut.remove(handleFocusLost);
				window.onDeactivate.remove(handleFocusLost);
				window.onMinimize.remove(handleFocusLost);
				window.onClose.remove(handleFocusLost);
			}
		}
		#else
		if (timer != null)
		{
			timer.stop();
			timer = null;
		}
		#end

		#if js
		js.Browser.document.removeEventListener("visibilitychange", handleVisibility);
		js.Browser.window.removeEventListener("pagehide", handleUnload);
		js.Browser.window.removeEventListener("beforeunload", handleUnload);
		#end

		#if flixel
		flixel.FlxG.signals.preStateSwitch.remove(handleStateSwitch);
		#end
	}
}
