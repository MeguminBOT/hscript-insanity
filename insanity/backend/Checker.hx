package insanity.backend;

import insanity.backend.Expr;

/**
	This is a special type that can be used in API.
	It will be type-checked as `Script` but will compile/execute as `Real`
**/
typedef TypeCheck<Real, Script> = Real;

/** A checker type: the vocabulary the optional static type-checker reasons in. */
enum TType {
	/** A type variable (monomorph) that may still be unified to a concrete type. */
	TMono(r:{r:TType});

	/** `Void`. */
	TVoid;

	/** `Int`. */
	TInt;

	/** `Float`. */
	TFloat;

	/** `Bool`. */
	TBool;

	/** `Dynamic`. */
	TDynamic;

	/** A named type parameter. */
	TParam(name:String);

	/** A name that could not be resolved to a type. */
	TUnresolved(name:String);

	/** A nullable wrapper `Null<T>`. */
	TNull(t:TType);

	/** A class instance with type arguments. */
	TInst(c:CClass, args:Array<TType>);

	/** An enum with type arguments. */
	TEnum(e:CEnum, args:Array<TType>);

	/** A typedef with type arguments. */
	TType(t:CTypedef, args:Array<TType>);

	/** An abstract with type arguments. */
	TAbstract(a:CAbstract, args:Array<TType>);

	/** A function type. */
	TFun(args:Array<{name:String, opt:Bool, t:TType}>, ret:TType);

	/** An anonymous structure type. */
	TAnon(fields:Array<{name:String, opt:Bool, t:TType}>);

	/** A lazily-computed type. */
	TLazy(f:Void->TType);
}

/** The expected-value context an expression is checked in. */
private enum WithType {
	/** The value is unused. */
	NoValue;

	/** A value is expected, of no particular type. */
	Value;

	/** A value of a specific type is expected. */
	WithType(t:TType);
}

/** A top-level type declaration the checker knows about. */
enum CTypedecl {
	/** A class. */
	CTClass(c:CClass);

	/** An enum. */
	CTEnum(e:CEnum);

	/** A typedef. */
	CTTypedef(t:CTypedef);

	/** A plain alias to a type. */
	CTAlias(t:TType);

	/** An abstract. */
	CTAbstract(a:CAbstract);
}

/** Metadata as seen by the checker. */
typedef CMetadata = Array<{name:String, params:Null<Array<Expr>>}>;

/** Fields shared by every named checker type. */
typedef CNamedType = {
	/** The type's name. */
	var name:String;

	/** Its type parameters. */
	var params:Array<TType>;

	/** Its metadata, if any. */
	var ?meta:CMetadata;
}

/** A class known to the checker. */
typedef CClass = {
	> CNamedType,

	/** The super-class, if any. */
	var ?superClass:TType;

	/** The constructor field, if any. */
	var ?constructor:CField;

	/** Implemented interfaces, if any. */
	var ?interfaces:Array<TType>;

	/** Whether this is an interface. */
	var ?isInterface:Bool;

	/** Instance fields keyed by name. */
	var fields:Map<String, CField>;

	/** Static fields keyed by name. */
	var statics:Map<String, CField>;
}

/** A class field known to the checker. */
typedef CField = {
	/** Whether the field is public. */
	var isPublic:Bool;

	/** Whether the field is writable. */
	var canWrite:Bool;

	/** Whether the field's type is fully known. */
	var complete:Bool;

	/** Whether the field is a method. */
	var ?isMethod:Bool;

	/** The field's own type parameters. */
	var params:Array<TType>;

	/** The field name. */
	var name:String;

	/** The field type. */
	var t:TType;

	/** The field's metadata, if any. */
	var ?meta:CMetadata;
}

/** An enum known to the checker. */
typedef CEnum = {
	> CNamedType,

	/** Its constructors, each with optional arguments. */
	var constructors:Array<{name:String, ?args:Array<{name:String, opt:Bool, t:TType}>}>;
}

/** A typedef known to the checker. */
typedef CTypedef = {
	> CNamedType,

	/** The aliased type. */
	var t:TType;
}

/** An abstract known to the checker. */
typedef CAbstract = {
	> CNamedType,

	/** The underlying type. */
	var t:TType;

	/** `from` conversion source types. */
	var from:Array<TType>;

	/** `to` conversion target types. */
	var to:Array<TType>;

	/** Names forwarded to the underlying type. */
	var forwards:Map<String, Bool>;

	/** The abstract's implementation class. */
	var impl:CClass;
}

/** A completion result: an expression and its inferred type. */
class Completion {
	/** The completed expression. */
	public var expr:Expr;

	/** Its inferred type. */
	public var t:TType;

	/**
	 * @param expr The completed expression.
	 * @param t Its inferred type.
	 */
	public function new(expr, t) {
		this.expr = expr;
		this.t = t;
	}
}

/** The type database the checker resolves names against, seeded from an RTTI XML API dump. */
@:allow(hscript.Checker)
class CheckerTypes {
	/** All known type declarations, keyed by name. */
	var types:Map<String, CTypedecl> = new Map();

	/** Cached `String` type. */
	var t_string:TType;

	/** Type parameters in scope while resolving a type. */
	var localParams:Map<String, TType>;

	/** A parser used to parse type expressions from the RTTI dump. */
	var parser:hscript.Parser;

	/** Seeds the database with the primitive types. */
	public function new() {
		types = new Map();
		types.set("Void", CTAlias(TVoid));
		types.set("Int", CTAlias(TInt));
		types.set("Float", CTAlias(TFloat));
		types.set("Bool", CTAlias(TBool));
		types.set("Dynamic", CTAlias(TDynamic));
		parser = new hscript.Parser();
	}

	/**
	 * Loads types from an RTTI XML API description.
	 *
	 * @param api The RTTI XML root.
	 */
	public function addXmlApi(api:Xml) {
		var types = new haxe.rtti.XmlParser();
		types.process(api, "");
		var todo = [];
		for (v in types.root)
			addXmlType(v, todo);
		for (f in todo)
			f();
		t_string = getType("String");
	}

	/**
	 * Registers a class type, creating an empty one if none is given.
	 *
	 * @param name The class name.
	 * @param ct An existing class definition to register, or null to create one.
	 * @return The registered class definition.
	 */
	public function defineClass(name:String, ?ct:CClass) {
		if (ct == null)
			ct = {
				name: name,
				fields: [],
				statics: [],
				params: [],
			};
		types.set(name, CTClass(ct));
		return ct;
	}

	/**
	 * Converts one RTTI class field into a checker field, skipping accessors, overrides, and
	 * `@:noScript` members.
	 *
	 * @param f The RTTI class field.
	 * @return The checker field, or null if it should be skipped.
	 */
	function addField(f:haxe.rtti.CType.ClassField) {
		if (f.isOverride || f.name.substr(0, 4) == "get_" || f.name.substr(0, 4) == "set_")
			return null;
		var complete = !StringTools.startsWith(f.name, "__"); // __uid, etc. (no metadata in such fields)
		for (m in f.meta) {
			if (m.name == ":noScript")
				return null;
			if (m.name == ":noCompletion")
				complete = false;
		}
		var pkeys = [];
		var fl:CField = {
			isPublic: f.isPublic,
			canWrite: f.set.match(RNormal | RCall(_) | RDynamic),
			isMethod: f.set == RMethod || f.set == RDynamic,
			complete: complete,
			params: [],
			name: f.name,
			t: null
		};
		for (p in f.params) {
			var pt = TParam(p);
			var key = f.name + "." + p;
			pkeys.push(key);
			fl.params.push(pt);
			localParams.set(key, pt);
		}
		fl.t = makeXmlType(f.type);
		if (f.meta != null && f.meta.length > 0) {
			fl.meta = [];
			for (m in f.meta)
				fl.meta.push({name: m.name, params: [for (p in m.params) try parser.parseString(p) catch (e:hscript.Expr.Error) null]});
		}
		while (pkeys.length > 0)
			localParams.remove(pkeys.pop());
		return fl;
	}

