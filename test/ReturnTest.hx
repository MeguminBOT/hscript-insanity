import hxscript.Script;

class ReturnTest {
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
		var s = new Script("result = (" + body + ");", "r");
		s.onProgramError = function(e:haxe.Exception) trace("ERR " + e.message);
		s.start();
		return s.variables.get("result");
	}

	static function main() {
		eq("plain", ev("{ function f() return 7; f(); }"), 7);
		eq("no value", ev("{ function f() { return; } f(); }"), null);
		eq("early return", ev("{ function f() { return 1; 2; } f(); }"), 1);
		eq("from while", ev("{ function f() { var i=0; while(i<10) { if (i==3) return i; i++; } return -1; } f(); }"), 3);
		eq("from do-while", ev("{ function f() { var i=0; do { if (i==2) return i; i++; } while(i<10); return -1; } f(); }"), 2);
		eq("from for", ev("{ function f() { for (v in [0,1,2,3,4,5]) { if (v==4) return v; } return -1; } f(); }"), 4);
		eq("nested loops", ev("{ function f() { for (i in [0,1,2]) for (j in [0,1,2]) if (i+j==3) return i*10+j; return -1; } f(); }"), 12);
		eq("from switch", ev("{ function f(x) { switch(x) { case 1: return 'one'; default: return 'other'; } } f(1); }"), "one");
		eq("from try", ev("{ function f() { try { return 5; } catch(e:Dynamic) { return -1; } } f(); }"), 5);
		eq("from catch", ev("{ function f() { try { throw 'x'; } catch(e:Dynamic) { return 9; } } f(); }"), 9);
		eq("nested block", ev("{ function f() { { { return 3; } } } f(); }"), 3);
		eq("nested calls", ev("{ function g() return 2; function f() return g() * 3; f(); }"), 6);
		eq("recursion", ev("{ function fac(n) { if (n <= 1) return 1; return n * fac(n-1); } fac(5); }"), 120);
		eq("loop after call", ev("{ function g() return 1; var t=0; for (i in [1,2,3,4,5]) t += g(); t; }"), 5);
		eq("cond return", ev("{ function f(x) { if (x) return 'y'; return 'n'; } f(false); }"), "n");
		eq("return in fn arg", ev("{ function g(v) return v+1; function f() { return g(4); } f(); }"), 5);
		trace("== " + pass + " passed, " + fail + " failed ==");
	}
}
