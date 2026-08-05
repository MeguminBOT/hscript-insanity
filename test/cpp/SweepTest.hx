import hxscript.Environment;
import hxscript.syntax.Expr.ImportMode;
import hxscript.Module;
import hxscript.compile.Cppia;
import hxscript.compile.Compiler;
import hxscript.syntax.Parser;
import hxscript.types.ScriptedClass;

/** A host object scripts call into, with an optional argument the script leaves off. */
class Sweep {
	public static var shared:Sweep = new Sweep();

	public function new() {}

	public function greet(word:String, ?mark:String):String {
		return word + (mark == null ? '!' : mark);
	}

	public static function tag(name:String, ?suffix:String):String {
		return name + (suffix == null ? '-' : suffix);
	}
}

/**
 * Every construct a script may reasonably use, run interpreted and compiled and compared.
 *
 * The point is the REFUSED column: anything the emitter declines is a script that silently falls
 * back to being interpreted, which is correct but is not the goal.
 */
class SweepTest {
	/** Constructs the emitter declined. Reported, but not a failure: the interpreter still runs them. */
	static var refused:Int = 0;

	public static function run():Void {
		var cases:Array<Array<String>> = [
			['hostMethodOptional', 'return host.greet(\'hi\');', 'hi!', ''],
			['hostMethodAllArgs', 'return host.greet(\'hi\', \'?\');', 'hi?', ''],
			['hostStaticOptional', 'return Sweep.tag(\'x\');', 'x-', ''],
			['keyValueFor', 'var t:String = \'\'; for (k => v in [\'a\' => 1]) t += k + v; return t;', 'a1', ''],
			['patternMatch', 'var p:Dynamic = {n: 3}; switch (p) { case {n: v}: return \'n\' + v; default: return \'no\'; }', 'n3', ''],
			['switchGuard', 'var i:Int = 5; switch (i) { case v if (v > 3): return \'big\'; default: return \'small\'; }', 'big', ''],
			['mapComprehension', 'var m:Map<Int,Int> = [for (k in 0...3) k => k * 2]; return Std.string(m.get(2));', '4', ''],
			['restArgs', 'return Std.string(sum(1, 2, 3));', '6', '\tstatic function sum(...nums:Int):Int { var t:Int = 0; for (n in nums) t += n; return t; }\n'],
			['propertyAccessor', 'var b:Box = new Box(); b.doubled = 5; return Std.string(b.doubled);', '10', '}\nclass Box {\n\tvar raw:Int = 0;\n\tpublic var doubled(get, set):Int;\n\tpublic function new() {}\n\tfunction get_doubled():Int { return raw * 2; }\n\tfunction set_doubled(v:Int):Int { raw = v; return v; }\n'],
			['abstractDecl', 'var m:Meters = 3; return Std.string(m.big());', '300', '}\nabstract Meters(Int) from Int to Int {\n\tpublic function big():Int { return this * 100; }\n'],
			['nestedStruct', 'var p:Dynamic = {pos: {x: 2, y: 7}}; switch (p) { case {pos: {y: b}}: return \'y\' + b; default: return \'no\'; }', 'y7', ''],
			['arrayPattern', 'var a:Array<Int> = [4, 9]; switch (a) { case [x, y]: return Std.string(x + y); default: return \'no\'; }', '13', ''],
			['arrayLiteralPat', 'var a:Array<Int> = [1, 2]; switch (a) { case [1, v]: return \'v\' + v; default: return \'no\'; }', 'v2', ''],
			['structWildcard', 'var p:Dynamic = {a: 1, b: 2}; switch (p) { case {a: _, b: q}: return \'q\' + q; default: return \'no\'; }', 'q2', ''],
			['structGuard', 'var p:Dynamic = {n: 9}; switch (p) { case {n: v} if (v > 5): return \'big\' + v; default: return \'small\'; }', 'big9', ''],
			['patternFallthru', 'var p:Dynamic = {z: 1}; switch (p) { case {q: v}: return \'q\'; default: return \'fell\'; }', 'fell', ''],
			['absCtor', 'var m:Meters = new Meters(4); return Std.string(m.big());', '400', '}\nabstract Meters(Int) from Int to Int {\n\tpublic function new(v:Int) { this = v; }\n\tpublic function big():Int { return this * 100; }\n\tpublic function plus(o:Int):Meters { return new Meters(this + o); }\n\tpublic function raw():Int { return this; }\n\tpublic static function zero():Meters { return new Meters(0); }\n'],
			['absChain', 'var m:Meters = new Meters(2); return Std.string(m.plus(3).big());', '500', '}\nabstract Meters(Int) from Int to Int {\n\tpublic function new(v:Int) { this = v; }\n\tpublic function big():Int { return this * 100; }\n\tpublic function plus(o:Int):Meters { return new Meters(this + o); }\n\tpublic function raw():Int { return this; }\n\tpublic static function zero():Meters { return new Meters(0); }\n'],
			['absStatic', 'var m:Meters = Meters.zero(); return Std.string(m.big());', '0', '}\nabstract Meters(Int) from Int to Int {\n\tpublic function new(v:Int) { this = v; }\n\tpublic function big():Int { return this * 100; }\n\tpublic function plus(o:Int):Meters { return new Meters(this + o); }\n\tpublic function raw():Int { return this; }\n\tpublic static function zero():Meters { return new Meters(0); }\n'],
			['absArg', 'var m:Meters = new Meters(7); return Std.string(Meters.twice(m));', '14', '}\nabstract Meters(Int) from Int to Int {\n\tpublic function new(v:Int) { this = v; }\n\tpublic function big():Int { return this * 100; }\n\tpublic function plus(o:Int):Meters { return new Meters(this + o); }\n\tpublic function raw():Int { return this; }\n\tpublic static function zero():Meters { return new Meters(0); }\n\tpublic static function twice(v:Meters):Int { return v.raw() * 2; }\n'],
			['absField', 'var h:Holder2 = new Holder2(); h.dist = new Meters(5); return Std.string(h.dist.big());', '500', '}\nabstract Meters(Int) from Int to Int {\n\tpublic function new(v:Int) { this = v; }\n\tpublic function big():Int { return this * 100; }\n\tpublic function plus(o:Int):Meters { return new Meters(this + o); }\n\tpublic function raw():Int { return this; }\n\tpublic static function zero():Meters { return new Meters(0); }\n}\nclass Holder2 {\n\tpublic var dist:Meters;\n\tpublic function new() {}\n'],
			['absNoCtor', 'var f:Feet = 6; return Std.string(f.inches());', '72', '}\nabstract Feet(Int) from Int to Int {\n\tpublic function inches():Int { return this * 12; }\n'],
			['absLoop', 'var m:Meters = new Meters(0); for (i in 0...3) m = m.plus(2); return Std.string(m.big());', '600', '}\nabstract Meters(Int) from Int to Int {\n\tpublic function new(v:Int) { this = v; }\n\tpublic function big():Int { return this * 100; }\n\tpublic function plus(o:Int):Meters { return new Meters(this + o); }\n\tpublic function raw():Int { return this; }\n\tpublic static function zero():Meters { return new Meters(0); }\n'],
			['absArray', 'var a:Array<Meters> = [new Meters(1), new Meters(2)]; return Std.string(a[1].big());', '200', '}\nabstract Meters(Int) from Int to Int {\n\tpublic function new(v:Int) { this = v; }\n\tpublic function big():Int { return this * 100; }\n\tpublic function plus(o:Int):Meters { return new Meters(this + o); }\n\tpublic function raw():Int { return this; }\n\tpublic static function zero():Meters { return new Meters(0); }\n'],
			['absCond', 'var m:Meters = new Meters(5); var n:Meters = m.raw() > 3 ? m.plus(1) : m; return Std.string(n.big());', '600', '}\nabstract Meters(Int) from Int to Int {\n\tpublic function new(v:Int) { this = v; }\n\tpublic function big():Int { return this * 100; }\n\tpublic function plus(o:Int):Meters { return new Meters(this + o); }\n\tpublic function raw():Int { return this; }\n\tpublic static function zero():Meters { return new Meters(0); }\n'],
			['absString', 'var w:Word = \'hi\'; return w.shout();', 'HI!', '}\nabstract Word(String) from String to String {\n\tpublic function shout():String { return this.toUpperCase() + \'!\'; }\n'],
			['varArgsField', 'return Std.string(adder(1, 2, 3));', '6', '\tpublic static var adder:Dynamic = Reflect.makeVarArgs(function(a:Array<Dynamic>):Dynamic {\n\t\tvar t:Int = 0;\n\t\tfor (v in a) t += v;\n\t\treturn t;\n\t});\n'],
			['closureField', 'return Std.string(twice(5));', '10', '\tpublic static var twice:Dynamic = function(n:Int):Int { return n * 2; };\n'],
			['opOverload', 'var a:Cash = 3; var b:Cash = 4; var c:Cash = a + b; return Std.string(c.amount());', '7', '}\nabstract Cash(Int) from Int to Int {\n\tpublic function amount():Int { return this; }\n\t@:op(A + B) public function add(o:Cash):Cash { return new Cash(this + o); }\n\tpublic function new(v:Int) { this = v; }\n'],
			['arrayAccess', 'var g:Grid = new Grid(); return Std.string(g[2]);', '20', '}\nabstract Grid(Array<Int>) {\n\tpublic function new() { this = [0, 10, 20]; }\n\t@:arrayAccess public function get(i:Int):Int { return this[i]; }\n'],
			['propGetSet', 'var b:Prop = new Prop(); b.v = 4; return Std.string(b.v);', '8', '}\nclass Prop {\n\tvar raw:Int = 0;\n\tpublic var v(get, set):Int;\n\tpublic function new() {}\n\tfunction get_v():Int { return raw * 2; }\n\tfunction set_v(n:Int):Int { raw = n; return n; }\n'],
			['enumPattern', 'var e:Colour = Red(3); switch (e) { case Red(n): return \'r\' + n; case Blue: return \'b\'; }', 'r3', '}\nenum Colour { Red(n:Int); Blue; }\nclass Unused2 {\n\tpublic function new() {}\n'],
			['keyValueMap', 'var m:Map<String,Int> = [\'a\' => 1, \'b\' => 2]; var t:Int = 0; for (k => v in m) t += v; return Std.string(t);', '3', ''],
		];

		// Both sides need telling: the interpreter through Config, the emitter through its lists.
		hxscript.Config.globalVariables.set('host', Sweep.shared);
		hxscript.Config.globalImports.set('Sweep', INormal);
		Compiler.ambient = ['Sweep'];
		Compiler.statics = ['host=Sweep::shared'];

		for (c in cases)
			sweep(c[0], c[1], c[2], c[3]);

		TestCase.log('  ' + refused + ' refused');
	}