	/**
	 * Converts one RTTI type tree node (class/enum/typedef/abstract) into a checker declaration,
	 * queueing follow-up work whose resolution needs all types present.
	 *
	 * @param x The RTTI type node.
	 * @param todo A list to append deferred resolution steps to.
	 */
	function addXmlType(x:haxe.rtti.CType.TypeTree, todo:Array<Void->Void>) {
		switch (x) {
			case TPackage(name, full, subs):
				for (s in subs)
					addXmlType(s, todo);
			case TClassdecl(c):
				if (types.exists(c.path))
					return;
				var cl:CClass = {
					name: c.path,
					params: [],
					fields: new Map(),
					statics: new Map(),
				};
				addMeta(c, cl);
				if (c.isInterface)
					cl.isInterface = true;
				for (p in c.params)
					cl.params.push(TParam(p));
				todo.push(function() {
					var params = cl.params;
					localParams = [for (t in cl.params) c.path + "." + Checker.typeStr(t) => t];
					if (StringTools.endsWith(cl.name, "_Impl_")) {
						for (a in types)
							switch (a) {
								case CTAbstract(a) if (a.impl == cl):
									for (t in a.params)
										localParams.set(a.name + "." + Checker.typeStr(t), t);
									break;
								default:
							}
					}
					if (c.superClass != null)
						cl.superClass = getType(c.superClass.path, [for (t in c.superClass.params) makeXmlType(t)]);
					if (c.interfaces != null) {
						cl.interfaces = [];
						for (i in c.interfaces)
							cl.interfaces.push(getType(i.path, [for (t in i.params) makeXmlType(t)]));
					}
					for (f in c.fields) {
						var f = addField(f);
						if (f != null) {
							if (f.name == "new")
								cl.constructor = f;
							else
								cl.fields.set(f.name, f);
						}
					}
					for (f in c.statics) {
						var f = addField(f);
						if (f != null)
							cl.statics.set(f.name, f);
					}
					localParams = null;
				});
				types.set(cl.name, CTClass(cl));
			case TEnumdecl(e):
				if (types.exists(e.path))
					return;
				var en:CEnum = {
					name: e.path,
					params: [],
					constructors: [],
				};
				addMeta(e, en);
				for (p in e.params)
					en.params.push(TParam(p));
				todo.push(function() {
					localParams = [for (t in en.params) e.path + "." + Checker.typeStr(t) => t];
					for (c in e.constructors)
						en.constructors.push({name: c.name, args: c.args == null ? null : [for (a in c.args) {name: a.name, opt: a.opt, t: makeXmlType(a.t)}]});
					localParams = null;
				});
				types.set(en.name, CTEnum(en));
			case TTypedecl(t):
				if (types.exists(t.path))
					return;
				var td:CTypedef = {
					name: t.path,
					params: [],
					t: null,
				};
				for (p in t.params)
					td.params.push(TParam(p));
				if (t.path == "hscript.TypeCheck")
					td.params.reverse();
				todo.push(function() {
					localParams = [for (pt in td.params) t.path + "." + Checker.typeStr(pt) => pt];
					td.t = makeXmlType(t.type);
					localParams = null;
				});
				types.set(t.path, CTTypedef(td));
			case TAbstractdecl(a):
				if (types.exists(a.path))
					return;
				var ta:CAbstract = {
					name: a.path,
					params: [],
					t: null,
					from: [],
					to: [],
					forwards: new Map(),
					impl: null,
				};
				addMeta(a, ta);
				for (p in a.params)
					ta.params.push(TParam(p));
				todo.push(function() {
					localParams = [for (t in ta.params) a.path + "." + Checker.typeStr(t) => t];
					ta.t = makeXmlType(a.athis);
					for (f in a.from)
						if (f.field == null)
							ta.from.push(makeXmlType(f.t));
					for (t in a.to)
						if (t.field == null)
							ta.to.push(makeXmlType(t.t));
					for (m in a.meta)
						if (m.name == ":forward" && m.params != null) {
							for (i in m.params)
								ta.forwards.set(i, true);
						}
					localParams = null;
				});
				todo.unshift(function() {
					if (a.impl != null) {
						var t = resolve(a.impl.path);
						if (t != null)
							switch (t) {
								case TInst(c, _):
									ta.impl = c;
								default:
							}
					}
				});
				types.set(a.path, CTAbstract(ta));
		}
	}

	/**
	 * Copies metadata from an RTTI type onto a checker type.
	 *
	 * @param src The RTTI type info.
	 * @param to The checker type to copy metadata onto.
	 */
	function addMeta(src:haxe.rtti.CType.TypeInfos, to:CNamedType) {
		if (src.meta == null || src.meta.length == 0)
			return;
		to.meta = [];
		for (m in src.meta)
			to.meta.push({name: m.name, params: [for (p in m.params) try parser.parseString(p) catch (e:hscript.Expr.Error) null]});
	}

	/**
	 * Converts an RTTI type reference into a checker `TType`.
	 *
	 * @param t The RTTI type.
	 * @return The checker type.
	 */
	function makeXmlType(t:haxe.rtti.CType.CType):TType {
		return switch (t) {
			case CUnknown: TUnresolved("Unknown");
			case CEnum(name, params): getType(name, [for (t in params) makeXmlType(t)]);
			case CClass(name, params): getType(name, [for (t in params) makeXmlType(t)]);
			case CTypedef(name, params): getType(name, [for (t in params) makeXmlType(t)]);
			case CFunction(args, ret): TFun([for (a in args) {name: a.name, opt: a.opt, t: makeXmlType(a.t)}], makeXmlType(ret));
			case CAnonymous(fields):
				inline function isOpt(m:haxe.rtti.CType.MetaData) {
					if (m == null)
						return false;
					var b = false;
					for (m in m)
						if (m.name == ":optional") {
							b = true;
							break;
						}
					return b;
				}
				TAnon([for (f in fields) {name: f.name, t: makeXmlType(f.type), opt: isOpt(f.meta)}]);
			case CDynamic(t): TDynamic;
			case CAbstract(name, params):
				switch (name) {
					default:
						getType(name, [for (t in params) makeXmlType(t)]);
				}
		}
	}

	/**
	 * Resolves a type by name to its concrete `TType`, following aliases.
	 *
	 * @param name The type name.
	 * @param args Type arguments, if any.
	 * @return The resolved type, or null if unknown.
	 */
	function getType(name:String, ?args:Array<TType>):TType {
		if (localParams != null) {
			var t = localParams.get(name);
			if (t != null)
				return t;
		}
		var t = resolve(name, args);
		if (t == null) {
			var pack = name.split(".");
			if (pack.length > 1) {
				// bugfix for some args reported as pack._Name.Name while they are not private
				var priv = pack[pack.length - 2];
				if (priv.charCodeAt(0) == "_".code) {
					pack.remove(priv);
					return getType(pack.join("."), args);
				}
			}
			return TUnresolved(name); // most likely private class
		}
		return t;
	}

	/**
	 * Resolves a type name (honouring local type parameters) to a `TType`.
	 *
	 * @param name The type name.
	 * @param args Type arguments, if any.
	 * @return The resolved type.
	 */
	public function resolve(name:String, ?args:Array<TType>):TType {
		if (name == "Null") {
			if (args == null || args.length != 1)
				throw "Missing Null<T> parameter";
			return TNull(args[0]);
		}
		var t = types.get(name);
		if (t == null)
			return null;
		if (args == null)
			args = [];
		return switch (t) {
			case CTClass(c): TInst(c, args);
			case CTEnum(e): TEnum(e, args);
			case CTTypedef(t): TType(t, args);
			case CTAbstract(a): TAbstract(a, args);
			case CTAlias(t): t;
		}
	}
}

/**
 * The optional static type-checker. It walks an expression tree, inferring and unifying `TType`s and
 * reporting type errors, and also supports completion queries. It is opt-in and separate from the
 * (untyped) runtime interpreter.
 */
class Checker {
	/** The type database used to resolve names. */
	public var types:CheckerTypes;

	/** Local variable types in the current scope. */
	var locals:Map<String, TType>;

	/** Global variable types. */
	var globals:Map<String, TType> = new Map();

	/** Event types (callback signatures). */
	var events:Map<String, TType> = new Map();

	/** The function type currently being checked (for `return` typing). */
	var currentFunType:TType;

	/** Whether the current check is a completion query. */
	var isCompletion:Bool;

	/** Whether new variables may be defined in the current scope. */
	var allowDefine:Bool;

	/** Whether the current function has returned a value. */
	var hasReturn:Bool;

	/** The call expression currently being checked. */
	var callExpr:Expr;

	/** Whether `private` access is enforced. */
	public var checkPrivate:Bool = true;

	/** Whether `async`/`await` typing is allowed. */
	public var allowAsync:Bool;

	/** The expected return type, or null to disallow `return` with a value. */
	public var allowReturn:Null<TType>;

	/** Whether globals may be defined by assignment. */
	public var allowGlobalsDefine:Bool;

