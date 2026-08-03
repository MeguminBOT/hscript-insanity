package hxscript.compile;

#if hxscript_cppia
import haxe.ds.StringMap;
import haxe.io.Bytes;
import hxscript.syntax.Expr;

/**
 * Turns hxscript's syntax tree into a cppia module.
 *
 * cppia resolves names when the module links, so `emitIdent` must place each one as a local, a field
 * of the enclosing class, or a type; anything else throws `CppiaUnsupported` rather than being
 * guessed at. An unknown TYPE is not a refusal -- it is emitted as `Dynamic`, costing dispatch speed
 * for that expression alone.
 */
class CppiaEmitter {
	/** Names that resolve to a type without an import. Anything else must be imported or declared. */
	static var BUILTIN_TYPES:Array<String> = [
		'Array',
		'Bool',
		'Date',
		'DateTools',
		'Dynamic',
		'EReg',
		'Float',
		'Int',
		'Lambda',
		'Math',
		'Reflect',
		'Std',
		'String',
		'StringBuf',
		'StringTools',
		'Sys',
		'Type',
		'Xml'
	];

	/** Binary operators that map straight through to a cppia token of the same spelling. */
	static var BINOPS:Array<String> = [
		'+', '-', '*', '/', '%', '&', '|', '^', '<<', '>>', '>>>', '==', '!=', '>=', '<=', '>', '<', '&&', '||'
	];

	/** Compound assignments, which cppia spells the same way but reads as a `SetExpr`. */
	static var ASSIGN_OPS:Array<String> = ['+=', '-=', '*=', '/=', '&=', '|=', '^=', '<<=', '>>=', '>>>='];

	var w:CppiaWriter;
	var classCount:Int;
	var nextVarId:Int;

	var scopes:Array<StringMap<Int>>;
	var typePaths:StringMap<String>;
	var moduleClasses:StringMap<Bool>;

	var currentClass:String;
	var currentSuper:String;
	var members:StringMap<Bool>;
	var statics:StringMap<Bool>;

	/** Constructor names of every enum this batch declares, by full type path. */
	var enumCtors:StringMap<StringMap<Bool>>;

	public function new() {
		w = new CppiaWriter();
		classCount = 0;
		nextVarId = 1;
		scopes = [];
		typePaths = new StringMap();
		moduleClasses = new StringMap();
		members = new StringMap();
		statics = new StringMap();
		enumCtors = new StringMap();
		currentClass = '';
		currentSuper = '';

		for (name in BUILTIN_TYPES)
			typePaths.set(name, name);
	}

	/**
	 * Records the types a module declares and imports, without emitting anything. Every module must
	 * be declared before any is emitted.
	 *
	 * @param decls The module's declarations.
	 */
	public function declare(decls:Array<ModuleDecl>):Void {
		var pack:String = '';

		for (decl in decls) {
			switch (decl.d) {
				case DPackage(path):
					pack = path.join('.');
				case DImport(path, mode):
					var full:String = path.join('.');
					var short:String = switch (mode) {
						case IAsName(alias): alias;
						case _: path[path.length - 1];
					}
					typePaths.set(short, full);
				case DClass(c) | DInterface(c):
					var full:String = pack.length > 0 ? pack + '.' + c.name : c.name;
					typePaths.set(c.name, full);
					moduleClasses.set(full, true);
				case DEnum(en):
					var full:String = pack.length > 0 ? pack + '.' + en.name : en.name;
					typePaths.set(en.name, full);
					moduleClasses.set(full, true);

					var ctors:StringMap<Bool> = new StringMap();
					for (name in en.names)
						ctors.set(name, true);
					enumCtors.set(full, ctors);
				case _:
			}
		}
	}

