import hxscript.Environment;
import hxscript.Module;
import hxscript.compile.Cppia;
import hxscript.compile.CppiaResult;
import hxscript.types.ScriptedClass;

/**
 * Checks that a property on a host object behaves the same compiled as interpreted.
 *
 * cppia reaches a named field on a host object without going through its accessors, so a property
 * reads as null and a write does nothing -- with no error either way, which is what makes this worth
 * a test of its own rather than trusting it. Every engine object is full of these: a sprite's text,
 * its colour, which cameras it draws to.
 */
class PropTest {
	static var SRC:String = 'package p;
class Holder {
	public var scaled(get, set):Int;

	var real:Int = 0;

	function get_scaled():Int return real;

	function set_scaled(v:Int):Int {
		real = v * 2;
		return real;
	}

	public function new() {}
}
class T {
	public static function run(sink:HostSink):Dynamic {
		sink.tinted = 21;
		return sink.tinted;
	}

	// The object belongs to the batch but the field is not one of its plain variables, so reading and
	// writing must agree on going through the accessor. Disagreeing produces an assignment to a call,
	// which the loader refuses for the whole module.
	public static function viaAccessor():Dynamic {
		var h:Holder = new Holder();
		h.scaled = 21;
		return h.scaled;
	}
}
';
	static var failures:Int = 0;

	public static function main():Void {
		cpp.cppia.Host.enableJit(true);
		var env = new Environment();
		var m = new Module(SRC, 'T', ['p'], 'probe');
		env.addModule(m);
		env.variables.set('HostSink', HostSink);
		m.init(env);
		m.start(env);
		m.startTypes(env);
		var cls:ScriptedClass = cast env.resolve('p.T');
		var interpreted:Dynamic = Reflect.callMethod(null, cls.reflectGetField('run'), [new HostSink()]);
		report('interpreted', interpreted);
		report('interpreted, batch accessor', Reflect.callMethod(null, cls.reflectGetField('viaAccessor'), []));

		var decls = new hxscript.syntax.Parser().parseModule(SRC, 'T', 0, ['p']);
		var r:CppiaResult = Cppia.compile([{name: 'p.T', decls: decls}], ['HostSink']);
		if (r.bytes == null) {
			Sys.println('  FAIL refused: ' + r.skipped[0].reason);
			Sys.exit(1);
		}
		var mod = cpp.cppia.Module.fromData(r.bytes.getData());
		mod.boot();
		try {
			var built:Class<Dynamic> = mod.resolveClass('p.T');
			report('compiled', Reflect.callMethod(null, Reflect.field(built, 'run'), [new HostSink()]));
			report('compiled, batch accessor', Reflect.callMethod(null, Reflect.field(built, 'viaAccessor'), []));
		} catch (e:Dynamic) {
			failures++;
			Sys.println('  FAIL compiled threw: ' + e);
		}

		Sys.println('');
		Sys.println(failures == 0 ? 'host properties agree' : failures + ' disagreed');
		Sys.exit(failures == 0 ? 0 : 1);
	}

	/**
	 * Checks one answer.
	 *
	 * Forty two, because the setter doubles what it is given: a value that arrived without passing
	 * through the setter would be twenty one, and one that never arrived at all would be null.
	 */
	static function report(how:String, got:Dynamic):Void {
		var ok:Bool = Std.string(got) == '42';
		if (!ok) {
			failures++;
		}
		Sys.println('  ' + (ok ? 'ok  ' : 'FAIL') + ' ' + how + '   ' + got);
	}
}
