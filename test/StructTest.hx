import insanity.Script;
import insanity.Config;

/**
 * Structural typedefs and inline anonymous-structure annotations: field presence, field types,
 * optional fields, and that `is` / `cast` agree with what an annotation accepts.
 */
class StructTest {
	static var pass:Int = 0;
	static var fail:Int = 0;

	/**
	 * Records one assertion.
	 *
	 * @param name What is being checked.
	 * @param cond Whether it held.
	 */
	static function ok(name:String, cond:Bool):Void {
		if (cond) {
			pass++;
			trace("  ok   " + name);
		} else {
			fail++;
			trace("  FAIL " + name);
		}
	}

	/**
	 * Runs a script and reports whether it completed or raised.
	 *
	 * @param body The script source.
	 * @return True if the script ran to completion.
	 */
	static function ran(body:String):Bool {
		var s = new Script("res = 'ran'; try { " + body + " } catch (e:Dynamic) { res = 'threw'; }", "p");
		s.onProgramError = function(e:haxe.Exception) {};
		s.start();
		return s.variables.get("res") == "ran";
	}

	/**
	 * Runs a script and reports the value of a boolean expression evaluated after it. The declarations
	 * have to precede the assignment, so they are passed separately rather than prefixed to `test`.
	 *
	 * @param pre Declarations to run first.
	 * @param test The expression to evaluate.
	 * @return True if the expression evaluated to true.
	 */
	static function yes(pre:String, test:String):Bool {
		var s = new Script(pre + "res = false; try { res = (" + test + "); } catch (e:Dynamic) { res = false; }", "p");
		s.onProgramError = function(e:haxe.Exception) {};
		s.start();
		return s.variables.get("res") == true;
	}

	static function main():Void {
		Config.typedMode = true;

		var point = "typedef Point = {x:Int, y:Int};\n";
		var opt = "typedef Opt = {x:Int, ?y:Int};\n";
		var meta = "typedef MetaOpt = {x:Int, @:optional y:Int};\n";
		var nest = "typedef Nested = {p:{x:Int}};\n";
		var nullable = "typedef Nullable = {x:Null<Int>};\n";

		trace("-- field presence --");
		ok("good object", ran(point + "var p:Point = {x:1, y:2};"));
		ok("missing field throws", !ran(point + "var p:Point = {x:1};"));
		ok("non-object throws", !ran(point + "var p:Point = 5;"));
		// Haxe rejects a *literal* carrying fields the expected type does not declare. This is a
		// runtime check on a value, so extra fields simply do not stop it satisfying the structure.
		ok("extra fields allowed", ran(point + "var p:Point = {x:1, y:2, z:3};"));

		trace("-- field types --");
		ok("wrong field type throws", !ran(point + "var p:Point = {x:1, y:'hi'};"));
		ok("Int field takes Int", ran(point + "var p:Point = {x:1, y:2};"));
		ok("Int field rejects Float", !ran(point + "var p:Point = {x:1, y:2.5};"));
		ok("inline anon checks type", !ran("var p:{a:Int} = {a:'hi'};"));
		ok("inline anon good", ran("var p:{a:Int} = {a:1};"));
		ok("nested structure checked", !ran(nest + "var n:Nested = {p:{x:'hi'}};"));
		ok("nested structure good", ran(nest + "var n:Nested = {p:{x:1}};"));

		trace("-- optional fields --");
		ok("?field may be absent", ran(opt + "var p:Opt = {x:1};"));
		ok("?field may be present", ran(opt + "var p:Opt = {x:1, y:2};"));
		ok("?field still type-checked", !ran(opt + "var p:Opt = {x:1, y:'hi'};"));
		ok("@:optional may be absent", ran(meta + "var p:MetaOpt = {x:1};"));
		ok("@:optional still type-checked", !ran(meta + "var p:MetaOpt = {x:1, y:'hi'};"));
		ok("required field still required", !ran(opt + "var p:Opt = {y:2};"));
		ok("Null<Int> field takes null", ran(nullable + "var p:Nullable = {x:null};"));
		ok("Null<Int> field rejects String", !ran(nullable + "var p:Nullable = {x:'hi'};"));

		trace("-- is / cast agree --");
		ok("is true for match", yes(point, "{x:1, y:2} is Point"));
		ok("is false for missing", !yes(point, "{x:1} is Point"));
		ok("is false for wrong type", !yes(point, "{x:1, y:'hi'} is Point"));
		ok("is true with ?field absent", yes(opt, "{x:1} is Opt"));
		ok("cast accepts match", ran(point + "cast({x:1, y:2}, Point);"));
		ok("cast rejects missing", !ran(point + "cast({x:1}, Point);"));
		ok("cast rejects wrong type", !ran(point + "cast({x:1, y:'hi'}, Point);"));

		trace("-- dynamic mode --");
		Config.typedMode = false;
		ok("dynamic mode ignores types", ran(point + "var p:Point = {x:1, y:'hi'};"));
		ok("dynamic mode ignores presence", ran(point + "var p:Point = {x:1};"));
		Config.typedMode = true;

		trace("== " + pass + " passed, " + fail + " failed ==");
	}
}
