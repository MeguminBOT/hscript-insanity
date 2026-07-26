import insanity.Script;

/**
 * Native abstracts seen from a script: construction, field and static access, method calls, and
 * `@:op` operator dispatch. Every operator case is asserted against the value native Haxe produces
 * for the same expression, since matching Haxe is the whole point.
 */
class AbstractTest {
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
			trace("  ok   " + name);
		} else {
			fail++;
			trace("  FAIL " + name);
		}
	}

	/**
	 * Runs a script expression and returns its value as a string, so a thrown error is reported
	 * rather than aborting the run.
	 *
	 * @param body The expression to evaluate.
	 * @return The result of `Std.string` on the value, or `threw: <error>`.
	 */
	static function eval(body:String):String {
		var s = new Script("res = 'no result'; try { res = Std.string(" + body + "); } catch (e:Dynamic) { res = 'threw: ' + e; }", "abs");
		s.onProgramError = function(e:haxe.Exception) {};
		s.start();
		return s.variables.get("res");
	}

	/**
	 * Asserts that a script expression produces what native Haxe produced for the same expression.
	 *
	 * @param name What is being checked.
	 * @param body The script expression.
	 * @param native The value native Haxe computed.
	 */
	static function same(name:String, body:String, native:Dynamic):Void {
		var got:String = eval(body);
		var want:String = Std.string(native);
		if (got != want)
			trace("       got " + got + ", native Haxe gives " + want);
		ok(name, got == want);
	}

	static function main():Void {
		trace("-- abstracts --");

		var a:OpVec = 1;
		var b:OpVec = 2;

		ok("cast constructs", eval("{ var v:OpVec = cast 7; v.raw; }") == "7");
		ok("cast() constructs", eval("cast(7, OpVec).raw") == "7");
		ok("property reads", eval("{ var v:OpVec = cast 7; v.raw; }") == "7");
		ok("static reads", eval("OpVec.ZERO.raw") == "0");
		ok("method call", eval("{ var x:OpVec = cast 1; var y:OpVec = cast 2; x.add(y).raw; }") == "21");

		// @:op dispatch. Each fixture operator returns something plain Int arithmetic would not, so
		// these fail loudly if the interpreter falls back to the boxed value instead of dispatching.
		same("a + b dispatches", "{ var x:OpVec = cast 1; var y:OpVec = cast 2; (x + y).raw; }", (a + b).raw);
		same("a - b dispatches", "{ var x:OpVec = cast 5; var y:OpVec = cast 2; (x - y).raw; }", ((5 : OpVec) - (2 : OpVec)).raw);
		same("a * b dispatches", "{ var x:OpVec = cast 3; var y:OpVec = cast 4; (x * y).raw; }", ((3 : OpVec) * (4 : OpVec)).raw);
		same("a == b dispatches", "{ var x:OpVec = cast 5; var y:OpVec = cast 6; x == y; }", (5 : OpVec) == (6 : OpVec));
		same("a > b dispatches", "{ var x:OpVec = cast 1; var y:OpVec = cast 9; x > y; }", (1 : OpVec) > (9 : OpVec));

		// `!=` has no fixture operator; Haxe derives it from `==`, and so does the interpreter.
		same("a != b negates ==", "{ var x:OpVec = cast 5; var y:OpVec = cast 9; x != y; }", (5 : OpVec) != (9 : OpVec));

		// No `@:op(A < B)`. Haxe rejects this at compile time even with an implicit cast to the
		// underlying type available, so there is no native result to match; the interpreter is
		// deliberately permissive and falls back to the boxed values.
		ok("a < b falls back", eval("{ var x:OpVec = cast 1; var y:OpVec = cast 9; x < y; }") == "true");

		ok("a += b dispatches", eval("{ var x:OpVec = cast 1; var y:OpVec = cast 2; x += y; x.raw; }") == "21");

		// An abstract with no operators at all must compare and combine on what it boxes. Comparing
		// the wrappers would compare identity and report two equal values as different.
		same("bare == compares values", "{ var x:OpBare = cast 5; var y:OpBare = cast 5; x == y; }", (5 : OpBare) == (5 : OpBare));
		same("bare != compares values", "{ var x:OpBare = cast 5; var y:OpBare = cast 6; x != y; }", (5 : OpBare) != (6 : OpBare));
		// Arithmetic and ordering on an operator-free abstract are likewise rejected by Haxe, and
		// likewise fall back here.
		ok("bare + falls back", eval("{ var x:OpBare = cast 2; var y:OpBare = cast 3; x + y; }") == "5");
		ok("bare < falls back", eval("{ var x:OpBare = cast 2; var y:OpBare = cast 3; x < y; }") == "true");

		// Mixing an abstract with a plain value: the operator method takes the abstract's own type,
		// so the boxed value is what the fallback combines.
		ok("abstract + Int falls back", eval("{ var x:OpBare = cast 2; x + 3; }") == "5");

		// An abstract on the *right*. Haxe needs `@:commutative` to accept these at all, but getting
		// them wrong here is not a compile error, it is a silently wrong number: before the operands
		// were both checked, hxcpp coerced the wrapper through `(b : Float)` and `1 * vec` gave 0.
		ok("Int + abstract dispatches", eval("{ var y:OpVec = cast 2; (1 + y).raw; }") == "12");
		ok("Int * abstract dispatches", eval("{ var y:OpVec = cast 2; (1 * y).raw; }") == "3");
		ok("Int - abstract falls back", eval("{ var y:OpVec = cast 2; 1 - y; }") == "-1");
		ok("Int < abstract falls back", eval("{ var y:OpVec = cast 2; 1 < y; }") == "true");
		ok("Int == abstract compares values", eval("{ var y:OpVec = cast 1; 1 == y; }") == "true");

		trace("-- " + pass + " passed, " + fail + " failed --");
	}
}
