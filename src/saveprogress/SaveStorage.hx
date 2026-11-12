package saveprogress;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

class SaveStorage
{
	public static inline var EXTENSION:String = ".sav";
	public static inline var TEMP_EXTENSION:String = ".tmp";
	public static inline var BACKUP_EXTENSION:String = ".bak";

	public static var directory(get, set):String;

	static var customDirectory:Null<String> = null;

	public static function read(key:String):Array<String>
	{
		var result:Array<String> = [];
		for (suffix in [EXTENSION, TEMP_EXTENSION, BACKUP_EXTENSION])
		{
			var content = readRaw(key + suffix);
			if (content != null && content.length > 0)
				result.push(content);
		}
		return result;
	}

	public static function write(key:String, content:String):Bool
	{
		#if sys
		try
		{
			ensureDirectory();
			var main = path(key + EXTENSION);
			var temp = path(key + TEMP_EXTENSION);
			var backup = path(key + BACKUP_EXTENSION);

			File.saveContent(temp, content);
			if (File.getContent(temp) != content)
				return false;

			if (FileSystem.exists(main))
			{
				if (FileSystem.exists(backup))
					FileSystem.deleteFile(backup);
				FileSystem.rename(main, backup);
			}
			FileSystem.rename(temp, main);
			return true;
		}
		catch (e:Dynamic)
		{
			return false;
		}
		#elseif js
		var storage = js.Browser.getLocalStorage();
		if (storage == null)
			return false;
		try
		{
			var previous = storage.getItem(path(key + EXTENSION));
			if (previous != null)
				storage.setItem(path(key + BACKUP_EXTENSION), previous);
			storage.setItem(path(key + EXTENSION), content);
			return true;
		}
		catch (e:Dynamic)
		{
			return false;
		}
		#else
		memory.set(key + EXTENSION, content);
		return true;
		#end
	}

	public static function exists(key:String):Bool
	{
		return readRaw(key + EXTENSION) != null || readRaw(key + BACKUP_EXTENSION) != null;
	}

	public static function delete(key:String):Void
	{
		for (suffix in [EXTENSION, TEMP_EXTENSION, BACKUP_EXTENSION])
			deleteRaw(key + suffix);
	}

	public static function list(?prefix:String):Array<String>
	{
		var names:Array<String> = [];
		for (file in listRaw())
		{
			if (!StringTools.endsWith(file, EXTENSION))
				continue;
			var key = file.substr(0, file.length - EXTENSION.length);
			if (prefix == null || StringTools.startsWith(key, prefix))
				names.push(key);
		}
		names.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
		return names;
	}

	public static function sanitize(name:String):String
	{
		var buffer = new StringBuf();
		for (i in 0...name.length)
		{
			var code = StringTools.fastCodeAt(name, i);
			var valid = (code >= "a".code && code <= "z".code) || (code >= "A".code && code <= "Z".code) || (code >= "0".code && code <= "9".code)
				|| code == "_".code || code == ".".code;
			buffer.addChar(valid ? code : "_".code);
		}
		var result = buffer.toString();
		return result.length == 0 ? "_" : result;
	}

	static function readRaw(file:String):Null<String>
	{
		#if sys
		var full = path(file);
		try
		{
			if (FileSystem.exists(full) && !FileSystem.isDirectory(full))
				return File.getContent(full);
		}
		catch (e:Dynamic) {}
		return null;
		#elseif js
		var storage = js.Browser.getLocalStorage();
		return storage == null ? null : storage.getItem(path(file));
		#else
		return memory.get(file);
		#end
	}

	static function deleteRaw(file:String):Void
	{
		#if sys
		var full = path(file);
		try
		{
			if (FileSystem.exists(full))
				FileSystem.deleteFile(full);
		}
		catch (e:Dynamic) {}
		#elseif js
		var storage = js.Browser.getLocalStorage();
		if (storage != null)
			storage.removeItem(path(file));
		#else
		memory.remove(file);
		#end
	}

	static function listRaw():Array<String>
	{
		#if sys
		var root = directory;
		try
		{
			if (FileSystem.exists(root) && FileSystem.isDirectory(root))
				return FileSystem.readDirectory(root);
		}
		catch (e:Dynamic) {}
		return [];
		#elseif js
		var storage = js.Browser.getLocalStorage();
		var result:Array<String> = [];
		if (storage == null)
			return result;
		var root = directory;
		for (i in 0...storage.length)
		{
			var key = storage.key(i);
			if (key != null && StringTools.startsWith(key, root))
				result.push(key.substr(root.length));
		}
		return result;
		#else
		return [for (key in memory.keys()) key];
		#end
	}

	static inline function path(file:String):String
	{
		return directory + file;
	}

	#if sys
	static function ensureDirectory():Void
	{
		var root = directory;
		if (!FileSystem.exists(root))
			FileSystem.createDirectory(root);
	}
	#elseif !js
	static var memory:Map<String, String> = [];
	#end

	static function get_directory():String
	{
		if (customDirectory != null)
			return customDirectory;

		#if (lime && !html5 && !js)
		var base = lime.system.System.applicationStorageDirectory;
		if (base != null && base.length > 0)
			return normalize(base) + "saveprogress/";
		#end

		#if sys
		return normalize(Sys.getCwd()) + "saves/";
		#else
		return "saveprogress/";
		#end
	}

	static function set_directory(value:String):String
	{
		customDirectory = value == null || value.length == 0 ? null : normalize(value);
		return value;
	}

	static function normalize(value:String):String
	{
		value = value.split("\\").join("/");
		return StringTools.endsWith(value, "/") ? value : value + "/";
	}
}