	/**
	 * Emits every type a module declares.
	 *
	 * @param decls The module's declarations.
	 * @throws CppiaUnsupported If any declaration has no cppia spelling.
	 */
	public function emit(decls:Array<ModuleDecl>):Void {
		var pack:String = '';

		for (decl in decls) {
			switch (decl.d) {
				case DPackage(path):
					pack = path.join('.');
				case DClass(c):
					emitClass(c, pack, false, decl.pos);
				case DInterface(c):
					emitClass(c, pack, true, decl.pos);
				case DImport(_, _) | DUsing(_):
				case DEnum(en):
					emitEnum(en, pack);
				case DAbstract(_):
					throw new CppiaUnsupported('abstract declarations', decl.pos);
				case DTypedef(_):
				case DField(_):
					throw new CppiaUnsupported('module-level fields', decl.pos);
			}
		}
	}

	/** Assembles the finished module. */
	public function finish():Bytes {
		w.token('NOMAIN');
		w.newline();
		w.token('RESOURCES');
		w.int(0);
		w.newline();
		return w.finish(classCount);
	}

	/**
	 * Emits an enum declaration. Unlike a class record, no super type or interface list is written
	 * and the fields are constructors rather than `FUNCTION`/`VAR` records.
	 *
	 * @param en The enum to emit.
	 * @param pack Its package, or the empty string.
	 */
	function emitEnum(en:EnumDecl, pack:String):Void {
		var full:String = pack.length > 0 ? pack + '.' + en.name : en.name;

		w.newline();
		w.token('ENUM');
		w.type(full);
		w.int(en.names.length);

		for (name in en.names) {
			var ctor:EnumFieldDecl = en.constructs.get(name);
			var args:Array<Argument> = ctor.arguments == null ? [] : ctor.arguments;

			w.str(name);
			w.int(args.length);
			for (a in args) {
				w.str(a.name);
				w.type(a.t == null ? '' : typeName(a.t));
			}
		}

		w.bool(false);
		w.newline();

		classCount++;
	}

	function emitClass(c:ClassDecl, pack:String, isInterface:Bool, pos:Position):Void {
		var full:String = pack.length > 0 ? pack + '.' + c.name : c.name;

		currentClass = full;
		currentSuper = c.extend == null ? '' : typeName(c.extend);
		members = new StringMap();
		statics = new StringMap();

		for (f in c.fields) {
			if (hasAccess(f, AStatic))
				statics.set(f.name, true);
			else
				members.set(f.name, true);
		}

		w.newline();
		w.token(isInterface ? 'INTERFACE' : 'CLASS');
		w.type(full);
		w.type(currentSuper);
		w.int(c.implement.length);
		for (i in c.implement)
			w.type(typeName(i));
		w.int(c.fields.length);
		w.newline();

		for (f in c.fields)
			emitField(f, isInterface, pos);

		classCount++;
	}

	function emitField(f:FieldDecl, isInterface:Bool, pos:Position):Void {
		var isStatic:Bool = hasAccess(f, AStatic);

		switch (f.kind) {
			case KFunction(fn):
				w.token('FUNCTION');
				w.bool(isStatic);
				w.bool(hasAccess(f, ADynamic));
				w.str(f.name);
				w.type(fn.ret == null ? '' : typeName(fn.ret));
				w.int(fn.args.length);
				for (a in fn.args) {
					w.str(a.name);
					w.bool(a.opt == true || a.value != null);
					w.type(a.t == null ? '' : typeName(a.t));
				}

				if (!isInterface)
					emitFunctionBody(fn, f.name == 'new', pos);
				w.newline();

			case KVar(v):
				if (v.get != null && v.get != 'default' && v.get != 'null')
					throw new CppiaUnsupported('property accessors', pos);
				if (v.set != null && v.set != 'default' && v.set != 'null')
					throw new CppiaUnsupported('property accessors', pos);

				w.token('VAR');
				w.bool(isStatic);
				w.token('N');
				w.token('N');
				w.bool(false);
				w.str(f.name);
				w.type(v.type == null ? '' : typeName(v.type));

				if (v.expr == null) {
					w.int(0);
				} else {
					w.int(1);
					pushScope();
					expr(v.expr);
					popScope();
				}
				w.newline();
		}
	}

