import hxscript.Script;

/**
 * Script-declared abstracts: construction, methods, properties, statics, implicit boxing at an
 * annotation, `@:op` operators, and `@:to` conversions. The declaration under test is the same one
 * for every case, so a failure points at the operation rather than at the declaration.
 */
class ScriptedAbstractTest {
	static var pass:Int = 0;
	static var fail:Int = 0;

	/** The abstract every case runs against. */
	static var decl:String = "
abstract Meters(Float) from Float to Float {
	public function new(v:Float) this = v;

	public var cm(get, never):Float;
	function get_cm():Float return this * 100;

	public function describe():String return this + 'm';

	@:op(A + B) public function add(rhs:Meters):Meters return new Meters(this + rhs);
	@:op(A * B) public function scale(k:Float):Meters return new Meters(this * k);
	@:op(A == B) public function eq(rhs:Meters):Bool return this == rhs;
	@:op(A > B) public function gt(rhs:Meters):Bool return this > rhs;
	@:op(-A) public function negate():Meters return new Meters(-this);
	@:arrayAccess public function part(k:Int):Float return this * k;

	@:to public function toStr():String return 'M' + this;

	public static var ZERO:Float = 0;
	public static function of(v:Float):Meters return new Meters(v);
}
";

	/**
	 * Records one assertion.
	 *
	 * @param name What is being checked.
	 * @param cond Whether it held.
	 */
	static function ok(name:String, cond:Bool):Void {
		if (cond) {
			pass++;
			trace("  ok   " + name);
		} else {
			fail++;
			trace("  FAIL " + name);
		}
	}

	/**
	 * Evaluates an expression against the declaration under test.
	 *
	 * @param body The expression to evaluate.
	 * @return The result as a string, or `threw: <error>`.
	 */
	static function eval(body:String):String {
		var s = new Script(decl + "res = 'no result'; try { res = Std.string(" + body + "); } catch (e:Dynamic) { res = 'threw: ' + e; }", "sa");
		s.onProgramError = function(e:haxe.Exception) {};
		s.start();
		return s.variables.get("res");
	}

	/**
	 * Asserts that an expression evaluates to an expected string.
	 *
	 * @param name What is being checked.
	 * @param body The expression to evaluate.
	 * @param want The expected result.
	 */
	static function is(name:String, body:String, want:String):Void {
		var got:String = eval(body);
		if (got != want)
			trace("       got " + got + ", wanted " + want);
		ok(name, got == want);
	}

	/**
	 * Evaluates an expression against a declaration given for the case, rather than the shared one.
	 *
	 * @param decl The declaration to run against.
	 * @param body The expression to evaluate.
	 * @return The result as a string, or `threw: <error>`.
	 */
	static function evalWith(decl:String, body:String):String {
		var s = new Script(decl + "res = 'no result'; try { res = Std.string(" + body + "); } catch (e:Dynamic) { res = 'threw: ' + e; }", "sa");
		s.onProgramError = function(e:haxe.Exception) {};
		s.start();
		return s.variables.get("res");
	}

	static function main():Void {
		trace("-- construction and members --");
		is("new + method", "new Meters(2.5).describe()", "2.5m");
		is("property getter", "new Meters(2.5).cm", "250");
		is("static var", "Meters.ZERO", "0");
		is("static method", "Meters.of(4).describe()", "4m");
		is("cast() boxes", "cast(3.5, Meters).describe()", "3.5m");

		trace("-- implicit boxing at an annotation --");
		is("typed var boxes", "{ var m:Meters = 2.5; m.describe(); }", "2.5m");
		is("reassignment stays boxed", "{ var m:Meters = 1; m = 7; m.describe(); }", "7m");
		is("typed argument boxes", "{ function f(m:Meters) return m.describe(); f(9); }", "9m");

		trace("-- operators --");
		is("A + B", "{ var a:Meters = 1; var b:Meters = 2; (a + b).describe(); }", "3m");
		is("A * B", "{ var a:Meters = 3; (a * 2).describe(); }", "6m");
		is("A == B true", "{ var a:Meters = 1; var b:Meters = 1; a == b; }", "true");
		is("A == B false", "{ var a:Meters = 1; var b:Meters = 2; a == b; }", "false");
		is("A > B", "{ var a:Meters = 5; var b:Meters = 2; a > b; }", "true");
		is("-A", "{ var a:Meters = 4; (-a).describe(); }", "-4m");
		is("a[i]", "{ var a:Meters = 3; a[2]; }", "6");
		is("compound assign", "{ var a:Meters = 1; var b:Meters = 2; a += b; a.describe(); }", "3m");

		trace("-- conversions and identity --");
		is("@:to conversion", "{ var a:Meters = 2; cast(a, String); }", "M2");
		is("is Meters", "{ var a:Meters = 2; a is Meters; }", "true");
		is("is not Meters", "2.5 is Meters", "false");

		trace("-- the constructor actually runs --");
		// A constructor that is not the identity: if it were skipped and the argument boxed directly,
		// every one of these would still look plausible, which is exactly how it slipped through once.
		var box = "abstract Box(Int) { public function new(v:Int) this = v * 10; public function raw():Int return this; }
";
		ok("ctor body runs", evalWith(box, "new Box(4).raw()") == "40");
		ok("ctor with no args runs", evalWith("abstract E(Array<Int>) { public function new() this = [1, 2, 3]; public function n():Int return this.length; }
", "new E().n()") == "3");

		trace("-- @:forward --");
		var listed = "@:forward(length) abstract Stack(Array<Int>) from Array<Int> { public function new() this = []; }
";
		var all = "@:forward abstract Bag(Array<Int>) from Array<Int> { public function new() this = []; }
";
		ok("listed field forwards", evalWith(listed, "{ var s:Stack = [1, 2]; s.length; }") == "2");
		ok("unlisted field does not", evalWith(listed, "{ var s:Stack = [1, 2]; s.indexOf(2); }").indexOf("threw") == 0);
		ok("bare forwards everything", evalWith(all, "{ var b:Bag = [7, 8]; b.indexOf(8); }") == "1");
		ok("forwarded method mutates", evalWith(all, "{ var b = new Bag(); b.push(1); b.push(2); b.length; }") == "2");
		ok("own members still win", evalWith(all, "{ var b = new Bag(); Std.string(b); }") == "[]");

		trace("-- enum abstract still works --");
		is("enum abstract constant", "{ enum abstract Col(Int) { var Red = 3; var Blue = 4; } Col.Red; }", "3");
		is("enum abstract unqualified", "{ enum abstract Col(Int) { var Red = 3; var Blue = 4; } Blue; }", "4");

		trace("-- " + pass + " passed, " + fail + " failed --");
	}
}
