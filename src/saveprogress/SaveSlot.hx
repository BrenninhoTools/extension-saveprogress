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

	public function hasChanges():Bool
	{
		if (dirty)
			return true;
		capture();
		return SaveCodec.encode(data) != lastEncoded;
	}

	public function reload():Bool
	{
		data = [];
		lastEncoded = null;
		dirty = false;
		var success = load();
		if (!success)
			capture();
		return success;
	}

	public function saveSnapshot(snapshot:String, ?label:String):Null<SaveSnapshot>
	{
		capture();
		var id = SaveStorage.sanitize(snapshot);
		var time = Date.now().getTime();
		var text = label != null ? label : snapshot;
		var payload:Map<String, Dynamic> = [
			"name" => id,
			"label" => text,
			"slot" => name,
			"time" => time,
			"data" => data
		];

		if (!SaveStorage.write(snapshotKey(id), SaveCodec.encode(payload)))
		{
			SaveProgress.onError.dispatch('Failed to write manual save "$snapshot" in slot "$name"');
			return null;
		}

		var info = new SaveSnapshot(id, name, text, time);
		SaveProgress.onManualSave.dispatch(info);
		return info;
	}

	public function loadSnapshot(snapshot:String):Bool
	{
		var id = SaveStorage.sanitize(snapshot);
		var payload = readSnapshot(id);
		if (payload == null)
		{
			SaveProgress.onError.dispatch('Manual save "$snapshot" in slot "$name" was not found or is corrupted');
			return false;
		}

		data = cast payload.get("data");
		apply();
		markDirty();
		if (SaveProgress.mode == SaveMode.AUTO)
			flush();
		SaveProgress.onManualLoad.dispatch(infoOf(id, payload));
		return true;
	}

	public function snapshotInfo(snapshot:String):Null<SaveSnapshot>
	{
		var id = SaveStorage.sanitize(snapshot);
		var payload = readSnapshot(id);
		return payload == null ? null : infoOf(id, payload);
	}

	public function snapshotExists(snapshot:String):Bool
	{
		return SaveStorage.exists(snapshotKey(SaveStorage.sanitize(snapshot)));
	}

	public function listSnapshots():Array<SaveSnapshot>
	{
		var prefix = key + "@";
		var result:Array<SaveSnapshot> = [];
		for (file in SaveStorage.list(prefix))
		{
			var id = file.substr(prefix.length);
			var payload = readSnapshot(id);
			if (payload != null)
				result.push(infoOf(id, payload));
		}
		result.sort((a, b) -> a.time > b.time ? -1 : (a.time < b.time ? 1 : 0));
		return result;
	}

	public function deleteSnapshot(snapshot:String):Bool
	{
		var file = snapshotKey(SaveStorage.sanitize(snapshot));
		if (!SaveStorage.exists(file))
			return false;
		SaveStorage.delete(file);
		return true;
	}

	public function deleteSnapshots():Void
	{
		for (file in SaveStorage.list(key + "@"))
			SaveStorage.delete(file);
	}

	inline function snapshotKey(id:String):String
	{
		return key + "@" + id;
	}

	function readSnapshot(id:String):Null<Map<String, Dynamic>>
	{
		for (content in SaveStorage.read(snapshotKey(id)))
		{
			var payload = SaveCodec.decode(content);
			if (payload != null && Std.isOfType(payload.get("data"), haxe.ds.StringMap))
				return payload;
		}
		return null;
	}

	function infoOf(id:String, payload:Map<String, Dynamic>):SaveSnapshot
	{
		var label:Null<String> = payload.get("label");
		var time:Null<Float> = payload.get("time");
		return new SaveSnapshot(id, name, label != null ? label : id, time != null ? time : 0);
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
