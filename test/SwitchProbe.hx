import hxscript.Environment;
import hxscript.Module;
import hxscript.types.ScriptedClass;

/**
 * Checks whether interpreter switching explains why a call into another scripted class costs more
 * than a call within one.
 *
 * Every scripted class builds its own `Interp`, and `expr` keeps a static pointing at whichever one
 * is currently evaluating. Staying inside a class leaves that static alone; crossing into another
 * rewrites it on the way in and again on the way out. If that is the cost, the switch count should
 * scale with the number of cross-class calls and stay near zero for same-class ones.
 *
 * Both cases do identical work and differ only in which class the callee lives in, so a difference
 * in time is attributable to the crossing rather than to the body.
 *
 * Build with `-D hxscript_profile` for the counter.
 */
class SwitchProbe {
	static var HELPER:String = "package p;

class Helper {
	public static function bump(a:Float):Float {
		return a + 1.0;
	}
}
";

	static var CALLER:String = "package p;

import p.Helper;

class Caller {
	public static var acc:Float = 0;

	public static function same(n:Int):Void {
		var i:Int = 0;
		var a:Float = 0;
		while (i < n) {
			a = bump(a);
			i++;
		}
		acc = a;
	}

	public static function bump(a:Float):Float {
		return a + 1.0;
	}

	public static function sameQualified(n:Int):Void {
		var i:Int = 0;
		var a:Float = 0;
		while (i < n) {
			a = Caller.bump(a);
			i++;
		}
		acc = a;
	}

	public static function cross(n:Int):Void {
		var i:Int = 0;
		var a:Float = 0;
		while (i < n) {
			a = Helper.bump(a);
			i++;
		}
		acc = a;
	}
}
";

	static var ITERATIONS:Int = 200000;

	public static function main():Void {
		var env:Environment = new Environment();
		add(env, 'Helper', HELPER);
		add(env, 'Caller', CALLER);

		var cls:ScriptedClass = cast env.resolve('p.Caller');
		if (cls == null) {
			Sys.println('Caller did not resolve');
			Sys.exit(1);
		}

		run(cls, 'same', 2000);
		run(cls, 'sameQualified', 2000);
		run(cls, 'cross', 2000);

		var sameMs:Float = 0;
		var crossMs:Float = 0;
		var sameSwitches:Int = 0;
		var crossSwitches:Int = 0;
		var qualMs:Float = 0;

		for (r in 0...3) {
			var a = measure(cls, 'same');
			var q = measure(cls, 'sameQualified');
			var b = measure(cls, 'cross');
			if (r == 0 || q.ms < qualMs)
				qualMs = q.ms;

			if (r == 0 || a.ms < sameMs) {
				sameMs = a.ms;
				sameSwitches = a.switches;
			}
			if (r == 0 || b.ms < crossMs) {
				crossMs = b.ms;
				crossSwitches = b.switches;
			}
		}

		Sys.println('calls per case: ' + ITERATIONS);
		Sys.println('');
		Sys.println('  same class   ' + Std.int(sameMs) + ' ms   ' + sameSwitches + ' interpreter switches');
		Sys.println('  same, qualified   ' + Std.int(qualMs) + ' ms');
		Sys.println('  other class  ' + Std.int(crossMs) + ' ms   ' + crossSwitches + ' interpreter switches');
		Sys.println('');

		var overhead:Float = sameMs > 0 ? (crossMs - sameMs) * 100.0 / sameMs : 0;
		Sys.println('  crossing costs ' + Math.round(overhead) + '% more');

		if (crossSwitches > sameSwitches) {
			var extra:Int = crossSwitches - sameSwitches;
			var perCall:Float = extra / ITERATIONS;
			Sys.println('  ' + extra + ' extra switches, ' + (Math.round(perCall * 100) / 100) + ' per call');
			var ns:Float = (crossMs - sameMs) * 1000000 / extra;
			Sys.println('  ' + Math.round(ns) + ' ns per switch, if the switch is the whole difference');
		} else {
			Sys.println('  switching does NOT explain it: counts are equal');
		}
	}

	static function measure(cls:ScriptedClass, method:String):{ms:Float, switches:Int} {
		#if hxscript_profile
		var before:Int = hxscript.runtime.Interp.interpSwitches;
		#else
		var before:Int = 0;
		#end

		var t0:Float = haxe.Timer.stamp();
		run(cls, method, ITERATIONS);
		var ms:Float = (haxe.Timer.stamp() - t0) * 1000;

		#if hxscript_profile
		var after:Int = hxscript.runtime.Interp.interpSwitches;
		#else
		var after:Int = 0;
		#end

		return {ms: ms, switches: after - before};
	}

	static function run(cls:ScriptedClass, method:String, n:Int):Void {
		var fn:Dynamic = cls.reflectGetField(method);
		if (fn == null) {
			Sys.println('missing ' + method);
			return;
		}
		Reflect.callMethod(null, fn, [n]);
	}

	static function add(env:Environment, name:String, source:String):Void {
		var module:Module = new Module('', name, ['p'], name);
		module.onParsingError = function(e:haxe.Exception):Void {
			Sys.println(name + ' parse: ' + e.message);
		};
		module.onProgramError = function(e:haxe.Exception):Void {
			Sys.println(name + ' program: ' + e.message);
		};
		module.parse(source);
		env.addModule(module);
		module.init(env);
		module.start(env);
		module.startTypes(env);
	}
}
