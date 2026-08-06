import hxscript.Script;
import TestCase.eq;

/**
 * Bitwise operators, and unary complement in particular.
 *
 * `~` was accepted by the parser's unary-operator table, by the interpreter and by the cppia
 * emitter, but the lexer only ever reached it through the regex path and rejected anything else.
 * The error it produced named the character *after* the operator, so the reported position was one
 * past the real fault and pointed at an identifier that was perfectly valid.
 */
class BitwiseTest {
	static function ev(b:String):Dynamic {
		var s = new Script("result = (" + b + ");", "b");
		s.onProgramError = function(e:haxe.Exception) trace("ERR " + e.message);
		s.start();
		return s.variables.get("result");
	}

	public static function run():Void {
		eq("complement zero", ev("~0"), ~0);
		eq("complement one", ev("~1"), ~1);
		eq("complement negative", ev("~-1"), ~-1);
		eq("complement parenthesised", ev("~(1 | 2)"), ~(1 | 2));
		eq("complement of var", ev("{ var x = 5; ~x; }"), ~5);
		eq("complement twice", ev("~~7"), 7);

		eq("mask out a bit", ev("0xFF & ~0x20"), 0xFF & ~0x20);
		eq("mask out two bits", ev("0xFF & ~(1 | 2)"), 0xFF & ~(1 | 2));
		eq("complement then shift", ev("(~0xF0) & 0xFF"), (~0xF0) & 0xFF);

		eq("and", ev("0xF0 & 0x3C"), 0xF0 & 0x3C);
		eq("or", ev("0xF0 | 0x0F"), 0xF0 | 0x0F);
		eq("xor", ev("0xFF ^ 0x0F"), 0xFF ^ 0x0F);
		eq("shl", ev("1 << 8"), 1 << 8);
		eq("shr", ev("0x100 >> 4"), 0x100 >> 4);
		eq("ushr", ev("-1 >>> 28"), -1 >>> 28);

		eq("regex still lexes", ev("{ var r = ~/ab+c/; r != null; }"), true);
		eq("regex after complement", ev("{ var m = ~0xF; var r = ~/x/; r != null && m == ~0xF; }"), true);

		eq("complement in condition", ev("{ var f = 0x20; (f & ~0x20) == 0; }"), true);
		eq("complement compound", ev("{ var s = 0xFF; s &= ~0x20; s; }"), 0xFF & ~0x20);
	}

	static function main():Void {
		run();
		TestCase.exit();
	}
}
