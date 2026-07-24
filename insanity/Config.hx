package insanity;

#if (!macro) import insanity.tools.Defines; #end
import insanity.backend.Expr;
import insanity.custom.*;
#if hl import insanity.custom.HL; #end

/**
 * Global, process-wide interpreter configuration: which interpreter class to instantiate, access
 * rules, reflection shims, the default variable/import/type-proxy tables, and the type blacklist.
 * These are static so every `Interp`, `Module`, and `Script` shares one setup.
 */
class Config {
	#if (!macro)
	/** The interpreter class instantiated by `Module`/`Script`; override to plug in a subclass. */
	public static var interpClass:Class<insanity.backend.Interp> = insanity.backend.Interp;

	/**
	 * Enforces `private` on script-declared members: reading or writing one from
	 * outside the declaring class (or a subclass) errors instead of succeeding.
	 * Only explicit `private` counts -- scripts treat unmarked members as public,
	 * unlike Haxe, because every existing script relies on that.
	 */
	public static var strictAccess:Bool = false;

	/**
	 * Emulation shims for methods that have NO runtime representation and so can't be reflected on --
	 * notably `inline extern` overloads, which compiled Haxe inlines at the call site but a script can
	 * only reach reflectively (and gets null). A shim is a real compiled closure that performs the
	 * call; it is keyed by the owner's fully-qualified class name + `.` + method (e.g.
	 * `some.pack.Owner.method`). When `obj.method(args)` finds no runtime method, the interpreter looks
	 * up a shim for the object's class (walking up its superclasses) before failing. The closure
	 * receives the receiver and the call arguments.
	 */
	public static var callShims:Map<String, (o:Dynamic, args:Array<Dynamic>) -> Dynamic> = new Map();

	/** Preprocessor values visible to `#if`/`#elseif` in scripts, seeded from the host compiler defines plus `insanity`. */
	public static var preprocessorValues:Map<String, Dynamic> = Defines.appendCompilerDefines(['insanity' => '1']);

	/** Variables defined in every interpreter by default (the literals `null`/`true`/`false`). */
	public static var globalVariables:Map<String, Dynamic> = ['null' => null, 'true' => true, 'false' => false];

	/** Imports applied to every interpreter by default (the root package, wildcard-imported). */
	public static var globalImports:Map<String, ImportMode> = ['' => IAll];

	/** Maps a native type name a script might reference to the proxy class that stands in for it. */
	@:unreflective public static var typeProxy:Map<String, Dynamic> = [
		#if hl
		'Math' => HLMath,
		#end
		'Reflect' => InsanityReflect,
		'Type' => InsanityType,
		'Std' => InsanityStd
	];

	/** Types scripts are forbidden to touch, grouped by how they are matched (exact type, module, or package). */
	@:unreflective public static var blacklist:Map<ConfigBlacklistKind,
		Array<String>> = [ByPackage(false) => [], ByPackage(true) => [], ByModule => [], ByType => [],];
	#end
}

/** Helpers for enforcing the `Config.blacklist`. */
class ConfigUtil {
	/**
	 * Tests whether a type is blacklisted by exact name, by its module, or by its package (exact or
	 * prefix, depending on how the package rule was registered).
	 *
	 * @param type The class or enum to test.
	 * @return True if the type is blacklisted.
	 */
	public static function typeIsBlacklisted(type:Dynamic):Bool {
		if (type == null)
			return false;

		var name:String = (type is Enum ? Type.getEnumName(type) : Type.getClassName(type));
		if (Config.blacklist.get(ByType)?.contains(name))
			return true;

		var info = insanity.backend.TypeCollection.main.fromCompilePath(name);
		if (info != null) {
			if (Config.blacklist.get(ByModule)?.contains(info[0].module))
				return true;
			if (Config.blacklist.get(ByPackage(false))?.contains(info[0].pack.join('.')))
				return true;
			if (Config.blacklist.exists(ByPackage(true))) {
				var eq:Bool = false;
				var pack:String = info[0].pack.join('.');

				for (p in Config.blacklist.get(ByPackage(true))) {
					if (StringTools.startsWith(pack, p))
						return true;
				}
			}
		}

		return false;
	}

	/**
	 * Passes a type through unless it is blacklisted, in which case it warns and returns null. Used
	 * to gate type lookups at their resolution points.
	 *
	 * @param type The class or enum to check.
	 * @return The same type, or null if blacklisted.
	 */
	public static function assertBlacklisted(type:Dynamic):Dynamic {
		if (typeIsBlacklisted(type)) {
			trace('WARNING: ${type is Enum ? Type.getEnumName(type) : Type.getClassName(type)} is blacklisted');

			return null;
		} else {
			return type;
		}
	}
}

/** How a `Config.blacklist` entry matches a type. */
enum ConfigBlacklistKind {
	/** Match every type in a package; `recursive` also matches sub-packages by prefix. */
	ByPackage(recursive:Bool);

	/** Match every type in a module. */
	ByModule;

	/** Match one exact type by fully-qualified name. */
	ByType;
}
