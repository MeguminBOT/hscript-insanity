package insanity.types;

import insanity.runtime.Interp;
import insanity.syntax.Expr;
import insanity.Module;

using StringTools;
using insanity.types.TypeCollection;

/** Helpers for resolving the types a scripted class extends or implements. */
class ScriptedTools {
	/** Every native class that has a generated scripting bridge, keyed by class name. */
	public static var scriptedClasses(default, never):Map<String, Class<IScriptedInstance>> = insanity.macro.ScriptedMacro.listScriptedClasses();

	/**
	 * Resolves an `extends`/`implements` type reference against the declaring module's
	 * imports first, then the interpreter's, then the compiled type collection.
	 *
	 * @param t The type reference to resolve.
	 * @param module The declaring module whose imports take priority, if any.
	 * @param interp The interpreter whose imports/environment are consulted next, if any.
	 * @return The resolved type.
	 * @throws String If the type cannot be found or the reference is not a path.
	 */
	public static function resolveType(t:CType, ?module:Module, ?interp:Interp):Dynamic {
		return switch (t) {
			case CTPath(path, _):
				var p:String = path.join('.');

				var type = (module?.interp.imports.get(p) ?? interp?.imports.get(p) ?? Tools.resolve(p, interp?.environment));
				if (type == null)
					throw 'Type not found: $p';

				type;
			case null:
				null;
			default:
				throw 'Invalid type $t';
				null;
		}
	}

	/**
	 * Like `resolveType`, but for `implements` entries. A native interface that the
	 * runtime can't hand back as a value still names a valid contract -- the generated
	 * bridge is what satisfies it -- so a known-but-unresolvable interface returns null
	 * instead of throwing. An outright unknown name still throws.
	 *
	 * @param t The interface reference to resolve.
	 * @param module The declaring module whose imports take priority, if any.
	 * @param interp The interpreter whose imports/environment are consulted next, if any.
	 * @return The resolved interface, or null for a known-but-unresolvable native interface.
	 * @throws String If the name is outright unknown or the reference is not a path.
	 */
	public static function resolveInterface(t:CType, ?module:Module, ?interp:Interp):Dynamic {
		var p:String = switch (t) {
			case CTPath(path, _): path.join('.');
			default: throw 'Invalid interface $t';
		}

		var type = (module?.interp.imports.get(p) ?? interp?.imports.get(p) ?? Tools.resolve(p, interp?.environment));
		if (type != null)
			return type;

		if (TypeCollection.main.fromPath(p) == null && interp?.environment?.types.fromPath(p) == null)
			throw 'Type not found: $p';

		return null;
	}

	/**
	 * Resolves a base type to something a scripted class can extend: either an already-scripted
	 * class, or a native class that has a generated bridge.
	 *
	 * @param t The base type (a scripted class or a native class).
	 * @return The scripted class, or the bridge class for a native base.
	 * @throws String If the native class has no scripting bridge.
	 */
	public static function resolve(t:Dynamic):Dynamic {
		if (t is ScriptedClass)
			return cast t;

		var cls:String = Type.getClassName(t);
		if (scriptedClasses.exists(cls))
			return scriptedClasses.get(cls);

		throw 'Class $cls can\'t be extended for scripting';
		return null;
	}
}
