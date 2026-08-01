import hxscript.Script;
import hxscript.Module;
import hxscript.Environment;

/**
 * That a class or static field declared with a type is bound the way the identical LOCAL is, and
 * that an error inside a field initializer or a method arrives with its call stack.
 *
 * The local is the control throughout. A field used to be assigned straight into its slot without
 * the declared type being applied, so an abstract-typed field never boxed: its methods and operators
 * were unreachable while the same declaration as a local worked.
 */
class FieldBindTest {
	static var pass:Int = 0;
	static var fail:Int = 0;

	/**
	 * Records one assertion.
	 *
	 * @param name What is being checked.
	 * @param cond Whether it held.
	 */
	static function ok(name:String, cond:Bool):Void {
		if (cond) {
			pass++;
			trace('  ok   ' + name);
		} else {
			fail++;
			trace('  FAIL ' + name);
		}
	}

	/** A script declaring an abstract and a class that stores it in an instance and a static field. */
	static inline var SOURCE:String = "
abstract Meters(Float) from Float to Float {
    public function new(v:Float) this = v;
    public function describe():String return this + 'm';
    @:op(A + B) public function add(o:Meters):Meters return new Meters(this + (o : Float));
}

class Box {
    public var dist:Meters = 5.0;
    public static var origin:Meters = 1.0;
    public function new() {}
}

function run(what:String) {
    var local:Meters = 5.0;
    var b = new Box();
    return switch (what) {
        case 'local': local.describe();
        case 'field': b.dist.describe();
        case 'static': Box.origin.describe();
        case 'op': (b.dist + local).describe();
        default: 'unknown';
    };
}
";

	/**
	 * Evaluates one case of `SOURCE`.
	 *
	 * @param what Which binding to exercise.
	 * @return The result, or `threw: <error>`.
	 */
	static function eval(what:String):String {
		var s = new Script(SOURCE, 'FieldBindTest.hxs');
		s.onProgramError = function(e:haxe.Exception):Void {};
		s.start();
		try {
			return Std.string(s.call('run', [what]));
		} catch (e:Dynamic)
			return 'threw: ' + Std.string(e);
	}

	static function main():Void {
		trace('-- an abstract-typed binding boxes wherever it is declared --');
		ok('local (the control)', eval('local') == '5m');
		ok('instance field', eval('field') == '5m');
		ok('static field', eval('static') == '1m');
		ok('operator on a field', eval('op') == '10m');

		trace('-- a field-initializer error carries its stack --');
		// Script and Module report failures with `haxe.Exception.details()`, which includes the
		// frames; the class hooks interpolated the value instead, so an error in a field initializer
		// or a method arrived with no stack at all.
		// `describeError` is what the class hooks render through, so it is asserted directly rather
		// than through a trace: an exception must arrive with frames, a bare value must survive as-is.
		var probe:String = '';
		var s = new Script("function boom() throw 'ouch';
boom();", 'StackProbe.hxs');
		s.onProgramError = function(e:haxe.Exception):Void probe = hxscript.types.ScriptedClass.describeError(e);
		s.start();

		ok('an exception renders its frames', probe.indexOf('Called from') >= 0);
		ok('and names the throwing function', probe.indexOf('boom') >= 0);
		ok('a bare value renders as itself', hxscript.types.ScriptedClass.describeError('plain') == 'plain');

		trace('-- ' + pass + ' passed, ' + fail + ' failed --');
	}
}