	function emitFunctionBody(fn:FunctionDecl, isConstructor:Bool, pos:Position):Void {
		emitFun(fn.args, fn.expr, fn.ret, pos);
	}

	/**
	 * Emits a `FUN` expression: the signature in stack-variable form, then the body. Used for both
	 * methods and function values.
	 *
	 * Captures are left to the loader, which walks the enclosing stack layout; this only has to nest
	 * and to keep variable ids unique. Default argument values become null-checks prepended to the
	 * body, since cppia accepts only constants in the signature.
	 *
	 * @param args The function's arguments.
	 * @param body Its body.
	 * @param ret Its return type, if annotated.
	 * @param pos Where it was declared.
	 */
	function emitFun(args:Array<Argument>, body:Expr, ret:Null<CType>, pos:Position):Void {
		pushScope();

		w.pos(pos == null ? 0 : pos.line);
		w.token('FUN');
		w.type(ret == null ? '' : typeName(ret));
		w.int(args.length);

		for (a in args) {
			if (a.rest == true)
				throw new CppiaUnsupported('rest arguments', pos);

			var id:Int = declareVar(a.name);

			w.str(a.name);
			w.int(id);
			w.bool(false);
			w.type(a.t == null ? '' : typeName(a.t));
			w.bool(false);
		}

		var prologue:Array<Expr> = [];
		for (a in args) {
			if (a.value != null) {
				var target:Expr = {e: EIdent(a.name), pos: pos};
				var isNull:Expr = {e: EBinop('==', target, {e: EIdent('null'), pos: pos}), pos: pos};
				var assign:Expr = {e: EBinop('=', target, a.value), pos: pos};
				prologue.push({e: EIf(isNull, assign, null), pos: pos});
			}
		}

		var boxedBody:Expr = body;
		var boxing = CppiaCapture.transform(args, {e: EBlock(prologue.concat([body])), pos: pos});
		boxedBody = boxing.body;

		var entry:Array<Expr> = [];
		for (name in boxing.boxedArgs) {
			var ident:Expr = {e: EIdent(name), pos: pos};
			entry.push({e: EBinop('=', ident, {e: EArrayDecl([ident]), pos: pos}), pos: pos});
		}

		if (entry.length == 0)
			expr(boxedBody);
		else
			expr({e: EBlock(entry.concat([boxedBody])), pos: pos});

		popScope();
	}

