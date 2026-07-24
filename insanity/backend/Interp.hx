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
import insanity.backend.CallStack;
import insanity.backend.types.Scripted;
import haxe.PosInfos;
import haxe.Constraints.IMap;
import Type as HaxeType;
import Reflect as HaxeReflect;
import insanity.custom.InsanityType.ICustomEnumValueType;
import insanity.custom.InsanityReflect as Reflect;
import insanity.custom.InsanityType as Type;
import insanity.custom.InsanityStd as Std;

using StringTools;
using insanity.tools.Tools;
using insanity.backend.TypeCollection;
using insanity.backend.types.Abstract;

enum Stop {
	SBreak;
	SContinue;
	SReturn;
}

enum Resolve {
	RNormal(f:String);
	RMaybe(f:String);
	RExpr(e:Expr);
}

typedef Variable = {
	var r:Dynamic;
	var ?a:InsanityAbstract;

	var ?isFinal:Bool;
	var ?access:Array<FieldAccess>;

	var ?get:String;
	var ?set:String;
}

class Interp {
	public var usings:Array<Dynamic>;
	public var imports:Map<String, Dynamic>;
	public var variables:Map<String, Dynamic>;

	public var parent:Dynamic = null;
	public var environment:Environment;

	public var defineGlobals:Bool = false;
	public var superConstructorAllowed:Bool = false;

	static var localsPool:Array<Map<String, Variable>> = [];

	var locals(get, never):Map<String, Variable>;
	var binops:Map<String, Expr->Expr->Dynamic>;

	public var callStackDepth:Int = 200;

	var stack:CallStack;

	var inTry:Bool;
	var metas:Metadata = [];
	var resolveFields:Array<Resolve> = [];
	var captures:Map<String, Dynamic>;
	var declared:Array<{n:String, old:Variable}>;
	var returnValue:Dynamic;

	static var void(default, never):Dynamic = {};
	static var accessingInterp:Interp = null;

	var position:Position = {origin: 'hscript', line: 0};
	var origin(get, never):String;
	var curAccess:String = '';

	public var canDefer:Bool = false;
	public var canInit:Bool = false;

	/** The scripted class this interpreter runs on behalf of, used for `private` checks. */
	public var ownerClass:InsanityScriptedClass = null;

	public function new(?environment:Environment, ?parent:Dynamic) {
		this.environment = environment;
		this.parent = parent;

		stack = new CallStack();

		imports = new Map();
		usings = new Array();
		captures = new Map();
		variables = new Map();
		declared = new Array();

		setDefaults();
		initOps();
	}

	public function setDefaults(wipe:Bool = true, includeConfig:Bool = true) {
		if (wipe) {
			imports.clear();
			usings.resize(0);
			variables.clear();
		}

		if (includeConfig) {
			for (k => v in Config.globalVariables)
				variables.set(k, v);

			for (k => v in Config.globalImports)
				importPath(k.split('.'), v);
		}

		variables.set('trace', Reflect.makeVarArgs(function(el) {
			var inf = posInfos();
			var v = el.shift();
			if (el.length > 0)
				inf.customParams = el;
			haxe.Log.trace(Std.string(v), inf);
		}));
	}

	public function toString():String {
		return '(parent: $parent | origin: $origin)';
	}

	public function posInfos():PosInfos {
		return cast {fileName: position.origin, lineNumber: position.line};
	}

	function get_locals():Map<String, Variable> {
		return stack.first()?.locals;
	}

	function get_origin():String {
		return position.origin;
	}

	function initOps() {
		binops = [
			"=" => assign,
			"+" => function(e1, e2) return expr(e1) + expr(e2),
			"-" => function(e1, e2) return expr(e1) - expr(e2),
			"*" => function(e1, e2) return expr(e1) * expr(e2),
			"/" => function(e1, e2) return expr(e1) / expr(e2),
			"%" => function(e1, e2) return expr(e1) % expr(e2),
			"&" => function(e1, e2) return expr(e1) & expr(e2),
			"|" => function(e1, e2) return expr(e1) | expr(e2),
			"^" => function(e1, e2) return expr(e1) ^ expr(e2),
			"<<" => function(e1, e2) return expr(e1) << expr(e2),
			">>" => function(e1, e2) return expr(e1) >> expr(e2),
			">>>" => function(e1, e2) return expr(e1) >>> expr(e2),
			"==" => function(e1, e2) return eqValues(expr(e1), expr(e2)),
			"!=" => function(e1, e2) return !eqValues(expr(e1), expr(e2)),
			">=" => function(e1, e2) return expr(e1) >= expr(e2),
			"<=" => function(e1, e2) return expr(e1) <= expr(e2),
			">" => function(e1, e2) return expr(e1) > expr(e2),
			"<" => function(e1, e2) return expr(e1) < expr(e2),
			"||" => function(e1, e2) return expr(e1) == true || expr(e2) == true,
			"&&" => function(e1, e2) return expr(e1) == true && expr(e2) == true,
			"..." => function(e1, e2) return new IntIterator(expr(e1), expr(e2)),
			"is" => function(e1, e2) return #if (haxe_ver >= 4.2) Std.isOfType #else Std.is #end (expr(e1), expr(e2)),
			"??" => function(e1, e2) return expr(e1) ?? expr(e2)
		];
		assignOp("+=", function(v1:Dynamic, v2:Dynamic) return v1 + v2);
		assignOp("-=", function(v1:Float, v2:Float) return v1 - v2);
		assignOp("*=", function(v1:Float, v2:Float) return v1 * v2);
		assignOp("/=", function(v1:Float, v2:Float) return v1 / v2);
		assignOp("%=", function(v1:Float, v2:Float) return v1 % v2);
		assignOp("&=", function(v1, v2) return v1 & v2);
		assignOp("|=", function(v1, v2) return v1 | v2);
		assignOp("^=", function(v1, v2) return v1 ^ v2);
		assignOp("<<=", function(v1, v2) return v1 << v2);
		assignOp(">>=", function(v1, v2) return v1 >> v2);
		assignOp(">>>=", function(v1, v2) return v1 >>> v2);
		assignOp("??=", function(v1, v2) return v1 ?? v2);
	}

	function setVar(name:String, v:Dynamic):Dynamic {
		if (AbstractTools.isAbstract(v))
			v = v.__a;

		var iv = imports.get(name);
		if (iv != null) {
			if (iv is Mirror) {
				switch (iv) {
					case MProperty(t, f):
						if (curAccess == f) {
							Reflect.setField(t, f, v);
						} else {
							Reflect.setProperty(t, f, v);
						}
						return Reflect.field(t, f);
					default:
				}
			}

			error(ECustom('Invalid assign'));
		}

		if (variables.exists(name)) {
			var vv = variables.get(name);
			if (vv is Mirror) {
				switch (vv) {
					case MProperty(t, f):
						if (curAccess == f) {
							Reflect.setField(t, f, v);
						} else {
							Reflect.setProperty(t, f, v);
						}
						return Reflect.field(t, f);
					default:
				}
			}

			variables.set(name, v);
		} else {
			if (stack.length <= 1 && defineGlobals) { // global scope
				variables.set(name, v);
				return v;
			}

			error(EUnknownVariable(name));
		}

		return v;
	}

