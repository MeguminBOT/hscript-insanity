import hxscript.syntax.Expr;
import hxscript.syntax.Parser;
import hxscript.syntax.Printer;
import TestCase.ok;

/**
 * That `Printer` prints module declarations, and prints them faithfully enough to reparse.
 *
 * The bar is ROUND-TRIP rather than "produces plausible text": print a parsed module, reparse the
 * output, print again, and require the two to be identical. Anything the printer drops or reorders
 * shows up as a difference on the second pass instead of as quietly missing source.
 */
class PrinterTest {
	/**
	 * Parses a module and prints every declaration back to source.
	 *
	 * @param src The module source.
	 * @param pack The package the source declares, which the parser checks against.
	 * @return The printed source.
	 */
	static function printModule(src:String, ?pack:Array<String>):String {
		var parser = new Parser();
		parser.allowTypes = parser.allowJSON = parser.allowMetadata = true;

		var printer = new Printer();
		var out = new StringBuf();
		for (d in parser.parseModule(src, 'PrinterTest.hxs', 0, pack ?? [])) {
			out.add(printer.exprToString({e: EDecl(d), pos: d.pos}));
			out.add('\n');
		}
		return out.toString();
	}

	/**
	 * Asserts that printing is stable across a reparse.
	 *
	 * @param name What is being checked.
	 * @param src The module source.
	 * @param pack The declared package, if any.
	 */
	static function roundTrips(name:String, src:String, ?pack:Array<String>):Void {
		var once:String = printModule(src, pack);
		var twice:String = printModule(once, pack);
		ok(name, once == twice && once.length > 0);
		if (once != twice)
			trace('    pass1:\n' + once + '\n    pass2:\n' + twice);
	}

	public static function run():Void {
		trace('-- declarations round-trip --');
		roundTrips('package and imports', "
package pkg.sub;
import haxe.io.Bytes;
import haxe.ds.Vector as Vec;
import sys.io.*;
using StringTools;
", ['pkg', 'sub']);

		roundTrips('typedef', '@:keep private typedef Point = {x:Int, y:Int};\n');

		roundTrips('enum with parameterised constructors', "
enum Shape {
    Circle(r:Float);
    Square(w:Float, h:Float);
    Dot;
}
");

		roundTrips('abstract with underlying, from and to', "
@:forward abstract Meters(Float) from Float to Float {
    public function new(v:Float) this = v;
    public function describe():String return this + 'm';
}
");

		roundTrips('interface', "
interface Named {
    public function label():String;
}
");

		roundTrips('class with statics, properties and override', "
@:keep class Thing extends Base implements Named {
    public static var count:Int = 0;
    public var name(default, set):String = 'x';
    final id:Int = 1;
    public function new() {}
    override public function toString():String return 'Thing';
}
");

		roundTrips('module-level fields', "
var moduleVar:Int = 7;
function moduleFn(a:Int, ?b:String = 'z', ...rest:Int):Void trace(a);
");

		trace('-- the output is source, not a placeholder --');
		var printed:String = printModule('class Thing { public var n:Int = 1; }\n');
		ok('names the declaration', printed.indexOf('class Thing') >= 0);
		ok('keeps the field', printed.indexOf('n : Int = 1') >= 0);
		ok('no leftover stub', printed.indexOf('decl') < 0);

	}

	static function main():Void {
		run();
		TestCase.exit();
	}
}
