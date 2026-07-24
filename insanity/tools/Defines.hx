package insanity.tools;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

class Defines {
	public static var compilerDefines(default, never):Map<String, Dynamic> #if (!macro) = getDefines() #end;

	public static function appendCompilerDefines(map:Map<String, Dynamic>):Map<String, Dynamic> {
		for (k => v in compilerDefines) {
			if (!map.exists(k))
				map.set(k, v);
		}

		return map;
	}

	public static macro function getDefines():Expr #if macro {
		return macro $v{haxe.macro.Context.getDefines()};
	} #end;
}
