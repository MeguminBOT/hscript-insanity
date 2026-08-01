import hxscript.Config;
import hxscript.Script;

/**
 * Access control on script-declared members: that explicit `private` is enforced, that unmarked
 * members deliberately are not, and that `@:privateAccess` waives the check at the call site.
 *
 * The gate is the part worth pinning down. `checkAccess` runs when `Config.strictAccess` OR
 * `Config.typedMode` is set, and typed mode is the default, so `private` is enforced out of the box
 * and leaving `strictAccess` false does not turn it off.
 */
class AccessTest {
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

	/** A class with one explicitly private member and one unmarked one. */
	static inline var HOLDER:String = "
class Holder {
    private var secret:Int = 42;
    var open:Int = 7;
    public function new() {}
}
";

	/**
	 * Evaluates an expression against `HOLDER`.
	 *
	 * @param body The expression to evaluate.
	 * @return Its value stringified, or `blocked` when the access was refused.
	 */
	static function eval(body:String):String {
		var s = new Script(HOLDER + '\nfunction run() return ' + body + ';', 'AccessTest.hxs');
		s.onProgramError = function(e:haxe.Exception):Void {};
		s.start();

		try {
			return Std.string(s.call('run'));
		} catch (e:Dynamic) {
			return 'blocked';
		}
	}

	static function main():Void {
		var wasStrict:Bool = Config.strictAccess;
		var wasTyped:Bool = Config.typedMode;

		trace('-- typed mode alone enforces private --');
		Config.strictAccess = false;
		Config.typedMode = true;
		ok('private is refused', eval('new Holder().secret') == 'blocked');
		ok('unmarked is not', eval('new Holder().open') == '7');

		trace('-- @:privateAccess waives it --');
		ok('reaches the private member', eval('@:privateAccess new Holder().secret') == '42');

		trace('-- strictAccess enforces it with typed mode off --');
		Config.strictAccess = true;
		Config.typedMode = false;
		ok('private is refused', eval('new Holder().secret') == 'blocked');
		ok('@:privateAccess still waives it', eval('@:privateAccess new Holder().secret') == '42');

		trace('-- both off leaves the check out entirely --');
		Config.strictAccess = false;
		Config.typedMode = false;
		ok('private is reachable', eval('new Holder().secret') == '42');

		Config.strictAccess = wasStrict;
		Config.typedMode = wasTyped;

		trace('-- ' + pass + ' passed, ' + fail + ' failed --');
	}
}