	/** Whether an `@:untyped`-style meta suppresses checks. */
	public var allowUntypedMeta:Bool;

	/**
	 * @param types An existing type database, or null to create an empty one.
	 */
	public function new(?types) {
		if (types == null)
			types = new CheckerTypes();
		this.types = types;
	}

	/**
	 * Exposes a class's fields as globals (walking up its super-classes), so scripts can reference
	 * them unqualified.
	 *
	 * @param cl The class whose fields to expose.
	 * @param params Type arguments for the class, or null to use fresh monomorphs.
	 * @param allowPrivate Whether to expose private fields too.
	 */
	public function setGlobals(cl:CClass, ?params:Array<TType>, allowPrivate = false) {
		if (params == null)
			params = [for (p in cl.params) makeMono()];
		while (true) {
			for (f in cl.fields)
				if (f.isPublic || allowPrivate)
					setGlobal(f.name, f.params.length == 0 ? f.t : TLazy(function() {
						var t = apply(f.t, f.params, [for (i in 0...f.params.length) makeMono()]);
						return apply(t, cl.params, params);
					}));
			if (cl.superClass == null)
				break;
			cl = switch (cl.superClass) {
				case TInst(csup, pl):
					params = [for (p in pl) apply(p, cl.params, params)];
					csup;
				default: throw "assert";
			}
		}
	}

	/** Removes a global. @param name The global name. */
	public function removeGlobal(name:String) {
		globals.remove(name);
	}

	/** Sets a global's type. @param name The global name. @param type Its type. */
	public function setGlobal(name:String, type:TType) {
		globals.set(name, type);
	}

	/** Sets an event's type. @param name The event name. @param type Its callback type. */
	public function setEvent(name:String, type:TType) {
		events.set(name, type);
	}

	/** @return The globals table. */
	public function getGlobals() {
		return globals;
	}

	/**
	 * Overridable hook: whether a bare identifier should resolve as a top-down enum constructor.
	 *
	 * @param en The enum being considered.
	 * @param field The constructor name.
	 * @return True to accept it as that enum's constructor.
	 */
	public dynamic function onTopDownEnum(en:CEnum, field:String) {
		return false;
	}

	/**
	 * Builds the checker argument types for a function's parameters.
	 *
	 * @param args The parameter list.
	 * @param pos An expression used for error positions.
	 * @return The typed arguments.
	 */
	function typeArgs(args:Array<Argument>, pos:Expr) {
		return [
			for (i in 0...args.length) {
				var a = args[i];
				var at = a.t == null ? makeMono() : makeType(a.t, pos);
				{name: a.name, opt: a.opt, t: at};
			}
		];
	}

	/**
	 * Type-checks an expression tree, the checker's entry point.
	 *
	 * @param expr The expression to check.
	 * @param withType The expected-value context.
	 * @param isCompletion Whether this is a completion query rather than a plain check.
	 * @return The inferred type.
	 */
	public function check(expr:Expr, ?withType:WithType, ?isCompletion = false) {
		if (withType == null)
			withType = NoValue;
		locals = new Map();
		if (types.t_string == null)
			types.t_string = types.getType("String");
		allowDefine = allowGlobalsDefine;
		this.isCompletion = isCompletion;
		if (edef(expr).match(EFunction(_)))
			expr = mk(EBlock([expr]), expr); // single function might be self recursive
		switch (edef(expr)) {
			case EBlock(el):
				var delayed = [];
				var last = TVoid;
				for (e in el) {
					while (true) {
						switch (edef(e)) {
							case EMeta(_, _, e2): e = e2;
							default: break;
						}
					}
					switch (edef(e)) {
						case EFunction(args, _, name, ret) if (name != null):
							var tret = ret == null ? makeMono() : makeType(ret, e);
							var ft = TFun(typeArgs(args, e), tret);
							locals.set(name, ft);
							delayed.push(function() {
								currentFunType = ft;
								typeExpr(e, NoValue);
								return ft;
							});
						default:
							for (f in delayed)
								f();
							delayed = [];
							if (el[el.length - 1] == e) last = typeExpr(e, withType); else typeExpr(e, NoValue);
					}
				}
				for (f in delayed)
					last = f();
				return last;
			default:
		}
		return typeExpr(expr, withType);
	}

	/** @param e An expression. @return Its definition (following metadata wrappers). */
	inline function edef(e:Expr) {
		return e.e;
	}

	/**
	 * Builds a position spanning two expressions (for error reporting).
	 *
	 * @param e1 The first expression.
	 * @param e2 The second expression.
	 * @return A dummy expression carrying the combined position.
	 */
	function punion(e1:Expr, e2:Expr):Expr {
		return {
			pmin: e1.pmin < e2.pmin ? e1.pmin : e2.pmin,
			pmax: e1.pmax > e2.pmax ? e1.pmax : e2.pmax,
			origin: e1.origin,
			line: e1.line < e2.line ? e1.line : e2.line,
			e: null,
		};
	}

	/**
	 * Raises a type error at an expression's position.
	 *
	 * @param msg The error message.
	 * @param curExpr The expression the error is about.
	 */
	inline function error(msg:String, curExpr:Expr) {
		var e = new Error(ECustom(msg), curExpr.pmin, curExpr.pmax, curExpr.origin, curExpr.line);
		if (!isCompletion)
			throw e;
	}

	/** @return A shallow copy of the current locals, to restore after a nested scope. */
	function saveLocals() {
		return [for (k in locals.keys()) k => locals.get(k)];
	}

	/**
	 * Converts a parsed type annotation into a checker `TType`.
	 *
	 * @param t The parsed type.
	 * @param e An expression for error positions.
	 * @return The checker type.
	 */
	function makeType(t:CType, e:Expr):TType {
		return switch (t) {
			case CTPath(path, params):
				var params = params == null ? [] : [for (p in params) makeType(p, e)];
				var ct = types.resolve(path.join("."), params);
				if (ct == null) {
					// maybe a subtype that is public ?
					var pack = path.copy();
					var name = pack.pop();
					if (pack.length > 0
						&& pack[pack.length - 1].charCodeAt(0) >= 'A'.code
						&& pack[pack.length - 1].charCodeAt(0) <= 'Z'.code) {
						pack.pop();
						pack.push(name);
						ct = types.resolve(pack.join("."), params);
					}
				}
				if (ct == null) {
					error("Unknown type " + path, e);
					ct = TDynamic;
				}
				return ct;
			case CTFun(args, ret):
				var i = 0;
				return TFun([for (a in args) {name: "p" + (i++), opt: false, t: makeType(a, e)}], makeType(ret, e));
			case CTAnon(fields):
				return TAnon([for (f in fields) {name: f.name, opt: false, t: makeType(f.t, e)}]);
			case CTParent(t):
				return makeType(t, e);
			case CTNamed(n, t):
				return makeType(t, e);
			case CTOpt(t):
				return makeType(t, e);
			case CTExpr(_):
				error("Unsupported expr type parameter", e);
				return null;
		}
	}

	/**
	 * Renders a checker type as a readable string (for messages).
	 *
	 * @param t The type.
	 * @return Its display string.
	 */
	public static function typeStr(t:TType) {
		inline function makeArgs(args:Array<TType>)
			return args.length == 0 ? "" : "<" + [for (t in args) typeStr(t)].join(",") + ">";
		return switch (t) {
			case TMono(r): r.r == null ? "Unknown" : typeStr(r.r);
			case TInst(c, args): c.name + makeArgs(args);
			case TEnum(e, args): e.name + makeArgs(args);
			case TType(t, args):
				if (t.name == "hscript.TypeCheck") typeStr(args[1]); else t.name + makeArgs(args);
			case TAbstract(a, args): a.name + makeArgs(args);
			case TFun(args, ret): "(" + [
					for (a in args)
						(a.opt ? "?" : "") + (a.name == "" ? "" : a.name + ":") + typeStr(a.t)
				].join(", ") + ") -> " + typeStr(ret);
			case TAnon(fields): "{" + [for (f in fields) (f.opt ? "?" : "") + f.name + ":" + typeStr(f.t)].join(", ") + "}";
			case TParam(name): name;
			case TNull(t): "Null<" + typeStr(t) + ">";
			case TUnresolved(name): "?" + name;
			default: t.getName().substr(1);
		}
	}