	function assign(e1:Expr, e2:Expr):Dynamic {
		var v = expr(e2);
		switch (Tools.expr(e1)) {
			case EIdent(id):
				if (locals.exists(id)) {
					setLocal(id, v);
				} else {
					setVar(id, v);
				}
			case EField(e, f, _):
				v = set(expr(e), f, v);
			case EArray(e, index):
				var arr:Dynamic = expr(e);
				var index:Dynamic = expr(index);
				if (isMap(arr)) {
					setMapValue(arr, index, v);
				} else {
					arr[index] = v;
				}

			default:
				error(EInvalidOp("="));
		}
		return v;
	}

	function assignOp(op, fop:Dynamic->Dynamic->Dynamic) {
		binops.set(op, function(e1, e2) return evalAssignOp(op, fop, e1, e2));
	}

	function evalAssignOp(op, fop, e1, e2):Dynamic {
		var v;
		switch (Tools.expr(e1)) {
			case EIdent(id):
				v = fop(expr(e1), expr(e2));

				if (locals.exists(id)) {
					setLocal(id, v);
				} else {
					setVar(id, v);
				}
			case EField(e, f, _):
				var obj = expr(e);
				v = fop(get(obj, f), expr(e2));
				v = set(obj, f, v);
			case EArray(e, index):
				var arr:Dynamic = expr(e);
				var index:Dynamic = expr(index);
				if (isMap(arr)) {
					v = fop(getMapValue(arr, index), expr(e2));
					setMapValue(arr, index, v);
				} else {
					v = fop(arr[index], expr(e2));
					arr[index] = v;
				}
			default:
				return error(EInvalidOp(op));
		}
		return v;
	}

	public function getLocal(id:String, ?map:Map<String, Variable>):Dynamic {
		var map:Map<String, Variable> = (map ?? locals);
		var l:Variable = map.get(id);
		if (l == null)
			return null;

		switch (l.get) {
			case 'null':
				if (accessingInterp != this)
					throw 'This expression cannot be accessed for reading';
				return (l.a ?? l.r);
			case 'never':
				throw 'This expression cannot be accessed for reading';
				return null;
			case 'get' | 'dynamic' if (getMeta(':bypassAccessor') != null):
				return (l.a ?? l.r);
			case 'get' | 'dynamic':
				if (curAccess == id)
					return l.r;

				var hasLocal:Bool = locals.exists('get_$id');
				if (hasLocal || variables.exists('get_$id')) {
					var prevAccess:String = curAccess;
					curAccess = id;
					var v = Reflect.callMethod(this, hasLocal ? locals.get('get_$id').r : variables.get('get_$id'), []);
					curAccess = prevAccess;
					return v;
				}

				error(ECustom('Method get_$id required by property $id is missing'));
				return null;
			case 'default' | null:
				return (l.a ?? l.r);
			default:
				throw 'Invalid property accessor';
				return null;
		}
	}

	public function setLocal(id:String, v:Dynamic, ?map:Map<String, Variable>):Dynamic {
		var map:Map<String, Variable> = (map ?? locals);
		var l:Variable = map.get(id);
		if (l == null)
			return null;

		if (l.isFinal)
			throw 'Cannot assign to final';

		if (l.access != null && Reflect.isFunction(l.r) && !l.access.contains(ADynamic))
			throw 'Cannot rebind method $id: please use \'dynamic\' before method declaration';

		switch (l.set) {
			case 'null':
				if (accessingInterp != this)
					throw 'This expression cannot be accessed for writing';
				return l.r = v;
			case 'never':
				throw 'This expression cannot be accessed for writing';
				return null;
			case 'set' | 'dynamic' if (getMeta(':bypassAccessor') != null):
				return l.r = v;
			case 'set' | 'dynamic':
				if (curAccess == id)
					return l.r = v;

				var hasLocal:Bool = locals.exists('set_$id');
				if (hasLocal || variables.exists('set_$id')) {
					var prevAccess:String = curAccess;
					curAccess = id;
					Reflect.callMethod(this, hasLocal ? locals.get('set_$id').r : variables.get('set_$id'), [v]);
					curAccess = prevAccess;
					return l.r;
				}

				error(ECustom('Method set_$id required by property $id is missing'));
				return null;
			case 'default' | null:
				return l.r = v;
			default:
				error(ECustom('Invalid property accessor ${l.set}'));
				return null;
		}
	}

	function increment(e:Expr, prefix:Bool, delta:Int):Dynamic {
		position = e.pos;
		var e = e.e;

		switch (e) {
			case EIdent(id):
				var l = locals.get(id);
				var v:Dynamic = (locals.exists(id) ? getLocal(id) : resolve(id));
				if (prefix) {
					v += delta;
					if (locals.exists(id))
						setLocal(id, v)
					else
						setVar(id, v);
				} else {
					if (locals.exists(id))
						setLocal(id, v + delta)
					else
						setVar(id, v + delta);
				}
				return v;
			case EField(e, f, _):
				var obj = expr(e);
				var v:Dynamic = get(obj, f);
				if (prefix) {
					v += delta;
					set(obj, f, v);
				} else
					set(obj, f, v + delta);
				return v;
			case EArray(e, index):
				var arr:Dynamic = expr(e);
				var index:Dynamic = expr(index);
				if (isMap(arr)) {
					var v = getMapValue(arr, index);
					if (prefix) {
						v += delta;
						setMapValue(arr, index, v);
					} else {
						setMapValue(arr, index, v + delta);
					}
					return v;
				} else {
					var v = arr[index];
					if (prefix) {
						v += delta;
						arr[index] = v;
					} else
						arr[index] = v + delta;
					return v;
				}
			default:
				return error(EInvalidOp((delta > 0) ? "++" : "--"));
		}
	}

	public function executeModule(decls:Array<ModuleDecl>, path:String):Void {
		try {
			if (stack.length == 0)
				pushStack(SModule(path));

			for (decl in decls) {
				position = decl.pos;

				switch (decl.d) {
					default:
					case DUsing(path):
						usingType(path);
					case DImport(path, mode):
						importPath(path, mode);
				}
			}
		} catch (e:haxe.Exception) {
			if (e is InterpException) {
				throw e;
			} else {
				pushStack();

				throw new InterpException(stack, e.message);
			}
		}
	}

	public function execute(expr:Expr):Dynamic {
		try {
			stack.stack.resize(0);
			declared = new Array();

			return exprReturn(expr);
		} catch (e:haxe.Exception) {
			if (e is InterpException) {
				throw e;
			} else {
				pushStack();

				throw new InterpException(stack, e.message);
			}
		}

		return null;
	}

	function exprReturn(e, ?t:CType):Dynamic {
		try {
			return expr(e, t);
		} catch (e:Stop) {
			#if cpp
			if (!(e is Stop))
				throw e;
			#end

			switch (e) {
				case SBreak:
					throw "Invalid break";
				case SContinue:
					throw "Invalid continue";
				case SReturn:
					var v = returnValue;
					returnValue = null;
					return v;
			}
		}
		return null;
	}

