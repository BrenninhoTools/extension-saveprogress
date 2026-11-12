package saveprogress;

class SaveSignal<T>
{
	var listeners:Array<T->Void> = [];

	public function new() {}

	public function add(listener:T->Void):Void
	{
		if (indexOf(listener) == -1)
			listeners.push(listener);
	}

	public function remove(listener:T->Void):Void
	{
		var index = indexOf(listener);
		if (index != -1)
			listeners.splice(index, 1);
	}

	public function removeAll():Void
	{
		listeners.resize(0);
	}

	public function dispatch(value:T):Void
	{
		for (listener in listeners.copy())
			listener(value);
	}

	function indexOf(listener:T->Void):Int
	{
		for (i in 0...listeners.length)
			if (Reflect.compareMethods(listeners[i], listener))
				return i;
		return -1;
	}
}