	function expr(e:Expr):Void {
		if (e == null) {
			w.pos(0);
			w.token('NULL');
			return;
		}

		var line:Int = e.pos == null ? 0 : e.pos.line;

		switch (e.e) {
			case EConst(c):
				w.pos(line);
				switch (c) {
					case CInt(v):
						w.token('i');
						w.int(v);
					case CFloat(f):
						w.token('f');
						w.str(Std.string(f));
					case CString(s, interp):
						if (interp == true && s.indexOf('$') >= 0)
							throw new CppiaUnsupported('string interpolation', e.pos);
						w.token('s');
						w.str(s);
					case CReg(_, _):
						throw new CppiaUnsupported('regex literals', e.pos);
				}

			case EIdent(v):
				emitIdent(v, e.pos);

			case EParent(inner):
				expr(inner);

			case EBlock(list):
				w.pos(line);
				w.token('BLOCK');
				pushScope();
				emitBlockBody(list, e.pos);
				popScope();

			case EVar(_, _, _, _, _, _):
				w.pos(line);
				w.token('BLOCK');
				emitBlockBody([e], e.pos);

			case EIf(cond, e1, e2):
				w.pos(line);
				if (e2 == null) {
					w.token('IF');
					expr(cond);
					expr(e1);
				} else {
					w.token('IFELSE');
					expr(cond);
					expr(e1);
					expr(e2);
				}

			case ETernary(cond, e1, e2):
				w.pos(line);
				w.token('IFELSE');
				expr(cond);
				expr(e1);
				expr(e2);

			case EWhile(cond, body):
				w.pos(line);
				w.token('WHILE');
				w.int(1);
				expr(cond);
				expr(body);

			case EDoWhile(cond, body):
				w.pos(line);
				w.token('WHILE');
				w.int(0);
				expr(cond);
				expr(body);

			case EFor(v, it, body):
				switch (it.e) {
					case EBinop('...', _, _):
						w.pos(line);
						w.token('FOR');
						pushScope();
						var id:Int = declareVar(v);
						w.str(v);
						w.int(id);
						w.bool(false);
						w.unknownType();
						emitIterable(it);
						expr(body);
						popScope();
					case _:
						emitForIn(v, it, body, e.pos);
				}

			case EForGen(_, _):
				throw new CppiaUnsupported('key-value for loops', e.pos);

			case EBreak:
				w.pos(line);
				w.token('BREAK');

			case EContinue:
				w.pos(line);
				w.token('CONTINUE');

			case EReturn(v):
				w.pos(line);
				if (v == null) {
					w.token('RETURN');
				} else {
					w.token('RETVAL');
					w.type('');
					expr(v);
				}

			case EThrow(v):
				w.pos(line);
				w.token('THROW');
				expr(v);

			case EBinop(op, e1, e2):
				emitBinop(op, e1, e2, e.pos);

			case EUnop(op, prefix, inner):
				w.pos(line);
				switch (op) {
					case '-':
						w.token('NEG');
					case '!':
						w.token('!');
					case '~':
						w.token('~');
					case '++':
						w.token(prefix ? '++' : '+++');
					case '--':
						w.token(prefix ? '--' : '---');
					default:
						throw new CppiaUnsupported('unary operator ' + op, e.pos);
				}
				expr(inner);

			case ECall(callee, params):
				emitCall(callee, params, e.pos);

			case EField(obj, f, maybe):
				if (maybe == true)
					throw new CppiaUnsupported('null-safe field access', e.pos);
				emitField2(obj, f, e.pos);

			case EArray(arr, index):
				w.pos(line);
				w.token('ARRAYI');
				w.type('Array');
				expr(arr);
				expr(index);

			case EArrayDecl(items):
				for (item in items) {
					switch (item.e) {
						case EBinop('=>', _, _):
							throw new CppiaUnsupported('map literals', e.pos);
						case _:
					}
				}
				w.pos(line);
				w.token('ADEF');
				w.type('Array');
				w.int(items.length);
				for (item in items)
					expr(item);

			case ENew(cl, params):
				w.pos(line);
				w.token('NEW');
				w.type(resolveType(cl, e.pos));
				w.int(params.length);
				for (p in params)
					expr(p);

			case EObject(fields):
				w.pos(line);
				w.token('OBJDEF');
				w.int(fields.length);
				for (f in fields)
					w.str(f.name);
				for (f in fields)
					expr(f.e);

			case ETry(body, v, _, ecatch, extra):
				if (extra != null && extra.length > 0)
					throw new CppiaUnsupported('multiple catch clauses', e.pos);

				w.pos(line);
				w.token('TRY');
				w.int(1);
				expr(body);

				pushScope();
				var id:Int = declareVar(v);
				w.str(v);
				w.int(id);
				w.bool(false);
				w.type('');
				expr(ecatch);
				popScope();

			case ESwitch(cond, cases, defaultExpr):
				emitSwitch(cond, cases, defaultExpr, e.pos);

			case ECast(inner, _):
				w.pos(line);
				w.token('CAST');
				expr(inner);

			case ECheckType(inner, _):
				expr(inner);

			case EMeta(_, _, inner):
				expr(inner);

			case EFunction(args, body, _, ret, _):
				emitFun(args, body, ret, e.pos);

			case EDecl(_):
				throw new CppiaUnsupported('inline type declarations', e.pos);

			case EImport(_, _) | EUsing(_):
				w.pos(line);
				w.token('NULL');
		}
	}