	function pushStack(?item:StackItem, ?locals:Map<String, Variable>) {
		var last:Stack = stack.stack.shift();

		if (last != null) {
			stack.stack.unshift({
				locals: last.locals,
				item: switch (last.item) {
					case SFilePos(item, _, _): SFilePos(item, position.origin, position.line, position.column);
					default: SFilePos(last.item, position.origin, position.line, position.column);
				}
			});
		}
		if (item != null) {
			stack.stack.unshift({locals: locals ?? duplicate(), item: item});

			if (stack.length > callStackDepth)
				error(ECustom('Stack overflow'));
		}
	}

	function shiftStack(put:Bool = true):Stack {
		var item:Stack = stack.stack.shift();

		if (put)
			localsPool.push(item.locals);

		return item;
	}

	inline function duplicate(?h:Map<String, Variable>):Map<String, Variable> {
		if (localsPool.length > 0) {
			var locals:Map<String, Variable> = localsPool.pop();

			if (h != null) {
				locals.clear();
				for (k => v in h)
					locals.set(k, v);
			}

			return locals;
		} else {
			return (h?.copy() ?? new Map());
		}
	}

	function restore(old:Int) {
		while (declared.length > old) {
			var d = declared.pop();

			if (d.old == null) {
				locals.remove(d.n);
			} else {
				locals.set(d.n, d.old);
			}
		}
	}

	function error(e:Error, rethrow = false):Dynamic {
		pushStack();

		var exception:InterpException = new InterpException(stack, Printer.errorToString(e));
		if (rethrow)
			this.rethrow(exception)
		else
			throw exception;

		return null;
	}

	inline function rethrow(e:Dynamic) {
		#if hl
		hl.Api.rethrow(e);
		#else
		throw e;
		#end
	}

	function createEnum(t:Enum<Dynamic>, i:Int, ?args:Array<Dynamic>):EnumValue {
		try {
			return Type.createEnumIndex(t, i, args);
		} catch (e:haxe.Exception) {
			throw 'Failed to construct enum of type ${Type.getEnumName(t)}';
		}
	}

	function createAbstractEnum(t:Class<InsanityAbstract>, i:Int):InsanityAbstract {
		try {
			return AbstractTools.createEnumIndex(t, i);
		} catch (e:haxe.Exception) {
			var t:Dynamic = t;
			throw 'Failed to construct enum of type ${t.impl}';
		}
	}

	// Enum equality is structural in Haxe, so `==`/`!=` compare scripted enum values by
	// constructor + arguments rather than object identity. Everything else keeps native `==`.
	inline function eqValues(a:Dynamic, b:Dynamic):Bool {
		if (a is ICustomEnumValueType && b is ICustomEnumValueType)
			return cast(a, ICustomEnumValueType).eq(b);
		return a == b;
	}

	// Whether enum `t`'s constructor at index `i` takes parameters. Scripted enums answer
	// from their decl; native enums are probed by whether the no-arg value exists in allEnums.

	/**
	 * Returns the live instance of a scripted enum. A `Mirror.MEnumValue` can outlive the enum
	 * instance it captured (e.g. a module reloaded under it), leaving `values`/`decl` null; the
	 * environment always maps the enum's path to the current one, so swap to that when the held
	 * instance looks dead. Non-scripted and healthy instances pass straight through.
	 */
	function liveEnum(t:Dynamic):Dynamic {
		if (t is InsanityScriptedEnum) {
			var e:InsanityScriptedEnum = cast t;
			if ((!e.initialized || e.values == null) && environment != null) {
				var live:Dynamic = environment.resolve(e.path);
				if (live != null && live is InsanityScriptedEnum)
					return live;
			}
		}
		return t;
	}

	/**
	 * Materializes a bare enum constructor `Mirror.MEnumValue`. Re-resolves the enum to its live
	 * instance first (a cached import can outlive a reloaded module), so a bare `Foo` builds
	 * against the current type exactly like qualified `Enum.Foo`. A parameterized constructor
	 * yields a varargs builder; a parameterless one yields the value itself so it matches `case Foo`.
	 */
	function resolveEnumValue(t:Dynamic, i:Int):Dynamic {
		t = liveEnum(t);
		if (enumConstructorHasArgs(t, i))
			return Reflect.makeVarArgs(function(params:Array<Dynamic>) return createEnum(t, i, params));
		return createEnum(t, i);
	}

	function enumConstructorHasArgs(t:Dynamic, i:Int):Bool {
		if (t is InsanityScriptedEnum)
			return cast(t, InsanityScriptedEnum).constructorHasArgs(i);

		var constructs:Array<String> = HaxeType.getEnumConstructs(t);
		if (constructs == null || i < 0 || i >= constructs.length)
			return false;

		var name:String = constructs[i];
		for (v in HaxeType.allEnums(t))
			if (HaxeType.enumConstructor(v) == name)
				return false;
		return true;
	}

	inline function resolveMirror(v:Dynamic):Dynamic {
		if (v is Mirror) {
			switch (v) {
				default:
					return v;
				case MProperty(t, f):
					if (curAccess == f) {
						return Reflect.field(t, f);
					} else {
						return Reflect.getProperty(t, f);
					}
				case MEnumValue(t, i):
					return resolveEnumValue(t, i);
				case MAbstractEnumValue(t, i):
					return createAbstractEnum(t, i);
			}
		} else {
			return v;
		}
	}

	public function resolve(id:String):Dynamic {
		if (imports.exists(id)) {
			var v:Dynamic = imports.get(id);

			if (v == null)
				error(ECustom('Module $id does not define type $id'));

			return resolveMirror(v);
		}

		if (!variables.exists(id))
			error(EUnknownVariable(id));

		return resolveMirror(variables.get(id));
	}

	public function isResolvable(id:String):Bool {
		return (imports.exists(id) || variables.exists(id));
	}

	function importType(name:String, t:Dynamic, enumValueImport:Bool = true) {
		if (t == null)
			return;

		if (canInit && t is IInsanityType && t.module != null && !t.initializing && !t.initialized && !t.failed)
			t.module.startType(environment, t);

		if (t is InsanityScriptedTypedef) {
			var alias:Dynamic = cast(t, InsanityScriptedTypedef).alias;

			if (alias != null)
				imports.set(name, alias);
		} else if (t is InsanityScriptedEnum) {
			imports.set(name, t);

			if (enumValueImport)
				importEnumValues(t);
		} else if (t is IInsanityType) {
			imports.set(name, t);
		} else if (t is Class) {
			if (Type.getSuperClass(t) == InsanityAbstract && t.isEnum) {
				for (i => construct in AbstractTools.getEnumConstructs(t))
					imports.set(construct, MAbstractEnumValue(t, i));
				imports.set(name, t);
				return;
			}

			imports.set(name, t);
		} else if (t is Enum) {
			imports.set(name, t);

			if (enumValueImport)
				importEnumValues(t);
		} else {
			throw 'Invalid import type $t';
		}
	}

	function importEnumValues(t:Dynamic) {
		for (i => v in Type.getEnumConstructs(t))
			imports.set(v, MEnumValue(t, i));
	}

