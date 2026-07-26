import insanity.Script;
class SweepProbe {
	static var gaps = 0;
	static function p(n:String, src:String, want:String) {
		var s = new Script(src + "\nres = 'UNSET';", "s");
		s = new Script("res='<none>'; try { res = Std.string(" + src + "); } catch (e:Dynamic) { res='THREW: '+e; }", "s");
		s.onParsingError = function(e:haxe.Exception) {};
		s.onProgramError = function(e:haxe.Exception) {};
		s.start();
		var got = Std.string(s.variables.get("res"));
		if (got != want) { gaps++; trace("  GAP   " + n + " => " + got + "   (want " + want + ")"); }
		else trace("  ok    " + n + " => " + got);
	}
	static function raw(n:String, src:String, want:String) {
		var s = new Script(src, "s");
		s.onParsingError = function(e:haxe.Exception) trace("  GAP   " + n + " PARSE: " + e.message);
		s.onProgramError = function(e:haxe.Exception) trace("  GAP   " + n + " RUN: " + e.message);
		s.start();
		var got = Std.string(s.variables.get("res"));
		if (got != want) { gaps++; trace("  GAP   " + n + " => " + got + "   (want " + want + ")"); }
		else trace("  ok    " + n + " => " + got);
	}
	static function main() {
		trace("-- numeric edges --");
		p("int div neg",    "Std.int(-7 / 2)", "-3");
		p("mod neg",        "-7 % 3", "-1");
		p("bit ops",        "(6 & 3) + (6 | 3) + (6 ^ 3)", "14");
		p("shifts",         "(1 << 4) + (16 >> 2) + (-8 >>> 28)", "35");
		p("postfix vs pre", "{ var i=1; var a=i++; var b=++i; a*10+b; }", "13");
		p("compound field", "{ var o={v:1}; o.v += 5; o.v; }", "6");
		p("compound arr",   "{ var a=[1]; a[0] *= 7; a[0]; }", "7");
		p("num to string",  "1 + 2 + 'x' + 1 + 2", "3x12");
		p("float fmt",      "0.5 + 0.25", "0.75");
		trace("-- preprocessor --");
		raw("if define",    "#if insanity\nres='yes';\n#else\nres='no';\n#end", "yes");
		raw("if not def",   "#if nope\nres='yes';\n#else\nres='no';\n#end", "no");
		raw("elseif",       "#if nope\nres='a';\n#elseif insanity\nres='b';\n#else\nres='c';\n#end", "b");
		raw("nested pp",    "#if insanity\n#if nope\nres='x';\n#else\nres='y';\n#end\n#end", "y");
		trace("-- strings / lexer --");
		p("escapes",        "'a\tb\nc'.length", "5");
		p("unicode esc",    "'\u0041'", "A");
		p("nested interp",  "{ var a=[1,2]; '${a[0] + a[1]}'; }", "3");
		p("interp field",   "{ var o={n:'z'}; 'v=${o.n}'; }", "v=z");
		p("regex replace",  "~/a+/g.replace('aaXaa','-')", "-X-");
		p("dquote no interp","{ var v=1; \"$v\"; }", "$v");
		trace("-- errors --");
		p("multi-catch",    "{ try { throw 5; } catch (s:String) { 'str'; } catch (i:Int) { 'int'; } }", "int");
		p("rethrow",        "{ try { try { throw 'x'; } catch (e:Dynamic) { throw e; } } catch (e:Dynamic) { 'outer:'+e; } }", "outer:x");
		p("null safe",      "{ var o = null; o?.field; }", "null");
		p("catch order",    "{ try { throw 'a'; } catch (e:Int) { 'i'; } catch (e:String) { 's'; } }", "s");
		trace("-- imports / using --");
		raw("import alias", "import Math as M;\nres = M.max(1,2);", "2");
		raw("import field", "import Math.abs;\nres = abs(-3);", "3");
		raw("using ext",    "using StringTools;\nres = 'ab'.startsWith('a');", "true");
		trace("== " + gaps + " gaps ==");
	}
}
