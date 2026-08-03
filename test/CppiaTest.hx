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
		#if cppia_jit
		cpp.cppia.Host.enableJit(true);
		#end

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
		check('switch on a local as case', 'var k = 2; var a = 2; switch (a) { case k: return "hit"; default: return "miss"; }', 'hit');
		check('switch multi value', 'var a = 3; switch (a) { case 1, 2: return "low"; case 3, 4: return "high"; default: return "?"; }', 'high');
		check('switch on string', 'var s = "b"; switch (s) { case "a": return "A"; case "b": return "B"; default: return "?"; }', 'B');

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