	function importPath(path:Array<String>, mode:ImportMode):Void {
		if (mode == IAll) {
			var fullPath:String = path.join('.');
			var types:Array<TypeInfo> = Tools.listTypesEx(fullPath, true, [TypeCollection.main, environment?.types]);

			if (types == null)
				return;

			imports.set(fullPath.substr(fullPath.lastIndexOf('.') + 1), null);
			for (type in types) {
				if (type.module != type.name && type.name != 'Main')
					continue; // lol
				if (type.name.indexOf('_Impl_') > -1 || type.name.startsWith('InsanityAbstract_'))
					continue;

				importType(type.name, type.kind == 'abstract' ? AbstractTools.resolve(type.compilePath()) : type.resolve(environment), false);
			}

			return;
		}

		var fields:Array<String> = [];

		var i:Int = path.length;
		while (i-- > 0) {
			var fullPath:String = path.slice(0, i + 1).join('.');

			if (path[i].isTypeIdentifier()) {
				var types:Array<TypeInfo> = Tools.listTypesEx(fullPath, [TypeCollection.main, environment?.types]);

				if (types != null) {
					var field:String = fields.shift();
					if (fields.length > 0)
						error(EUnexpected(field));

					if (field != null) {
						var t:Dynamic = null;
						for (type in types) {
							if (type.name == path[i])
								t = type.resolve(environment);

							if (type.name == '${path[i]}_Fields_') {
								var t = type.resolve(environment);

								if (!Type.getClassFields(t).contains(field))
									continue;

								switch (mode) {
									case IAsName(alias):
										return imports.set(alias, MProperty(t, field));
									default:
										return imports.set(field, MProperty(t, field));
								}
							}
						}

						if (t is Class || t is InsanityScriptedClass) {
							if (!Type.getClassFields(t).contains(field))
								error(ECustom('Module ${path[i]} does not define field $field'));

							switch (mode) {
								case IAsName(alias):
									return imports.set(alias, MProperty(t, field));
								default:
									return imports.set(field, MProperty(t, field));
							}
						} else if (t is Enum || t is InsanityScriptedEnum) {
							var i:Int = Type.getEnumConstructs(t).indexOf(field);

							if (i >= 0) {
								switch (mode) {
									case IAsName(alias):
										return imports.set(alias, MEnumValue(t, i));
									default:
										return imports.set(field, MEnumValue(t, i));
								}
							} else {
								error(EUnknownField(path[i], field));
							}
						} else {
							error(ECustom('Module ${path[i]} does not define type $field'));
						}
					}

					switch (mode) {
						case IAsName(alias):
							for (type in types) {
								if (type.name == path[i]) {
									importType(alias, type.resolve(environment));

									return;
								}
							}

							error(ECustom('Module ${path[i]} does not define ${path[i]}'));

						default:
							imports.set(path[i], null);

							for (type in types) {
								if (type.name.indexOf('_Impl_') > -1)
									continue;

								if (type.name.endsWith('_Fields_')) {
									var t = type.resolve(environment);

									if (imports.get(path[i]) == null)
										imports.set(path[i], t);

									for (field in Reflect.fields(t))
										imports.set(field, MProperty(t, field));

									continue;
								}

								importType(type.name, type.kind == 'abstract' ? AbstractTools.resolve(type.compilePath()) : type.resolve(environment));
							}
					}

					return;
				}
			}

			fields.unshift(path[i]);
		}

		error(EUnknownType(path.join('.')));
	}

	function usingType(path:Array<String>):Void {
		var tf:String = null;

		var i:Int = path.length;
		while (i-- > 0) {
			var fullPath:String = path.slice(0, i + 1).join('.');

			if (path[i].isTypeIdentifier()) {
				var types:Array<TypeInfo> = Tools.listTypesEx(fullPath, [TypeCollection.main, environment?.types]);

				if (types != null && types.length > 0) {
					for (type in types) {
						var t = type.resolve();
						if (t is Class && !usings.contains(t))
							usings.push(t);
						imports.set(type.name, t);
					}

					return;
				}

				if (tf != null)
					error(ECustom('Module ${path[i]} does not define type $tf'));
			}

			if (tf != null)
				break;
			tf = path[i];
		}

		error(EUnknownType(path.join('.')));
	}

	public function startDecl(decl:ModuleDecl) {
		position = decl.pos;

		switch (decl.d) {
			case DClass(m):
				if (variables.exists(m.name))
					return;

				var cls = new InsanityScriptedClass(m);
				cls.init(environment, this);
				cls.initialized = true;

				imports.set(m.name, cls);

			case DInterface(m):
				if (variables.exists(m.name))
					return;

				var iface = new InsanityScriptedInterface(m);
				iface.init(environment, this);
				iface.initialized = true;

				imports.set(m.name, iface);

			case DEnum(m):
				if (variables.exists(m.name))
					return;

				var cls = new InsanityScriptedEnum(m);
				cls.init(environment, this);
				cls.initialized = true;

				imports.set(m.name, cls);

			case DTypedef(m):
				if (variables.exists(m.name))
					return;

				var cls = new InsanityScriptedTypedef(m);
				cls.init(environment, this);
				cls.initialized = true;

				if (cls.alias != null)
					imports.set(m.name, cls.alias);

			default:
		}
	}

	public function buildFunction(?name:String, params:Array<Argument>, fexpr:Expr, ?ret:CType, ?id:Int, ?functionLocals:Map<String, Variable>,
			su:Bool = false) {
		var capturedLocals = (functionLocals == null ? duplicate(locals) : null);

		var hasOpt = false, hasRest = false, minParams = 0;

		for (p in params) {
			if (p.opt) {
				hasOpt = true;
			} else if (p.rest) {
				hasRest = true;
			} else {
				minParams++;
			}
		}

		var f = Reflect.makeVarArgs(function(args:Array<Dynamic>) {
			superConstructorAllowed = su;

			if (args?.length ?? 0 != params.length) {
				if (args.length < minParams) {
					var str = "Invalid number of parameters. Got " + args.length + ", required " + minParams;
					if (name != null)
						str += " for function '" + name + "'";
					error(ECustom(str));
				}
				// make sure mandatory args are forced
				var args2 = [];
				var extraParams = args.length - minParams;
				var pos = 0;
				for (p in params) {
					if (p.rest) {
						if (pos < args.length)
							args2.push(args[pos++]);
					} else if (p.opt) {
						if (extraParams > 0) {
							args2.push(args[pos++]);
							extraParams--;
						} else {
							args2.push(p.value == null ? null : expr(p.value));
						}
					} else
						args2.push(args[pos++]);
				}
				if (hasRest)
					args2 = args2.concat(args.slice(params.length));
				args = args2;
			}
			var old = declared.length;
			pushStack(name == null ? SLocalFunction(id) : SMethod(position.origin, name), functionLocals ?? duplicate(capturedLocals));

			for (i in 0...params.length) {
				var name:String = params[i].name;

				declared.push({n: name, old: locals.get(name)});

				if (i == params.length - 1 && hasRest) {
					locals.set(name, {r: args.slice(params.length - 1)});
				} else {
					locals.set(name, {r: tryCast(args[i], params[i].t)});
				}
			}

			var r = null;
			if (inTry) {
				try {
					r = tryCast(exprReturn(fexpr), ret);
				} catch (e:Dynamic) {
					shiftStack(functionLocals == null);
					#if neko
					neko.Lib.rethrow(e);
					#else
					throw e;
					#end
				}
			} else {
				r = tryCast(exprReturn(fexpr), ret);
			}

			restore(old);

			shiftStack(functionLocals == null);
			superConstructorAllowed = false;

			return r;
		});

		if (name != null) {
			if (stack.length > 1) { // function-in-function is a local function
				declared.push({n: name, old: locals.get(name)});
				var ref = {r: f};
				locals.set(name, ref);
				capturedLocals.set(name, ref); // allow self-recursion
			} else { // global function
				if (defineGlobals) {
					variables.set(name, f);
				} else {
					locals.set(name, {r: f});
				}
			}
		}

		return f;
	}