	/**
	 * Applies a callback to each immediate sub-type of a type.
	 *
	 * @param t The type to visit.
	 * @param callb The callback run on each direct child type.
	 */
	public static function typeIter(t:TType, callb:TType->Void) {
		switch (t) {
			case TMono(r) if (r.r != null):
				callb(r.r);
			case TNull(t):
				callb(t);
			case TInst(_, tl), TAbstract(_, tl), TEnum(_, tl), TType(_, tl):
				for (t in tl)
					callb(t);
			case TFun(args, ret):
				for (t in args)
					callb(t.t);
				callb(ret);
			case TAnon(fl):
				for (f in fl)
					callb(f.t);
			case TLazy(f):
				callb(f());
			default:
		}
	}

	/**
	 * Occurs-check: whether monomorph `a` appears within `t` (which would make a cyclic link).
	 *
	 * @param a The monomorph to look for.
	 * @param t The type to search.
	 * @return True if `a` occurs in `t`.
	 */
	function linkLoop(a:TType, t:TType) {
		if (t == a)
			return true;
		switch (t) {
			case TMono(r):
				if (r.r == null)
					return false;
				return linkLoop(a, r.r);
			case TEnum(_, tl), TInst(_, tl), TType(_, tl), TAbstract(_, tl):
				for (t in tl)
					if (linkLoop(a, t))
						return true;
				return false;
			case TFun(args, ret):
				for (arg in args)
					if (linkLoop(a, arg.t))
						return true;
				return linkLoop(a, ret);
			case TDynamic:
				if (t == TDynamic)
					return false;
				return linkLoop(a, TDynamic);
			case TAnon(fl):
				for (f in fl)
					if (linkLoop(a, f.t))
						return true;
				return false;
			default:
				return false;
		}
	}

	/**
	 * Binds a monomorph to a type (unless that would create a cycle).
	 *
	 * @param a The type being linked to.
	 * @param b The other type in the unification.
	 * @param r The monomorph cell to write into.
	 * @return True if the link succeeded.
	 */
	function link(a:TType, b:TType, r:{r:TType}) {
		if (linkLoop(a, b))
			return follow(b) == a;
		if (b == TDynamic)
			return true;
		r.r = b;
		return true;
	}

	/**
	 * Whether two types are equal (up to monomorph following).
	 *
	 * @param t1 The first type.
	 * @param t2 The second type.
	 * @return True if equal.
	 */
	function typeEq(t1:TType, t2:TType) {
		if (t1 == t2)
			return true;
		switch ([t1, t2]) {
			case [TMono(r), _]:
				if (r.r == null) {
					if (!link(t1, t2, r))
						return false;
					r.r = t2;
					return true;
				}
				return typeEq(r.r, t2);
			case [_, TMono(r)]:
				if (r.r == null) {
					if (!link(t2, t1, r))
						return false;
					r.r = t1;
					return true;
				}
				return typeEq(t1, r.r);
			case [TType(t1, pl1), TType(t2, pl2)] if (t1 == t2):
				for (i in 0...pl1.length)
					if (!typeEq(pl1[i], pl2[i]))
						return false;
				return true;
			case [TType(t1, pl1), _]:
				return typeEq(apply(t1.t, t1.params, pl1), t2);
			case [_, TType(t2, pl2)]:
				return typeEq(t1, apply(t2.t, t2.params, pl2));
			case [TInst(cl1, pl1), TInst(cl2, pl2)] if (cl1 == cl2):
				for (i in 0...pl1.length)
					if (!typeEq(pl1[i], pl2[i]))
						return false;
				return true;
			case [TEnum(e1, pl1), TEnum(e2, pl2)] if (e1 == e2):
				for (i in 0...pl1.length)
					if (!typeEq(pl1[i], pl2[i]))
						return false;
				return true;
			case [TAbstract(a1, pl1), TAbstract(a2, pl2)] if (a1 == a2):
				for (i in 0...pl1.length)
					if (!typeEq(pl1[i], pl2[i]))
						return false;
				return true;
			case [TNull(t1), TNull(t2)]:
				return typeEq(t1, t2);
			case [TNull(t1), _]:
				return typeEq(t1, t2);
			case [_, TNull(t2)]:
				return typeEq(t1, t2);
			case [TFun(args1, r1), TFun(args2, r2)] if (args1.length == args2.length):
				for (i in 0...args1.length)
					if (!typeEq(args1[i].t, args2[i].t))
						return false;
				return typeEq(r1, r2);
			case [TAnon(a1), TAnon(a2)] if (a1.length == a2.length):
				var m = new Map();
				for (f in a2)
					m.set(f.name, f);
				for (f1 in a1) {
					var f2 = m.get(f1.name);
					if (f2 == null)
						return false;
					if (!typeEq(f1.t, f2.t))
						return false;
				}
				return true;
			default:
		}
		return false;
	}

	/**
	 * Attempts to unify two types, binding monomorphs as needed, without raising an error on failure.
	 *
	 * @param t1 The type to unify from.
	 * @param t2 The type to unify to.
	 * @return True if unification succeeded.
	 */
	public function tryUnify(t1:TType, t2:TType) {
		if (t1 == t2)
			return true;
		switch ([t1, t2]) {
			case [TMono(r), _]:
				if (r.r == null) {
					if (!link(t1, t2, r))
						return false;
					r.r = t2;
					return true;
				}
				return tryUnify(r.r, t2);
			case [_, TMono(r)]:
				if (r.r == null) {
					if (!link(t2, t1, r))
						return false;
					r.r = t1;
					return true;
				}
				return tryUnify(t1, r.r);
			case [TType(t1, pl1), _]:
				return tryUnify(apply(t1.t, t1.params, pl1), t2);
			case [_, TType(t2, pl2)]:
				return tryUnify(t1, apply(t2.t, t2.params, pl2));
			case [TNull(t1), _]:
				return tryUnify(t1, t2);
			case [_, TNull(t2)]:
				return tryUnify(t1, t2);
			case [TFun(args1, r1), TFun(args2, r2)] if (args1.length == args2.length):
				for (i in 0...args1.length) {
					var a1 = args1[i];
					var a2 = args2[i];
					if (a2.opt && !a1.opt)
						return false;
					if (!tryUnify(a2.t, a1.t))
						return false;
				}
				if (follow(r2) == TVoid)
					return true;
				return tryUnify(r1, r2);
			case [_, TDynamic]:
				return true;
			case [TDynamic, _]:
				return true;
			case [TAnon(a1), TAnon(a2)]:
				if (a2.length == 0) // always unify with {}
					return true;
				var m = new Map();
				for (f in a1)
					m.set(f.name, f);
				for (f2 in a2) {
					var f1 = m.get(f2.name);
					if (f1 == null) {
						if (f2.opt)
							continue;
						return false;
					}
					if (!typeEq(f1.t, f2.t))
						return false;
				}
				return true;
			case [TInst(cl1, pl1), TInst(cl2, pl2)]:
				while (cl1 != cl2) {
					if (cl1.interfaces != null) {
						for (i in cl1.interfaces) {
							switch (i) {
								case TInst(cli, args):
									var i = TInst(cli, [for (a in args) apply(a, cl1.params, pl1)]);
									if (tryUnify(i, t2)) return true;
								default:
									throw "assert";
							}
						}
					}
					switch (cl1.superClass) {
						case null: return false;
						case TInst(c, args):
							pl1 = [for (a in args) apply(a, cl1.params, pl1)];
							cl1 = c;
						default: throw "assert";
					}
				}
				for (i in 0...pl1.length)
					if (!typeEq(pl1[i], pl2[i]))
						return false;
				return true;
			case [TInst(cl1, pl1), TAnon(fl)]:
				for (i in 0...fl.length) {
					var f2 = fl[i];
					var f1 = null;
					var cl = cl1;
					while (true) {
						f1 = cl.fields.get(f2.name);
						if (f1 != null)
							break;
						if (cl.superClass == null)
							return false;
						cl = switch (cl.superClass) {
							case TInst(c, _): c;
							default: throw "assert";
						}
					}
					if (!typeEq(apply(f1.t, cl1.params, pl1), f2.t))
						return false;
				}
				return true;
			case [TInt, TFloat]:
				return true;
			case [TFun(_), TAbstract({name: "haxe.Function"}, _)]:
				return true;
			case [_, TAbstract(a, args)]:
				for (ft in a.from) {
					var t = apply(ft, a.params, args);
					if (tryUnify(t1, t))
						return true;
				}
			case [TAbstract(a, args), _]:
				for (tt in a.to) {
					var t = apply(tt, a.params, args);
					if (tryUnify(t, t2))
						return true;
				}
			default:
		}
		return typeEq(t1, t2);
	}