	/**
	 * Emits a block's contents, folding each `var` into the `TVARS` record cppia expects. Ids are
	 * taken in order and initialisers stay where they were written.
	 *
	 * @param list The block's expressions.
	 * @param pos Where the block starts.
	 */
	function emitBlockBody(list:Array<Expr>, pos:Position):Void {
		var out:Array<Expr> = [];
		for (item in list)
			out.push(item);

		w.int(out.length);
		w.newline();

		for (item in out) {
			switch (item.e) {
				case EFunction(fargs, fbody, fname, fret, _) if (fname != null):
					w.pos(item.pos == null ? 0 : item.pos.line);
					w.token('TVARS');
					w.int(1);

					var id:Int = declareVar(fname);
					w.token('VARDECLI');
					w.str(fname);
					w.int(id);
					w.bool(false);
					w.unknownType();
					w.unknownType();
					emitFun(fargs, fbody, fret, item.pos);
					w.newline();

				case EVar(n, t, init, get, set, _):
					if (get != null || set != null)
						throw new CppiaUnsupported('local property accessors', item.pos);

					w.pos(item.pos == null ? 0 : item.pos.line);
					w.token('TVARS');
					w.int(1);

					var id:Int = declareVar(n);
					if (init == null) {
						w.token('VARDECL');
						w.str(n);
						w.int(id);
						w.bool(false);
						w.type(t == null ? '' : typeName(t));
					} else {
						w.token('VARDECLI');
						w.str(n);
						w.int(id);
						w.bool(false);
						w.type(t == null ? '' : typeName(t));
						w.type('');
						expr(init);
					}
					w.newline();

				case _:
					expr(item);
					w.newline();
			}
		}
	}

	/**
	 * Emits the subject of a `for`, lowering a `...` range to an `IntIterator` since cppia has no
	 * interval expression.
	 *
	 * @param it The iterable expression.
	 */
	function emitIterable(it:Expr):Void {
		switch (it.e) {
			case EBinop('...', low, high):
				w.pos(it.pos == null ? 0 : it.pos.line);
				w.token('NEW');
				w.type('IntIterator');
				w.int(2);
				expr(low);
				expr(high);
			case _:
				expr(it);
		}
	}

	/**
	 * Emits a `for` over something other than a range.
	 *
	 * cppia's loop requires a real iterator, so the subject is bound to a temporary and tested once
	 * per loop for a `hasNext` field, falling back to `iterator()`.
	 *
	 * @param v The loop variable name.
	 * @param it The iterable expression.
	 * @param body The loop body.
	 * @param pos Where the loop starts.
	 */
	function emitForIn(v:String, it:Expr, body:Expr, pos:Position):Void {
		var tmp:String = '`for' + (nextVarId++);
		var subject:Expr = {e: EIdent(tmp), pos: pos};

		var probe:Expr = {
			e: ECall({e: EField({e: EIdent('Reflect'), pos: pos}, 'field'), pos: pos}, [subject, {e: EConst(CString('hasNext')), pos: pos}]),
			pos: pos
		};
		var isIterator:Expr = {e: EBinop('!=', probe, {e: EIdent('null'), pos: pos}), pos: pos};
		var asIterator:Expr = {e: ECall({e: EField(subject, 'iterator'), pos: pos}, []), pos: pos};
		var chosen:Expr = {e: ETernary(isIterator, subject, asIterator), pos: pos};

		w.pos(pos == null ? 0 : pos.line);
		w.token('BLOCK');
		pushScope();
		w.int(2);
		w.newline();

		w.pos(pos == null ? 0 : pos.line);
		w.token('TVARS');
		w.int(1);
		var tmpId:Int = declareVar(tmp);
		w.token('VARDECLI');
		w.str(tmp);
		w.int(tmpId);
		w.bool(false);
		w.unknownType();
		w.unknownType();
		expr(it);
		w.newline();

		w.pos(pos == null ? 0 : pos.line);
		w.token('FOR');
		var id:Int = declareVar(v);
		w.str(v);
		w.int(id);
		w.bool(false);
		w.unknownType();
		expr(chosen);
		expr(body);
		w.newline();

		popScope();
	}

