package saveprogress;

import haxe.Timer;

private typedef SaveTracker =
{
	getter:Void->Dynamic,
	setter:Dynamic->Void
}

class SaveSlot
{
	public var name(default, null):String;
	public var key(default, null):String;
	public var dirty(default, null):Bool = false;
	public var loaded(default, null):Bool = false;
	public var recovered(default, null):Bool = false;
	public var lastSaveTime(default, null):Float = -1;

	var data:Map<String, Dynamic> = [];
	var trackers:Map<String, SaveTracker> = [];
	var lastEncoded:Null<String> = null;

	public function new(name:String, key:String)
	{
		this.name = name;
		this.key = key;
	}

	public function get<T>(field:String, ?fallback:T):T
	{
		var tracker = trackers.get(field);
		if (tracker != null)
			return cast tracker.getter();
		return data.exists(field) ? cast data.get(field) : fallback;
	}

	public function set<T>(field:String, value:T):T
	{
		data.set(field, value);
		var tracker = trackers.get(field);
		if (tracker != null)
			tracker.setter(value);
		markDirty();
		return value;
	}

	public function has(field:String):Bool
	{
		return data.exists(field) || trackers.exists(field);
	}

	public function remove(field:String):Bool
	{
		trackers.remove(field);
		var removed = data.remove(field);
		if (removed)
			markDirty();
		return removed;
	}

	public function fields():Array<String>
	{
		capture();
		var result = [for (field in data.keys()) field];
		result.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
		return result;
	}

	public function clear():Void
	{
		data.clear();
		markDirty();
	}

	public function track<T>(field:String, getter:Void->T, setter:T->Void):Void
	{
		trackers.set(field, {getter: cast getter, setter: cast setter});
		if (data.exists(field))
			setter(cast data.get(field));
		else
			data.set(field, getter());
	}

	public function trackFields(field:String, target:Dynamic, names:Array<String>):Void
	{
		var getter = function():Dynamic
		{
			var snapshot = {};
			for (name in names)
				Reflect.setField(snapshot, name, Reflect.getProperty(target, name));
			return snapshot;
		};
		var setter = function(value:Dynamic):Void
		{
			if (value == null)
				return;
			for (name in names)
				if (Reflect.hasField(value, name))
					Reflect.setProperty(target, name, Reflect.field(value, name));
		};
		track(field, getter, setter);
	}

	public function untrack(field:String):Bool
	{
		return trackers.remove(field);
	}

	public function markDirty():Void
	{
		dirty = true;
		SaveProgress.notifyChange(this);
	}

	public function load():Bool
	{
		var candidates = SaveStorage.read(key);
		for (i in 0...candidates.length)
		{
			var decoded = SaveCodec.decode(candidates[i]);
			if (decoded == null)
				continue;
			data = decoded;
			lastEncoded = i == 0 ? candidates[i] : null;
			recovered = i > 0;
			dirty = recovered;
			loaded = true;
			apply();
			SaveProgress.onLoad.dispatch(this);
			return true;
		}

		if (candidates.length > 0)
			SaveProgress.onError.dispatch('Save slot "$name" is corrupted and could not be recovered');

		loaded = true;
		recovered = false;
		return false;
	}

	public function flush(force:Bool = false):Bool
	{
		capture();
		var encoded = SaveCodec.encode(data);
		if (!force && encoded == lastEncoded)
		{
			dirty = false;
			return true;
		}

		if (!SaveStorage.write(key, encoded))
		{
			SaveProgress.onError.dispatch('Failed to write save slot "$name"');
			return false;
		}

		lastEncoded = encoded;
		lastSaveTime = Timer.stamp();
		dirty = false;
		SaveProgress.onSave.dispatch(this);
		return true;
	}

	public function erase():Void
	{
		SaveStorage.delete(key);
		data.clear();
		for (field => tracker in trackers)
			data.set(field, tracker.getter());
		lastEncoded = null;
		dirty = false;
		recovered = false;
	}

	public function export():String
	{
		capture();
		return SaveCodec.encode(data);
	}

	public function importData(content:String, save:Bool = true):Bool
	{
		var decoded = SaveCodec.decode(content);
		if (decoded == null)
			return false;
		data = decoded;
		apply();
		dirty = true;
		return save ? flush(true) : true;
	}

	function capture():Void
	{
		for (field => tracker in trackers)
			data.set(field, tracker.getter());
	}

	function apply():Void
	{
		for (field => tracker in trackers)
			if (data.exists(field))
				tracker.setter(data.get(field));
	}
}