	/**
	 * Unifies two types, raising a type error at `e` if they don't unify.
	 *
	 * @param t1 The type to unify from.
	 * @param t2 The type to unify to.
	 * @param e The expression for error positions.
	 */
	public function unify(t1:TType, t2:TType, e:Expr) {
		if (!tryUnify(t1, t2) && !abstractCast(t1, t2, e))
			error(typeStr(t1) + " should be " + typeStr(t2), e);
	}

	/**
	 * Tries an abstract `from`/`to` implicit cast between two types.
	 *
	 * @param t1 The source type.
	 * @param t2 The target type.
	 * @param e The expression for error positions.
	 * @return The cast-through type if one applies, else null.
	 */
	public function abstractCast(t1:TType, t2:TType, e:Expr) {
		return false;
		var tf1 = follow(t1);
		var tf2 = follow(t2);
		return getAbstractCast(tf1, tf2, e, false) || getAbstractCast(tf2, tf1, e, true);
	}

	/**
	 * Finds an abstract conversion between two types in one direction.
	 *
	 * @param from The source type.
	 * @param to The target type.
	 * @param e The expression for error positions.
	 * @param isFrom Whether to search the abstract's `from` list (else its `to` list).
	 * @return The converted type if a conversion applies, else null.
	 */
	function getAbstractCast(from:TType, to:TType, e:Expr, isFrom:Bool) {
		switch (from) {
			case TAbstract(a, args) if (a.impl != null):
				for (s in a.impl.statics) {
					if (s.meta == null)
						continue;
					var found = false;
					for (m in s.meta)
						if (m.name == (isFrom ? ":from" : ":to")) {
							found = true;
							break;
						}
					if (!found)
						continue;
					switch (s.t) {
						case TFun([arg], _):
							var at = apply(arg.t, s.params, [for (_ in s.params) makeMono()]);
							at = apply(at, a.params, args);
							var acc = mk(null, e);
							if (tryUnify(to, at) && resolveGlobal(a.impl.name, acc, Value) != null) {
								e.e = ECall(mk(EField(acc, s.name), e), [mk(e.e, e)]);
								return true;
							}
						default:
					}
				}
			default:
		}
		return false;
	}

	/**
	 * Substitutes type parameters with arguments throughout a type.
	 *
	 * @param t The type to specialize.
	 * @param params The type-parameter placeholders.
	 * @param args The type arguments to substitute in.
	 * @return The specialized type.
	 */
	public function apply(t:TType, params:Array<TType>, args:Array<TType>) {
		if (args.length != params.length)
			throw "Invalid number of type parameters";
		if (args.length == 0)
			return t;
		var subst = new Map();
		for (i in 0...params.length)
			subst.set(params[i], args[i]);
		function map(t:TType) {
			var st = subst.get(t);
			if (st != null)
				return st;
			return mapType(t, map);
		}
		return map(t);
	}

	/**
	 * Rebuilds a type with `f` applied to each immediate sub-type.
	 *
	 * @param t The type to map.
	 * @param f The mapping applied to each direct child type.
	 * @return The mapped type.
	 */
	public function mapType(t:TType, f:TType->TType) {
		switch (t) {
			case TMono(r):
				if (r.r == null)
					return t;
				return f(t);
			case TVoid, TInt, TFloat, TBool, TDynamic, TParam(_), TUnresolved(_):
				return t;
			case TEnum(_, []), TInst(_, []), TAbstract(_, []), TType(_, []):
				return t;
			case TNull(t):
				return TNull(f(t));
			case TInst(c, args):
				return TInst(c, [for (t in args) f(t)]);
			case TEnum(e, args):
				return TEnum(e, [for (t in args) f(t)]);
			case TType(t, args):
				return TType(t, [for (t in args) f(t)]);
			case TAbstract(a, args):
				return TAbstract(a, [for (t in args) f(t)]);
			case TFun(args, ret):
				return TFun([for (a in args) {name: a.name, opt: a.opt, t: f(a.t)}], f(ret));
			case TAnon(fields):
				return TAnon([for (af in fields) {name: af.name, opt: af.opt, t: f(af.t)}]);
			case TLazy(l):
				return f(l());
		}
	}

	/**
	 * Follows bound monomorphs and aliases to the underlying type.
	 *
	 * @param t The type to follow.
	 * @return The followed type.
	 */
	public function follow(t:TType) {
		return switch (t) {
			case TMono(r): if (r.r != null) follow(r.r) else t;
			case TType(t, args): follow(apply(t.t, t.params, args));
			case TNull(t): follow(t);
			case TLazy(f): follow(f());
			default: t;
		}
	}

	/**
	 * Lists the accessible fields of a type (for completion), including inherited ones.
	 *
	 * @param t The type.
	 * @return Each field's name and type.
	 */
	public function getFields(t:TType):Array<{name:String, t:TType}> {
		var fields = [];
		switch (follow(t)) {
			case TInst(c, args):
				var map = (t) -> apply(t, c.params, args);
				while (c != null) {
					for (fname in c.fields.keys()) {
						var f = c.fields.get(fname);
						if (!f.isPublic || !f.complete)
							continue;
						var name = f.name, t = map(f.t);
						if (allowAsync && StringTools.startsWith(name, "a_")) {
							t = unasync(t);
							name = name.substr(2);
						}
						fields.push({name: name, t: t});
					}
					if (c.isInterface && c.interfaces != null) {
						for (i in c.interfaces) {
							for (f in getFields(i))
								fields.push({name: f.name, t: map(f.t)});
						}
					}
					if (c.superClass == null)
						break;
					switch (c.superClass) {
						case TInst(csup, args):
							var curMap = map;
							map = (t) -> curMap(apply(t, csup.params, args));
							c = csup;
						default:
							break;
					}
				}
			case TAnon(fl):
				for (f in fl)
					fields.push({name: f.name, t: f.t});
			case TFun(args, ret):
				if (isCompletion)
					fields.push({name: "bind", t: TFun(args, TVoid)});
			case TAbstract(a, pl):
				for (v in a.forwards.keys()) {
					var t = getField(apply(a.t, a.params, pl), v, null, false);
					fields.push({name: v, t: t});
				}
			default:
		}
		return fields;
	}

	/**
	 * Resolves and validates one field access, applying type arguments and write-access checks.
	 *
	 * @param cf The field.
	 * @param ct The owning type.
	 * @param args The owning type's type arguments.
	 * @param forWrite Whether the access is a write.
	 * @param e The expression for error positions.
	 * @return The field's (specialized) type.
	 */
	function checkField(cf:CField, ct:CNamedType, args, forWrite, e) {
		if (!cf.isPublic && checkPrivate)
			error("Can't access private field " + cf.name + " on " + ct.name, e);
		if (forWrite && !cf.canWrite)
			error("Can't write readonly field " + cf.name + " on " + ct.name, e);
		var t = cf.t;
		if (cf.params != null)
			t = apply(t, cf.params, [for (i in 0...cf.params.length) makeMono()]);
		return apply(t, ct.params, args);
	}

	/**
	 * Looks up field `f` on type `t`, searching classes, anonymous structures, and abstract forwards.
	 *
	 * @param t The owning type.
	 * @param f The field name.
	 * @param e The expression for error positions.
	 * @param forWrite Whether the access is a write.
	 * @return The field's type, or null if not found.
	 */
	function getField(t:TType, f:String, e:Expr, forWrite = false) {
		switch (follow(t)) {
			case TInst(c, args):
				var cf = c.fields.get(f);
				if (cf == null && allowAsync) {
					cf = c.fields.get("a_" + f);
					if (cf != null) {
						var isPublic = true; // consider a_ prefixed as script specific
						cf = {
							isPublic: isPublic,
							canWrite: false,
							params: cf.params,
							name: cf.name,
							t: unasync(cf.t),
							complete: cf.complete
						};
						if (cf.t == null)
							cf = null;
					}
				}
				if (cf == null && c.isInterface && c.interfaces != null) {
					for (i in c.interfaces) {
						var ft = getField(i, f, e, forWrite);
						if (ft != null)
							return apply(ft, c.params, args);
					}
				}
				if (cf == null) {
					if (c.superClass == null)
						return null;
					var ft = getField(c.superClass, f, e, forWrite);
					if (ft != null)
						ft = apply(ft, c.params, args);
					return ft;
				}
				return checkField(cf, c, args, forWrite, e);
			case TDynamic:
				return makeMono();
			case TAnon(fields):
				for (af in fields)
					if (af.name == f)
						return af.t;
				return null;
			case TAbstract(a, pl) if (a.forwards.exists(f)):
				return getField(apply(a.t, a.params, pl), f, e, forWrite);
			case TAbstract(a, pl) if (a.impl != null):
				var cf = a.impl.statics.get(f);
				if (cf == null)
					return null;
				var acc = mk(null, e);
				var impl = resolveGlobal(a.impl.name, acc, Value);
				if (impl == null)
					return null;
				var t = checkField(cf, a, pl, forWrite, e);
				switch (e.e) {
					case EField(obj, f):
						if (cf.isMethod) {
							switch (callExpr?.e) {
								case null:
								case ECall(ec, params) if (ec == e):
									e.e = EField(acc, f);
									params.unshift(mk(ECast(obj), obj));
									return t;
								default:
							}
						} else {
							e.e = ECall(mk(EField(acc, "get_" + f), e), [obj]);
							return t;
						}
					default:
				}
				return null;
			default:
				return null;
		}
	}

