import hxscript.Environment;
import hxscript.Module;
import hxscript.compile.Cppia;
import hxscript.compile.CppiaResult;
import hxscript.types.ScriptedClass;

/** Measures the same script interpreted and compiled, and checks that both give the same answer. */
class CppiaBench {
	static var SOURCE:String = 'package p;
class T {
	public static function run():Dynamic {
		var total:Int = 0;
		var i:Int = 0;
		while (i < 300000) {
			var a:Int = i * 3;
			var b:Int = a - i;
			if (b > 100) {
				total += b % 7;
			} else {
				total += 1;
			}
			i++;
		}
		return total;
	}
}
';

	public static function main():Void {
		cpp.cppia.Host.enableJit(true);
		var interpreted:Dynamic = null;
		var compiled:Dynamic = null;

		var env:Environment = new Environment();
		var module:Module = new Module('', 'T', ['p'], 'bench');
		module.parse(SOURCE);
		env.addModule(module);
		module.init(env);
		module.start(env);
		module.startTypes(env);
		var cls:ScriptedClass = cast env.resolve('p.T');
		var interpFn:Dynamic = cls.reflectGetField('run');

		Reflect.callMethod(null, interpFn, []);
		var t0:Float = haxe.Timer.stamp();
		interpreted = Reflect.callMethod(null, interpFn, []);
		var interpMs:Float = (haxe.Timer.stamp() - t0) * 1000;

		var parser = new hxscript.syntax.Parser();
		var decls = parser.parseModule(SOURCE, 'bench', 0, ['p']);

		var t1:Float = haxe.Timer.stamp();
		var result:CppiaResult = Cppia.compile([{name: 'p.T', decls: decls}]);
		var compileMs:Float = (haxe.Timer.stamp() - t1) * 1000;

		if (result.bytes == null) {
			Sys.println('refused: ' + result.skipped[0].reason);
			return;
		}

		var t2:Float = haxe.Timer.stamp();
		var cmodule = cpp.cppia.Module.fromData(result.bytes.getData());
		cmodule.boot();
		var loadMs:Float = (haxe.Timer.stamp() - t2) * 1000;

		var ccls:Class<Dynamic> = cmodule.resolveClass('p.T');
		var cppiaFn:Dynamic = Reflect.field(ccls, 'run');

		Reflect.callMethod(null, cppiaFn, []);
		var t3:Float = haxe.Timer.stamp();
		compiled = Reflect.callMethod(null, cppiaFn, []);
		var cppiaMs:Float = (haxe.Timer.stamp() - t3) * 1000;

		Sys.println('answers      interpreted='
			+ interpreted
			+ '  cppia='
			+ compiled
			+ (Std.string(interpreted) == Std.string(compiled) ? '  (agree)' : '  DISAGREE'));
		Sys.println('emit         ' + fmt(compileMs) + ' ms   (' + result.bytes.length + ' bytes)');
		Sys.println('load + link  ' + fmt(loadMs) + ' ms');
		Sys.println('interpreted  ' + fmt(interpMs) + ' ms');
		Sys.println('cppia        ' + fmt(cppiaMs) + ' ms');
		Sys.println('speedup      ' + fmt(interpMs / cppiaMs) + 'x');
	}

	static function fmt(v:Float):String {
		return Std.string(Math.round(v * 100) / 100);
	}
}
