import insanity.Script;

class LoopTest {
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
		var s = new Script("result = (" + b + ");", "l");
		s.onProgramError = function(e:haxe.Exception) trace("ERR " + e.message);
		s.start();
		return s.variables.get("result");
	}

	static function main() {
		eq("break while", ev("{ var i=0; while(i<100) { if (i==5) break; i++; } i; }"), 5);
		eq("continue while", ev("{ var i=0; var s=0; while(i<10) { i++; if (i%2==0) continue; s+=i; } s; }"), 25);
		eq("break for", ev("{ var t=0; for (v in [1,2,3,4,5]) { if (v==3) break; t+=v; } t; }"), 3);
		eq("continue for", ev("{ var t=0; for (v in [1,2,3,4,5]) { if (v%2==0) continue; t+=v; } t; }"), 9);
		eq("break inner only", ev("{ var t=0; for (i in [1,2]) { for (j in [1,2,3]) { if (j==2) break; t+=j; } } t; }"), 2);
		eq("cont inner only", ev("{ var t=0; for (i in [1,2]) { for (j in [1,2,3]) { if (j==2) continue; t+=j; } } t; }"), 8);
		eq("break do-while", ev("{ var i=0; do { i++; if (i==3) break; } while(i<100); i; }"), 3);
		eq("break in block", ev("{ var i=0; while(i<100) { { if (i==4) break; } i++; } i; }"), 4);
		eq("break then code", ev("{ var t=0; for (v in [1,2,3]) { if (v==2) break; t+=v; } t+100; }"), 101);
		eq("compr plain", ev("[for (v in [1,2,3]) v*2]"), [2, 4, 6]);
		eq("compr filtered", ev("[for (v in [1,2,3,4]) if (v%2==1) v]"), [1, 3]);
		eq("return over loop", ev("{ function f() { for (v in [1,2,3]) { if (v==2) return v; } return -1; } f(); }"), 2);
		eq("loop after break", ev("{ var a=0; for (v in [1,2,3]) { if (v==2) break; a+=v; } for (v in [1,2]) a+=10; a; }"), 21);
		trace("== " + pass + " passed, " + fail + " failed ==");
	}
}