	static function sweep(name:String, body:String, want:String, extra:String):Void {
		var src:String = 'package s;\nclass C {\n\tpublic static function go():Dynamic {\n'
			+ body + '\n\t}\n' + extra + '}\n';

		var interp:String = viaInterp(src);
		var compiled:String = viaCppia(src);

		var detail:String = 'interp=' + StringTools.rpad(interp, ' ', 10) + 'cppia=' + compiled;

		if (StringTools.startsWith(compiled, 'REFUSED')) {
			refused++;
			TestCase.log('  REFUSED ' + StringTools.rpad(name, ' ', 20) + detail);
		} else if (compiled == want && interp == want) {
			TestCase.ok(name + '   ' + detail, true);
		} else {
			TestCase.bad(name, detail + '   wanted ' + want);
		}
	}

	static function viaInterp(src:String):String {
		try {
			var env = new Environment();
			env.addModule(new Module(src, 'C', ['s'], 'sweep'));
			for (m in env.modules) m.init(env);
			for (m in env.modules) m.start(env);
			for (m in env.modules) m.startTypes(env);
			var cls:ScriptedClass = cast env.resolve('s.C');
			return Std.string(Reflect.callMethod(null, cls.reflectGetField('go'), []));
		} catch (e:Dynamic) {
			return 'THREW: ' + e;
		}
	}

	static function viaCppia(src:String):String {
		try {
			var decls = new Parser().parseModule(src, 'sweep', 0, ['s']);
			var r = Cppia.compile([{name: 's.C', decls: decls}], Compiler.ambient, null, Compiler.statics);
			if (r.bytes == null)
				return 'REFUSED: ' + (r.skipped.length > 0 ? r.skipped[0].reason : '?');

			var m = cpp.cppia.Module.fromData(r.bytes.getData());
			m.boot();
			return Std.string(Reflect.callMethod(null, Reflect.field(m.resolveClass('s.C'), 'go'), []));
		} catch (e:Dynamic) {
			return 'THREW: ' + e;
		}
	}

	static function main():Void {
		run();
		TestCase.exit();
	}
}
