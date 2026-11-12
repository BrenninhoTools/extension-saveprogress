package saveprogress;

import haxe.Serializer;
import haxe.Unserializer;
import haxe.crypto.Crc32;
import haxe.io.Bytes;

class SaveCodec
{
	public static inline var HEADER:String = "SPRG1";

	public static function encode(data:Map<String, Dynamic>):String
	{
		var serializer = new Serializer();
		serializer.useCache = true;
		serializer.serialize(data);
		var body = serializer.toString();
		return HEADER + ":" + checksum(body) + ":" + body;
	}

	public static function decode(content:Null<String>):Null<Map<String, Dynamic>>
	{
		if (content == null || !StringTools.startsWith(content, HEADER + ":"))
			return null;

		var start = HEADER.length + 1;
		var separator = content.indexOf(":", start);
		if (separator == -1)
			return null;

		var sum = content.substring(start, separator);
		var body = content.substr(separator + 1);
		if (sum != checksum(body))
			return null;

		try
		{
			var value:Dynamic = Unserializer.run(body);
			if (Std.isOfType(value, haxe.ds.StringMap))
				return cast value;
		}
		catch (e:Dynamic) {}
		return null;
	}

	static function checksum(body:String):String
	{
		return StringTools.hex(Crc32.make(Bytes.ofString(body)), 8);
	}
}
