/*
 * Copyright (C)2008-2017 Haxe Foundation
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

package insanity.backend;

import insanity.backend.Expr;
import insanity.backend.Exception;

using insanity.tools.Tools;

enum Token {
	TEof;
	TConst(c:Const);
	TId(s:String);
	TOp(s:String);
	TPOpen;
	TPClose;
	TBrOpen;
	TBrClose;
	TDot;
	TQuestionDot;
	TComma;
	TSemicolon;
	TBkOpen;
	TBkClose;
	TQuestion;
	TDoubleDot;
	TMeta(s:String);
	TPrepro(s:String);
}

class Parser {
	// config / variables
	public var line:Int;
	public var opChars:String;
	public var identChars:String;
	public var opPriority:Map<String, Int>;
	public var opRightAssoc:Map<String, Bool>;
	public var columnOffset:Int;

	/**
		allows to check for #if / #else in code
	**/
	public var preprocessorValues:Map<String, Dynamic> = new Map();

	/**
		activate JSON compatiblity
	**/
	public var allowJSON:Bool;

	/**
		allow types declarations
	**/
	public var allowTypes:Bool;

	/**
		allow haxe metadata declarations
	**/
	public var allowMetadata:Bool;

	/**
		resume from parsing errors (when parsing incomplete code, during completion for example)
	**/
	public var resumeErrors:Bool;

	// implementation
	var decl:Bool;
	var pack:Array<String>;
	var origin:String;
	var input:String;
	var readPos:Int;
	var offset:Int;
	var currentPos(get, never):Int;

	var char:Int;
	var ops:Array<Bool>;
	var idents:Array<Bool>;
	var fid:Int = 0;
	var uid:Int = 0;

	var tokenMin:Int;
	var tokenMax:Int;
	var oldTokenMin:Int;
	var oldTokenMax:Int;
	var tokens:List<{min:Int, max:Int, t:Token}>;

	public function new() {
		line = 1;
		opChars = "+*/-=!><&|^%~";
		identChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_";
		var priorities = [
			["%"],
			["*", "/"],
			["+", "-"],
			["<<", ">>", ">>>"],
			["|", "&", "^"],
			["??"],
			["==", "!=", ">", "<", ">=", "<="],
			["..."],
			["&&"],
			["||"],
			[
				"=", "+=", "-=", "*=", "/=", "%=", "<<=", ">>=", ">>>=", "|=", "&=", "^=", "=>", "??="
			],
			["->"],
			["in", "is"]
		];

		opPriority = new Map();
		opRightAssoc = new Map();
		for (i in 0...priorities.length) {
			for (x in priorities[i]) {
				opPriority.set(x, i);
				if (i == 10)
					opRightAssoc.set(x, true);
			}
		}

		for (x in ["!", "++", "--", "~"]) // unary "-" handled in parser directly!
			opPriority.set(x, x == "++" || x == "--" ? -1 : -2);

		preprocessorBinops = [
			'&&' => function(a:Dynamic, b:Dynamic) return (a && b),
			'||' => function(a:Dynamic, b:Dynamic) return (a || b),
			'==' => function(a:Dynamic, b:Dynamic) return (a == b),
			'!=' => function(a:Dynamic, b:Dynamic) return (a != b),
			'>=' => function(a:Dynamic, b:Dynamic) return (a >= b),
			'<=' => function(a:Dynamic, b:Dynamic) return (a <= b),
			'>' => function(a:Dynamic, b:Dynamic) return (a > b),
			'<' => function(a:Dynamic, b:Dynamic) return (a < b)
		];
	}

	inline function get_currentPos()
		return readPos + offset;

	public inline function error(err, pmin, pmax) {
		if (!resumeErrors)
			throw new ParserException(err, pmin, pmax, origin, line);
	}

	public function invalidChar(c) {
		error(EInvalidChar(c), readPos - 1, readPos - 1);
	}

	function initParser(origin, pos) {
		columnOffset = 0;
		line = 1;
		decl = false;
		preprocStack = [];
		this.origin = origin;
		readPos = 0;
		tokenMin = oldTokenMin = pos;
		tokenMax = oldTokenMax = pos;
		tokens = new List();
		offset = pos;
		char = -1;
		ops = new Array();
		idents = new Array();
		fid = uid = 0;
		for (i in 0...opChars.length)
			ops[opChars.charCodeAt(i)] = true;
		for (i in 0...identChars.length)
			idents[identChars.charCodeAt(i)] = true;
	}

	public function parseScript(s:String, ?origin:String = "hscript", ?position:Int = 0) {
		initParser(origin, position);
		input = s;
		readPos = 0;
		var a = new Array();
		while (true) {
			var tk = token();
			if (tk == TEof)
				break;
			push(tk);
			parseFullExpr(a);
		}
		return if (a.length == 1) a[0] else mk(EBlock(a), 0);
	}

	function unexpected(tk):Dynamic {
		error(EUnexpected(tokenString(tk)), tokenMin, tokenMax);
		return null;
	}

	inline function push(tk) {
		tokens.push({t: tk, min: tokenMin, max: tokenMax});
		tokenMin = oldTokenMin;
		tokenMax = oldTokenMax;
	}

	inline function ensure(tk) {
		var t = token();
		if (t != tk)
			unexpected(t);
	}

	inline function ensureToken(tk) {
		var t = token();
		if (!Type.enumEq(t, tk))
			unexpected(t);
	}

	function maybe(tk) {
		var t = token();
		if (Type.enumEq(t, tk))
			return true;
		push(t);
		return false;
	}

	function getIdent() {
		var tk = token();
		switch (tk) {
			case TId(id):
				return id;
			default:
				unexpected(tk);
				return null;
		}
	}

	inline function expr(e:Expr) {
		return e.e;
	}

	inline function pmin(e:Expr) {
		return e.pos.pmin;
	}

	inline function pmax(e:Expr) {
		return e.pos.pmax;
	}

	inline function mk(e, ?pmin:Int, ?pmax:Int):Expr {
		return {e: e, pos: getPos(pmin, pmax)};
	}

	inline function mkd(d, ?pmin:Int, ?pmax:Int):ModuleDecl {
		return {d: d, pos: getPos(pmin, pmax)};
	}

	inline function getPos(pmin:Int = -1, pmax:Int = -1):Position {
		if (pmin < 0)
			pmin = tokenMin;
		if (pmax < 0)
			pmax = tokenMax;

		var column:Int = ((pmin < columnOffset ? pmax : pmin) - columnOffset + 1);

		return {
			pmin: pmin,
			pmax: pmax,
			origin: origin,
			line: line,
			column: column
		};
	}

	function isBlock(e) {
		if (e == null)
			return false;
		return switch (expr(e)) {
			case EBlock(_), EObject(_), ESwitch(_): true;
			case EFunction(_, e, _, _): isBlock(e);
			case EVar(_, t, e): e != null ? isBlock(e) : t != null ? t.match(CTAnon(_)) : false;
			case EIf(_, e1, e2): if (e2 != null) isBlock(e2) else isBlock(e1);
			case EBinop(_, _, e): isBlock(e);
			case EUnop(_, prefix, e): !prefix && isBlock(e);
			case EWhile(_, e): isBlock(e);
			case EDoWhile(_, e): isBlock(e);
			case EFor(_, _, e), EForGen(_, e): isBlock(e);
			case EReturn(e): e != null && isBlock(e);
			case ETry(_, _, _, e): isBlock(e);
			case EMeta(":markup", _, _): true;
			case EMeta(_, _, e): isBlock(e);
			default: false;
		}
	}

	function parseFullExpr(exprs:Array<Expr>) {
		var e = parseExpr();
		exprs.push(e);

		var tk = token();
		// this is a hack to support var a,b,c; with a single EVar
		while (tk == TComma && e != null && expr(e).match(EVar(_))) {
			e = parseStructure("var"); // next variable
			exprs.push(e);
			tk = token();
		}

		if (tk != TSemicolon && tk != TEof) {
			if (isBlock(e))
				push(tk);
			else
				unexpected(tk);
		}
	}

	function parseObject(p1) {
		// parse object
		var fl = new Array();
		while (true) {
			var tk = token(false);
			var id = null;
			switch (tk) {
				case TId(i):
					id = i;
				case TConst(c):
					if (!allowJSON)
						unexpected(tk);
					switch (c) {
						case CString(s): id = s;
						default: unexpected(tk);
					}
				case TBrClose:
					break;
				default:
					unexpected(tk);
					break;
			}
			ensure(TDoubleDot);
			fl.push({name: id, e: parseExpr()});
			tk = token();
			switch (tk) {
				case TBrClose:
					break;
				case TComma:
				default:
					unexpected(tk);
			}
		}
		return parseExprNext(mk(EObject(fl), p1));
	}

	function interpolateString(s:String) {
		var se = mk(EConst(CString(s)));

		while (true) {
			var e:Expr = null;

			var c = StringTools.fastCodeAt(input, readPos); // this is so Stupid
			if (idents[c]) {
				var ident:String = '';
				while (true) {
					var c = readChar();
					if (!idents[c] || StringTools.isEof(c)) {
						readPos--;
						break;
					} else {
						ident += String.fromCharCode(c);
					}
				}
				e = mk(EIdent(ident.toString()));
			} else {
				ensure(TBrOpen);
				e = parseExpr();
				ensure(TBrClose);
			}

			var r = parseString("'".code, true); // grab next bit of string

			switch (r) {
				case TConst(CString(s, i)):
					se = mk(EBinop('+', mk(EBinop('+', se, e)), mk(EConst(CString(s)))));

					if (i == null || !i)
						break;
				default:
			}
		}

		return mk(EParent(se));
	}

	function parseExpr(?type) {
		var tk = token();
		var p1 = tokenMin;

		switch (tk) {
			case TId(id):
				var e = parseStructure(id, type);
				if (e == null)
					e = mk(EIdent(id));
				return parseExprNext(e);
			case TConst(CString(s, true)):
				return parseExprNext(interpolateString(s));
			case TConst(c):
				return parseExprNext(mk(EConst(c)));
			case TPOpen:
				tk = token();
				if (tk == TPClose) {
					ensureToken(TOp("->"));
					var eret = parseExpr();
					return mkLambda([], eret, p1);
				}
				push(tk);
				var e = parseExpr();
				tk = token();
				switch (tk) {
					case TPClose:
						return parseExprNext(mk(EParent(e), p1, tokenMax));
					case TDoubleDot:
						var t = parseType();
						tk = token();
						switch (tk) {
							case TPClose:
								return parseExprNext(mk(ECheckType(e, t), p1, tokenMax));
							case TComma:
								switch (expr(e)) {
									case EIdent(v): return parseLambda([{name: v, t: t}], pmin(e));
									default:
								}
							default:
						}
					case TComma:
						switch (expr(e)) {
							case EIdent(v): return parseLambda([{name: v}], pmin(e));
							default:
						}
					case TEof if (resumeErrors):
						return e;
					default:
				}
				return unexpected(tk);
			case TBrOpen:
				tk = token();
				switch (tk) {
					case TBrClose:
						return parseExprNext(mk(EObject([]), p1));
					case TId(_):
						var tk2 = token();
						push(tk2);
						push(tk);
						switch (tk2) {
							case TDoubleDot:
								return parseExprNext(parseObject(p1));
							default:
						}
					case TConst(CString(s, true)):
						push(tk);
					case TConst(c):
						if (allowJSON) {
							switch (c) {
								case CString(s):
									var tk2 = token();
									push(tk2);
									push(tk);
									switch (tk2) {
										case TDoubleDot:
											return parseExprNext(parseObject(p1));
										default:
									}
								default:
									push(tk);
							}
						} else push(tk);
					default:
						push(tk);
				}
				var a = new Array();
				while (true) {
					parseFullExpr(a);
					tk = token();
					if (tk == TBrClose || (resumeErrors && tk == TEof))
						break;
					push(tk);
				}
				return mk(EBlock(a), p1);
			case TOp(op):
				if (op == "-") {
					var start = tokenMin;
					var e = parseExpr();
					if (e == null)
						return makeUnop(op, e);
					switch (expr(e)) {
						case EConst(CInt(i)):
							return mk(EConst(CInt(-i)), start, pmax(e));
						case EConst(CFloat(f)):
							return mk(EConst(CFloat(-f)), start, pmax(e));
						default:
							return makeUnop(op, e);
					}
				}
				if (opPriority.get(op) < 0)
					return makeUnop(op, parseExpr());
				if (op == "<") {
					var start = readPos - 1;
					var ident = getIdent();
					if (tokens.length != 0)
						throw "assert";
					if (readPos == start + ident.length + 1) {
						var endTag = "</" + ident + ">";
						var end = input.indexOf(endTag, readPos);
						if (end < 0) {
							endTag = '/>';
							end = input.indexOf(endTag, readPos);
						}
						if (end >= 0) {
							readPos = end + endTag.length;
							char = -1;
							start--;
							var end = readPos - 1;
							tokenMin = (start + offset);
							tokenMax = (end + offset);
							var str = input.substr(start, end - start + 1);
							return mk(EMeta(":markup", [], mk(EConst(CString(str)))));
						}
					}
				}
				return unexpected(tk);
			case TBkOpen:
				var a = new Array();
				tk = token();
				var first = true;
				while (tk != TBkClose && (!resumeErrors || tk != TEof)) {
					if (!first) {
						if (tk != TComma)
							unexpected(tk);
						else {
							tk = token();
							if (tk == TBkClose)
								break;
						}
					}
					first = false;
					push(tk);
					a.push(parseExpr());
					tk = token();
				}
				return parseExprNext(mk(EArrayDecl(a), p1));
			case TMeta(id) if (allowMetadata):
				var args = parseMetaArgs();
				return mk(EMeta(id, args, parseExpr()), p1);
			default:
				return unexpected(tk);
		}
	}

	function parseLambda(args:Array<Argument>, pmin) {
		while (true) {
			var id = getIdent();
			var t = maybe(TDoubleDot) ? parseType() : null;
			args.push({name: id, t: t});
			var tk = token();
			switch (tk) {
				case TComma:
				case TPClose:
					break;
				default:
					unexpected(tk);
					break;
			}
		}
		ensureToken(TOp("->"));
		var eret = parseExpr();
		return mkLambda(args, eret, pmin);
	}

	function mkLambda(args, eret, p) {
		return mk(EFunction(args, mk(EReturn(eret), pmin(eret)), ++fid), p);
	}

	function parseMetaArgs() {
		var tk = token();
		if (tk != TPOpen) {
			push(tk);
			return null;
		}
		var args = [];
		tk = token();
		if (tk != TPClose) {
			push(tk);
			while (true) {
				args.push(parseExpr());
				switch (token()) {
					case TComma:
					case TPClose:
						break;
					case tk:
						unexpected(tk);
				}
			}
		}
		return args;
	}

	function makeUnop(op, e) {
		if (e == null && resumeErrors)
			return null;
		return switch (expr(e)) {
			case EBinop(bop, e1, e2): mk(EBinop(bop, makeUnop(op, e1), e2), pmin(e1), pmax(e2));
			case ETernary(e1, e2, e3): mk(ETernary(makeUnop(op, e1), e2, e3), pmin(e1), pmax(e3));
			default: mk(EUnop(op, true, e), pmin(e), pmax(e));
		}
	}

	function makeBinop(op, e1, e) {
		if (e == null && resumeErrors)
			return mk(EBinop(op, e1, e), pmin(e1), pmax(e1));
		return switch (expr(e)) {
			case EBinop(op2, e2, e3):
				var delta = opPriority.get(op) - opPriority.get(op2);
				if (delta < 0
					|| (delta == 0 && !opRightAssoc.exists(op))) mk(EBinop(op2, makeBinop(op, e1, e2), e3), pmin(e1),
						pmax(e3)); else mk(EBinop(op, e1, e), pmin(e1), pmax(e));
			case ETernary(e2, e3, e4):
				if (opRightAssoc.exists(op)) mk(EBinop(op, e1, e), pmin(e1), pmax(e)); else mk(ETernary(makeBinop(op, e1, e2), e3, e4), pmin(e1), pmax(e));
			default:
				mk(EBinop(op, e1, e), pmin(e1), pmax(e));
		}
	}

	function parseStructure(id, ?type) {
		var p1 = tokenMin;

		if (id != 'import' && id != 'using')
			decl = true;

		return switch (id) {
			case "using":
				if (decl)
					error(ECustom('import and using may not appear after a declaration'), p1, tokenMax);

				var path:Array<String> = [getIdent()];

				while (true) {
					var t = token();
					if (t != TDot) {
						push(t);
						break;
					}

					t = token();
					switch (t) {
						case TId(id):
							path.push(id);
						default:
							unexpected(t);
					}
				}

				mk(EUsing(path));
			case "import":
				if (decl)
					error(ECustom('import and using may not appear after a declaration'), p1, tokenMax);

				var path:Array<String> = [getIdent()];
				var mode:ImportMode = INormal;
				var tid:String = null;

				if (path[0].isTypeIdentifier())
					tid = path[0];

				while (true) {
					var t = token();
					if (t != TDot) {
						push(t);
						break;
					}

					t = token();
					switch (t) {
						case TId(id):
							if (mode == IAll)
								unexpected(t);

							if (tid != null || id.isTypeIdentifier())
								tid = id;

							path.push(id);
						case TOp("*"):
							if (tid != null)
								unexpected(t);

							mode = IAll;
						default:
							unexpected(t);
					}
				}

				if (mode != IAll && (maybe(TId('as')) || maybe(TId('in')))) {
					if (tid == null) // no type identifier found
						error(ECustom('Module name must start with an uppercase letter'), p1, tokenMax);

					var t = token();
					switch (t) {
						case TId(id):
							if (!id.isTypeIdentifier() && tid.isTypeIdentifier())
								error(ECustom('Type aliases must start with an uppercase letter'), p1, tokenMax);

							mode = IAsName(id);
						default:
							unexpected(t);
					}
				}

				mk(EImport(path, mode));
			case "class", "enum", "typedef":
				push(TId(id));
				var decl = parseModuleDecl();
				if (!maybe(TSemicolon))
					push(TSemicolon);

				mk(EDecl(decl));
			case "if":
				ensure(TPOpen);
				var cond = parseExpr();
				ensure(TPClose);
				var e1 = parseExpr();
				var e2 = null;
				var semic = false;
				var tk = token();
				if (tk == TSemicolon) {
					semic = true;
					tk = token();
				}
				if (Type.enumEq(tk, TId("else")))
					e2 = parseExpr();
				else {
					push(tk);
					if (semic)
						push(TSemicolon);
				}
				mk(EIf(cond, e1, e2), p1, (e2 == null) ? tokenMax : pmax(e2));
			case "var", "final":
				var ident = getIdent();
				var get = null, set = null;
				if (id == 'var' && maybe(TPOpen)) {
					get = getIdent();
					ensure(TComma);
					set = getIdent();
					ensure(TPClose);
				}
				var tk = token();
				var t = null;
				if (tk == TDoubleDot && allowTypes) {
					t = parseType();
					tk = token();
				}
				var e = null;

				switch (tk) {
					case TOp("="): e = parseExpr(t);
					case TOp(_): unexpected(tk);
					case TComma | TSemicolon: push(tk);
					// Above case should be enough but semicolon is not mandatory after }
					case _ if (t != null): push(tk);
					default: unexpected(tk);
				}

				mk(EVar(ident, t, e, get, set, id == 'final'), p1, (e == null) ? tokenMax : pmax(e));
			case "while":
				var econd = parseExpr();
				var e = parseExpr();
				mk(EWhile(econd, e), p1, pmax(e));
			case "do":
				var e = parseExpr();
				var tk = token();
				switch (tk) {
					case TId("while"): // Valid
					default: unexpected(tk);
				}
				var econd = parseExpr();
				mk(EDoWhile(econd, e), p1, pmax(econd));
			case "for":
				ensure(TPOpen);
				var eit = parseExpr();
				ensure(TPClose);
				var e = parseExpr();
				switch (expr(eit)) {
					case EBinop("in", ev, eit):
						switch (expr(ev)) {
							case EIdent(v):
								return mk(EFor(v, eit, e), p1, pmax(e));
							default:
						}
					default:
				}
				mk(EForGen(eit, e), p1, pmax(e));
			case "break": mk(EBreak);
			case "continue": mk(EContinue);
			case "else": unexpected(TId(id));
			case "inline":
				if (!maybe(TId("function")))
					unexpected(TId("inline"));
				return parseStructure("function");
			case "function":
				var tk = token();
				var name = null;
				switch (tk) {
					case TId(id): name = id;
					default: push(tk);
				}
				var inf = parseFunctionDecl();
				mk(EFunction(inf.args, inf.body, name, inf.ret, (name == null ? ++fid : null)), p1, pmax(inf.body));
			case "return":
				var tk = token();
				push(tk);
				var e = if (tk == TSemicolon) null else parseExpr();
				mk(EReturn(e), p1, if (e == null) tokenMax else pmax(e));
			case "new":
				var a = new Array();
				a.push(getIdent());
				while (true) {
					var tk = token();
					switch (tk) {
						case TDot:
							a.push(getIdent());
						case TPOpen:
							break;
						default:
							unexpected(tk);
							break;
					}
				}
				var args = parseExprList(TPClose);
				mk(ENew(a.join("."), args), p1);
			case "throw":
				var e = parseExpr();
				mk(EThrow(e), p1, pmax(e));
			case "try":
				var e = parseExpr();
				ensureToken(TId("catch"));
				// One or more catch clauses: the first fills v/t/ecatch, the rest go into
				// `extra`, matched in declaration order at runtime (typed multi-catch).
				function parseCatch():{v:String, t:Null<CType>, expr:Expr} {
					ensure(TPOpen);
					var cv = getIdent();
					var ct:Null<CType> = null;
					if (maybe(TDoubleDot)) {
						if (allowTypes)
							ct = parseType();
						else
							ensureToken(TId("Dynamic"));
					}
					ensure(TPClose);
					return {v: cv, t: ct, expr: parseExpr()};
				}
				var head = parseCatch();
				var extra:Array<{v:String, t:Null<CType>, expr:Expr}> = null;
				while (true) {
					var tk = token();
					switch (tk) {
						case TId("catch"):
							if (extra == null)
								extra = [];
							extra.push(parseCatch());
						default:
							push(tk);
							break;
					}
				}
				mk(ETry(e, head.v, head.t, head.expr, extra), p1, tokenMax);
			case "switch":
				var e = parseExpr();
				var def = null, cases = [];
				ensure(TBrOpen);
				while (true) {
					var tk = token();
					switch (tk) {
						case TId("case"):
							var c = {values: [], expr: null, guard: null};
							cases.push(c);
							while (true) {
								var e:Expr;

								if (maybe(TId('var'))) {
									e = mk(EVar(getIdent()), p1);
								} else {
									e = parseExpr();
								}

								c.values.push(e);
								tk = token();

								switch (tk) {
									case TId('if'):
										ensure(TPOpen);
										c.guard = parseExpr();
										ensure(TPClose);

										switch (tk = token()) {
											case TDoubleDot:
												break;
											default:
												unexpected(tk);
												break;
										}
									case TComma:
										// next expr
									case TDoubleDot:
										break;
									default:
										unexpected(tk);
										break;
								}
							}
							var exprs = [];
							while (true) {
								tk = token();
								push(tk);
								switch (tk) {
									case TId("case"), TId("default"), TBrClose:
										break;
									case TEof if (resumeErrors):
										break;
									default:
										parseFullExpr(exprs);
								}
							}
							c.expr = if (exprs.length == 1) exprs[0]; else if (exprs.length == 0) mk(EBlock([]), tokenMin,
								tokenMin); else mk(EBlock(exprs), pmin(exprs[0]), pmax(exprs[exprs.length - 1]));
						case TId("default"):
							if (def != null)
								unexpected(tk);
							ensure(TDoubleDot);
							var exprs = [];
							while (true) {
								tk = token();
								push(tk);
								switch (tk) {
									case TId("case"), TId("default"), TBrClose:
										break;
									case TEof if (resumeErrors):
										break;
									default:
										parseFullExpr(exprs);
								}
							}
							def = if (exprs.length == 1) exprs[0]; else if (exprs.length == 0) mk(EBlock([]), tokenMin,
								tokenMin); else mk(EBlock(exprs), pmin(exprs[0]), pmax(exprs[exprs.length - 1]));
						case TBrClose:
							break;
						default:
							unexpected(tk);
							break;
					}
				}
				mk(ESwitch(e, cases, def), p1, tokenMax);
			case "cast":
				var tk = token();
				if (tk == TPOpen) {
					var e = parseExpr();
					ensure(TComma);
					var t = parseType();
					ensure(TPClose);
					mk(ECast(e, t), p1, tokenMax);
				} else {
					push(tk);
					var e = parseExpr();
					mk(ECast(e, type), p1, tokenMax);
				}
			case "untyped":
				// The interpreter is dynamically typed, so `untyped` only suppresses compile-time
				// checks that don't exist here: evaluate the inner expression as-is. Handles both
				// `untyped expr` and `untyped { block }`.
				parseExpr();
			default:
				null;
		}
	}

	function parseExprNext(e1:Expr) {
		var tk = token();
		switch (tk) {
			case TOp(op):
				if (op == "->") {
					// single arg reinterpretation of `f -> e` , `(f) -> e` and `(f:T) -> e`
					switch (expr(e1)) {
						case EIdent(i), EParent(expr(_) => EIdent(i)):
							var eret = parseExpr();
							return mkLambda([{name: i}], eret, pmin(e1));
						case ECheckType(expr(_) => EIdent(i), t):
							var eret = parseExpr();
							return mkLambda([{name: i, t: t}], eret, pmin(e1));
						default:
					}
					unexpected(tk);
				}

				if (opPriority.get(op) == -1) {
					if (isBlock(e1) || switch (expr(e1)) {
							case EParent(_): true;
							default: false;
						}) {
						push(tk);
						return e1;
						}
					return parseExprNext(mk(EUnop(op, false, e1), pmin(e1)));
				}
				return makeBinop(op, e1, parseExpr());
			case TId(op) if (opPriority.exists(op)):
				return parseExprNext(makeBinop(op, e1, parseExpr()));
			case TDot | TQuestionDot:
				var field = getIdent();
				return parseExprNext(mk(EField(e1, field, tk == TQuestionDot), pmin(e1)));
			case TPOpen:
				return parseExprNext(mk(ECall(e1, parseExprList(TPClose)), pmin(e1)));
			case TBkOpen:
				var e2 = parseExpr();
				ensure(TBkClose);
				return parseExprNext(mk(EArray(e1, e2), pmin(e1)));
			case TQuestion:
				var e2 = parseExpr();
				ensure(TDoubleDot);
				var e3 = parseExpr();
				return mk(ETernary(e1, e2, e3), pmin(e1), pmax(e3));
			default:
				push(tk);
				return e1;
		}
	}

	function parseFunctionArgs(restAllowed:Bool = true) {
		var args = new Array();
		var hasRest = false;
		var tk = token();
		if (tk != TPClose) {
			var done = false;
			while (!done) {
				var name = null, opt = false, rest = false;
				switch (tk) {
					case TQuestion:
						opt = true;
						tk = token();
					case TOp('...'):
						if (!restAllowed)
							unexpected(tk);
						rest = true;
						tk = token();
					default:
				}

				switch (tk) {
					case TId(id):
						if (hasRest)
							error(ECustom('Rest should only be used for the last function argument'), tokenMin, tokenMax);
						hasRest = rest;
						name = id;
					default:
						unexpected(tk);
						break;
				}

				var arg:Argument = {name: name, rest: rest, opt: opt};
				if (allowTypes) {
					if (maybe(TDoubleDot))
						arg.t = parseType();
					if (maybe(TOp("="))) {
						if (rest)
							error(ECustom('Rest argument cannot have default value'), tokenMin, tokenMax);
						arg.value = parseExpr();
						arg.opt = true;
					}
				}

				args.push(arg);
				tk = token();

				switch (tk) {
					case TComma:
						tk = token();
					case TPClose:
						done = true;
					default:
						unexpected(tk);
				}
			}
		}
		return args;
	}

	function parseFunctionDecl(allowNoBody:Bool = false) {
		parseParams(); // erase method type parameters, e.g. `function map<T, R>(...)`
		ensure(TPOpen);
		var args = parseFunctionArgs();
		var ret = null;
		if (allowTypes) {
			var tk = token();
			if (tk != TDoubleDot)
				push(tk);
			else
				ret = parseType();
		}
		if (allowNoBody && maybe(TSemicolon))
			return {args: args, ret: ret, body: null};
		return {args: args, ret: ret, body: parseExpr()};
	}

	function parsePath() {
		var path = [getIdent()];
		while (true) {
			var t = token();
			if (t != TDot) {
				push(t);
				break;
			}
			path.push(getIdent());
		}
		return path;
	}

	function parseType():CType {
		var t = token();
		switch (t) {
			case TId(v):
				push(t);
				var path = parsePath();
				var params = null;
				t = token();
				switch (t) {
					case TOp(op):
						if (op == "<") {
							params = [];
							while (true) {
								switch (token(false)) {
									case TConst(c):
										params.push(CTExpr(mk(EConst(c))));
									case tk:
										push(tk);
										params.push(parseType());
								}
								t = token();
								switch (t) {
									case TComma: continue;
									case TOp(op):
										if (op == ">")
											break;
										if (op.charCodeAt(0) == ">".code) {
											tokens.add({t: TOp(op.substr(1)), min: tokenMax - op.length - 1, max: tokenMax});
											break;
										}
									default:
								}
								unexpected(t);
								break;
							}
						} else push(t);
					default:
						push(t);
				}
				return parseTypeNext(CTPath(path, params));
			case TPOpen:
				var a = token();
				var b = token();

				push(b);
				push(a);

				function withReturn(args) {
					switch token() { // I think it wouldn't hurt if ensure used enumEq
						case TOp('->'):
						case t:
							unexpected(t);
					}

					return CTFun(args, parseType());
				}

				switch [a, b] {
					case [TPClose, _] | [TId(_), TDoubleDot]:
						var args = [
							for (arg in parseFunctionArgs()) {
								switch arg.value {
									case null:
									case v:
										error(ECustom('Default values not allowed in function types'), v.pos.pmin, v.pos.pmax);
								}

								CTNamed(arg.name, if (arg.opt) CTOpt(arg.t) else arg.t);
							}
						];

						return withReturn(args);
					default:
						var t = parseType();
						return switch token() {
							case TComma:
								var args = [t];

								while (true) {
									args.push(parseType());
									if (!maybe(TComma))
										break;
								}
								ensure(TPClose);
								withReturn(args);
							case TPClose:
								parseTypeNext(CTParent(t));
							case t: unexpected(t);
						}
				}
			case TBrOpen:
				var fields = [];
				var meta = null;
				while (true) {
					t = token();
					switch (t) {
						case TBrClose: break;
						case TId("var"), TId("final"):
							var name = getIdent();
							ensure(TDoubleDot);
							if (t.match(TId("final"))) {
								if (meta == null)
									meta = [];
								meta.push({name: ":final", params: []});
							}
							fields.push({name: name, t: parseType(), meta: meta});
							meta = null;
							ensure(TSemicolon);
						case TId(name):
							ensure(TDoubleDot);
							fields.push({name: name, t: parseType(), meta: meta});
							t = token();
							switch (t) {
								case TComma:
								case TBrClose: break;
								default: unexpected(t);
							}
						case TMeta(name):
							if (meta == null)
								meta = [];
							meta.push({name: name, params: parseMetaArgs()});
						default:
							unexpected(t);
							break;
					}
				}
				return parseTypeNext(CTAnon(fields));
			default:
				return unexpected(t);
		}
	}

	function parseTypeNext(t:CType) {
		var tk = token();
		switch (tk) {
			case TOp(op):
				if (op != "->") {
					push(tk);
					return t;
				}
			default:
				push(tk);
				return t;
		}
		var t2 = parseType();
		switch (t2) {
			case CTFun(args, _):
				args.unshift(t);
				return t2;
			default:
				return CTFun([t], t2);
		}
	}

	function parseExprList(etk) {
		var args = new Array();
		var tk = token();
		if (tk == etk)
			return args;
		push(tk);
		while (true) {
			args.push(parseExpr());
			tk = token();
			switch (tk) {
				case TComma:
				default:
					if (tk == etk)
						break;
					unexpected(tk);
					break;
			}
		}
		return args;
	}

	// ------------------------ module -------------------------------

	public function parseModule(content:String, ?origin:String = "hscript", position:Int = 0, ?pack:Array<String>, importModule:Bool = false) {
		this.pack = pack;
		initParser(origin, position);
		input = content;
		readPos = 0;
		allowTypes = true;
		allowMetadata = true;

		var decls = [];
		while (true) {
			var tk = token();
			if (tk == TEof)
				break;
			push(tk);
			decls.push(parseModuleDecl(decls, importModule));
		}

		if (!importModule) {
			pack ??= [];
			var fullPack = pack.join('.');
			var thisPack = (switch (decls[0]?.d) {
				case DPackage(path): path;
				default: [];
			}).join('.');
			if (thisPack != fullPack) {
				throw new haxe.Exception('"package${thisPack.length > 0 ? ' ' : ''}$thisPack;" in $origin should be "package${fullPack.length > 0 ? ' ' : ''}$fullPack;"');
			}
		}

		return decls;
	}

	function parseMetadata():Metadata {
		var meta = [];
		while (true) {
			var tk = token();
			switch (tk) {
				case TMeta(name):
					meta.push({name: name, params: parseMetaArgs()});
				default:
					push(tk);
					break;
			}
		}
		return meta;
	}

	// Type parameters are recorded by name and erased: constraints are parsed and
	// dropped, and every parameter resolves to Dynamic at runtime.
	function parseParams():Array<String> {
		var params:Array<String> = [];
		if (!maybe(TOp("<")))
			return params;

		while (true) {
			var name = getIdent();
			if (!name.isTypeIdentifier())
				error(ECustom('Type parameter name should start with an uppercase letter'), tokenMin, tokenMax);
			params.push(name);

			if (maybe(TDoubleDot)) {
				if (maybe(TPOpen)) {
					while (true) {
						parseType();
						if (!maybe(TComma))
							break;
					}
					ensure(TPClose);
				} else {
					parseType();
				}
			}

			var t = token();
			switch (t) {
				case TComma:
					continue;
				case TOp(op):
					if (op == ">")
						break;
					// A nested parameter list closes with `>>`, which lexes as one operator.
					if (op.charCodeAt(0) == ">".code) {
						tokens.add({t: TOp(op.substr(1)), min: tokenMax - op.length - 1, max: tokenMax});
						break;
					}
				default:
			}
			unexpected(t);
			break;
		}

		return params;
	}

	function parseAbstractDecl(name:String, meta:Metadata, params:Array<String>, isEnum:Bool, isPrivate:Bool):ModuleDecl {
		// `abstract Name(Underlying) from A to B { ... }`. The underlying type and from/to casts
		// erase (the runtime is dynamic). An enum abstract's members become static constants,
		// tagged @:enumAbstract so the module exposes them unqualified, like enum constructors.
		if (maybe(TPOpen)) {
			parseType();
			ensure(TPClose);
		}
		while (true) {
			var t = token();
			switch (t) {
				case TId("from"), TId("to"):
					parseType();
				default:
					push(t);
					break;
			}
		}
		var fields = [];
		ensure(TBrOpen);
		while (!maybe(TBrClose)) {
			var f = parseField(true);
			if (isEnum && !f.access.contains(AStatic))
				f.access.push(AStatic);
			fields.push(f);
		}
		var m = isEnum ? meta.concat([{name: ':enumAbstract', params: []}]) : meta;
		return mkd(DClass({
			name: name,
			meta: m,
			params: params,
			extend: null,
			implement: [],
			fields: fields,
			isPrivate: isPrivate,
			isExtern: false,
		}), tokenMin, tokenMax);
	}

	function parseModuleDecl(?decls:Array<ModuleDecl>, importModule:Bool = false):ModuleDecl {
		var meta = parseMetadata();
		var ident = getIdent();
		var isPrivate = false, isExtern = false;
		while (true) {
			switch (ident) {
				case "private":
					isPrivate = true;
				case "extern":
					isExtern = true;
				default:
					break;
			}
			ident = getIdent();
		}
		if (ident != 'package' && ident != 'import' && ident != 'using')
			decl = true;

		return switch (ident) {
			case "using":
				if (decl)
					error(ECustom('import and using may not appear after a declaration'), tokenMin, tokenMax);

				var path:Array<String> = [getIdent()];

				while (true) {
					var t = token();
					if (t != TDot) {
						push(t);
						break;
					}

					t = token();
					switch (t) {
						case TId(id):
							path.push(id);
						default:
							unexpected(t);
					}
				}

				ensure(TSemicolon);

				return mkd(DUsing(path), tokenMin, tokenMax);
			case "package":
				if (decls != null && decls.length > 0)
					error(EUnexpected(ident), tokenMin, tokenMax);

				var noPath = maybe(TSemicolon);
				var path = (noPath ? [] : parsePath());
				if (!noPath)
					ensure(TSemicolon);

				return mkd(DPackage(path), tokenMin, tokenMax);
			case "import":
				if (decl)
					error(ECustom('import and using may not appear after a declaration'), tokenMin, tokenMax);

				var path:Array<String> = [getIdent()];
				var mode:ImportMode = INormal;
				var tid:String = null;

				if (path[0].isTypeIdentifier())
					tid = path[0];

				while (true) {
					var t = token();
					if (t != TDot) {
						push(t);
						break;
					}

					t = token();
					switch (t) {
						case TId(id):
							if (mode == IAll)
								unexpected(t);

							if (tid != null || id.isTypeIdentifier())
								tid = id;

							path.push(id);
						case TOp("*"):
							if (tid != null)
								unexpected(t);

							mode = IAll;
						default:
							unexpected(t);
					}
				}

				if (mode != IAll && (maybe(TId('as')) || maybe(TId('in')))) {
					if (tid == null) // no type identifier found
						error(ECustom('Module name must start with an uppercase letter'), tokenMin, tokenMax);

					var t = token();
					switch (t) {
						case TId(id):
							if (!id.isTypeIdentifier() && tid.isTypeIdentifier())
								error(ECustom('Type aliases must start with an uppercase letter'), tokenMin, tokenMax);

							mode = IAsName(id);
						default:
							unexpected(t);
					}
				}

				ensure(TSemicolon);

				return mkd(DImport(path, mode), tokenMin, tokenMax);
			case "class":
				if (importModule)
					error(EImportHx, tokenMin, tokenMax);

				var name = getIdent();
				if (!name.isTypeIdentifier())
					error(ECustom('Type name should start with an uppercase letter'), tokenMin, tokenMax);

				var params = parseParams();
				var extend = null;
				var implement = [];

				while (true) {
					var t = token();
					switch (t) {
						case TId("extends"):
							extend = parseType();
						case TId("implements"):
							implement.push(parseType());
						default:
							push(t);
							break;
					}
				}

				// origin = pack.join('.');
				// origin = (origin.length > 0 ? '$origin.$name' : name);

				var fields = [];
				ensure(TBrOpen);
				while (!maybe(TBrClose))
					fields.push(parseField());

				return mkd(DClass({
					name: name,
					meta: meta,
					params: params,
					extend: extend,
					implement: implement,
					fields: fields,
					isPrivate: isPrivate,
					isExtern: isExtern,
				}), tokenMin, tokenMax);
			case "interface":
				if (importModule)
					error(EImportHx, tokenMin, tokenMax);

				var name = getIdent();
				if (!name.isTypeIdentifier())
					error(ECustom('Type name should start with an uppercase letter'), tokenMin, tokenMax);

				var params = parseParams();
				// Haxe spells interface inheritance `extends`, and allows several of them;
				// they all land in `implement` so the runtime has one parent list to walk.
				var implement = [];

				while (true) {
					var t = token();
					switch (t) {
						case TId("extends"), TId("implements"):
							implement.push(parseType());
						default:
							push(t);
							break;
					}
				}

				var fields = [];
				ensure(TBrOpen);
				while (!maybe(TBrClose))
					fields.push(parseField(true));

				return mkd(DInterface({
					name: name,
					meta: meta,
					params: params,
					extend: null,
					implement: implement,
					fields: fields,
					isPrivate: isPrivate,
					isExtern: isExtern,
				}), tokenMin, tokenMax);
			case "enum":
				if (importModule)
					error(EImportHx, tokenMin, tokenMax);

				// `enum abstract Name(T) { var A = v; }` -- constants of the underlying type.
				var enumPeek = token();
				if (enumPeek.match(TId("abstract"))) {
					var aName = getIdent();
					if (!aName.isTypeIdentifier())
						error(ECustom('Type name should start with an uppercase letter'), tokenMin, tokenMax);
					return parseAbstractDecl(aName, meta, parseParams(), true, isPrivate);
				}
				push(enumPeek);

				var name = getIdent();
				if (!name.isTypeIdentifier())
					error(ECustom('Type name should start with an uppercase letter'), tokenMin, tokenMax);

				var params = parseParams();
				var names:Array<String> = [];
				var constructs:Map<String, EnumFieldDecl> = [];

				ensure(TBrOpen);
				while (!maybe(TBrClose)) {
					var field:EnumFieldDecl = parseEnumField();
					constructs.set(field.name, field);

					// if (names.contains(field.name))
					// 	error(ECustom('Duplicate constructor ${field.name}'), tokenMin, tokenMax);

					names.push(field.name);
				}

				return mkd(DEnum({
					name: name,
					meta: meta,
					params: params,
					isPrivate: isPrivate,
					constructs: constructs,
					names: names
				}), tokenMin, tokenMax);
			case "abstract":
				if (importModule)
					error(EImportHx, tokenMin, tokenMax);

				var name = getIdent();
				if (!name.isTypeIdentifier())
					error(ECustom('Type name should start with an uppercase letter'), tokenMin, tokenMax);

				var params = parseParams();
				var isEnumAbstract = false;
				for (m in meta)
					if (m.name == ':enum')
						isEnumAbstract = true;
				return parseAbstractDecl(name, meta, params, isEnumAbstract, isPrivate);
			case "typedef":
				if (importModule)
					error(EImportHx, tokenMin, tokenMax);

				var name = getIdent();
				if (!name.isTypeIdentifier())
					error(ECustom('Type name should start with an uppercase letter'), tokenMin, tokenMax);

				var params = parseParams();

				ensureToken(TOp("="));

				var t = parseType();
				switch (t) {
					case CTPath(_, _):
						ensure(TSemicolon);

					default:
						maybe(TSemicolon);
				}

				return mkd(DTypedef({
					name: name,
					meta: meta,
					params: params,
					isPrivate: isPrivate,
					t: t,
				}), tokenMin, tokenMax);
			case "var", "final", "function":
				push(TId(ident));

				var f = parseField();

				return mkd(DField({
					name: f.name,
					meta: f.meta,
					kind: f.kind,
					params: null,
					isPrivate: isPrivate,
				}), tokenMin, tokenMax);
			default:
				unexpected(TId(ident));
		}
		return null;
	}

	function parseEnumField():EnumFieldDecl {
		var arguments:Array<Argument> = null;
		var meta = parseMetadata();
		var id = getIdent();

		if (maybe(TPOpen))
			arguments = parseFunctionArgs(false);

		ensure(TSemicolon);

		return {
			name: id,
			meta: meta,
			arguments: arguments
		};
	}

	function parseField(allowNoBody:Bool = false):FieldDecl {
		var meta = parseMetadata();
		var access = [];
		while (true) {
			var id = getIdent();
			switch (id) {
				case "override":
					access.push(AOverride);
				case "dynamic":
					access.push(ADynamic);
				case "public":
					access.push(APublic);
				case "private":
					access.push(APrivate);
				case "inline":
					access.push(AInline);
				case "static":
					access.push(AStatic);
				case "macro":
					access.push(AMacro);
				case "overload":
					// Overloading isn't dispatched at runtime; accept the modifier and treat the
					// method as ordinary (last same-named definition wins).
				case "function":
					var name = getIdent();
					var inf = parseFunctionDecl(allowNoBody);
					// A brace-less body (`function get_x() return x;`) leaves the terminating
					// semicolon for us; a block body may carry an optional one. Swallow it so the
					// member loop doesn't choke -- matching what real Haxe accepts.
					maybe(TSemicolon);
					return {
						name: name,
						meta: meta,
						access: access,
						kind: KFunction({
							args: inf.args,
							expr: inf.body,
							ret: inf.ret,
						}),
					};
				case "var", "final":
					// `final function` is a non-overridable method, not a field -- parse it as an
					// ordinary method (override-prevention isn't enforced at runtime).
					if (id == 'final') {
						var peek = token();
						push(peek);
						if (peek.match(TId("function"))) {
							getIdent();
							var fname = getIdent();
							var finf = parseFunctionDecl(allowNoBody);
							maybe(TSemicolon);
							return {
								name: fname,
								meta: meta,
								access: access,
								kind: KFunction({args: finf.args, expr: finf.body, ret: finf.ret}),
							};
						}
					}
					var name = getIdent();
					var get = null, set = null;
					if (id != 'final' && maybe(TPOpen)) {
						get = getIdent();
						ensure(TComma);
						set = getIdent();
						ensure(TPClose);
					}
					var type = maybe(TDoubleDot) ? parseType() : null;
					var expr = maybe(TOp("=")) ? parseExpr() : null;

					if (expr != null) {
						if (isBlock(expr))
							maybe(TSemicolon);
						else
							ensure(TSemicolon);
					} else if (type != null && type.match(CTAnon(_))) {
						maybe(TSemicolon);
					} else
						ensure(TSemicolon);

					return {
						name: name,
						meta: meta,
						access: access,
						kind: KVar({
							get: get,
							set: set,
							type: type,
							expr: expr,
							isFinal: (id == 'final')
						}),
					};
				default:
					unexpected(TId(id));
					break;
			}
		}
		return null;
	}

	// ------------------------ lexing -------------------------------

	inline function readChar() {
		return StringTools.fastCodeAt(input, readPos++);
	}

	inline function parseEscape(c:Int, b:StringBuf, old:Int) {
		var p1 = (currentPos - 1);
		switch (c) {
			case 'n'.code:
				b.addChar('\n'.code);
			case 'r'.code:
				b.addChar('\r'.code);
			case 't'.code:
				b.addChar('\t'.code);
			case "'".code, '"'.code, '\\'.code:
				b.addChar(c);
			case '/'.code:
				if (allowJSON)
					b.addChar(c)
				else
					invalidChar(c);
			case "u".code:
				if (!allowJSON)
					invalidChar(c);
				var k = 0;
				for (i in 0...4) {
					k <<= 4;
					var char = readChar();
					switch (char) {
						case 48, 49, 50, 51, 52, 53, 54, 55, 56, 57: // 0-9
							k += char - 48;
						case 65, 66, 67, 68, 69, 70: // A-F
							k += char - 55;
						case 97, 98, 99, 100, 101, 102: // a-f
							k += char - 87;
						default:
							if (StringTools.isEof(char)) {
								line = old;
								error(EUnterminatedString, p1, p1);
							}
							invalidChar(char);
					}
				}
				b.addChar(k);
			default:
				invalidChar(c);
		}
	}

	function parseString(until:Int, interpolate:Bool = false) {
		var c = 0;
		var b = new StringBuf();
		var esc = false;
		var old = line;
		var s = input;
		var p1 = currentPos - 1;

		while (true) {
			var c = readChar();
			if (StringTools.isEof(c)) {
				line = old;
				error(EUnterminatedString, p1, p1);
				break;
			}
			if (esc) {
				esc = false;
				parseEscape(c, b, old);
			} else if (c == 92) {
				esc = true;
			} else if (c == until) {
				break;
			} else if (interpolate && c == '$'.code) {
				var next = readChar();
				if (idents[next] || next == '{'.code) {
					readPos--;
					return TConst(CString(b.toString(), true));
				} else if (next == '$'.code) {
					b.addChar(c);
				} else {
					b.addChar(c);
					b.addChar(next);
				}
			} else {
				if (c == 10) {
					columnOffset = p1;
					line++;
				}
				b.addChar(c);
			}
		}
		return TConst(CString(b.toString()));
	}

	function parseRegex() {
		var c = 0;
		var old = line;
		var p1 = currentPos - 1;
		var esc = false;

		var p = new StringBuf();
		var m = new StringBuf();

		while (true) {
			var c = readChar();

			if (StringTools.isEof(c) || c == 10) {
				line = old;
				error(EUnterminatedRegex, p1, p1);
				break;
			}

			if (esc) {
				esc = false;
				parseEscape(c, p, old);
			} else if (c == '\\'.code) {
				esc = true;
			} else if (c == '/'.code) {
				while (true) {
					var c = readChar();
					if (c < 97 || c > 122)
						break;

					switch (c) {
						case 'i'.code, 'g'.code, 'm'.code, 's'.code, 'u'.code:
							m.addChar(c);
						default:
							error(ECustom('Invalid regular expression option'), p1, p1);
					}
				}
				break;
			} else {
				p.addChar(c);
			}
		}

		readPos--;
		return TConst(CReg(p.toString(), m.toString()));
	}

	function token(interpolateStrings:Bool = true) {
		var t = tokens.pop();
		if (t != null) {
			tokenMin = t.min;
			tokenMax = t.max;
			return t.t;
		}
		oldTokenMin = tokenMin;
		oldTokenMax = tokenMax;
		tokenMin = (this.char < 0) ? currentPos : currentPos - 1;
		var t = _token(interpolateStrings);
		tokenMax = (this.char < 0) ? currentPos - 1 : currentPos - 2;
		return t;
	}

	function _token(interpolateStrings:Bool = true) {
		var char;
		var colOffset:Int = this.columnOffset;
		if (this.char < 0)
			char = readChar();
		else {
			char = this.char;
			this.char = -1;
		}
		while (true) {
			if (StringTools.isEof(char)) {
				this.char = char;
				return TEof;
			}
			switch (char) {
				case 0:
					return TEof;
				case 32, 9, 13: // space, tab, CR
					tokenMin++;
				case 10:
					columnOffset = currentPos;
					line++; // LF
					tokenMin++;
				case 48, 49, 50, 51, 52, 53, 54, 55, 56, 57: // 0...9
					var n = (char - 48) * 1.0;
					var exp = 0.;
					while (true) {
						char = readChar();
						exp *= 10;
						switch (char) {
							case 48, 49, 50, 51, 52, 53, 54, 55, 56, 57:
								n = n * 10 + (char - 48);
							case "_".code: // digit separator
							case "e".code, "E".code:
								var tk = token();
								var pow:Null<Int> = null;
								switch (tk) {
									case TConst(CInt(e)): pow = e;
									case TOp("-"):
										tk = token();
										switch (tk) {
											case TConst(CInt(e)): pow = -e;
											default: push(tk);
										}
									default:
										push(tk);
								}
								if (pow == null)
									invalidChar(char);
								if (exp == 0)
									exp = 10;
								return TConst(CFloat((Math.pow(10, pow) / exp) * n * 10));
							case ".".code:
								if (exp > 0) {
									// in case of '0...'
									if (exp == 10 && readChar() == ".".code) {
										push(TOp("..."));
										var i = Std.int(n);
										return TConst((i == n) ? CInt(i) : CFloat(n));
									}
									invalidChar(char);
								}
								exp = 1.;
							case "x".code:
								if (n > 0 || exp > 0)
									invalidChar(char);
								// read hexa
								var n = 0;
								while (true) {
									char = readChar();
									switch (char) {
										case 48, 49, 50, 51, 52, 53, 54, 55, 56, 57: // 0-9
											n = (n << 4) + char - 48;
										case 65, 66, 67, 68, 69, 70: // A-F
											n = (n << 4) + (char - 55);
										case 97, 98, 99, 100, 101, 102: // a-f
											n = (n << 4) + (char - 87);
										case "_".code: // digit separator
										default:
											this.char = char;
											return TConst(CInt(n));
									}
								}
							case "b".code:
								if (n > 0 || exp > 0)
									invalidChar(char);
								// read binary
								var n = 0;
								while (true) {
									char = readChar();
									switch (char) {
										case 48, 49: // 0-1
											n = (n << 1) + (char - 48);
										case "_".code: // digit separator
										default:
											this.char = char;
											return TConst(CInt(n));
									}
								}
							default:
								this.char = char;
								this.columnOffset = colOffset;
								var i = Std.int(n);
								return TConst((exp > 0) ? CFloat(n * 10 / exp) : ((i == n) ? CInt(i) : CFloat(n)));
						}
					}
				case ";".code:
					return TSemicolon;
				case "(".code:
					return TPOpen;
				case ")".code:
					return TPClose;
				case ",".code:
					return TComma;
				case ".".code:
					char = readChar();
					switch (char) {
						case 48, 49, 50, 51, 52, 53, 54, 55, 56, 57:
							var n = char - 48;
							var exp = 1;
							while (true) {
								char = readChar();
								exp *= 10;
								switch (char) {
									case 48, 49, 50, 51, 52, 53, 54, 55, 56, 57:
										n = n * 10 + (char - 48);
									default:
										this.char = char;
										this.columnOffset = colOffset;
										return TConst(CFloat(n / exp));
								}
							}
						case ".".code:
							char = readChar();
							if (char != ".".code)
								invalidChar(char);
							return TOp("...");
						default:
							this.char = char;
							this.columnOffset = colOffset;
							return TDot;
					}
				case "~".code:
					char = readChar();
					if (char == "/".code)
						return parseRegex();
					invalidChar(char);
				case "{".code:
					return TBrOpen;
				case "}".code:
					return TBrClose;
				case "[".code:
					return TBkOpen;
				case "]".code:
					return TBkClose;
				case "'".code, '"'.code:
					return parseString(char, interpolateStrings && char == "'".code);
				case "?".code:
					char = readChar();
					if (char == ".".code) {
						return TQuestionDot;
					} else if (char == '?'.code) {
						char = readChar();
						if (char == "=".code) {
							return TOp('??=');
						} else {
							return TOp('??');
						}
					}
					this.char = char;
					this.columnOffset = colOffset;
					return TQuestion;
				case ":".code:
					return TDoubleDot;
				case '='.code:
					char = readChar();
					if (char == '='.code)
						return TOp("==");
					else if (char == '>'.code)
						return TOp("=>");
					this.char = char;
					this.columnOffset = colOffset;
					return TOp("=");
				case '@'.code:
					char = readChar();
					if (idents[char] || char == ':'.code) {
						var id = String.fromCharCode(char);
						while (true) {
							char = readChar();
							if (!idents[char]) {
								this.char = char;
								this.columnOffset = colOffset;
								return TMeta(id);
							}
							id += String.fromCharCode(char);
						}
					}
					invalidChar(char);
				case '#'.code:
					char = readChar();
					if (idents[char]) {
						var id = String.fromCharCode(char);
						while (true) {
							char = readChar();
							if (!idents[char]) {
								this.char = char;
								this.columnOffset = colOffset;
								return preprocess(id);
							}
							id += String.fromCharCode(char);
						}
					}
					invalidChar(char);
				default:
					if (ops[char]) {
						var op = String.fromCharCode(char);
						while (true) {
							char = readChar();
							if (StringTools.isEof(char))
								char = 0;
							if (!ops[char]) {
								this.char = char;
								return TOp(op);
							}
							var pop = op;
							op += String.fromCharCode(char);
							if (!opPriority.exists(op) && opPriority.exists(pop)) {
								if (op == "//" || op == "/*")
									return tokenComment(op, char);
								this.char = char;
								this.columnOffset = colOffset;
								return TOp(pop);
							}
						}
					}
					if (idents[char]) {
						var id = String.fromCharCode(char);
						while (true) {
							char = readChar();
							if (StringTools.isEof(char))
								char = 0;
							if (!idents[char]) {
								this.char = char;
								return TId(id);
							}
							id += String.fromCharCode(char);
						}
					}
					invalidChar(char);
			}
			char = readChar();
		}
		return null;
	}

	function preprocValue(id:String):Dynamic {
		return (preprocessorValues.get(id) ?? Config.preprocessorValues.get(id));
	}

	var preprocStack:Array<{r:Bool}>;
	var preprocessorBinops:Map<String, Dynamic->Dynamic->Bool>;

	function parsePreproCond() {
		var tk = token();
		return switch (tk) {
			case TPOpen:
				var e = parseExpr();
				ensure(TPClose);
				e;
			case TId(id):
				mk(EIdent(id), tokenMin, tokenMax);
			case TOp("!"):
				mk(EUnop("!", true, parsePreproCond()), tokenMin, tokenMax);
			default:
				unexpected(tk);
		}
	}

	function evalPreproCond(e:Expr):Dynamic {
		switch (expr(e)) {
			case EIdent(id):
				return preprocValue(id);
			case EConst(CInt(v)):
				return v;
			case EConst(CFloat(v)):
				return v;
			case EConst(CString(v)):
				return v;
			case EUnop("!", _, e):
				var v:Dynamic = evalPreproCond(e);
				return (v is Bool ? !v : v == null);
			case EParent(e):
				return evalPreproCond(e);
			case EBinop(op, e1, e2) if (preprocessorBinops.exists(op)):
				return preprocessorBinops.get(op)(evalPreproCond(e1), evalPreproCond(e2));
			case EBinop(op, _, _):
				error(EInvalidPreprocessor('Unsupported operation $op'), currentPos, currentPos);
				return null;
			default:
				error(EInvalidPreprocessor(expr(e).getName()), currentPos, currentPos);
				return null;
		}
	}

	function preprocess(id:String):Token {
		switch (id) {
			case "if":
				var e = parsePreproCond();
				var v:Dynamic = evalPreproCond(e);

				if (v != null && (!(v is Bool) || v != false)) {
					preprocStack.push({r: true});
					return token();
				}

				preprocStack.push({r: false});
				skipTokens();

				return token();
			case "else", "elseif" if (preprocStack.length > 0):
				if (preprocStack[preprocStack.length - 1].r) {
					preprocStack[preprocStack.length - 1].r = false;
					skipTokens();
					return token();
				} else if (id == "else") {
					preprocStack.pop();
					preprocStack.push({r: true});
					return token();
				} else {
					// elseif
					preprocStack.pop();
					return preprocess("if");
				}
			case "end" if (preprocStack.length > 0):
				preprocStack.pop();
				return token();
			case 'error':
				if (preprocStack.length < 1 || preprocStack[preprocStack.length - 1].r) {
					var string:String = switch (expr(parseExpr())) {
						case EConst(CString(v)): v;
						default: 'Not implemented';
					};
					error(ECustom(string), currentPos, currentPos);
				}

				return token();
			default:
				return TPrepro(id);
		}
	}

	function skipTokens() {
		var spos = preprocStack.length - 1;
		var obj = preprocStack[spos];
		var pos = currentPos;
		while (true) {
			var tk = token();
			if (preprocStack[spos] != obj) {
				push(tk);
				break;
			}
			if (tk == TEof)
				error(EInvalidPreprocessor("Unclosed"), pos, pos);
		}
	}

	function tokenComment(op:String, char:Int) {
		var c = op.charCodeAt(1);
		var s = input;
		if (c == '/'.code) { // comment
			while (char != '\r'.code && char != '\n'.code) {
				char = readChar();
				if (StringTools.isEof(char))
					break;
			}
			this.char = char;
			return token();
		}
		if (c == '*'.code) {/* comment */
			var old = line;
			if (op == "/**/") {
				this.char = char;
				return token();
			}
			while (true) {
				while (char != '*'.code) {
					if (char == '\n'.code) {
						columnOffset = currentPos;
						line++;
					}
					char = readChar();
					if (StringTools.isEof(char)) {
						line = old;
						error(EUnterminatedComment, tokenMin, tokenMin);
						break;
					}
				}
				char = readChar();
				if (StringTools.isEof(char)) {
					line = old;
					error(EUnterminatedComment, tokenMin, tokenMin);
					break;
				}
				if (char == '/'.code)
					break;
			}
			return token();
		}
		this.char = char;
		return TOp(op);
	}

	function constString(c) {
		return switch (c) {
			case CInt(v): Std.string(v);
			case CFloat(f): Std.string(f);
			case CString(s): s; // TODO : escape + quote
			case CReg(p, m): '~/$p/$m';
		}
	}

	function tokenString(t) {
		return switch (t) {
			case TEof: "<eof>";
			case TConst(c): constString(c);
			case TId(s): s;
			case TOp(s): s;
			case TPOpen: "(";
			case TPClose: ")";
			case TBrOpen: "{";
			case TBrClose: "}";
			case TDot: ".";
			case TQuestionDot: "?.";
			case TComma: ",";
			case TSemicolon: ";";
			case TBkOpen: "[";
			case TBkClose: "]";
			case TQuestion: "?";
			case TDoubleDot: ":";
			case TMeta(id): "@" + id;
			case TPrepro(id): "#" + id;
		}
	}
}
