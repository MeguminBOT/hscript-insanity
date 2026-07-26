import insanity.Script;
import insanity.Config;

class TypedTest {
	static var pass = 0;
	static var fail = 0;

	static function ok(name:String, cond:Bool) {
		if (cond) {
			pass++;
			trace("  ok   " + name);
		} else {
			fail++;
			trace("  FAIL " + name);
		}
	}

	static function main() {
		// ---- numeric (unconditional) ----
		var s = new Script('
results = [];
function tag(v) return Std.string(Type.typeof(v));
results.push("mul="   + tag(5 * 5));                    // TInt
results.push("div="   + tag(10 / 4));                   // TFloat (2.5)
results.push("mod="   + tag(10 % 3));                   // TInt
results.push("sub="   + tag({ var a = 5; a -= 1; a; }));// TInt
results.push("inc="   + tag({ var b = 5; b++; b; }));   // TInt
results.push("mix="   + tag(5 + 2.5));                  // TFloat (7.5)
results.push("cat="   + (5 + " x"));                    // "5 x"
', "num");
		s.start();
		var r:Array<Dynamic> = s.variables.get("results");
		function has(v:String)
			return Lambda.has(r, v);
		ok("mul stays Int", has("mul=TInt"));
		ok("div is Float", has("div=TFloat"));
		ok("mod stays Int", has("mod=TInt"));
		ok("x-=1 stays Int", has("sub=TInt"));
		ok("x++ stays Int", has("inc=TInt"));
		ok("Int+Float is Float", has("mix=TFloat"));
		ok("Int+String concats", has("cat=5 x"));

		// ---- typed enforcement ON ----
		Config.typedMode = true;
		ok("var Int = Float throws", throws("var x:Int = 3.5;"));
		ok("var Float = Int accepted", eval("{ var f:Float = 5; f; }") == 5 && !throws("var f:Float = 5;"));
		ok("var Int = Int ok", eval("{ var i:Int = 5; i; }") == 5);
		ok("checktype (5:Int) ok", eval("(5 : Int)") == 5);
		ok("checktype (5.5:Int) throws", throws("(5.5 : Int);"));
		ok("cast(5, Int) ok", eval("cast(5, Int)") == 5);
		ok("cast('hi', Int) throws", throws("cast('hi', Int);"));
		ok("bad string assign throws", throws("var s:String = 5;"));

		// ---- dynamic mode OFF ----
		Config.typedMode = false;
		ok("dynamic: var Int = Float allowed", !throws("var x:Int = 3.5;"));
		ok("dynamic: cast('hi', Int) allowed", !throws("cast('hi', Int);"));
		Config.typedMode = true;

		trace("== " + pass + " passed, " + fail + " failed ==");
	}

	static function eval(body:String):Dynamic {
		var s = new Script("result = (" + body + ");", "e");
		s.start();
		return s.variables.get("result");
	}

	static function throws(body:String):Bool {
		var threw = false;
		var s = new Script("threw = false; try { " + body + " } catch (e:Dynamic) { threw = true; }", "t");
		s.start();
		return s.variables.get("threw") == true;
	}
}
