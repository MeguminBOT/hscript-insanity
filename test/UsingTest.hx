import hxscript.Script;
import hxscript.Module;
import hxscript.Environment;

/**
 * Static extensions on script-declared classes: that a `using` on one registers at all, that the
 * right one is chosen when several share a method name, and that an error thrown inside the chosen
 * extension reaches the caller.
 *
 * The name-collision case is the point. A `using` used to be matched by method NAME alone, so
 * `(5).twice()` reached whichever extension was registered first regardless of what it accepts.
 */
class UsingTest {
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

	/**
	 * Runs `body` against two extension modules and returns the result, or `threw: <e>`.
	 *
	 * `StringExt` is registered FIRST and its `twice` returns a marked string, so an `Int` receiver
	 * picking it up is visible in the result rather than coincidentally producing the right number.
	 *
	 * @param body The script body to evaluate.
	 * @return The stringified result, or `threw: <error>`.
	 */
	static function evalWith(body:String):String {
		var env = new Environment();
		env.addModule(new Module("
class StringExt {
    public static function twice(s:String):String return '[' + s + s + ']';
}
", 'StringExt', [], 'StringExt.hxs'));
		env.addModule(new Module("
class IntExt {
    public static function twice(i:Int):Int return i * 2;
    public static function boom(i:Int):Int throw 'from the extension';
}
", 'IntExt', [], 'IntExt.hxs'));
		env.start();

		var out:String = 'threw: <nothing>';
		var s = new Script("
using StringExt;
using IntExt;

function run() return " + body + ";
", 'UsingTest.hxs', env);
		s.onProgramError = function(e:haxe.Exception):Void out = 'threw: ' + e.message;
		s.start();

		try {
			out = Std.string(s.call('run'));
		} catch (e:Dynamic)
			out = 'threw: ' + Std.string(e);
		return out;
	}

	static function main():Void {
		trace('-- a using on a scripted class registers --');
		// Gating registration on `is Class` skipped scripted classes entirely, so every call through
		// one failed with `Cannot call`.
		ok('string extension resolves', evalWith("'ab'.twice()") == '[abab]');

		trace('-- the receiver type selects the extension --');
		// StringExt is registered first and also declares `twice`; picking by name alone would take it.
		ok('int receiver takes the int extension', evalWith('(5).twice()') == '10');
		ok('string receiver still takes the string one', evalWith("'x'.twice()") == '[xx]');

		trace('-- errors inside an extension are not swallowed --');
		// The resolution loop used to call every candidate inside `try { } catch {}`, so a genuine
		// error inside the matched extension was discarded and reported as `Cannot call`.
		var boom:String = evalWith('(5).boom()');
		ok('the extension error surfaces', boom.indexOf('from the extension') >= 0);
		ok('it is not reported as Cannot call', boom.indexOf('Cannot call') < 0);

		trace('-- no candidate still reports cleanly --');
		ok('unknown method reports', evalWith('(5).notAnExtension()').indexOf('threw') == 0);

		trace('-- ' + pass + ' passed, ' + fail + ' failed --');
	}
}