	/**
	 * Unwraps an async/`Promise`-like type to the value it resolves to.
	 *
	 * @param t The (possibly async) type.
	 * @return The awaited value type.
	 */
	public function unasync(t:TType):TType {
		switch (follow(t)) {
			case TFun(args, ret) if (args.length > 0):
				var rargs = args.copy();
				switch (follow(rargs.shift().t)) {
					case TFun([r], _): return TFun(rargs, r.t);
					default:
				}
			default:
		}
		return null;
	}

	/**
	 * Type-checks an expression against an expected type.
	 *
	 * @param expr The expression.
	 * @param t The expected type.
	 * @return The inferred type.
	 */
	function typeExprWith(expr:Expr, t:TType) {
		var et = typeExpr(expr, WithType(t));
		unify(et, t, expr);
		return t;
	}

	/** @return A fresh, unbound monomorph type. */
	function makeMono() {
		return TMono({r: null});
	}

	/**
	 * Infers the element type produced by iterating a type.
	 *
	 * @param t The iterable type.
	 * @return The element type.
	 */
	function makeIterator(t):TType {
		return TAnon([
			{name: "next", opt: false, t: TFun([], t)},
			{name: "hasNext", opt: false, t: TFun([], TBool)}
		]);
	}

	/**
	 * Wraps an expression definition with another expression's position.
	 *
	 * @param e The expression definition.
	 * @param p The expression whose position to copy.
	 * @return The positioned expression.
	 */
	function mk(e, p):Expr {
		return {
			e: e,
			pmin: p.pmin,
			pmax: p.pmax,
			origin: p.origin,
			line: p.line
		};
	}

	/** @param t A type. @return Whether it is `String`. */
	function isString(t:TType) {
		t = follow(t);
		return t.match(TInst({name: "String"}, _));
	}

	/**
	 * Records a completion result and stops checking (by throwing a `Completion`).
	 *
	 * @param expr The expression being completed.
	 * @param t Its type.
	 */
	function onCompletion(expr:Expr, t:TType) {
		if (isCompletion)
			throw new Completion(expr, t);
	}

	/**
	 * Type-checks a field access `o.f`.
	 *
	 * @param o The object expression.
	 * @param f The field name.
	 * @param expr The whole access expression (for positions).
	 * @param withType The expected-value context.
	 * @param forWrite Whether the access is a write.
	 * @return The field's type.
	 */
	function typeField(o:Expr, f:String, expr:Expr, withType, forWrite:Bool) {
		if (f == null && isCompletion) {
			var ot = typeExpr(o, Value);
			onCompletion(expr, ot);
			return TDynamic;
		}
		var path = [{f: f, e: expr}];
		while (true) {
			switch (edef(o)) {
				case EField(e, f) if (f != null):
					path.unshift({f: f, e: o});
					o = e;
				case EIdent(i):
					path.unshift({f: i, e: o});
					return typePath(path, withType, forWrite);
				default:
					break;
			}
		}
		return readPath(typeExpr(o, Value), path, forWrite);
	}

	/**
	 * Walks a resolved field-access path, typing each step.
	 *
	 * @param ot The base object type.
	 * @param path The chain of field accesses.
	 * @param forWrite Whether the final access is a write.
	 * @return The type at the end of the path.
	 */
	function readPath(ot:TType, path:Array<{f:String, e:Expr}>, forWrite) {
		for (p in path) {
			var ft = getField(ot, p.f, p.e, p == path[path.length - 1] ? forWrite : false);
			if (ft == null) {
				error(typeStr(ot) + " has no field " + p.f, p.e);
				return TDynamic;
			}
			ot = ft;
		}
		return ot;
	}

	/**
	 * Types a dotted access path, resolving a leading type/global run before member access.
	 *
	 * @param path The chain of field accesses.
	 * @param withType The expected-value context.
	 * @param forWrite Whether the final access is a write.
	 * @return The type at the end of the path.
	 */
	function typePath(path:Array<{f:String, e:Expr}>, withType, forWrite:Bool) {
		var root = path[0];
		var l = locals.get(root.f);
		if (l != null) {
			path.shift();
			return readPath(l, path, forWrite);
		}
		var t = resolveGlobal(root.f, root.e, path.length == 1 ? withType : Value);
		if (t != null) {
			path.shift();
			return readPath(t, path, forWrite);
		}
		var fields = [];
		while (path.length > 1) {
			var name = [for (p in path) p.f].join(".");
			var union = punion(path[0].e, path[path.length - 1].e);
			var t = resolveGlobal(name, union, Value);
			if (t != null) {
				if (union.e != null)
					path[path.length - 1].e.e = union.e;
				return readPath(t, fields, forWrite);
			}
			fields.unshift(path.pop());
		}
		if (!isCompletion)
			error("Unknown identifier " + root.f, root.e);
		return TDynamic;
	}

	/**
	 * Whether a metadata list contains an entry with the given name.
	 *
	 * @param meta The metadata.
	 * @param name The name to look for.
	 * @return True if present.
	 */
	function hasMeta(meta:Metadata, name:String) {
		for (m in meta)
			if (m.name == name)
				return true;
		return false;
	}

	/**
	 * Resolves a bare identifier as a global, type, or top-down enum constructor.
	 *
	 * @param name The identifier.
	 * @param expr The expression for error positions.
	 * @param withType The expected-value context (steers top-down enum resolution).
	 * @return The resolved type, or null if unresolved.
	 */
	function resolveGlobal(name:String, expr:Expr, withType:WithType):TType {
		var g = globals.get(name);
		if (g != null) {
			return switch (g) {
				case TLazy(f): f();
				default: g;
			}
		}
		if (allowAsync) {
			g = globals.get("a_" + name);
			if (g != null)
				g = unasync(g);
			if (g != null)
				return g;
		}
		switch (name) {
			case "null":
				return makeMono();
			case "true", "false":
				return TBool;
			case "trace":
				return TDynamic;
			default:
				switch (withType) {
					// enum constructor resolution
					case WithType(et = TEnum(e, args)):
						for (c in e.constructors)
							if (c.name == name) {
								if (onTopDownEnum(e, name)) { // deprecated
									var ct = c.args == null ? et : TFun(c.args, et);
									return apply(ct, e.params, args);
								}
								var acc = getTypeAccess(et, expr, name);
								if (acc != null) {
									expr.e = acc;
									var ct = c.args == null ? et : TFun(c.args, et);
									return apply(ct, e.params, args);
								}
								break;
							}
					// abstract enum resolution
					case WithType(at = TAbstract(a, args)) if (hasMeta(a.meta, ":enum")):
						var f = a.impl.statics.get(name);
						if (f != null && hasMeta(f.meta, ":enum")) {
							var acc = getTypeAccess(TInst(a.impl, []), expr, name);
							if (acc != null) {
								expr.e = acc;
								return at;
							}
						}
					default:
				}
				// this variable resolution
				var g = locals.get("this");
				if (g != null) {
					// local this resolution
					var prev = checkPrivate;
					checkPrivate = false;
					var t = getField(g, name, expr);
					checkPrivate = prev;
					if (t != null) {
						expr.e = EField(mk(EIdent("this"), expr), name);
						return t;
					}
					// static resolution
					switch (g) {
						case TInst(c, _):
							var f = c.statics.get(name);
							if (f != null) {
								var acc = getTypeAccess(g, expr, name);
								if (acc != null) {
									expr.e = acc;
									return apply(f.t, f.params, [for (a in f.params) makeMono()]);
								}
							}
						default:
					}
				}
				// type path resolution
				var t = types.getType(name);
				if (!t.match(TUnresolved(_))) {
					var acc = getTypeAccess(t, expr);
					if (acc != null) {
						expr.e = acc;
						switch (t) {
							case TInst(c, _):
								return TAnon([for (f in c.statics) {name: f.name, t: f.t, opt: false}]);
							case TEnum(e, _):
								return TAnon([
									for (f in e.constructors)
										{name: f.name, t: f.args == null ? t : TFun(f.args, t), opt: false}
								]);
							default:
								throw "assert";
						}
					}
				}
		}
		return null;
	}

