package saveprogress;

typedef SaveOptions =
{
	?slot:String,
	?directory:String,
	?interval:Float,
	?saveOnChange:Bool,
	?changeDelay:Float,
	?saveOnFocusLost:Bool,
	?saveOnExit:Bool,
	?saveOnStateSwitch:Bool
}