	public function expr(e:Expr, ?t:CType, void:Bool = false, mapCompr:Bool = false):Dynamic {
		Type.environment = environment;
		accessingInterp = this;
		position = e.pos;
		var e = e.e;

		if (stack.length == 0)
			pushStack(SScript(position.origin));

		switch (e) {
			case EDecl(decl):
				startDecl(decl);
			case EUsing(path):
				usingType(path);
			case EImport(path, mode):
				importPath(path, mode);
			case EConst(c):
				switch (c) {
					case CInt(v): return v;
					case CFloat(f): return f;
					case CString(s): return s;
					case CReg(p, m): return new EReg(p, m);
				}
			case EIdent(id):
				if (captures.exists(id))
					return captures.get(id);
				if (locals.exists(id))
					return getLocal(id);
				return resolve(id);
			case EVar(n, t, e, get, set, isFinal):
				declared.push({n: n, old: locals.get(n)});

				var v:Dynamic = (e == null ? null : expr(e, t));
				var l:Variable = (AbstractTools.isAbstract(v) ? {r: v.__a, a: v} : {r: v});

				if (get != null)
					l.get = get;
				if (set != null)
					l.set = set;
				if (isFinal)
					l.isFinal = isFinal;

				locals.set(n, l);
			case EParent(e):
				return expr(e, void, mapCompr);
			case EBlock(exprs):
				var loc = Lambda.count(locals);
				var old = declared.length;
				var v = null;
				for (e in exprs)
					v = expr(e, void, mapCompr);
				if (loc > 0)
					restore(old);
				return v;
			case EField(e, f, m):
				return resolveField(e, f, m);
			case EBinop('=>', e1, e2) if (mapCompr):
				return e;
			case EBinop(op, e1, e2):
				var fop = binops.get(op);
				if (fop == null)
					error(EInvalidOp(op));
				return fop(e1, e2);
			case EUnop(op, prefix, e):
				switch (op) {
					case "!":
						return expr(e) != true;
					case "-":
						return -expr(e);
					case "++":
						return increment(e, prefix, 1);
					case "--":
						return increment(e, prefix, -1);
					case "~":
						return ~expr(e);
					default:
						error(EInvalidOp(op));
				}
			case ECall(e, params):
				var args = new Array();
				for (p in params)
					args.push(expr(p));

				switch (Tools.expr(e)) {
					case EField(e, f, m):
						var obj = expr(e);
						if (obj == null) {
							if (m)
								return null;
							error(EInvalidAccess(f));
						}
						return fcall(obj, f, args);
					default:
						return call(null, expr(e), args);
				}
			case EIf(econd, e1, e2):
				return if (expr(econd)) expr(e1, void, mapCompr) else if (e2 == null) (void ? Interp.void : null) else expr(e2, void, mapCompr);
			case EWhile(econd, e):
				whileLoop(econd, e);
				return null;
			case EDoWhile(econd, e):
				doWhileLoop(econd, e);
				return null;
			case EFor(v, it, e):
				forLoop(v, it, expr.bind(e));
				return null;
			case EForGen(it, e):
				Tools.getKeyIterator(it, function(vk, vv, it) {
					if (vk == null) {
						position = it.pos;
						error(ECustom("Invalid for expression"));
						return;
					}
					forKeyValueLoop(vk, vv, it, expr.bind(e));
				});
				return null;
			case EBreak:
				throw SBreak;
			case EContinue:
				throw SContinue;
			case EReturn(e):
				returnValue = e == null ? null : expr(e, void, mapCompr);
				throw SReturn;
			case EFunction(params, fexpr, name, ret, id):
				return buildFunction(name, params, fexpr, ret, id);
			case EArrayDecl(arr):
				var compr:Dynamic = null;

				var exprCompr:(e:Expr, ?inFor:Bool) -> Dynamic = null;

				function forExpr(e:Expr) {
					var v:Dynamic = exprCompr(e, true);

					if (v is ExprDef) {
						switch (v) {
							default:
							case EBinop('=>', e1, e2):
								var key:Dynamic = expr(e1);

								if (key is String) {
									compr ??= new haxe.ds.StringMap();
								} else if (key is Int) {
									compr ??= new haxe.ds.IntMap();
								} else if (HaxeReflect.isEnumValue(key)) {
									compr ??= new haxe.ds.EnumValueMap();
								} else {
									compr ??= new haxe.ds.ObjectMap();
								}

								compr.set(key, expr(e2));
								return;
						}
					}

					if (v != Interp.void) {
						compr ??= new Array();

						compr.push(v);
					}
				}

				exprCompr = function(e:Expr, inFor:Bool = false):Dynamic {
					return switch (Tools.expr(e)) {
						case EBlock(e):
							var v = Interp.void;

							for (e in e)
								v = exprCompr(e, inFor);

							v;

						case EParent(e):
							exprCompr(e, inFor);

						case EFor(n, it, e):
							forLoop(n, it, forExpr.bind(e));

							Interp.void;

						case EForGen(it, e):
							Tools.getKeyIterator(it, function(vk, vv, it) {
								if (vk == null) {
									position = it.pos;
									error(ECustom('Invalid for expression'));
									return;
								}

								forKeyValueLoop(vk, vv, it, forExpr.bind(e));
							});

							Interp.void;

						default:
							expr(e, inFor, inFor);
					}
				}

				if (arr.length > 0 && Tools.expr(arr[0]).match(EBinop("=>", _))) { // infer from keys ...
					var keys = [];
					var values = [];
					for (e in arr) {
						switch (Tools.expr(e)) {
							case EBinop("=>", eKey, eValue):
								keys.push(expr(eKey));
								values.push(expr(eValue));
							default:
								position = e.pos;
								error(ECustom("Invalid map key=>value expression"));
						}
					}
					return makeMap(keys, values);
				} else { // infer from type declaration ... (empty map)
					if (arr.length == 1) {
						exprCompr(arr[0]);

						if (compr != null)
							return compr;
					}

					switch (t) {
						case CTPath(path, params): // hell
							var fullPath:String = path.join('.');

							if (fullPath == 'Map') { // infer from parameters
								if (params == null || params.length < 2)
									error(ECustom('Not enough type parameters for Map')); // we dont really care about the value type , but whatever
								else if (params.length > 2)
									error(ECustom('Too many type parameters for Map'));

								switch (params[0]) {
									case CTAnon(_):
										return new haxe.ds.ObjectMap<Dynamic, Dynamic>();
									case CTPath(path, _):
										var fullPath:String = path.join('.');

										if (fullPath == 'String') {
											return new Map<String, Dynamic>();
										} else if (fullPath == 'Int') {
											return new Map<Int, Dynamic>();
										} else {
											var type:TypeInfo = null;
											var r = (Tools.resolve(fullPath, environment) ?? imports.get(fullPath));
											if (r is Class) {
												type = TypeCollection.main.fromCompilePath(Type.getClassName(r))[0];
											} else if (r == null) {
												error(EUnknownType(fullPath));
											}

											if (/*Reflect.isEnumValue(r)*/ false) { // todo resolve enum values??
												return new haxe.ds.EnumValueMap<Dynamic, Dynamic>();
											} else if (type?.kind == 'class') {
												return new haxe.ds.ObjectMap<Dynamic, Dynamic>();
											}
										}
									default:
								}

								var p = new Printer();
								error(ECustom('Map of type <${p.typeToString(params[0])}, ${p.typeToString(params[1])}> is not accepted'));
							} else {
								var t:Dynamic = resolve(fullPath); // alias stuff

								if (t is haxe.ds.IntMap || t is haxe.ds.StringMap || t is haxe.ds.ObjectMap || t is haxe.ds.EnumValueMap)
									return Type.createInstance(t, []);
							}
						default:
					}

					var a = new Array();
					for (e in arr)
						a.push(expr(e));
					return a;
				}
			case EArray(e, index):
				var arr:Dynamic = expr(e);
				var index:Dynamic = expr(index);
				if (isMap(arr))
					return getMapValue(arr, index);
				return arr[index];
			case ENew(cl, params):
				var a = new Array();
				for (e in params)
					a.push(expr(e));
				return cnew(cl, a);
			case EThrow(e):
				error(ECustom(Std.string(expr(e))));
			case ETry(e, n, _, ecatch):
				var old = declared.length;
				var oldTry = inTry;
				try {
					inTry = true;
					var v:Dynamic = expr(e);
					restore(old);
					inTry = oldTry;
					return v;
				} catch (err:Stop) {
					inTry = oldTry;
					throw err;
				} catch (err:Dynamic) {
					// restore vars
					restore(old);
					inTry = oldTry;
					// declare 'v'
					declared.push({n: n, old: locals.get(n)});
					locals.set(n, {r: err});
					var v:Dynamic = expr(ecatch);
					restore(old);
					return v;
				}
			case EObject(fl):
				var o = {};
				for (f in fl)
					set(o, f.name, expr(f.e));
				return o;
			case ETernary(econd, e1, e2):
				return if (expr(econd) == true) expr(e1) else expr(e2);
			case ESwitch(e, cases, def):
				var hasCapture:Bool = false;

				function iterCapture(e:Expr) {
					switch (e.e) {
						case EIdent('_') | EIdent(_.isTypeIdentifier() => false):
							hasCapture = true;

						case EIdent(id):

						case EVar(_):
							hasCapture = true;

						default:
							e.iter(iterCapture);
					}
				}

				function checkCapture(e:Expr) {
					hasCapture = false;
					e.iter(iterCapture);
					return hasCapture;
				}

				function testCase(e:Expr, match:Dynamic, deep:Bool = true) {
					return switch (e.e) {
						case EIdent(id):
							if (imports.exists(id) || variables.exists(id))
								return matchValues(resolve(id), match);

							if (id != '_' && id.isTypeIdentifier())
								throw 'Unknown identifier: $id, pattern variables must be lower-case or with \'var \' prefix';

							captures.set(id, match);
							return true;

						case EField(ve, f, m):
							testCase(ve, match);
							matchValues(get(expr(ve), f, m), match);

						case EVar(id):
							captures.set(id, match);
							true;

						case EConst(_):
							(expr(e) == match);

						case EParent(exr):
							testCase(exr, match);

						case EBinop('=>', e1, e2):
							captures.set('_', match);

							var a:Dynamic = expr(e1);
							testCase(e2, a);

							matchValues(a, expr(e2));

						case EBinop('|', e1, e2):
							testCase(e1, match);
							testCase(e2, match);
							(matchValues(match, expr(e1)) || matchValues(match, expr(e2)));

						case EObject(f):
							if (!Reflect.isObject(match))
								return false;
							for (f in f) {
								if (!Reflect.hasField(match, f.name) || !testCase(f.e, Reflect.field(match, f.name)))
									return false;
							}
							true;

						case EArrayDecl(a):
							if (!(match is Array))
								return false;
							if (a.length != match.length)
								return false;
							for (i => e in a) {
								if (!testCase(e, match[i]))
									return false;
							}
							true;

						case ECall(ce, params):
							if (checkCapture(ce)) {
								testCase(ce, match);
							} else {
								var v = expr(ce);

								var ev = Reflect.callMethod(null, v, [for (_ in params) null]);
								if (Type.getEnum(ev) == Type.getEnum(match) && Type.enumConstructor(ev) == Type.enumConstructor(match)) {
									var matchParams = Type.enumParameters(match);

									for (i => param in params) {
										if (!testCase(param, matchParams[i]))
											return false;
									}
								} else {
									return false;
								}
							}
							true;

						default:
							error(EUnrecognizedPattern(e));
					}
				}

				var val:Dynamic = expr(e);
				var match = false;
				for (c in cases) {
					for (exr in c.values) {
						captures.clear();

						match = testCase(exr, val);

						captures.remove('_');

						if (c.guard != null && !expr(c.guard))
							match = false;

						if (match)
							break;
					}
					if (match) {
						val = expr(c.expr, void, mapCompr);
						break;
					}
				}

				if (!match)
					val = def == null ? null : expr(def, void, mapCompr);

				captures.clear();

				return val;
			case EMeta(meta, args, e):
				var r:Dynamic, old = metas.length;
				metas.push({name: meta, params: args});

				try {
					r = expr(e);
					metas.resize(old);
				} catch (e:Dynamic) {
					metas.resize(old);
					#if neko neko.Lib.rethrow(e); #else throw e; #end
				}

				return r;
			case ECast(e, t):
				return tryCast(expr(e), t);
			case ECheckType(e, _):
				return expr(e);
		}
		return (void ? Interp.void : null);
	}

