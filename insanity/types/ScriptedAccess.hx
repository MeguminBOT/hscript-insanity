package insanity.types;

using StringTools;
using insanity.types.TypeCollection;

/** Access helper for reaching the scripted class behind an instance or class value. */
@:access(insanity.types.IScriptedInstance)
class ScriptedAccess {
	/**
	 * The scripted class an instance (or a class value) belongs to, if any.
	 *
	 * @param o An instance or class value.
	 * @return The scripted class, or null if `o` isn't scripted.
	 */
	public static function declaringClass(o:Dynamic):ScriptedClass {
		if (o is IScriptedInstance)
			return o.__base;
		if (o is ScriptedClass)
			return cast o;

		return null;
	}
}
