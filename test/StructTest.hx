import insanity.Script;
import insanity.Config;
class StructTest {
	static function probe(name:String, body:String) {
		var s = new Script("res = 'ran'; try { " + body + " } catch (e:Dynamic) { res = 'threw'; }", "p");
		s.start();
		trace(name + " => " + s.variables.get("res"));
	}
	static function main() {
		Config.typedMode = true;
		var pre = "typedef Point = {x:Int, y:Int};\n";
		probe("named typedef, good obj",   pre + "var p:Point = {x:1, y:2};");        // ran
		probe("named typedef, missing y",  pre + "var p:Point = {x:1};");             // threw
		probe("named typedef, wrong val",  pre + "var p:Point = 5;");                 // threw
		probe("is Point true",             pre + "if (!({x:1,y:2} is Point)) throw 'no';"); // ran
		probe("is Point false",            pre + "if ({x:1} is Point) throw 'yes';"); // ran (correctly not a Point)
		probe("inline anon good",          "var p:{a:Int} = {a:1};");                 // ran
		probe("inline anon missing",       "var p:{a:Int} = {b:1};");                 // threw
		probe("cast to Point ok",          pre + "cast({x:1,y:2}, Point);");          // ran
		probe("cast to Point bad",         pre + "cast({x:1}, Point);");              // threw
	}
}
