package insanity.custom;

import insanity.backend.types.Scripted.InsanityScriptedClass;
import insanity.backend.types.Scripted.InsanityScriptedInterface;

class InsanityStd {
	@:deprecated('Std.is is deprecated. Use Std.isOfType instead.')
	public static inline function is(v:Dynamic, t:Dynamic):Bool {
		return isOfType(v, t);
	}

	static function matchesScripted(v:Dynamic, t:Dynamic):Bool {
		if (!(v is IScripted))
			return false;

		var base:InsanityScriptedClass = @:privateAccess v.__base;
		if (base == null)
			return false;

		if (t is InsanityScriptedInterface)
			return base.implementsInterface(cast t);

		while (base != null) {
			if (base == t)
				return true;

			var extending:Dynamic = base.extending;
			base = (extending is InsanityScriptedClass) ? cast extending : null;
		}

		return false;
	}

	public static inline function isOfType(v:Dynamic, t:Dynamic):Bool {
		if (t is InsanityScriptedClass || t is InsanityScriptedInterface) {
			return matchesScripted(v, t);
		} else {
			return Std.isOfType(v, t);
		}
	}

	public static inline function downcast(value:Dynamic, c:Dynamic):Dynamic {
		if (c is InsanityScriptedClass || c is InsanityScriptedInterface) {
			return (matchesScripted(value, c) ? value : null);
		} else {
			return Std.downcast(value, c);
		}
	}

	@:deprecated('Std.instance() is deprecated. Use Std.downcast() instead.')
	public static inline function instance(value:Dynamic, c:Dynamic):Dynamic {
		return downcast(value, c);
	}

	public static inline function string(s:Dynamic):String {
		return Std.string(s);
	}

	public static inline function int(x:Float):Int {
		return Std.int(x);
	}

	public static inline function parseInt(x:String):Null<Int> {
		return Std.parseInt(x);
	}

	public static inline function parseFloat(x:String):Float {
		return Std.parseFloat(x);
	}

	public static inline function random(x:Int):Int {
		return Std.random(x);
	}
}
