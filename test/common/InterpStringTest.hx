import hxscript.Script;
import TestCase.eq;

/**
 * Single-quoted strings, and the dollar sign in particular.
 *
 * A `$` inside a single-quoted string starts an interpolation only when an identifier or a `{`
 * follows it. Anything else makes it a literal dollar, and the character after it has not been
 * consumed by anything yet.
 *
 * The lexer used to append that following character to the buffer instead of putting it back. For
 * `'$'` the following character is the closing quote, so the string swallowed its own terminator
 * and ran on until it found the next quote somewhere else in the file. The failure was therefore
 * reported nowhere near the string that caused it, which made it look like a fault in whatever
 * unrelated line happened to hold the quote it eventually stopped at.
 */
class InterpStringTest {
	static function ev(body:String):Dynamic {
		var s = new Script("result = (" + body + ");", "b");
		s.onProgramError = function(e:haxe.Exception) trace("ERR " + e.message);
		s.start();
		return s.variables.get("result");
	}

	public static function run():Void {
		eq("lone dollar", ev("'$'"), "$");
		eq("dollar at the end", ev("'ab$'"), "ab$");
		eq("dollar in the middle", ev("'a$-b'"), "a$-b");
		eq("dollar before a space", ev("'a$ b'"), "a$ b");
		eq("escaped dollar", ev("'a$$b'"), "a$b");
		eq("dollar before a digit", ev("'$5'"), "$5");
		eq("two lone dollars", ev("'$' + '$'"), "$$");

		eq("a string after a lone dollar still lexes", ev("'$' + 'tail'"), "$tail");
		eq("and the one after that does too", ev("'$' + ';' + '$'"), "$;$");

		eq("interpolation still works", ev("{ var x = 7; 'v$x'; }"), "v7");
		eq("braced interpolation still works", ev("{ var x = 7; 'v${x + 1}'; }"), "v8");
		eq("interpolation after a lone dollar", ev("{ var x = 2; '$' + 'n$x'; }"), "$n2");

		eq("double quotes take no interpolation", ev("\"$\""), "$");
		eq("nor a name after one", ev("\"$x\""), "$x");

		eq("empty single-quoted string", ev("''"), "");
		eq("a dollar alone is not empty", ev("'$'.length"), 1);
	}

	static function main():Void {
		run();
		TestCase.exit();
	}
}