	inline function resolveField(e:Expr, f:String, m:Bool = false):Dynamic {
		final canResolve = (resolveFields.length == 0);

		resolveFields.unshift(m ? RMaybe(f) : RNormal(f));
		switch (Tools.expr(e)) {
			case EIdent(id):
				resolveFields.unshift(RNormal(id));
			case EField(_, _, _):
				expr(e);
			default:
				resolveFields.unshift(RExpr(e));
		}

		if (!canResolve)
			return null;

		var __tempResolveFields:Array<Resolve> = resolveFields;
		resolveFields = [];

		var got:Dynamic = null,
			gotType:TypeInfo = null,
			unknown:Null<String> = null;

		var fullProp:String = '';
		for (i => prop in __tempResolveFields) {
			var field:String, maybe:Bool;

			switch (prop) {
				case RNormal(f):
					field = f;
					maybe = false;
				case RMaybe(f):
					field = f;
					maybe = true;
				case RExpr(e):
					got = expr(e);
					continue;
			}

			if (got == null) {
				fullProp = (fullProp.length == 0 ? field : '$fullProp.$field');

				if (i == 0) {
					if (captures.exists(field)) {
						got = captures.get(field);
					} else if (locals.exists(field)) {
						got = getLocal(field);
					} else if (isResolvable(field)) {
						got = resolve(field);
					} else {
						unknown = field;
					}

					if (got != null)
						continue;
				}

				var info = (TypeCollection.main.fromPath(fullProp) ?? environment?.types.fromPath(fullProp));

				if (info != null) {
					unknown = null;
					gotType = info[0];

					if (i == __tempResolveFields.length - 1)
						got = gotType.resolve(environment);
				} else if (gotType != null) {
					var t = gotType.resolve(environment);
					got = get(t, field, maybe);
				}
			} else {
				got = get(got, field, maybe);
			}
		}

		if (unknown != null)
			error(EUnknownVariable(unknown));

		return got;
	}

