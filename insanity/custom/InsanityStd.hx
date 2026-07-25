package insanity.custom;

import insanity.backend.types.Scripted.InsanityScriptedClass;
import insanity.backend.types.Scripted.InsanityScriptedInterface;
import insanity.backend.types.Scripted.InsanityScriptedEnum;
import insanity.backend.types.Scripted.InsanityScriptedTypedef;
import insanity.custom.InsanityType.ICustomEnumValueType;

/**
 * A drop-in replacement for `Std`, aliased as `Std` inside the interpreter. It adds scripted-type
 * awareness to `isOfType`/`downcast` (walking the scripted class/interface chain) and forwards the
 * rest to native `Std`.
 */
class InsanityStd {
	/**
	 * Deprecated alias for `isOfType`.
	 *
	 * @param v The value to test.
	 * @param t The class or interface to test against.
	 * @return True if `v` is of type `t`.
	 */
	@:deprecated('Std.is is deprecated. Use Std.isOfType instead.')
	public static inline function is(v:Dynamic, t:Dynamic):Bool {
		return isOfType(v, t);
	}

	/**
	 * Tests a scripted value against a scripted class or interface by walking its base chain
	 * (or checking implemented interfaces).
	 *
	 * @param v The value to test; must be a scripted instance to match.
	 * @param t The scripted class or interface to test against.
	 * @return True if `v`'s scripted type is, extends, or implements `t`.
	 */
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

	/**
	 * Runtime type check that understands scripted classes/interfaces.
	 *
	 * @param v The value to test.
	 * @param t The class or interface to test against.
	 * @return True if `v` is of type `t`.
	 */
	public static inline function isOfType(v:Dynamic, t:Dynamic):Bool {
		if (t is InsanityCoreType) {
			return switch (cast(t, InsanityCoreType)) {
				case CTInt: Std.isOfType(v, Int);
				case CTFloat: Std.isOfType(v, Float);
				case CTBool: Std.isOfType(v, Bool);
			};
		}
		if (t is InsanityScriptedClass || t is InsanityScriptedInterface) {
			return matchesScripted(v, t);
		} else if (t is InsanityScriptedEnum) {
			// A scripted enum value belongs to `t` when its enum is `t` (compared by path so a
			// reloaded enum still matches).
			if (!(v is ICustomEnumValueType))
				return false;
			var e:Dynamic = cast(v, ICustomEnumValueType).typeGetEnum();
			return e == t || (e is InsanityScriptedEnum && (cast(e, InsanityScriptedEnum).path == cast(t, InsanityScriptedEnum).path));
		} else if (t is InsanityScriptedTypedef) {
			return cast(t, InsanityScriptedTypedef).matchesStructure(v);
		} else {
			return Std.isOfType(v, t);
		}
	}

	/**
	 * Safe cast that understands scripted classes/interfaces.
	 *
	 * @param value The value to cast.
	 * @param c The target class or interface.
	 * @return `value` if it is of type `c`, otherwise null.
	 */
	public static inline function downcast(value:Dynamic, c:Dynamic):Dynamic {
		if (c is InsanityCoreType)
			return (isOfType(value, c) ? value : null);
		if (c is InsanityScriptedClass || c is InsanityScriptedInterface) {
			return (matchesScripted(value, c) ? value : null);
		} else if (c is InsanityScriptedEnum || c is InsanityScriptedTypedef) {
			return (isOfType(value, c) ? value : null);
		} else {
			return Std.downcast(value, c);
		}
	}

	/**
	 * Deprecated alias for `downcast`.
	 *
	 * @param value The value to cast.
	 * @param c The target class.
	 * @return `value` if it is of type `c`, otherwise null.
	 */
	@:deprecated('Std.instance() is deprecated. Use Std.downcast() instead.')
	public static inline function instance(value:Dynamic, c:Dynamic):Dynamic {
		return downcast(value, c);
	}

	/**
	 * Converts a value to its string representation.
	 *
	 * @param s The value.
	 * @return Its string form.
	 */
	public static inline function string(s:Dynamic):String {
		return Std.string(s);
	}

	/**
	 * Truncates a float toward zero.
	 *
	 * @param x The float.
	 * @return The integer part.
	 */
	public static inline function int(x:Float):Int {
		return Std.int(x);
	}

	/**
	 * Parses an integer from a string.
	 *
	 * @param x The string.
	 * @return The parsed integer, or null if it isn't one.
	 */
	public static inline function parseInt(x:String):Null<Int> {
		return Std.parseInt(x);
	}

	/**
	 * Parses a float from a string.
	 *
	 * @param x The string.
	 * @return The parsed float, or `Math.NaN` if it isn't one.
	 */
	public static inline function parseFloat(x:String):Float {
		return Std.parseFloat(x);
	}

	/**
	 * Returns a random integer in `[0, x)`.
	 *
	 * @param x The exclusive upper bound.
	 * @return A random integer below `x`.
	 */
	public static inline function random(x:Int):Int {
		return Std.random(x);
	}
}
