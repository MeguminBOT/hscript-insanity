import hxscript.Script;

class ArgsTest {
	static var pass = 0;
	static var fail = 0;

	static function eq(name:String, got:Dynamic, want:Dynamic) {
		if (Std.string(got) == Std.string(want)) {
			pass++;
			trace("  ok   " + name + " = " + got);
		} else {
			fail++;
			trace("  FAIL " + name + " got " + got + " want " + want);
		}
	}

	static function ev(body:String):Dynamic {
		var s = new Script("result = (" + body + ");", "a");
		s.start();
		return s.variables.get("result");
	}

	static function main() {
		eq("exact 1 arg", ev("{ function f(a) return a * 2; f(21); }"), 42);
		eq("exact 2 args", ev("{ function f(a, b) return a + b; f(1, 2); }"), 3);
		eq("no args", ev("{ function f() return 7; f(); }"), 7);
		eq("optional omitted", ev("{ function f(a, ?b) return b == null ? a : a + b; f(5); }"), 5);
		eq("optional given", ev("{ function f(a, ?b) return b == null ? a : a + b; f(5, 3); }"), 8);
		eq("default omitted", ev("{ function f(a, b = 10) return a + b; f(5); }"), 15);
		eq("default given", ev("{ function f(a, b = 10) return a + b; f(5, 1); }"), 6);
		eq("rest empty", ev("{ function f(a, ...r) return a + r.length; f(1); }"), 1);
		eq("rest one", ev("{ function f(a, ...r) return a + r.length; f(1, 9); }"), 2);
		eq("rest many", ev("{ function f(a, ...r) return a + r.length; f(1, 9, 8, 7); }"), 4);
		eq("rest values", ev("{ function f(...r) return r.join('-'); f(1, 2, 3); }"), "1-2-3");
		eq("too few -> null", ev("{ function f(a, ?b) return b; f(1); }"), null);
		trace("== " + pass + " passed, " + fail + " failed ==");
	}
}