	inline function getMeta(name:String):MetadataEntry {
		var entry:MetadataEntry = null;

		for (meta in metas) {
			if (meta.name == name) {
				entry = meta;
				break;
			}
		}

		return entry;
	}

	public static function matchValues(v:Dynamic, with:Dynamic):Bool {
		if (v == with) {
			return true;
		} else if (v is ICustomEnumValueType && with is ICustomEnumValueType) {
			return cast(v, ICustomEnumValueType).eq(with);
		} else if (Reflect.isEnumValue(v) && Type.getEnum(v) != null && Type.getEnum(with) != null) {
			return Type.enumEq(v, with);
		}

		return false;
	}

	function tryCast(e:Dynamic, ?type):Dynamic {
		switch (type) {
			case CTPath(p, _):
				var path = p.join('.');
				var t = imports.get(path);

				if (t == null) {
					var info = TypeCollection.main.fromPath(path);
					if (info != null)
						t = info[0].compilePath().resolve();
				}

				if (e == null || t == null || !(t is Class))
					return e; // throw 'Type not found: $path';

				if (Type.getSuperClass(t) == InsanityAbstract) {
					return Type.createInstance(t, [e]);
				} else if (e is InsanityAbstract) {
					var r = e.resolveTo(Type.getClassName(t));
					if (r == null)
						throw 'Can\'t cast ${e.impl} to $path';
					else
						return r;
				}

			default:
		}

		return e;
	}

	function doWhileLoop(econd, e) {
		var old = declared.length;
		do {
			if (!loopRun(expr.bind(e)))
				break;
		} while (expr(econd) == true);
		restore(old);
	}

	function whileLoop(econd, e) {
		var old = declared.length;
		while (expr(econd) == true) {
			if (!loopRun(expr.bind(e)))
				break;
		}
		restore(old);
	}

	function makeIterator(v:Dynamic):Iterator<Dynamic> {
		if (v is Array)
			return (v : Array<Dynamic>).iterator();

		var iter = Reflect.field(v, 'iterator');
		#if hl
		if (iter != null)
			v = Reflect.callMethod(v, iter, []);
		#else
		v = (iter != null ? iter() : v);
		#end

		if (Reflect.field(v, 'hasNext') == null || Reflect.field(v, 'next') == null)
			error(EInvalidIterator(v));

		return v;
	}

	function makeKeyValueIterator(v:Dynamic):KeyValueIterator<Dynamic, Dynamic> {
		if ((v is haxe.ds.IntMap) || (v is haxe.ds.StringMap) || (v is haxe.ds.ObjectMap) || (v is haxe.ds.EnumValueMap)) {
			return (v : IMap<Dynamic, Dynamic>).keyValueIterator();
		} else if (v is Array) {
			return (v : Array<Dynamic>).keyValueIterator();
		}

		var iter = Reflect.field(v, 'keyValueIterator');
		#if hl
		if (iter != null)
			v = Reflect.callMethod(v, iter, []);
		#else
		v = (iter != null ? iter() : v);
		#end

		if (Reflect.field(v, 'hasNext') == null || Reflect.field(v, 'next') == null)
			error(EInvalidIterator(v));

		return v;
	}

	function forLoop(n, it, ef:Dynamic) {
		var old = declared.length;
		declared.push({n: n, old: locals.get(n)});

		var it = makeIterator(expr(it));
		var next = Reflect.field(it, 'next'),
			hasNext = Reflect.field(it, 'hasNext');

		while (hasNext()) {
			locals.set(n, {r: next()});

			if (!loopRun(ef))
				break;
		}

		restore(old);
	}

	function forKeyValueLoop(vk, vv, it, ef:Dynamic) {
		var old = declared.length;
		declared.push({n: vk, old: locals.get(vk)});
		declared.push({n: vv, old: locals.get(vv)});

		var it = makeKeyValueIterator(expr(it));
		var next = Reflect.field(it, 'next'),
			hasNext = Reflect.field(it, 'hasNext');

		while (hasNext()) {
			var v = next();

			if (v.key == null)
				error(EUnknownField(v, 'key'));
			if (v.value == null)
				error(EUnknownField(v, 'value'));

			locals.set(vk, {r: v.key});
			locals.set(vv, {r: v.value});

			if (!loopRun(ef))
				break;
		}

		restore(old);
	}

	inline function loopRun(f:Void->Void) {
		var cont = true;
		try {
			f();
		} catch (err:Stop) {
			switch (err) {
				case SContinue:
				case SBreak:
					cont = false;
				case SReturn:
					throw err;
			}
		}
		return cont;
	}

	inline function isMap(o:Dynamic):Bool {
		return (o is IMap);
	}

	inline function getMapValue(map:Dynamic, key:Dynamic):Dynamic {
		return cast(map, haxe.Constraints.IMap<Dynamic, Dynamic>).get(key);
	}

	inline function setMapValue(map:Dynamic, key:Dynamic, value:Dynamic):Void {
		cast(map, haxe.Constraints.IMap<Dynamic, Dynamic>).set(key, value);
	}

	function makeMap(keys:Array<Dynamic>, values:Array<Dynamic>):Dynamic {
		var isAllString:Bool = true;
		var isAllInt:Bool = true;
		var isAllObject:Bool = true;
		var isAllEnum:Bool = true;
		for (key in keys) {
			isAllString = isAllString && (key is String);
			isAllInt = isAllInt && (key is Int);
			isAllObject = isAllObject && Reflect.isObject(key);
			isAllEnum = isAllEnum && HaxeReflect.isEnumValue(key);
		}

		#if (haxe_ver >= 4.1)
		if (isAllInt) {
			var m = new Map<Int, Dynamic>();
			for (i => key in keys)
				m.set(key, values[i]);
			return m;
		}
		if (isAllString) {
			var m = new Map<String, Dynamic>();
			for (i => key in keys)
				m.set(key, values[i]);
			return m;
		}
		if (isAllEnum) {
			var m = new haxe.ds.EnumValueMap<Dynamic, Dynamic>();
			for (i => key in keys)
				m.set(key, values[i]);
			return m;
		}
		if (isAllObject) {
			var m = new Map<{}, Dynamic>();
			for (i => key in keys)
				m.set(key, values[i]);
			return m;
		}
		#else
		var m:Dynamic = {
			if (isAllInt)
				new haxe.ds.IntMap<Dynamic>();
			else if (isAllString)
				new haxe.ds.StringMap<Dynamic>();
			else if (isAllEnum)
				new haxe.ds.EnumValueMap<Dynamic, Dynamic>();
			else if (isAllObject)
				new haxe.ds.ObjectMap<Dynamic, Dynamic>();
			else
				null;
		}
		if (m != null) {
			for (n in 0...keys.length)
				setMapValue(m, keys[n], values[n]);
			return m;
		}
		#end
		error(ECustom("Invalid map keys " + keys));
		return null;
	}