	function emitBinop(op:String, e1:Expr, e2:Expr, pos:Position):Void {
		var line:Int = pos == null ? 0 : pos.line;

		if (op == '=') {
			w.pos(line);
			w.token('SET');
			expr(e1);
			expr(e2);
			return;
		}

		if (ASSIGN_OPS.indexOf(op) >= 0) {
			w.pos(line);
			w.token(op);
			expr(e1);
			expr(e2);
			return;
		}

		if (BINOPS.indexOf(op) >= 0) {
			w.pos(line);
			w.token(op);
			expr(e1);
			expr(e2);
			return;
		}

		if (op == '...')
			throw new CppiaUnsupported('interval operator outside a for loop', pos);

		throw new CppiaUnsupported('operator ' + op, pos);
	}

	function emitSwitch(cond:Expr, cases:Array<{values:Array<Expr>, expr:Expr, ?guard:Expr}>, defaultExpr:Null<Expr>, pos:Position):Void {
		for (c in cases) {
			if (c.guard != null)
				throw new CppiaUnsupported('case guards', pos);
			for (v in c.values) {
				switch (v.e) {
					case EConst(_) | EIdent(_) | EField(_, _, _):
					case _:
						throw new CppiaUnsupported('pattern matching in switch', pos);
				}
			}
		}

		w.pos(pos == null ? 0 : pos.line);
		w.token('SWITCH');
		w.int(cases.length);
		w.int(defaultExpr == null ? 0 : 1);
		expr(cond);

		for (c in cases) {
			w.int(c.values.length);
			for (v in c.values)
				expr(v);
			expr(c.expr);
		}

		if (defaultExpr != null)
			expr(defaultExpr);
	}

	function emitCall(callee:Expr, params:Array<Expr>, pos:Position):Void {
		var line:Int = pos == null ? 0 : pos.line;

		switch (callee.e) {
			case EField(obj, name, maybe):
				if (maybe == true)
					throw new CppiaUnsupported('null-safe calls', pos);

				var asType:Null<String> = typeOf(obj);
				if (asType != null) {
					if (isEnumCtor(asType, name)) {
						w.pos(line);
						w.token('CREATEENUM');
						w.type(asType);
						w.str(name);
						w.int(params.length);
						for (p in params)
							expr(p);
						return;
					}

					w.pos(line);
					w.token('CALLSTATIC');
					w.type(asType);
					w.str(name);
					w.int(params.length);
					for (p in params)
						expr(p);
					return;
				}

				switch (obj.e) {
					case EIdent('super'):
						w.pos(line);
						w.token('CALLSUPER');
						w.type(currentSuper);
						w.str(name);
						w.int(params.length);
						for (p in params)
							expr(p);
						return;
					case _:
				}

				w.pos(line);
				w.token('CALLMEMBER');
				w.type('');
				w.str(name);
				w.int(params.length);
				expr(obj);
				for (p in params)
					expr(p);

			case EIdent('super'):
				w.pos(line);
				w.token('CALLSUPERNEW');
				w.type(currentSuper);
				w.int(params.length);
				for (p in params)
					expr(p);

			case EIdent(name) if (lookupVar(name) == null && members.exists(name)):
				w.pos(line);
				w.token('CALLTHIS');
				w.type(currentClass);
				w.str(name);
				w.int(params.length);
				for (p in params)
					expr(p);

			case EIdent(name) if (lookupVar(name) == null && statics.exists(name)):
				w.pos(line);
				w.token('CALLSTATIC');
				w.type(currentClass);
				w.str(name);
				w.int(params.length);
				for (p in params)
					expr(p);

			case _:
				w.pos(line);
				w.token('CALL');
				w.int(params.length);
				expr(callee);
				for (p in params)
					expr(p);
		}
	}

	function emitField2(obj:Expr, name:String, pos:Position):Void {
		var line:Int = pos == null ? 0 : pos.line;

		var asType:Null<String> = typeOf(obj);
		if (asType != null) {
			if (isEnumCtor(asType, name)) {
				w.pos(line);
				w.token('FENUM');
				w.type(asType);
				w.str(name);
				return;
			}

			w.pos(line);
			w.token('FSTATIC');
			w.type(asType);
			w.str(name);
			return;
		}

		w.pos(line);
		w.token('FNAME');
		w.type('');
		w.str(name);
		expr(obj);
	}

