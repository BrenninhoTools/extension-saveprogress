package saveprogress;

class SaveSnapshot
{
	public var name(default, null):String;
	public var slot(default, null):String;
	public var label(default, null):String;
	public var time(default, null):Float;
	public var date(get, never):Date;

	public function new(name:String, slot:String, label:String, time:Float)
	{
		this.name = name;
		this.slot = slot;
		this.label = label;
		this.time = time;
	}

	function get_date():Date
	{
		return Date.fromTime(time);
	}
}
