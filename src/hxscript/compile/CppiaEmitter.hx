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
		'IntIterator',
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
	var scopeTypes:Array<StringMap<String>>;
	var typePaths:StringMap<String>;
	var moduleClasses:StringMap<Bool>;

	/**
	 * Plain instance variables of every class in the batch, by class path then field name, holding
	 * each field's declared type or the empty string when it had none.
	 *
	 * Only fields that are plain variables are here. A field with a `get` or `set` accessor is left
	 * out on purpose: reaching it directly would read the storage behind the property and skip the
	 * accessor that gives it its meaning.
	 */
	var classVars:StringMap<StringMap<String>>;

	/**
	 * The array type the next literal should be built as, or null for an untyped one.
	 *
	 * An array literal has nothing in it to say what it holds, so it was always built as the loose
	 * kind. That is fine until something reads it back through an annotation promising a specific
	 * kind, because the read trusts the annotation and reinterprets the memory -- which crashes rather
	 * than misbehaves. Carrying the target's type to the literal keeps the two descriptions of the
	 * same array in agreement.
	 */
	var expectedArray:Null<String> = null;

	var currentClass:String;
	var currentSuper:String;
	var members:StringMap<Bool>;
	var statics:StringMap<Bool>;
	var memberTypes:StringMap<String>;
	var staticTypes:StringMap<String>;

	/** Constructor names of every enum this batch declares, by full type path. */
	var enumCtors:StringMap<StringMap<Bool>>;

	/** Assignments for the current class's member field initialisers. */
	var memberInits:Array<Expr>;

	/** Top-level field names, mapped to the synthetic class holding them. */
	var moduleFields:StringMap<String>;

	/** Classes from this batch that the emitted code names. */
	var refs:Array<String>;

	/** Scripted classes the host has elsewhere, which this batch cannot reach. */
	var external:StringMap<Bool>;

	/** Bare names the host answers with a static of its own, as `owner::field`. */
	var ambientMembers:StringMap<String>;

	/**
	 * Static properties declared in this batch, as `class.field`, split by which accessor they have.
	 *
	 * A static read links straight to the storage slot, so unlike a member property the accessor is
	 * never consulted and has to be called outright.
	 */
	var staticGetters:StringMap<Bool>;

	var staticSetters:StringMap<Bool>;

	public function new() {
		w = new CppiaWriter();
		classCount = 0;
		nextVarId = 1;
		scopes = [];
		scopeTypes = [];
		typePaths = new StringMap();
		moduleClasses = new StringMap();
		classVars = new StringMap();
		members = new StringMap();
		statics = new StringMap();
		memberTypes = new StringMap();
		staticTypes = new StringMap();
		enumCtors = new StringMap();
		staticGetters = new StringMap();
		staticSetters = new StringMap();
		moduleFields = new StringMap();
		memberInits = [];
		refs = [];
		external = new StringMap();
		ambientMembers = new StringMap();
		currentClass = '';
		currentSuper = '';

		for (name in BUILTIN_TYPES)
			typePaths.set(name, name);
	}

	/**
	 * Registers types the host makes available to every script without an import.
	 *
	 * A script written against those names has no `DImport` to resolve them by, so without this the
	 * emitter cannot place them and refuses the module.
	 *
	 * @param paths Full type paths, each registered under its last segment. An entry written
	 *        `Name=full.path` registers under `Name` instead, for a host that binds a type to a name
	 *        of its own choosing.
	 */
	public function ambient(paths:Array<String>):Void {
		for (entry in paths) {
			var short:String;
			var path:String;

			var equals:Int = entry.indexOf('=');
			if (equals >= 0) {
				short = entry.substr(0, equals);
				path = entry.substr(equals + 1);
			} else {
				path = entry;
				var dot:Int = path.lastIndexOf('.');
				short = dot < 0 ? path : path.substr(dot + 1);
			}

			if (!typePaths.exists(short))
				typePaths.set(short, path);
		}
	}

	/**
	 * Records the types a module declares and imports, without emitting anything. Every module must
	 * be declared before any is emitted.
	 *
	 * @param decls The module's declarations.
	 */
	public function declare(decls:Array<ModuleDecl>, moduleName:String = null):Void {
		var pack:String = '';

		for (decl in decls) {
			switch (decl.d) {
				case DField(m):
					var owner:String = fieldsClass(decls, moduleName);
					moduleFields.set(m.name, owner);
					switch (m.kind) {
						case KVar(v):
							if (v.get == 'get' || v.get == 'dynamic')
								staticGetters.set(owner + '.' + m.name, true);
							if (v.set == 'set' || v.set == 'dynamic') staticSetters.set(owner + '.' + m.name, true);
						case _:
					}
				case _:
			}
		}

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

					var vars:StringMap<String> = new StringMap();
					for (f in c.fields) {
						if (hasAccess(f, AStatic))
							continue;
						switch (f.kind) {
							case KVar(v) if (plainAccess(v.get) && plainAccess(v.set)):
								vars.set(f.name, v.type == null ? '' : typeName(v.type));
							case _:
						}
					}
					classVars.set(full, vars);

					for (f in c.fields) {
						if (!hasAccess(f, AStatic))
							continue;
						switch (f.kind) {
							case KVar(v):
								if (v.get == 'get' || v.get == 'dynamic')
									staticGetters.set(full + '.' + f.name, true);
								if (v.set == 'set' || v.set == 'dynamic') staticSetters.set(full + '.' + f.name, true);
							case _:
						}
					}
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
	public function emit(decls:Array<ModuleDecl>, moduleName:String = null):Void {
		emitModuleFields(decls, moduleName);

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
			}
		}
	}

	/**
	 * The synthetic class a module's top-level fields become statics of, matching the interpreter's
	 * own `<name>_Fields_` convention.
	 *
	 * @param decls The module's declarations, read for its package.
	 * @param moduleName The module's name.
	 * @return The class path, or null when the module has no top-level fields to hold.
	 */
	function fieldsClass(decls:Array<ModuleDecl>, moduleName:String):String {
		var pack:String = '';
		for (decl in decls) {
			switch (decl.d) {
				case DPackage(path):
					pack = path.join('.');
				case _:
			}
		}

		var short:String = moduleName == null ? 'Module' : moduleName;
		var dot:Int = short.lastIndexOf('.');
		if (dot >= 0)
			short = short.substr(dot + 1);

		return (pack.length > 0 ? pack + '.' : '') + short + '_Fields_';
	}

	/**
	 * Emits a module's top-level fields as statics of one synthetic class.
	 *
	 * @param decls The module's declarations.
	 * @param moduleName The module's name.
	 */
	function emitModuleFields(decls:Array<ModuleDecl>, moduleName:String):Void {
		var fields:Array<FieldDecl> = [];
		var pos:Position = null;

		for (decl in decls) {
			switch (decl.d) {
				case DField(m):
					if (pos == null)
						pos = decl.pos;
					fields.push({
						name: m.name,
						meta: m.meta,
						kind: m.kind,
						access: m.isPrivate ? [AStatic, APrivate] : [AStatic, APublic]
					});
				case _:
			}
		}

		if (fields.length == 0)
			return;

		emitClass({
			name: fieldsClass(decls, moduleName),
			params: [],
			meta: [],
			isPrivate: false,
			extend: null,
			implement: [],
			fields: fields,
			isExtern: false
		}, '', false, pos);
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
		memberTypes = new StringMap();
		staticTypes = new StringMap();

		for (f in c.fields) {
			var declared:String = switch (f.kind) {
				case KVar(v): v.type == null ? null : typeName(v.type);
				case KFunction(fn): fn.ret == null ? null : typeName(fn.ret);
			}

			if (hasAccess(f, AStatic)) {
				statics.set(f.name, true);
				if (declared != null)
					staticTypes.set(f.name, declared);
			} else {
				members.set(f.name, true);
				if (declared != null)
					memberTypes.set(f.name, declared);
			}
		}

		memberInits = [];
		for (f in c.fields) {
			if (hasAccess(f, AStatic))
				continue;
			switch (f.kind) {
				case KVar(v) if (v.expr != null):
					var target:Expr = {e: EField({e: EIdent('this'), pos: pos}, f.name, false), pos: pos};
					memberInits.push({e: EBinop('=', target, v.expr), pos: pos});
				case _:
			}
		}

		w.newline();
		w.token(isInterface ? 'INTERFACE' : 'CLASS');
		w.type(full);
		useType(currentSuper);
		w.int(c.implement.length);
		for (i in c.implement)
			w.type(typeName(i));
		w.int(c.fields.length);
		w.newline();

		for (f in c.fields)
			emitField(f, isInterface, pos);

		classCount++;
	}

	/**
	 * Puts the class's member initialisers at the front of its constructor, after any `super` call.
	 *
	 * A member `VAR` record's initialiser is only run for statics, so a member field declared with a
	 * value would otherwise start zeroed.
	 *
	 * @param body The constructor body as written.
	 * @param pos Where the constructor is declared.
	 * @return The body with the initialisers prepended.
	 */
	function withMemberInits(body:Expr, pos:Position):Expr {
		if (memberInits.length == 0)
			return body;

		var out:Array<Expr> = [];
		var rest:Array<Expr> = switch (body.e) {
			case EBlock(list): list.copy();
			case _: [body];
		}

		if (rest.length > 0) {
			switch (rest[0].e) {
				case ECall({e: EIdent('super')}, _):
					out.push(rest.shift());
				case _:
			}
		}

		for (init in memberInits)
			out.push(init);
		for (item in rest)
			out.push(item);

		return {e: EBlock(out), pos: pos};
	}

	function emitField(f:FieldDecl, isInterface:Bool, pos:Position):Void {
		var isStatic:Bool = hasAccess(f, AStatic);

		switch (f.kind) {
			case KFunction(fn):
				var isConstructor:Bool = f.name == 'new';

				w.token('FUNCTION');
				w.bool(isStatic || isConstructor);
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
				w.token('VAR');
				w.bool(isStatic);
				w.token(accessCode(v.get, pos));
				w.token(accessCode(v.set, pos));
				w.bool(false);
				w.str(f.name);
				w.type(v.type == null ? '' : typeName(v.type));

				if (v.expr == null || !isStatic) {
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
		emitFun(fn.args, isConstructor ? withMemberInits(fn.expr, pos) : fn.expr, fn.ret, pos);
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

			var id:Int = declareVar(a.name, a.t == null ? null : typeName(a.t));

			w.str(a.name);
			w.int(id);
			w.bool(false);
			storableType(a.t == null ? '' : typeName(a.t));
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
		// The expected array type is meant for a literal standing directly where it was set, so
		// anything else consumes and discards it rather than letting it reach a nested literal that
		// has nothing to do with the target.
		if (e != null && !e.e.match(EArrayDecl(_)))
			expectedArray = null;

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
					case CString(s, _):
						w.token('s');
						w.str(s);
					case CReg(pattern, modifiers):
						w.token('NEW');
						w.type('EReg');
						w.int(2);
						w.pos(line);
						w.token('s');
						w.str(pattern);
						w.pos(line);
						w.token('s');
						w.str(modifiers == null ? '' : modifiers);
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
				expr(forAsWhile(v, it, body, e.pos));

			case EForGen(it, body):
				expr(keyValueLoop(it, body, e.pos));

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
				if (maybe == true) {
					expr(nullSafe(obj, function(safe:Expr):Expr {
						return {e: EField(safe, f, false), pos: e.pos};
					}, e.pos));
					return;
				}
				emitField2(obj, f, e.pos);

			case EArray(arr, index):
				var known:Null<String> = inferType(arr);
				w.pos(line);
				w.token('ARRAYI');
				w.type(known != null && known.substr(0, 5) == 'Array' ? known : 'Dynamic');
				expr(arr);
				expr(index);

			case EArrayDecl(items):
				if (items.length > 0 && items[0].e.match(EBinop('=>', _, _))) {
					expr(mapLiteral(items, e.pos));
					return;
				}
				var want:Null<String> = expectedArray;
				expectedArray = null;

				w.pos(line);
				w.token('ADEF');
				w.type(want == null ? 'Array' : want);
				w.int(items.length);
				for (item in items)
					expr(item);

			case ENew(cl, params):
				w.pos(line);
				w.token('NEW');
				useType(resolveType(cl, e.pos));
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

			case ETry(body, v, t, ecatch, extra):
				w.pos(line);
				w.token('TRY');
				w.int(1 + (extra == null ? 0 : extra.length));
				expr(body);

				emitCatch(v, t, ecatch);
				if (extra != null) {
					for (x in extra)
						emitCatch(x.v, x.t, x.expr);
				}

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

					var id:Int = declareVar(n, t == null ? null : typeName(t));
					if (init == null) {
						w.token('VARDECL');
						w.str(n);
						w.int(id);
						w.bool(false);
						storableType(t == null ? '' : typeName(t));
					} else {
						w.token('VARDECLI');
						w.str(n);
						w.int(id);
						w.bool(false);
						storableType(t == null ? '' : typeName(t));
						w.type('');
						expectedArray = elementArray(t == null ? null : typeName(t));
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
	 * Lowers a `for` into a `while` over an iterator.
	 *
	 * cppia's own loop expression has no JIT implementation: the base code generator traces the
	 * node's name and emits nothing, so with the JIT on the loop silently does not run at all. The
	 * Haxe compiler lowers `for` the same way and never produces one, which is why the gap goes
	 * unnoticed.
	 *
	 * The loop variable is declared inside the body so every pass rebinds it, which is what the loop
	 * expression did and what a closure made in the body expects.
	 *
	 * A range needs no iterator test; anything else is bound to a temporary and asked once whether it
	 * is already an iterator, since only a static type could answer that and there is none here.
	 *
	 * @param v The loop variable name.
	 * @param it The subject.
	 * @param body The loop body.
	 * @param pos Where the loop appears.
	 * @return An equivalent `while` loop.
	 */
	function forAsWhile(v:String, it:Expr, body:Expr, pos:Position):Expr {
		var outer:Array<Expr> = [];
		var name:String = tempName('it');
		var ref:Expr = {e: EIdent(name), pos: pos};

		switch (it.e) {
			case EBinop('...', low, high):
				outer.push({e: EVar(name, null, {e: ENew('IntIterator', [low, high]), pos: pos}, null, null, false), pos: pos});

			case _:
				var subject:String = tempName('sub');
				var subjectRef:Expr = {e: EIdent(subject), pos: pos};

				var probe:Expr = {
					e: ECall({e: EField({e: EIdent('Reflect'), pos: pos}, 'field'), pos: pos}, [subjectRef, {e: EConst(CString('hasNext')), pos: pos}]),
					pos: pos
				};
				var chosen:Expr = {
					e: ETernary({e: EBinop('!=', probe, {e: EIdent('null'), pos: pos}), pos: pos}, subjectRef,
						{e: ECall({e: EField(subjectRef, 'iterator'), pos: pos}, []), pos: pos}),
					pos: pos
				};

				outer.push({e: EVar(subject, null, it, null, null, false), pos: pos});
				outer.push({e: EVar(name, null, chosen, null, null, false), pos: pos});
		}

		var step:Expr = {e: ECall({e: EField(ref, 'next'), pos: pos}, []), pos: pos};
		var inner:Expr = {e: EBlock([{e: EVar(v, null, step, null, null, false), pos: pos}, body]), pos: pos};
		var test:Expr = {e: ECall({e: EField(ref, 'hasNext'), pos: pos}, []), pos: pos};

		outer.push({e: EWhile(test, inner), pos: pos});
		return {e: EBlock(outer), pos: pos};
	}

	function emitBinop(op:String, e1:Expr, e2:Expr, pos:Position):Void {
		var line:Int = pos == null ? 0 : pos.line;

		if (op == '=') {
			var setter:Null<String> = staticSetterFor(e1);
			if (setter != null) {
				w.pos(line);
				w.token('CALLSTATIC');
				w.type(setter.substr(0, setter.lastIndexOf('.')));
				w.str('set_' + setter.substr(setter.lastIndexOf('.') + 1));
				w.int(1);
				expr(e2);
				return;
			}

			w.pos(line);
			w.token('SET');
			expr(e1);
			expectedArray = elementArray(inferType(e1));
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

		if (op == '...') {
			w.pos(line);
			w.token('NEW');
			w.type('IntIterator');
			w.int(2);
			expr(e1);
			expr(e2);
			return;
		}

		throw new CppiaUnsupported('operator ' + op, pos);
	}

	function emitSwitch(cond:Expr, cases:Array<{values:Array<Expr>, expr:Expr, ?guard:Expr}>, defaultExpr:Null<Expr>, pos:Position):Void {
		for (c in cases) {
			if (c.guard != null || captureName(c) != null || destructure(c) != null) {
				expr(switchAsChain(cond, cases, defaultExpr, pos));
				return;
			}
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
				if (maybe == true) {
					expr(nullSafe(obj, function(safe:Expr):Expr {
						return {e: ECall({e: EField(safe, name, false), pos: pos}, params), pos: pos};
					}, pos));
					return;
				}

				var asType:Null<String> = typeOf(obj);
				if (asType != null) {
					if (isEnumCtor(asType, name)) {
						w.pos(line);
						w.token('CREATEENUM');
						useType(asType);
						w.str(name);
						w.int(params.length);
						for (p in params)
							expr(p);
						return;
					}

					if (!moduleClasses.exists(asType)) {
						w.pos(line);
						w.token('CALL');
						w.int(params.length);
						w.pos(line);
						w.token('FSTATIC');
						useType(asType);
						w.str(name);
						for (p in params)
							expr(p);
						return;
					}

					w.pos(line);
					w.token('CALLSTATIC');
					useType(asType);
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

			case EIdent(name) if (lookupVar(name) == null && moduleFields.exists(name)):
				w.pos(line);
				w.token('CALLSTATIC');
				w.type(moduleFields.get(name));
				w.str(name);
				w.int(params.length);
				for (p in params)
					expr(p);

			case EIdent(name) if (lookupVar(name) == null && ambientMembers.exists(name)):
				var target:String = ambientMembers.get(name);
				var split:Int = target.indexOf('::');

				w.pos(line);
				w.token('CALL');
				w.int(params.length);
				w.pos(line);
				w.token('FSTATIC');
				w.type(target.substr(0, split));
				w.str(target.substr(split + 2));
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
				useType(asType);
				w.str(name);
				return;
			}

			if (staticGetters.exists(asType + '.' + name)) {
				w.pos(line);
				w.token('CALLSTATIC');
				useType(asType);
				w.str('get_' + name);
				w.int(0);
				return;
			}

			w.pos(line);
			w.token('FSTATIC');
			useType(asType);
			w.str(name);
			return;
		}

		// A known class turns the access into an offset the loader resolves once, instead of a lookup
		// by name on every evaluation. That is the difference between a field read costing what
		// arithmetic costs and costing twenty-five times more, which is the whole cost of anything
		// shaped like a renderer.
		var holder:Null<String> = (obj.e.match(EIdent('this'))) ? currentClass : instanceClassOf(obj);
		if (holder != null && instanceVar(holder, name) != null) {
			w.pos(line);
			w.token('FLINK');
			w.type(holder);
			w.str(name);
			expr(obj);
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
			w.token(instanceVar(currentClass, v) != null ? 'FTHISINST' : 'FTHISNAME');
			w.type(currentClass);
			w.str(v);
			return;
		}

		if (statics.exists(v)) {
			if (staticGetters.exists(currentClass + '.' + v)) {
				w.pos(line);
				w.token('CALLSTATIC');
				w.type(currentClass);
				w.str('get_' + v);
				w.int(0);
				return;
			}

			w.pos(line);
			w.token('FSTATIC');
			w.type(currentClass);
			w.str(v);
			return;
		}

		if (moduleFields.exists(v)) {
			var owner:String = moduleFields.get(v);
			w.pos(line);

			if (staticGetters.exists(owner + '.' + v)) {
				w.token('CALLSTATIC');
				w.type(owner);
				w.str('get_' + v);
				w.int(0);
				return;
			}

			w.token('FSTATIC');
			w.type(owner);
			w.str(v);
			return;
		}

		if (typePaths.exists(v)) {
			w.pos(line);
			w.token('CLASSOF');
			w.type(typePaths.get(v));
			return;
		}

		if (emitAmbient(v, pos))
			return;

		if (currentSuper.length > 0) {
			w.pos(line);
			w.token('FNAME');
			w.unknownType();
			w.str(v);
			w.pos(line);
			w.token('THIS');
			return;
		}

		throw new CppiaUnsupported('unresolved identifier ' + v, pos);
	}

	/**
	 * Rewrites a switch as an if/else chain, which is how a guard is expressed: cppia's switch has no
	 * guard slot, and a case whose guard fails must fall through to later cases rather than to the
	 * default.
	 *
	 * @param cond The switch subject.
	 * @param cases Its cases.
	 * @param defaultExpr Its default branch, if any.
	 * @param pos Where the switch appears.
	 * @return A block evaluating to the same branch the switch would have taken.
	 */
	function switchAsChain(cond:Expr, cases:Array<{values:Array<Expr>, expr:Expr, ?guard:Expr}>, defaultExpr:Null<Expr>, pos:Position):Expr {
		var name:String = tempName('sw');
		var ref:Expr = {e: EIdent(name), pos: pos};

		var chain:Expr = defaultExpr;
		var i:Int = cases.length - 1;
		while (i >= 0) {
			var c = cases[i];
			var capture:Null<String> = captureName(c);
			var pattern = destructure(c);

			var body:Expr = c.expr;
			var test:Expr = null;

			if (pattern != null) {
				var bound:Array<Expr> = [];
				for (b in 0...pattern.binds.length) {
					var bind:String = pattern.binds[b];
					if (bind == '_')
						continue;

					var params:Expr = {
						e: ECall({e: EField({e: EIdent('Type'), pos: pos}, 'enumParameters'), pos: pos}, [ref]),
						pos: pos
					};
					var element:Expr = {e: EArray(params, {e: EConst(CInt(b)), pos: pos}), pos: pos};
					bound.push({e: EVar(bind, null, element, null, null, false), pos: pos});
				}

				bound.push(c.expr);
				body = {e: EBlock(bound), pos: pos};

				var ctor:Expr = {
					e: ECall({e: EField({e: EIdent('Type'), pos: pos}, 'enumConstructor'), pos: pos}, [ref]),
					pos: pos
				};
				test = {e: EBinop('==', ctor, {e: EConst(CString(pattern.name)), pos: pos}), pos: pos};
			} else if (capture != null) {
				body = {
					e: EBlock([{e: EVar(capture, null, ref, null, null, false), pos: pos}, c.expr]),
					pos: pos
				};
				test = {e: EIdent('true'), pos: pos};
			} else {
				for (v in c.values) {
					var eq:Expr = {e: EBinop('==', ref, v), pos: pos};
					test = test == null ? eq : {e: EBinop('||', test, eq), pos: pos};
				}
				if (test == null)
					test = {e: EIdent('true'), pos: pos};
			}

			if (c.guard != null) {
				var guard:Expr = c.guard;

				if (capture != null) {
					guard = CppiaCapture.substitute(guard, capture, ref);
				} else if (pattern != null) {
					for (b in 0...pattern.binds.length) {
						var bind:String = pattern.binds[b];
						if (bind == '_')
							continue;

						var params:Expr = {
							e: ECall({e: EField({e: EIdent('Type'), pos: pos}, 'enumParameters'), pos: pos}, [ref]),
							pos: pos
						};
						guard = CppiaCapture.substitute(guard, bind, {e: EArray(params, {e: EConst(CInt(b)), pos: pos}), pos: pos});
					}
				}

				test = capture != null ? {e: EParent(guard), pos: pos} : {
					e: EBinop('&&', {e: EParent(test), pos: pos}, {e: EParent(guard), pos: pos}),
					pos: pos
				};
			}

			chain = {e: EIf(test, body, chain), pos: pos};
			i--;
		}

		return {
			e: EBlock([{e: EVar(name, null, cond, null, null, false), pos: pos}, chain]),
			pos: pos
		};
	}

	/**
	 * The enum pattern a case destructures, when it does.
	 *
	 * @param c The case to inspect.
	 * @return The constructor name and the names it binds, or null when the case is not a pattern.
	 */
	function destructure(c:{values:Array<Expr>, expr:Expr, ?guard:Expr}):Null<{name:String, binds:Array<String>}> {
		for (v in c.values) {
			switch (v.e) {
				case ECall(callee, args):
					var name:String = switch (callee.e) {
						case EIdent(n): n;
						case EField(_, n, _): n;
						case _: null;
					}
					if (name == null)
						return null;

					var binds:Array<String> = [];
					for (a in args) {
						switch (a.e) {
							case EIdent(bind): binds.push(bind);
							case _: return null;
						}
					}
					return {name: name, binds: binds};
				case _:
			}
		}
		return null;
	}

	/**
	 * The name a case binds, when its pattern is a bare identifier rather than a value to match.
	 *
	 * hxscript treats any such identifier as a capture that always matches and rebinds, so it cannot
	 * be emitted as an equality test. `true`, `false` and `null` are literals, not captures.
	 *
	 * @param c The case to inspect.
	 * @return The bound name, or null when the case matches by value.
	 */
	function captureName(c:{values:Array<Expr>, expr:Expr, ?guard:Expr}):Null<String> {
		for (v in c.values) {
			switch (v.e) {
				case EIdent(name):
					if (name != 'true' && name != 'false' && name != 'null' && !typePaths.exists(name))
						return name;
				case _:
			}
		}
		return null;
	}

	/**
	 * Emits one catch clause. The loader picks the first whose declared type matches the thrown
	 * value, so an unannotated clause is written as `Dynamic` and catches everything.
	 *
	 * @param v The bound name.
	 * @param t Its declared type, if annotated.
	 * @param body The clause body.
	 */
	function emitCatch(v:String, t:Null<CType>, body:Expr):Void {
		pushScope();

		var declared:String = t == null ? '' : typeName(t);
		var id:Int = declareVar(v, declared);
		w.str(v);
		w.int(id);
		w.bool(false);
		w.type(declared);
		expr(body);

		popScope();
	}

	/**
	 * Wraps a `?.` access so the subject is evaluated once and only used when it is not null.
	 *
	 * @param obj The subject of the access.
	 * @param use Builds the access from the bound subject.
	 * @param pos Where the access appears.
	 * @return A block evaluating to the access, or to null.
	 */
	function nullSafe(obj:Expr, use:Expr->Expr, pos:Position):Expr {
		var name:String = tempName('safe');
		var ref:Expr = {e: EIdent(name), pos: pos};
		var isNull:Expr = {e: EBinop('==', ref, {e: EIdent('null'), pos: pos}), pos: pos};
		var guarded:Expr = {e: ETernary(isNull, {e: EIdent('null'), pos: pos}, use(ref)), pos: pos};

		return {
			e: EBlock([{e: EVar(name, null, obj, null, null, false), pos: pos}, guarded]),
			pos: pos
		};
	}

	/** A name no script can write, for a temporary the emitter introduces. */
	inline function tempName(prefix:String):String {
		return '`' + prefix + (nextVarId++);
	}

	/**
	 * Lowers a map literal into a block that builds the map and yields it.
	 *
	 * The concrete map is chosen from the key literals, falling back to `AnyMap`, which decides from
	 * the first key at runtime, when they are not all one kind.
	 *
	 * @param items The `key => value` entries.
	 * @param pos Where the literal appears.
	 * @return A block expression evaluating to the map.
	 */
	function mapLiteral(items:Array<Expr>, pos:Position):Expr {
		var allString:Bool = true;
		var allInt:Bool = true;

		for (item in items) {
			switch (item.e) {
				case EBinop('=>', key, _):
					switch (key.e) {
						case EConst(CString(_, _)): allInt = false;
						case EConst(CInt(_)): allString = false;
						case _:
							allString = false;
							allInt = false;
					}
				case _:
					throw new CppiaUnsupported('mixed array and map literal', pos);
			}
		}

		var mapClass:String = allString ? 'haxe.ds.StringMap' : (allInt ? 'haxe.ds.IntMap' : 'hxscript.runtime.AnyMap');

		var name:String = tempName('map');
		var target:Expr = {e: EIdent(name), pos: pos};
		var block:Array<Expr> = [
			{e: EVar(name, null, {e: ENew(mapClass, []), pos: pos}, null, null, false), pos: pos}
		];

		for (item in items) {
			switch (item.e) {
				case EBinop('=>', key, value):
					block.push({e: ECall({e: EField(target, 'set'), pos: pos}, [key, value]), pos: pos});
				case _:
			}
		}

		block.push(target);
		return {e: EBlock(block), pos: pos};
	}

	/**
	 * Lowers `for (k => v in it)` into a loop over the subject's key-value iterator.
	 *
	 * @param it The `k => v in subject` expression the parser produced.
	 * @param body The loop body.
	 * @param pos Where the loop appears.
	 * @return An equivalent plain `for` loop.
	 */
	function keyValueLoop(it:Expr, body:Expr, pos:Position):Expr {
		var key:String = null;
		var value:String = null;
		var subject:Expr = null;

		switch (it.e) {
			case EBinop('in', pair, iterable):
				switch (pair.e) {
					case EBinop('=>', k, v):
						switch [k.e, v.e] {
							case [EIdent(kn), EIdent(vn)]:
								key = kn;
								value = vn;
								subject = iterable;
							case _:
						}
					case _:
				}
			case _:
		}

		if (key == null)
			throw new CppiaUnsupported('key-value for loop', pos);

		var pairName:String = tempName('kv');
		var pairRef:Expr = {e: EIdent(pairName), pos: pos};

		var inner:Array<Expr> = [
			{e: EVar(key, null, {e: EField(pairRef, 'key'), pos: pos}, null, null, false), pos: pos},
			{e: EVar(value, null, {e: EField(pairRef, 'value'), pos: pos}, null, null, false), pos: pos},
			body
		];

		var iterator:Expr = {e: ECall({e: EField(subject, 'keyValueIterator'), pos: pos}, []), pos: pos};
		return {e: EFor(pairName, iterator, {e: EBlock(inner), pos: pos}), pos: pos};
	}

	/**
	 * Maps a property accessor to the cppia access code for it.
	 *
	 * Accessors are written as `V` rather than `C`. Both make the loader resolve `get_<name>` or
	 * `set_<name>` at link time, but only `V` also registers the field as a native property, and a
	 * by-name access -- which is how this emitter reads fields -- consults the accessor only for
	 * those. With `C` the read would silently return the storage slot instead.
	 *
	 * @param mode The accessor as written, or null for a plain field.
	 * @param pos Where the field is declared.
	 * @return The one-character access code.
	 */
	function accessCode(mode:Null<String>, pos:Position):String {
		return switch (mode) {
			case null | 'default' | 'null': 'N';
			case 'get' | 'set' | 'dynamic': 'V';
			case 'never': 'n';
			case _: throw new CppiaUnsupported('property accessor ' + mode, pos);
		}
	}

	/**
	 * The `class.field` of the static property an assignment targets, when it targets one.
	 *
	 * @param target The left side of the assignment.
	 * @return The qualified field, or null when the target is not a static property.
	 */
	function staticSetterFor(target:Expr):Null<String> {
		switch (target.e) {
			case EField(obj, name, _):
				var owner:Null<String> = typeOf(obj);
				if (owner == null)
					return null;
				var key:String = owner + '.' + name;
				return staticSetters.exists(key) ? key : null;

			case EIdent(name):
				if (lookupVar(name) != null || !statics.exists(name))
					return null;
				var key:String = currentClass + '.' + name;
				return staticSetters.exists(key) ? key : null;

			case _:
				return null;
		}
	}

	/**
	 * Writes the declared type of a variable slot.
	 *
	 * A slot is only ever stored as bool, int, float, string or object, and everything that is not
	 * one of the first four is an object -- so naming the exact class buys nothing, while naming one
	 * the loader cannot resolve leaves the slot with no store type at all and drops it to untyped
	 * access. Only the types that change the storage are written; the rest are `Dynamic`.
	 *
	 * @param path The declared type, or the empty string when there was none.
	 */
	function storableType(path:String):Void {
		if (path == null || path.length == 0) {
			w.unknownType();
			return;
		}

		switch (path) {
			case 'Int' | 'Float' | 'Bool' | 'String':
				w.type(path);
			case _:
				if (path.length >= 5 && path.substr(0, 5) == 'Array') {
					w.type(path);
					return;
				}

				var full:Null<String> = declaredClass(path);
				if (full != null)
					w.type(full);
				else
					w.unknownType();
		}
	}

	/**
	 * The full path of a class from this batch, given whatever the source called it.
	 *
	 * Worth resolving because the alternative is `Dynamic`, and `Dynamic` decides how every later
	 * access to the value is performed: a field read becomes a lookup by name at runtime rather than
	 * a known offset, and so does every method call. For a value touched once that is nothing; for
	 * one touched per column of per frame it is the difference between a renderer that keeps up and
	 * one that does not.
	 *
	 * Only classes declared here qualify. A host class would have to be resolved through the glue,
	 * and one that turned out not to be there would fail to link and take the whole module with it.
	 *
	 * @param path The type name as written, short or fully qualified.
	 * @return Its full path, or null if this batch does not declare it.
	 */
	/** An array type carrying an element kind, or null for anything else. */
	static function elementArray(name:Null<String>):Null<String> {
		return (name != null && name.length > 6 && name.substr(0, 6) == 'Array.') ? name : null;
	}

	/** Whether an accessor keyword leaves a field as ordinary storage. */
	static function plainAccess(access:String):Bool {
		return access == null || access == 'default' || access == 'null' || access == 'never';
	}

	/**
	 * The declared type of a plain instance variable, or null when the class has no such field.
	 *
	 * @param owner Full path of the class holding it.
	 * @param field The field name.
	 * @return Its declared type, the empty string when it had none, or null when it is not a plain
	 *         variable of that class.
	 */
	function instanceVar(owner:String, field:String):Null<String> {
		var vars:Null<StringMap<String>> = classVars.get(owner);
		return vars == null ? null : vars.get(field);
	}

	/** The class an expression is known to be an instance of, or null. */
	function instanceClassOf(e:Expr):Null<String> {
		var named:Null<String> = inferType(e);
		return named == null ? null : declaredClass(named);
	}

	function declaredClass(path:String):Null<String> {
		if (moduleClasses.exists(path))
			return path;

		var full:Null<String> = typePaths.get(path);
		return (full != null && moduleClasses.exists(full)) ? full : null;
	}

	/**
	 * Writes a type reference, noting it when it names a class from this batch.
	 *
	 * A reference to a class that ends up refused cannot link, and the loader rejects the WHOLE
	 * module for it, so the caller needs to know which of its own classes a module leans on.
	 *
	 * @param path The type being referenced.
	 */
	function useType(path:String):Void {
		if (moduleClasses.exists(path)) {
			if (refs.indexOf(path) < 0)
				refs.push(path);
		} else if (external.exists(path)) {
			throw new CppiaUnsupported('uses $path, which is compiled elsewhere', null);
		}

		w.type(path);
	}

	/**
	 * Registers scripted classes the host has elsewhere, which this batch cannot reach.
	 *
	 * cppia resolves a class either inside the module being loaded or as a host class. A scripted
	 * class living in another module is neither, so naming one produces a reference that fails to
	 * link and rejects the whole batch. Refusing here keeps the module interpreted instead.
	 *
	 * @param paths Full paths of those classes.
	 */
	public function externals(paths:Array<String>):Void {
		for (path in paths)
			external.set(path, true);
	}

	/**
	 * Registers bare names the host answers with a static of its own.
	 *
	 * A host may hand scripts a name that is neither a local, a field, nor a type -- a helper it
	 * injects into every interpreter. Compiled code has no interpreter to inject into, so the name
	 * has to be reached where it really lives.
	 *
	 * @param entries Each written `name=owner.path::field`.
	 */
	public function ambientStatics(entries:Array<String>):Void {
		for (entry in entries) {
			var equals:Int = entry.indexOf('=');
			if (equals < 0)
				continue;

			var target:String = entry.substr(equals + 1);
			if (target.indexOf('::') < 0)
				continue;

			ambientMembers.set(entry.substr(0, equals), target);
		}
	}

	/**
	 * Emits a read of a host-supplied bare name.
	 *
	 * @param name The bare name.
	 * @param pos Where it appears.
	 * @return Whether it was one, and has been emitted.
	 */
	function emitAmbient(name:String, pos:Position):Bool {
		var target:Null<String> = ambientMembers.get(name);
		if (target == null)
			return false;

		var split:Int = target.indexOf('::');
		w.pos(pos == null ? 0 : pos.line);
		w.token('FSTATIC');
		w.type(target.substr(0, split));
		w.str(target.substr(split + 2));
		return true;
	}

	/** Classes from this batch that the emitted code names. */
	public function references():Array<String> {
		return refs;
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
			case CTPath(path, params):
				var joined:String = path.join('.');
				if (joined == 'Array')
					return arrayTypeName(params);
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

	/**
	 * Spells an array type the way cppia names its specialisations, so element access reaches the
	 * typed builtin instead of the boxed one.
	 *
	 * Only the suffixes the loader knows may be produced; it throws on any other, so an element type
	 * it has no spelling for becomes `Array.Object`.
	 *
	 * @param params The array's type parameters, if written.
	 * @return The cppia type name.
	 */
	function arrayTypeName(params:Null<Array<CType>>):String {
		if (params == null || params.length != 1)
			return 'Array';

		return switch (params[0]) {
			case CTPath(['Int'], _): 'Array.int';
			case CTPath(['Bool'], _): 'Array.bool';
			case CTPath(['Float'], _): 'Array.Float';
			case CTPath(['String'], _): 'Array.String';
			case CTPath(['Dynamic'], _) | CTPath(['Any'], _): 'Array';
			case _: 'Array.Object';
		}
	}

	inline function hasAccess(f:FieldDecl, a:FieldAccess):Bool {
		return f.access.indexOf(a) >= 0;
	}

	inline function pushScope():Void {
		scopes.push(new StringMap());
		scopeTypes.push(new StringMap());
	}

	inline function popScope():Void {
		scopes.pop();
		scopeTypes.pop();
	}

	/**
	 * Binds a name to a fresh variable id.
	 *
	 * @param name The variable name.
	 * @param type Its declared type, if annotated.
	 * @return The variable id.
	 */
	function declareVar(name:String, ?type:String):Int {
		var id:Int = nextVarId++;
		if (scopes.length == 0)
			pushScope();
		scopes[scopes.length - 1].set(name, id);
		if (type != null && type.length > 0)
			scopeTypes[scopeTypes.length - 1].set(name, type);
		return id;
	}

	/** The declared type of a local, or null when it had none. */
	function lookupVarType(name:String):Null<String> {
		var i:Int = scopeTypes.length - 1;
		while (i >= 0) {
			var found:Null<String> = scopeTypes[i].get(name);
			if (found != null)
				return found;
			i--;
		}
		return null;
	}

	/**
	 * The type an expression is known to produce, used to pick a specialised cppia form.
	 *
	 * @param e The expression.
	 * @return Its type path, or null when not known.
	 */
	function inferType(e:Expr):Null<String> {
		switch (e.e) {
			case EIdent(v):
				if (lookupVar(v) != null)
					return lookupVarType(v);
				if (members.exists(v))
					return memberTypes.get(v);
				if (statics.exists(v))
					return staticTypes.get(v);
				return null;

			case EParent(inner):
				return inferType(inner);

			case EField(obj, f, _):
				var owner:Null<String> = typeOf(obj);
				if (owner != null && owner == currentClass)
					return staticTypes.get(f);

				var holder:Null<String> = (obj.e.match(EIdent('this'))) ? currentClass : instanceClassOf(obj);
				if (holder != null) {
					var declared:Null<String> = instanceVar(holder, f);
					if (declared != null && declared.length > 0)
						return declared;
				}
				return null;

			case ENew(cl, _):
				return typePaths.exists(cl) ? typePaths.get(cl) : null;

			case _:
				return null;
		}
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
