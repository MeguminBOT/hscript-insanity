import haxe.io.Bytes;
import hxscript.Environment;
import hxscript.Module;
import hxscript.compile.Cppia;
import hxscript.compile.CppiaInput;
import hxscript.compile.CppiaResult;
import hxscript.types.ScriptedClass;

/**
 * Differential test for the cppia backend: each case runs from the same source through both the
 * interpreter and the compiler, and the two answers must agree.
 *
 * The host must be built with `-D scriptable`.
 */
class CppiaTest {
	static var failures:Int = 0;
	static var refused:Int = 0;

	public static function main():Void {
		// Always on, because it is a different code path: an expression the JIT has no generator for
		// emits nothing at all rather than falling back, so a construct can pass every test here and
		// still do nothing in a host that turned the JIT on.
		cpp.cppia.Host.enableJit(true);

		check('int literal', 'return 7;', '7');
		check('arithmetic', 'return 6 * 7 - 2;', '40');
		check('local var', 'var a = 3; var b = 4; return a * b;', '12');
		check('if else', 'var a = 5; if (a > 3) return "big"; else return "small";', 'big');
		check('while loop', 'var i = 0; var n = 0; while (i < 10) { n += i; i++; } return n;', '45');
		check('for loop', 'var n = 0; for (i in 0...10) n += i; return n;', '45');
		check('array', 'var a = [1, 2, 3]; return a[0] + a[2];', '4');
		check('array push', 'var a = []; a.push(5); a.push(6); return a[1];', '6');
		check('string ops', 'var s = "hello"; return s.length;', '5');
		check('nested calls', 'return Std.string(Math.floor(3.7));', '3');
		check('ternary', 'var a = 4; return a > 2 ? "y" : "n";', 'y');
		check('switch', 'var a = 2; switch (a) { case 1: return "one"; case 2: return "two"; default: return "other"; }', 'two');
		check('do while', 'var i = 0; do { i++; } while (i < 5); return i;', '5');
		check('try catch', 'try { throw "boom"; } catch (e:Dynamic) { return "caught"; } return "no";', 'caught');
		check('object literal', 'var o = {a: 1, b: 2}; return o.a + o.b;', '3');
		check('recursion via static', 'return fact(5);', '120', '
			static function fact(n:Int):Int {
				if (n <= 1) return 1;
				return n * fact(n - 1);
			}
		');
		check('static field', 'count = 9; return count;', '9', 'static var count:Int = 0;');
		check('bitwise', 'return (12 & 10) | (1 << 3);', '8');
		check('modulo and division', 'return Std.string(17 % 5) + Std.string(Std.int(17 / 5));', '23');
		check('string compare', 'return "abc" == "abc" ? "eq" : "ne";', 'eq');

		check('function value', 'var f = function(a:Int) { return a * 2; }; return f(21);', '42');
		check('closure captures local', 'var n = 10; var f = function(a:Int) { return a + n; }; return f(5);', '15');
		check('closure sees later writes', 'var n = 1; var f = function() { return n; }; n = 99; return f();', '99');
		check('closure writes outward', 'var n = 0; var f = function() { n = 7; }; f(); return n;', '7');
		check('named local recursion', 'function fib(n:Int):Int { if (n < 2) return n; return fib(n - 1) + fib(n - 2); } return fib(10);', '55');
		check('closure over arg', 'return make(4)();', '16', '
			static function make(k:Int):Dynamic {
				return function() { return k * k; };
			}
		');
		check('nested closures', 'var a = 1; var f = function() { var b = 2; var g = function() { return a + b; }; return g(); }; return f();', '3');
		check('closure in loop', 'var fs = []; for (i in 0...3) { fs.push(function() { return i; }); } return fs[0]() + fs[1]() + fs[2]();', '3');
		check('array map with closure', 'var a = [1, 2, 3]; var t = 0; for (v in a) t += v * 2; return t;', '12');

		var colour:String = 'enum Colour { Red; Green; Rgb(r:Int, g:Int, b:Int); }';
		check('enum no-arg constructor', 'var c = Colour.Red; return Type.enumConstructor(c);', 'Red', '', colour);
		check('enum equality', 'var c = Colour.Green; return c == Colour.Green ? "eq" : "ne";', 'eq', '', colour);
		check('enum inequality', 'return Colour.Red == Colour.Green ? "eq" : "ne";', 'ne', '', colour);
		check('enum index', 'return Std.string(Type.enumIndex(Colour.Green));', '1', '', colour);
		check('enum with args', 'var c = Colour.Rgb(1, 2, 3); return Type.enumConstructor(c);', 'Rgb', '', colour);
		check('enum parameters', 'var c = Colour.Rgb(1, 2, 3); return Std.string(Type.enumParameters(c)[1]);', '2', '', colour);
		check('enum in array', 'var a = [Colour.Red, Colour.Green]; return Type.enumConstructor(a[1]);', 'Green', '', colour);
		check('enum returned from method', 'return Type.enumConstructor(pick(true));', 'Red', '
			static function pick(b:Bool):Colour {
				return b ? Colour.Red : Colour.Green;
			}
		', colour);
		check('enum switch', 'var c = Colour.Green; switch (c) { case Colour.Red: return "r"; case Colour.Green: return "g"; default: return "?"; }', 'g', '',
			colour);
		check('enum switch falls to default', 'var c = Colour.Rgb(1, 2, 3); switch (c) { case Colour.Red: return "r"; default: return "d"; }', 'd', '', colour);
		check('enum destructure binds parameters',
			'var c = Colour.Rgb(1, 2, 3); switch (c) { case Rgb(r, g, b): return Std.string(r + g + b); default: return "no"; }', '6', '', colour);
		check('enum destructure picks the right constructor',
			'var c = Colour.Green; switch (c) { case Rgb(r, g, b): return "rgb"; case Colour.Green: return "green"; default: return "?"; }', 'green', '',
			colour);
		check('enum destructure skips wildcards',
			'var c = Colour.Rgb(4, 5, 6); switch (c) { case Rgb(_, g, _): return Std.string(g); default: return "no"; }', '5', '', colour);
		check('enum destructure with guard',
			'var c = Colour.Rgb(1, 2, 3); switch (c) { case Rgb(r, g, b) if (r > 9): return "big"; case Rgb(r, g, b): return "small"; default: return "?"; }',
			'small', '', colour);
		check('bare ident case captures, not compares', 'var k = 99; var a = 2; switch (a) { case k: return "captured"; default: return "compared"; }',
			'captured');
		check('bare ident case rebinds the name', 'var k = 99; var a = 2; switch (a) { case k: return Std.string(k); default: return "no"; }', '2');
		check('capture with guard that fails', 'var a = 2; switch (a) { case v if (v > 5): return "big"; default: return "small"; }', 'small');
		check('capture after a literal case', 'var a = 7; switch (a) { case 1: return "one"; case v: return Std.string(v * 2); }', '14');
		check('switch multi value', 'var a = 3; switch (a) { case 1, 2: return "low"; case 3, 4: return "high"; default: return "?"; }', 'high');
		check('switch on string', 'var s = "b"; switch (s) { case "a": return "A"; case "b": return "B"; default: return "?"; }', 'B');

		check('interval as a value', 'var it = 0...3; var t = 0; while (it.hasNext()) t += it.next(); return t;', '3');
		check('interval bound to a local then looped', 'var it = 1...4; var t = 0; for (v in it) t += v; return t;', '6');

		check('module-level function', 'return helper(6);', '12', '', 'function helper(n:Int):Int return n * 2;');
		check('module-level var', 'return offset;', '9', '', 'var offset:Int = 9;');
		check('module-level var is writable', 'offset = 4; return offset;', '4', '', 'var offset:Int = 0;');
		check('module-level function calls another', 'return outer(3);', '9', '', '
			function inner(n:Int):Int return n * 3;
			function outer(n:Int):Int return inner(n);
		');

		check('member field initialiser', 'var t = new T(); return t.raw;', '7', '
			public var raw:Int = 7;
			public function new() {}
		');
		check('static field initialiser', 'return T.base;', '5', 'public static var base:Int = 5;');
		check('constructor assigns field', 'var t = new T(); return t.raw;', '3', '
			public var raw:Int = 0;
			public function new() { raw = 3; }
		');

		check('property getter', 'var t = new T(); return t.doubled;', '14', '
			public var raw:Int = 7;
			public var doubled(get, never):Int;
			function get_doubled():Int return raw * 2;
			public function new() {}
		');
		check('property setter', 'var t = new T(); t.half = 10; return t.raw;', '5', '
			public var raw:Int = 0;
			public var half(never, set):Int;
			function set_half(v:Int):Int { raw = Std.int(v / 2); return v; }
			public function new() {}
		');
		check('property get and set', 'var t = new T(); t.value = 4; return t.value;', '8', '
			public var store:Int = 0;
			public var value(get, set):Int;
			function get_value():Int return store;
			function set_value(v:Int):Int { store = v * 2; return v; }
			public function new() {}
		');
		// A plain field is reached by offset while a property on the SAME class must still go through
		// its accessor. Getting that wrong reads the storage behind the property and silently skips
		// the doubling, so the two are exercised together and the answer separates them.
		check('plain field and property together', 'var t = new T(); t.raw = 3; t.value = 4; return t.raw + t.value;', '11', '
			public var raw:Int = 0;
			public var store:Int = 0;
			public var value(get, set):Int;
			function get_value():Int return store;
			function set_value(v:Int):Int { store = v * 2; return v; }
			public function new() {}
		');
		check('field through a typed local', 'var t:T = new T(); t.raw = 6; var u:T = t; return u.raw;', '6', '
			public var raw:Int = 0;
			public function new() {}
		');

		// An array literal has nothing in it to say what it holds, so it used to be built loose while an
		// annotation promised a specific kind. Reading it back through that annotation reinterprets the
		// memory, which crashes rather than misbehaves, so these index one after the round trip.
		check('typed array local, literal init', 'var d:Array<Float> = [1.5, 2.5]; return d[1];', '2.5');
		check('typed int array local', 'var d:Array<Int> = [4, 5, 6]; return d[2];', '6');
		check('typed array field, indexed back', 'var t = new T(); t.data = [7.5]; return t.data[0];', '7.5', '
			public var data:Array<Float>;
			public function new() {}
		');
		check('typed array field, initialised in place', 'var t = new T(); return t.data[1];', '9', '
			public var data:Array<Int> = [8, 9];
			public function new() {}
		');

		check('static property', 'return T.only;', '42', '
			public static var only(get, never):Int;
			static function get_only():Int return 42;
		');
		check('static property setter', 'T.scaled = 5; return T.store;', '15', '
			public static var store:Int = 0;
			public static var scaled(never, set):Int;
			static function set_scaled(v:Int):Int { store = v * 3; return v; }
		');
		check('static property unqualified', 'return readIt();', '42', '
			public static var only(get, never):Int;
			static function get_only():Int return 42;
			static function readIt():Int return only;
		');

		check('regex match', 'var r = ~/[0-9]+/; return r.match("abc123") ? "yes" : "no";', 'yes');
		check('regex no match', 'var r = ~/^[0-9]+$/; return r.match("abc") ? "yes" : "no";', 'no');
		check('regex matched group', 'var r = ~/([a-z]+)([0-9]+)/; r.match("abc123"); return r.matched(2);', '123');
		check('regex with flags', 'var r = ~/ABC/i; return r.match("xxabcxx") ? "yes" : "no";', 'yes');
		check('regex replace', 'var r = ~/[0-9]/g; return r.replace("a1b2", "#");', 'a#b#');

		check('case guard taken', 'var a = 5; switch (a) { case v if (v > 3): return "big"; default: return "small"; }', 'big');
		check('case guard falls through to later case',
			'var a = 2; switch (a) { case 2 if (false): return "no"; case 2: return "yes"; default: return "?"; }', 'yes');
		check('case guard falls to default', 'var a = 1; switch (a) { case 1 if (false): return "no"; default: return "d"; }', 'd');
		check('case guard with multi value', 'var a = 3; switch (a) { case 1, 3 if (a > 2): return "hit"; default: return "miss"; }', 'hit');
		check('typed catch selects clause', 'try { throw "boom"; } catch (e:Int) { return "int"; } catch (e:String) { return "str"; }', 'str');
		check('typed catch first match wins', 'try { throw 7; } catch (e:Int) { return "int"; } catch (e:String) { return "str"; }', 'int');
		check('typed catch falls to dynamic', 'try { throw 1.5; } catch (e:Int) { return "int"; } catch (e:Dynamic) { return "dyn"; }', 'dyn');
		check('catch binds the value', 'try { throw "x"; } catch (e:String) { return e + "!"; }', 'x!');

		check('null-safe field, present', 'var o = {a: 5}; return o?.a;', '5');
		check('null-safe field, null', 'var o:Dynamic = null; return o?.a;', 'null');
		check('null-safe call, present', 'var s = "hi"; return s?.toUpperCase();', 'HI');
		check('null-safe call, null', 'var s:Dynamic = null; return s?.toUpperCase();', 'null');
		check('null-safe evaluates subject once', 'var n = 0; var a = [{v: 1}]; return bump(a)?.v;', '1', '
			static var calls:Int = 0;
			static function bump(a:Array<Dynamic>):Dynamic {
				calls++;
				return a[0];
			}
		');

		check('map literal, string keys', "var m = ['a' => 1, 'b' => 2]; return m.get('a') + m.get('b');", '3');
		check('map literal, int keys', 'var m = [1 => "x", 2 => "y"]; return m.get(2);', 'y');
		check('map literal, exists', "var m = ['a' => 1]; return m.exists('a') && !m.exists('b') ? 'ok' : 'no';", 'ok');
		check('map literal, empty then set', "var m = ['a' => 1]; m.set('c', 9); return Std.string(m.get('c'));", '9');
		check('key-value for over map', "var m = ['a' => 1, 'b' => 2]; var t = 0; for (k => v in m) t += v; return t;", '3');
		check('key-value for keys', "var m = ['a' => 1]; var s = ''; for (k => v in m) s += k; return s;", 'a');
		check('key-value for over array', 'var a = [10, 20, 30]; var t = 0; for (i => v in a) t += i * v; return t;', '80');

		// hxcpp cannot tell a whole Float from an Int inside a Dynamic, so a running total declared
		// Float used to be added as an Int and wrapped at two billion. These accumulate past that.
		check('float total past the int limit', 'var t:Float = 0; var i:Int = 0; while (i < 100) { t = t + 100000000; i++; } return t;', '10000000000');
		check('float total, compound assign', 'var t:Float = 0; var i:Int = 0; while (i < 100) { t += 100000000; i++; } return t;', '10000000000');
		check('float total, subtracting', 'var t:Float = 0; var i:Int = 0; while (i < 100) { t -= 100000000; i++; } return t;', '-10000000000');
		check('int multiply still wraps', 'var s:Int = 123456789; s = s * 1103515245; return s & 1073741823;', '231782385');

		check('string interpolation, ident', "var n = 5; return 'n is $n';", 'n is 5');
		check('string interpolation, expr', "var a = 2; var b = 3; return 'sum ${a + b}';", 'sum 5');
		check('string interpolation, escaped', "var n = 1; return 'cost $$5 for $n';", "cost $5 for 1");
		check('double quotes do not interpolate', "var n = 5; return \"n is $n\";", "n is $n");

		Sys.println('');
		Sys.println('----------------------------------------');
		Sys.println('refused by the emitter: ' + refused);
		Sys.println(failures == 0 ? 'interpreter and cppia agreed everywhere' : failures + ' disagreements');
		Sys.exit(failures == 0 ? 0 : 1);
	}

	/**
	 * Runs one body both ways and compares. A refusal is reported but does not count as a failure.
	 *
	 * @param label How to name the case in the report.
	 * @param body The method body to run.
	 * @param want The expected result.
	 * @param extra Extra class members.
	 * @param before Declarations preceding the class.
	 */
	static function check(label:String, body:String, want:String, extra:String = '', before:String = ''):Void {
		var source:String = 'package p;\n' + before + '\n' + 'class T {\n' + extra + '\n' + '\tpublic static function run():Dynamic {\n' + '\t\t' + body
			+ '\n' + '\t}\n' + '}\n';

		var interpreted:String = runInterpreted(source);
		if (interpreted != want) {
			failures++;
			Sys.println('  FAIL ' + label + '   interpreter itself gave ' + interpreted + ', wanted ' + want);
			return;
		}

		var decls = parse(source);
		if (decls == null) {
			failures++;
			Sys.println('  FAIL ' + label + '   could not parse');
			return;
		}

		var result:CppiaResult = Cppia.compile([{name: 'p.T', decls: decls}]);

		if (result.bytes == null) {
			refused++;
			var why:String = result.skipped.length > 0 ? result.skipped[0].reason : 'no reason given';
			Sys.println('  --   ' + label + '   refused: ' + why);
			return;
		}

		var got:String = runCompiled(result.bytes, label);
		if (got == want) {
			Sys.println('  ok   ' + label);
		} else {
			failures++;
			Sys.println('  FAIL ' + label + '   cppia gave ' + got + ', interpreter gave ' + interpreted);
		}
	}

	static function parse(source:String):Array<hxscript.syntax.Expr.ModuleDecl> {
		try {
			var parser = new hxscript.syntax.Parser();
			return parser.parseModule(source, 'test', 0, ['p']);
		} catch (e:Dynamic) {
			Sys.println('parse error: ' + e);
			return null;
		}
	}

	static function runInterpreted(source:String):String {
		try {
			var env:Environment = new Environment();
			var module:Module = new Module('', 'T', ['p'], 'test');
			var problem:String = null;
			module.onParsingError = function(e:haxe.Exception):Void {
				if (problem == null)
					problem = 'parse: ' + e.message;
			};
			module.onProgramError = function(e:haxe.Exception):Void {
				if (problem == null)
					problem = 'program: ' + e.message;
			};
			module.parse(source);
			env.addModule(module);
			module.init(env);
			module.start(env);
			module.startTypes(env);

			if (problem != null)
				return problem;

			var cls:ScriptedClass = cast env.resolve('p.T');
			return Std.string(Reflect.callMethod(null, cls.reflectGetField('run'), []));
		} catch (e:Dynamic) {
			return 'threw: ' + e;
		}
	}

	static function runCompiled(bytes:Bytes, label:String):String {
		try {
			var module = cpp.cppia.Module.fromData(bytes.getData());
			module.boot();
			var cls:Class<Dynamic> = module.resolveClass('p.T');
			if (cls == null)
				return 'class did not resolve';
			return Std.string(Reflect.callMethod(cls, Reflect.field(cls, 'run'), []));
		} catch (e:Dynamic) {
			return 'load threw: ' + e;
		}
	}
}
