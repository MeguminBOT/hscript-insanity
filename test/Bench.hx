import insanity.Script;

/**
 * Interpreter micro-benchmark. Each case isolates one hot path so an optimization can be
 * attributed: `call` exercises the call-stack frame push/pop, `blocks` the per-block scope
 * bookkeeping, `field` the field-access chain, `arith`/`locals` the operator dispatch and
 * variable lookup.
 */
class Bench {
	static var reps:Int = 3;

	static function bench(name:String, src:String):Void {
		// warm up (parse + first run), then take the best of `reps` to cut scheduler noise
		var best:Float = 1e9;
		for (i in 0...reps) {
			var s = new Script(src, name);
			var t0 = haxe.Timer.stamp();
			s.start();
			var dt = haxe.Timer.stamp() - t0;
			if (dt < best)
				best = dt;
		}
		trace(pad(name, 10) + Std.int(best * 1000) + " ms");
	}

	static function pad(s:String, n:Int):String {
		while (s.length < n)
			s += " ";
		return s;
	}

	static function main():Void {
		trace("-- interpreter micro-benchmark (best of " + reps + ") --");

		bench("arith", "var x = 0; var i = 0; while (i < 300000) { x += i * 2 - 1; i++; } x;");
		bench("locals", "var a = 1; var b = 2; var c = 3; var i = 0; while (i < 300000) { a = b + c; i++; } a;");
		bench("blocks", "var i = 0; var s = 0; while (i < 200000) { { var t = i; s = t; } i++; } s;");
		bench("call", "function f(a) return a + 1; var i = 0; var s = 0; while (i < 100000) { s = f(s); i++; } s;");
		bench("field", "var o = {a: 1, b: 2}; var i = 0; var s = 0; while (i < 200000) { s += o.a; i++; } s;");
		bench("method", "var arr = [1]; var i = 0; while (i < 100000) { arr.indexOf(1); i++; } i;");
		// Array element read and write, and the unary operators, all of which have to tell an
		// ordinary value apart from a wrapped abstract before they can act on it.
		bench("index", "var a = [1, 2, 3]; var i = 0; var s = 0; while (i < 200000) { s += a[1]; i++; } s;");
		bench("indexSet", "var a = [1, 2, 3]; var i = 0; while (i < 200000) { a[0] = i; i++; } a[0];");
		bench("not", "var b = false; var i = 0; var s = 0; while (i < 200000) { if (!b) s++; i++; } s;");
		bench("neg", "var x = 5; var i = 0; var s = 0; while (i < 200000) { s = -x; i++; } s;");

		// Attribution: 0 / 1 / 3 parameters at the same call count. The spread between them is the
		// per-parameter cost (declared.push + locals.set + tryCast); call0 is the fixed per-call
		// overhead (makeVarArgs, frame push, locals duplicate, restore, frame pop).
		bench("call0", "function f() return 1; var i = 0; var s = 0; while (i < 100000) { s = f(); i++; } s;");
		bench("call1", "function f(a) return a; var i = 0; var s = 0; while (i < 100000) { s = f(s); i++; } s;");
		bench("call3", "function f(a, b, c) return a; var i = 0; var s = 0; while (i < 100000) { s = f(s, 1, 2); i++; } s;");
		// A block with the same body but no call at all, as the floor.
		// Does `return` (implemented by throwing Stop.SReturn) dominate a call?
		bench("callRet", "function f() return 1; var i = 0; var s = 0; while (i < 100000) { s = f(); i++; } s;");
		bench("callNoRet", "function f() { 1; } var i = 0; var s = 0; while (i < 100000) { s = f(); i++; } s;");
		// break / continue still unwind by throwing Stop; continue can fire every iteration.
		bench("loopPlain", "var i = 0; var s = 0; while (i < 100000) { i++; s += i; } s;");
		bench("loopCont", "var i = 0; var s = 0; while (i < 100000) { i++; if (i % 2 == 0) continue; s += i; } s;");
		bench("noCall", "var i = 0; var s = 0; while (i < 100000) { s = s; i++; } s;");

		// Diagnostic: same call count, but the function is declared in a scope holding 20 locals.
		// If per-call cost scales with captured-scope size, the locals-map copy dominates calls.
		var many = "";
		for (n in 0...20)
			many += "var v" + n + " = " + n + "; ";
		bench("call_cap20", many + "function f(a) return a + 1; var i = 0; var s = 0; while (i < 100000) { s = f(s); i++; } s;");

		trace("-- done --");
	}
}
