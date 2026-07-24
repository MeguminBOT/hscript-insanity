package insanity;

#if (!macro) import insanity.tools.Defines; #end
import insanity.backend.Expr;
import insanity.custom.*;
#if hl import insanity.custom.HL; #end

class Config {
	#if (!macro)
	public static var interpClass:Class<insanity.backend.Interp> = insanity.backend.Interp;

	/**
	 * Enforces `private` on script-declared members: reading or writing one from
	 * outside the declaring class (or a subclass) errors instead of succeeding.
	 * Only explicit `private` counts -- scripts treat unmarked members as public,
	 * unlike Haxe, because every existing script relies on that.
	 */
	public static var strictAccess:Bool = false;

	/**
	 * Emulation shims for methods that have NO runtime representation and so can't be
	 * reflected on -- notably `inline extern` overloads like `FlxG.sound.playMusic`, which
	 * compiled Haxe inlines at the call site but a script can only reach reflectively (and
	 * gets null). A shim is a real compiled closure that performs the call; it's keyed by
	 * the owner's fully-qualified class name + `.` + method (e.g.
	 * `flixel.system.frontEnds.SoundFrontEnd.playMusic`). When `obj.method(args)` finds no
	 * runtime method, the interpreter looks up a shim for the object's class (walking up its
	 * superclasses) before failing. `o` is the receiver, `args` the call arguments.
	 */
	public static var callShims:Map<String, (o:Dynamic, args:Array<Dynamic>) -> Dynamic> = new Map();

	public static var preprocessorValues:Map<String, Dynamic> = Defines.appendCompilerDefines(['insanity' => '1']);

	public static var globalVariables:Map<String, Dynamic> = ['null' => null, 'true' => true, 'false' => false];

	public static var globalImports:Map<String, ImportMode> = ['' => IAll];

	@:unreflective public static var typeProxy:Map<String, Dynamic> = [
		#if hl
		'Math' => HLMath,
		#end
		'Reflect' => InsanityReflect,
		'Type' => InsanityType,
		'Std' => InsanityStd
	];

	@:unreflective public static var blacklist:Map<ConfigBlacklistKind,
		Array<String>> = [ByPackage(false) => [], ByPackage(true) => [], ByModule => [], ByType => [],];
	#end
}

class ConfigUtil {
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

	public static function assertBlacklisted(type:Dynamic):Dynamic {
		if (typeIsBlacklisted(type)) {
			trace('WARNING: ${type is Enum ? Type.getEnumName(type) : Type.getClassName(type)} is blacklisted');

			return null;
		} else {
			return type;
		}
	}
}

enum ConfigBlacklistKind {
	ByPackage(recursive:Bool);
	ByModule;
	ByType;
}
