import hxscript.Script;

class RangeTest {
	static var pass = 0;
	static var fail = 0;

	static function eq(n:String, got:Dynamic, want:Dynamic) {
		if (Std.string(got) == Std.string(want)) {
			pass++;
			trace("  ok   " + n + " = " + got);
		} else {
			fail++;
			trace("  FAIL " + n + " got " + got + " want " + want);
		}
	}

	static function ev(b:String):Dynamic {
		var s = new Script("result = (" + b + ");", "rg");
		s.onProgramError = function(e:haxe.Exception) trace("ERR " + e.message);
		s.start();
		return s.variables.get("result");
	}

	static function main() {
		eq("basic range", ev("{ var t=0; for (i in 0...5) t += i; t; }"), 10);
		eq("range var bounds", ev("{ var n=4; var t=0; for (i in 0...n) t += i; t; }"), 6);
		eq("empty range", ev("{ var t=0; for (i in 3...3) t += i; t; }"), 0);
		eq("range compr", ev("[for (i in 0...4) i*i]"), [0, 1, 4, 9]);
		eq("nested ranges", ev("{ var t=0; for (i in 0...3) for (j in 0...3) t++; t; }"), 9);
		eq("break in range", ev("{ var t=0; for (i in 0...10) { if (i==3) break; t+=i; } t; }"), 3);
		eq("cont in range", ev("{ var t=0; for (i in 0...6) { if (i%2==0) continue; t+=i; } t; }"), 9);
		eq("return in range", ev("{ function f() { for (i in 0...10) if (i==4) return i; return -1; } f(); }"), 4);
		eq("negative range", ev("{ var t=0; for (i in -2...2) t += i; t; }"), -2);
		eq("range in method", ev("{ var a=[]; for (i in 0...3) a.push(i); a.join('-'); }"), "0-1-2");
		trace("== " + pass + " passed, " + fail + " failed ==");
	}
}