	/**
	 * Builds the expression that accesses a type value (or one of its statics) at runtime.
	 *
	 * @param t The type being accessed.
	 * @param expr The source expression.
	 * @param field An optional static field name.
	 * @return The rewritten access expression.
	 */
	function getTypeAccess(t:TType, expr:Expr, ?field:String):ExprDef {
		return null;
	}

	/**
	 * The core type-inference switch: infers the type of one expression in a given value context,
	 * recursing into sub-expressions and unifying as it goes.
	 *
	 * @param expr The expression to type.
	 * @param withType The expected-value context.
	 * @return The inferred type.
	 */
	function typeExpr(expr:Expr, withType:WithType):TType {
		if (expr == null && isCompletion)
			return switch (withType) {
				case WithType(t): t;
				default: TDynamic;
			}
		switch (edef(expr)) {
			case EConst(c):
				return switch (c) {
					case CInt(_): TInt;
					case CFloat(_): TFloat;
					case CString(_): types.t_string;
				}
			case EIdent(v):
				return typePath([{f: v, e: expr}], withType, false);
			case EBlock(el):
				var t = TVoid;
				var locals = saveLocals();
				for (e in el)
					t = typeExpr(e, e == el[el.length - 1] ? withType : NoValue);
				this.locals = locals;
				return t;
			case EVar(n, t, init):
				var vt = t == null ? makeMono() : makeType(t, expr);
				if (init != null) {
					var et = typeExpr(init, t == null ? Value : WithType(vt));
					if (t == null)
						vt = et
					else
						unify(et, vt, init);
				}
				locals.set(n, vt);
				return TVoid;
			case EParent(e):
				return typeExpr(e, withType);
			case ECall(e, params):
				switch (edef(e)) {
					case EField(val, "bind"):
						var ft = typeExpr(val, Value);
						switch (ft) {
							case TFun(args, ret):
								var remainArgs = args.copy();
								for (p in params) {
									var a = remainArgs.shift();
									if (a == null) {
										error("Too many arguments", p);
										return TFun([], ret);
									}
									typeExprWith(p, a.t);
								}
								return TFun(remainArgs, ret);
							default:
						}
					default:
				}
				var prev = callExpr;
				callExpr = expr;
				var ft = typeExpr(e, switch ([edef(e), withType]) {
					case [EIdent(_), WithType(TEnum(_))]: withType;
					default: Value;
				});
				callExpr = prev;
				switch (follow(ft)) {
					case TFun(args, ret):
						for (i in 0...params.length) {
							var a = args[i];
							if (a == null) {
								error("Too many arguments", params[i]);
								break;
							}
							var t = typeExpr(params[i], a == null ? Value : WithType(a.t));
							unify(t, a.t, params[i]);
						}
						for (i in params.length...args.length)
							if (!args[i].opt)
								error("Missing argument " + args[i].name + ":" + typeStr(args[i].t), expr);
						return ret;
					case TDynamic:
						for (p in params)
							typeExpr(p, Value);
						return makeMono();
					default:
						error(typeStr(ft) + " cannot be called", e);
						return makeMono();
				}
			case EField(o, f):
				return typeField(o, f, expr, withType, false);
			case ECheckType(v, t):
				var ct = makeType(t, expr);
				var vt = typeExpr(v, WithType(ct));
				unify(vt, ct, v);
				return ct;
			case EMeta(m, args, e):
				return checkMeta(m, args, e, expr, withType);
			case EIf(cond, e1, e2), ETernary(cond, e1, e2):
				typeExprWith(cond, TBool);
				var t1 = typeExpr(e1, withType);
				if (e2 == null)
					return t1;
				var t2 = typeExpr(e2, withType);
				if (withType == NoValue)
					return TVoid;
				if (tryUnify(t2, t1))
					return t1;
				if (tryUnify(t1, t2))
					return t2;
				unify(t2, t1, e2); // error
			case EWhile(cond, e), EDoWhile(cond, e):
				typeExprWith(cond, TBool);
				typeExpr(e, NoValue);
				return TVoid;
			case EObject(fl):
				switch (withType) {
					case WithType(follow(_) => TAnon(tfields)) if (tfields.length > 0):
						var map = [for (f in tfields) f.name => f];
						return TAnon([
							for (f in fl) {
								var ft = map.get(f.name);
								var ft = if (ft == null) {
									error("Extra field " + f.name, f.e);
									TDynamic;
								} else ft.t;
								{t: typeExprWith(f.e, ft), opt: false, name: f.name}
							}
						]);
					default:
						return TAnon([for (f in fl) {t: typeExpr(f.e, Value), opt: false, name: f.name}]);
				}
			case EBreak, EContinue:
				return TVoid;
			case EReturn(v):
				var et = v == null ? TVoid : typeExpr(v, allowReturn == null ? Value : WithType(allowReturn));
				hasReturn = true;
				if (allowReturn == null)
					error("Return not allowed here", expr);
				else
					unify(et, allowReturn, v == null ? expr : v);
				return makeMono();
			case EArrayDecl(el):
				var et = null;
				for (v in el) {
					var t = typeExpr(v, et == null ? Value : WithType(et));
					if (et == null)
						et = t
					else if (!tryUnify(t, et)) {
						if (tryUnify(et, t))
							et = t
						else
							unify(t, et, v);
					}
				}
				if (et == null)
					et = makeMono();
				return types.getType("Array", [et]);
			case EArray(a, index):
				typeExprWith(index, TInt);
				var at = typeExpr(a, Value);
				switch (follow(at)) {
					case TInst({name: "Array"}, [et]): return et;
					default: error(typeStr(at) + " is not an Array", a);
				}
			case EThrow(e):
				typeExpr(e, Value);
				return makeMono();
			case EFunction(args, body, name, ret):
				var ft = null, tret = null, targs = null;
				if (currentFunType != null) {
					switch (currentFunType) {
						case TFun(args, ret):
							ft = currentFunType;
							tret = ret;
							targs = args;
						default:
							throw "assert";
					}
					currentFunType = null;
				} else {
					tret = ret == null ? makeMono() : makeType(ret, expr);
				}
				var locals = saveLocals();
				var oldRet = allowReturn;
				var oldGDef = allowDefine;
				var oldHasRet = hasReturn;
				allowReturn = tret;
				allowDefine = false;
				hasReturn = false;
				var withArgs = null;
				if (name != null && !withType.match(WithType(follow(_) => TFun(_)))) {
					var ev = events.get(name);
					if (ev != null)
						withType = WithType(ev);
				}
				var isShortFun = switch (edef(body)) {
					case EMeta(":lambda", _): true;
					default: false;
				}
				switch (withType) {
					case WithType(follow(_) => TFun(args, ret)):
						withArgs = args;
						if (!isShortFun || follow(ret) != TVoid) unify(tret, ret, expr);
					default:
				}
				if (targs == null)
					targs = typeArgs(args, expr);
				for (i in 0...targs.length) {
					var a = targs[i];
					if (withArgs != null) {
						if (i < withArgs.length)
							unify(withArgs[i].t, a.t, expr);
						else
							error("Extra argument " + a.name, expr);
					}
					this.locals.set(a.name, a.t);
				}
				if (withArgs != null && targs.length < withArgs.length)
					error("Missing "
						+ (withArgs.length - targs.length)
						+ " arguments ("
						+ [for (i in targs.length...withArgs.length) typeStr(withArgs[i].t)].join(",") + ")",
						expr);
				typeExpr(body, NoValue);
				if (!hasReturn && !tryUnify(tret, TVoid))
					error("Missing return " + typeStr(tret), expr);
				allowDefine = oldGDef;
				allowReturn = oldRet;
				hasReturn = oldHasRet;
				this.locals = locals;
				if (ft == null) {
					ft = TFun(targs, tret);
					if (name != null)
						locals.set(name, ft);
				}
				return ft;
			case EUnop(op, _, e):
				var et = typeExpr(e, Value);
				switch (op) {
					case "++", "--", "-":
						unify(et, TInt, e);
						return et;
					case "!":
						unify(et, TBool, e);
						return et;
					default:
				}
			case EFor(v, it, e):
				var locals = saveLocals();
				var itt = typeExpr(it, Value);
				var vt = getIteratorType(itt, it);
				this.locals.set(v, vt);
				typeExpr(e, NoValue);
				this.locals = locals;
				return TVoid;
			case EForGen(it, e):
				Tools.getKeyIterator(it, function(vk, vv, it) {
					if (vk == null) {
						error("Invalid for expression", it);
						return;
					}
					var locals = saveLocals();
					var itt = typeExpr(it, Value);
					var types = getKeyIteratorTypes(itt, it);
					this.locals.set(vk, types.key);
					this.locals.set(vv, types.value);
					typeExpr(e, NoValue);
					this.locals = locals;
				});
				return TVoid;
			case EBinop(op, e1, e2):
				switch (op) {
					case "&", "|", "^", ">>", ">>>", "<<":
						typeExprWith(e1, TInt);
						typeExprWith(e2, TInt);
						return TInt;
					case "=":
						if (allowDefine) {
							switch (edef(e1)) {
								case EIdent(i) if (!locals.exists(i) && !globals.exists(i)):
									var vt = typeExpr(e2, Value);
									locals.set(i, vt);
									return vt;
								default:
							}
						}
						var vt = switch (edef(e1)) {
							case EIdent(v): typePath([{f: v, e: e1}], withType, true);
							case EField(o, f): typeField(o, f, e1, withType, true);
							default: typeExpr(e1, Value);
						}
						typeExprWith(e2, vt);
						return vt;
					case "+":
						var t1 = typeExpr(e1, WithType(TInt));
						var t2 = typeExpr(e2, WithType(t1));
						tryUnify(t1, t2);
						switch ([follow(t1), follow(t2)]) {
							case [TInt, TInt]:
								return TInt;
							case [TFloat, TInt], [TInt, TFloat], [TFloat, TFloat]:
								return TFloat;
							case [TDynamic, _], [_, TDynamic]:
								return TDynamic;
							case [t1, t2]:
								if (isString(t1) || isString(t2))
									return types.t_string;
								unify(t1, TFloat, e1);
								unify(t2, TFloat, e2);
						}
					case "-", "*", "/", "%":
						var t1 = typeExpr(e1, WithType(TInt));
						var t2 = typeExpr(e2, WithType(t1));
						if (!tryUnify(t1, t2))
							unify(t2, t1, e2);
						switch ([follow(t1), follow(t2)]) {
							case [TInt, TInt]:
								if (op == "/")
									return TFloat;
								return TInt;
							case [TFloat | TDynamic, TInt | TDynamic], [TInt | TDynamic, TFloat | TDynamic], [TFloat, TFloat]:
								return TFloat;
							default:
								unify(t1, TFloat, e1);
								unify(t2, TFloat, e2);
						}
					case "&&", "||":
						typeExprWith(e1, TBool);
						typeExprWith(e2, TBool);
						return TBool;
					case "...":
						typeExprWith(e1, TInt);
						typeExprWith(e2, TInt);
						return makeIterator(TInt);
					case "==", "!=":
						var t1 = typeExpr(e1, Value);
						var t2 = typeExpr(e2, WithType(t1));
						if (!tryUnify(t1, t2))
							unify(t2, t1, e2);
						return TBool;
					case ">", "<", ">=", "<=":
						var t1 = typeExpr(e1, Value);
						var t2 = typeExpr(e2, WithType(t1));
						if (!tryUnify(t1, t2))
							unify(t2, t1, e2);
						switch (follow(t1)) {
							case TInt, TFloat, TBool, TInst({name: "String"}, _):
							default:
								error("Cannot compare " + typeStr(t1), expr);
						}
						return TBool;
					default:
						if (op.charCodeAt(op.length - 1) == "=".code) {
							var t = typeExpr(mk(EBinop(op.substr(0, op.length - 1), e1, e2), expr), withType);
							return typeExpr(mk(EBinop("=", e1, e2), expr), withType);
						}
						error("Unsupported operation " + op, expr);
				}
			case ETry(etry, v, et, ecatch):
				var vt = typeExpr(etry, withType);

				var old = locals.get(v);
				locals.set(v, makeType(et, ecatch));
				var ct = typeExpr(ecatch, withType);
				if (old != null)
					locals.set(v, old)
				else
					locals.remove(v);

				if (withType == NoValue)
					return TVoid;
				if (tryUnify(vt, ct))
					return ct;
				unify(ct, vt, ecatch);
				return vt;
			case ESwitch(value, cases, defaultExpr):
				var tmin = null;
				var vt = typeExpr(value, Value);
				inline function mergeType(t, p) {
					if (withType != NoValue) {
						if (tmin == null)
							tmin = t;
						else if (!tryUnify(t, tmin)) {
							unify(tmin, t, p);
							tmin = t;
						}
					}
				}
				for (c in cases) {
					for (v in c.values) {
						var ct = typeExpr(v, WithType(vt));
						unify(ct, vt, v);
					}
					var et = typeExpr(c.expr, withType);
					mergeType(et, c.expr);
				}
				if (defaultExpr != null)
					mergeType(typeExpr(defaultExpr, withType), defaultExpr);
				return withType == NoValue ? TVoid : tmin == null ? makeMono() : tmin;
			case ECast(e, t):
				var et = typeExpr(e, Value);
				return t == null ? makeMono() : makeType(t, expr);
			case ENew(cl, params):
		}
		error("Don't know how to type " + edef(expr).getName(), expr);
		return TDynamic;
	}