	/**
	 * Rejects reads/writes of a script-declared `private` member from outside the
	 * declaring class. No-op unless `Config.strictAccess` is on; native fields carry
	 * no access information at runtime and are never checked.
	 */
	inline function checkAccess(o:Dynamic, f:String):Void {
		if (!Config.strictAccess)
			return;

		var owner:InsanityScriptedClass = ScriptedAccess.declaringClass(o);
		if (owner == null)
			return;

		var declaring:InsanityScriptedClass = owner.privateOwnerOf(f);
		if (declaring == null)
			return;

		if (ownerClass == null || !ownerClass.isOrExtends(declaring))
			error(ECustom('Cannot access private field $f of ${declaring.path}'));
	}

	function get(o:Dynamic, f:String, maybe:Bool = false):Dynamic {
		if (canDefer && o is IInsanityType && !o.initialized)
			throw DDefer;

		checkAccess(o, f);

		if (o == null) {
			if (!maybe) {
				error(EInvalidAccess(f));
			} else {
				return null;
			}
		}

		if (o is Mirror) {
			switch (cast(o, Mirror)) {
				case MSuper(locals, _):
					if (locals == null) {
						error(EHasNoSuper);
					} else if (locals.exists(f)) {
						return (locals.get(f).a ?? locals.get(f).r);
					} else {
						error(EUnknownVariable(f));
					}
				default:
			}
		}

		var bypassAccessor:Bool = (getMeta(':bypassAccessor') != null);
		var prop = (if (bypassAccessor) {
			Reflect.field(o, f);
		} else {
			#if php
			// https://github.com/HaxeFoundation/haxe/issues/4915
			try {
				Reflect.getProperty(o, f);
			} catch (e:Dynamic) {
				Reflect.field(o, f);
			}
			#else
			Reflect.getProperty(o, f);
			#end
		});

		if (prop == null && hasField(o, f) == false) {
			var fields = getFieldsClass((o is Class || o is InsanityScriptedClass) ? Type.getClassName(o) : Type.getEnumName(o));
			if (fields != null)
				return (bypassAccessor ? Reflect.field(fields, f) : Reflect.getProperty(fields, f));
		}

		return prop;
	}

	function set(o:Dynamic, f:String, v:Dynamic):Dynamic {
		if (o == null)
			error(EInvalidAccess(f));

		if (canDefer && o is IInsanityType && !o.initialized)
			throw DDefer;

		checkAccess(o, f);

		if (AbstractTools.isAbstract(v))
			v = v.__a;

		var bypassAccessor:Bool = (getMeta(':bypassAccessor') != null);

		if (Reflect.field(o, f) == null && hasField(o, f) == false) {
			var fields = getFieldsClass((o is Class || o is InsanityScriptedClass) ? Type.getClassName(o) : Type.getEnumName(o));
			if (fields != null)
				(bypassAccessor ? Reflect.setField(fields, f, v) : Reflect.setProperty(fields, f, v));
		} else if (bypassAccessor) {
			Reflect.setField(o, f, v);
		} else {
			Reflect.setProperty(o, f, v);
		}

		return v;
	}

	inline function hasField(o:Dynamic, f:String):Null<Bool> {
		if (o is Class || o is InsanityScriptedClass) {
			return Type.getClassFields(o).contains(f);
		} else if (o is Enum || o is InsanityScriptedEnum) {
			return Type.getEnumConstructs(o).contains(f);
		} else {
			return null;
		}
	}

	inline function getFieldsClass(path:String):Dynamic {
		if (path.endsWith('_Fields_'))
			return null;

		if (path.startsWith('InsanityAbstract_'))
			path = Type.resolveClass(path).impl;

		var pack = path.substr(0, path.lastIndexOf('.') + 1);
		var name = path.substr(path.lastIndexOf('.') + 1);

		return Tools.resolve('${pack}_$name.${name}_Fields_', environment);
	}

	// Finds an emulation shim (Config.callShims) for method `f` on `o`, walking up `o`'s
	// superclass chain so a shim registered on a base class covers subclasses too. Handles
	// `o` being a class value (static-method shims) or an instance.
	function resolveCallShim(o:Dynamic, f:String):(Dynamic, Array<Dynamic>) -> Dynamic {
		if (o == null)
			return null;

		var cls:Dynamic = (o is Class) ? o : HaxeType.getClass(o);
		while (cls != null) {
			var name:String = HaxeType.getClassName(cls);
			if (name != null) {
				var shim = Config.callShims.get(name + '.' + f);
				if (shim != null)
					return shim;
			}
			cls = HaxeType.getSuperClass(cls);
		}
		return null;
	}

	function fcall(o:Dynamic, f:String, args:Array<Dynamic>):Dynamic {
		var fun:Dynamic = get(o, f);

		if (o != Std || f != 'string') { // dirty solution but Yeah what ever
			for (i => arg in args)
				args[i] = (AbstractTools.isAbstract(arg) ? arg.__a : arg);
		}

		if (!Reflect.isFunction(fun)) {
			for (t in usings) {
				var fun = get(t, f, true);
				if (Reflect.isFunction(fun)) {
					try {
						args.unshift(o);
						return Reflect.callMethod(t, fun, args);
					} catch (e:Dynamic) {}
				}
			}

			// A method with no runtime representation (an `inline extern` overload like
			// flixel's playMusic) reflects to null. Fall back to a registered emulation shim
			// keyed by the receiver's class before failing, so such calls still work.
			var shim = resolveCallShim(o, f);
			if (shim != null)
				return shim(o, args);

			error(ECustom('Cannot call $fun'));
		}

		return call(o, fun, args);
	}

	function call(o:Dynamic, f:Dynamic, args:Array<Dynamic>):Dynamic {
		if (f is Mirror) {
			switch (cast(f, Mirror)) {
				case MSuper(locals, constructor):
					if (constructor == null) {
						error(EHasNoSuper);
					} else if (!superConstructorAllowed) {
						error(ECustom('Cannot call super constructor outside class constructor'));
					} else {
						f = constructor;
					}
				default:
			}
		}

		if (f != Std.string) {
			for (i => arg in args)
				args[i] = (AbstractTools.isAbstract(arg) ? arg.__a : arg);
		}

		return Reflect.callMethod(o, f, args);
	}

	function cnew(cl:String, args:Array<Dynamic>):Dynamic {
		var c = Tools.resolve(cl, environment);
		c ??= resolve(cl);

		if (canDefer && c is IInsanityType && !c.initialized)
			throw DDefer;

		return Type.createInstance(c, args);
	}
}