	function emitIdent(v:String, pos:Position):Void {
		var line:Int = pos == null ? 0 : pos.line;

		switch (v) {
			case 'true':
				w.pos(line);
				w.token('true');
				return;
			case 'false':
				w.pos(line);
				w.token('false');
				return;
			case 'null':
				w.pos(line);
				w.token('NULL');
				return;
			case 'this':
				w.pos(line);
				w.token('THIS');
				return;
			default:
		}

		var local:Null<Int> = lookupVar(v);
		if (local != null) {
			w.pos(line);
			w.token('VAR');
			w.int(local);
			return;
		}

		if (members.exists(v)) {
			w.pos(line);
			w.token('FTHISNAME');
			w.type(currentClass);
			w.str(v);
			return;
		}

		if (statics.exists(v)) {
			w.pos(line);
			w.token('FSTATIC');
			w.type(currentClass);
			w.str(v);
			return;
		}

		if (typePaths.exists(v)) {
			w.pos(line);
			w.token('CLASSOF');
			w.type(typePaths.get(v));
			return;
		}

		throw new CppiaUnsupported('unresolved identifier ' + v, pos);
	}

	/** Whether a name is a constructor of an enum this batch declares. */
	function isEnumCtor(path:String, name:String):Bool {
		var ctors:Null<StringMap<Bool>> = enumCtors.get(path);
		return ctors != null && ctors.exists(name);
	}

	/** The type an expression names, when it names one rather than producing a value. */
	function typeOf(e:Expr):Null<String> {
		switch (e.e) {
			case EIdent(v):
				if (lookupVar(v) != null || members.exists(v) || statics.exists(v))
					return null;
				if (typePaths.exists(v))
					return typePaths.get(v);
				return null;

			case EField(_, _, _):
				var path:Null<String> = dottedPath(e);
				if (path != null && moduleClasses.exists(path))
					return path;
				return null;

			case _:
				return null;
		}
	}

	/** The dotted name a field-access chain spells, or null if anything in it is not a plain name. */
	function dottedPath(e:Expr):Null<String> {
		switch (e.e) {
			case EIdent(v):
				return v;
			case EField(obj, f, maybe):
				if (maybe == true)
					return null;
				var head:Null<String> = dottedPath(obj);
				return head == null ? null : head + '.' + f;
			case _:
				return null;
		}
	}

	function resolveType(name:String, pos:Position):String {
		if (typePaths.exists(name))
			return typePaths.get(name);
		if (name.indexOf('.') >= 0)
			return name;
		throw new CppiaUnsupported('unresolved type ' + name, pos);
	}

	/** The dotted path a type annotation names, or the empty string when it is not a plain path. */
	function typeName(t:CType):String {
		switch (t) {
			case CTPath(path, _):
				var joined:String = path.join('.');
				if (path.length == 1 && typePaths.exists(joined))
					return typePaths.get(joined);
				return joined;
			case CTParent(inner):
				return typeName(inner);
			case CTOpt(inner):
				return typeName(inner);
			case CTNamed(_, inner):
				return typeName(inner);
			case _:
				return '';
		}
	}

	inline function hasAccess(f:FieldDecl, a:FieldAccess):Bool {
		return f.access.indexOf(a) >= 0;
	}

	inline function pushScope():Void {
		scopes.push(new StringMap());
	}

	inline function popScope():Void {
		scopes.pop();
	}

	function declareVar(name:String):Int {
		var id:Int = nextVarId++;
		if (scopes.length == 0)
			pushScope();
		scopes[scopes.length - 1].set(name, id);
		return id;
	}

	function lookupVar(name:String):Null<Int> {
		var i:Int = scopes.length - 1;
		while (i >= 0) {
			var found:Null<Int> = scopes[i].get(name);
			if (found != null)
				return found;
			i--;
		}
		return null;
	}
}
#end