	/**
	 * Handles a metadata annotation during checking (e.g. an untyped escape).
	 *
	 * @param m The metadata name.
	 * @param args The metadata arguments.
	 * @param next The annotated expression.
	 * @param expr The whole meta expression (for positions).
	 * @param withType The expected-value context.
	 * @return The resulting type, or null to fall through to normal checking.
	 */
	function checkMeta(m:String, args:Array<Expr>, next:Expr, expr:Expr, withType) {
		if (m == ":untyped" && allowUntypedMeta)
			return makeMono();
		return typeExpr(next, withType);
	}

	/**
	 * Infers the element type of a `for (x in it)` iterator.
	 *
	 * @param itt The iterator/iterable type.
	 * @param it The iterator expression (for errors).
	 * @return The element type.
	 */
	function getIteratorType(itt:TType, it:Expr) {
		switch (follow(itt)) {
			case TInst({name: "Array"}, [t]):
				return t;
			default:
		}
		var ft = getField(itt, "iterator", it);
		if (ft == null)
			switch (itt) {
				case TAbstract(a, args):
					// special case : we allow unconditional access
					// to an abstract iterator() underlying value (eg: ArrayProxy)
					var at = apply(a.t, a.params, args);
					return getIteratorType(at, it);
				default:
			}
		if (ft != null)
			switch (ft) {
				case TFun([], ret):
					ft = ret;
				default:
					ft = null;
			}
		var t = makeMono();
		var iter = makeIterator(t);
		unify(ft != null ? ft : itt, iter, it);
		return t;
	}

	/**
	 * Infers the key and value types of a `for (k => v in it)` iterator.
	 *
	 * @param itt The key-value iterator/iterable type.
	 * @param it The iterator expression (for errors).
	 * @return The key and value types.
	 */
	function getKeyIteratorTypes(itt:TType, it:Expr) {
		switch (follow(itt)) {
			case TInst({name: "Array"}, [t]):
				return {key: TInt, value: t};
			default:
		}
		var ft = getField(itt, "keyValueIterator", it);
		if (ft == null)
			switch (itt) {
				case TAbstract(a, args):
					// special case : we allow unconditional access
					// to an abstract keyValueIterator() underlying value (eg: ArrayProxy)
					var at = apply(a.t, a.params, args);
					return getKeyIteratorTypes(at, it);
				default:
			}
		if (ft != null)
			switch (ft) {
				case TFun([], ret):
					ft = ret;
				default:
					ft = null;
			}
		var key = makeMono();
		var value = makeMono();
		var iter = makeIterator(TAnon([{name: "key", t: key, opt: false}, {name: "value", t: value, opt: false}]));
		unify(ft != null ? ft : itt, iter, it);
		return {key: key, value: value};
	}
}
