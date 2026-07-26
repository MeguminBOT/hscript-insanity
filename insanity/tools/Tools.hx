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

package insanity.tools;

import insanity.syntax.Expr;
import insanity.types.AbstractTools;
import insanity.proxy.TypeProxy;

using insanity.types.TypeCollection;
using insanity.types.AbstractValue;
using insanity.Environment;

/** AST and type-resolution helpers used throughout the parser and interpreter. */
class Tools {
	/**
	 * Applies `f` to each immediate sub-expression of `e` (a shallow, non-recursive walk).
	 *
	 * @param e The expression to visit.
	 * @param f The callback run on every direct child expression.
	 */
	public static function iter(e:Expr, f:Expr->Void) {
		switch (expr(e)) {
			case EConst(_), EIdent(_), EImport(_, _), EUsing(_), EDecl(_):
			case EVar(_, _, e):
				if (e != null)
					f(e);
			case EParent(e):
				f(e);
			case EBlock(el):
				for (e in el)
					f(e);
			case EField(e, _):
				f(e);
			case EBinop(_, e1, e2):
				f(e1);
				f(e2);
			case EUnop(_, _, e):
				f(e);
			case ECall(e, args):
				f(e);
				for (a in args)
					f(a);
			case EIf(c, e1, e2):
				f(c);
				f(e1);
				if (e2 != null)
					f(e2);
			case EWhile(c, e):
				f(c);
				f(e);
			case EDoWhile(c, e):
				f(c);
				f(e);
			case EFor(_, it, e):
				f(it);
				f(e);
			case EForGen(it, e):
				f(it);
				f(e);
			case EBreak, EContinue:
			case EFunction(_, e, _, _):
				f(e);
			case EReturn(e):
				if (e != null)
					f(e);
			case EArray(e, i):
				f(e);
				f(i);
			case EArrayDecl(el):
				for (e in el)
					f(e);
			case ENew(_, el):
				for (e in el)
					f(e);
			case EThrow(e):
				f(e);
			case ETry(e, _, _, c, extra):
				f(e);
				f(c);
				if (extra != null)
					for (cc in extra)
						f(cc.expr);
			case EObject(fl):
				for (fi in fl)
					f(fi.e);
			case ETernary(c, e1, e2):
				f(c);
				f(e1);
				f(e2);
			case ESwitch(e, cases, def):
				f(e);
				for (c in cases) {
					for (v in c.values)
						f(v);
					f(c.expr);
				}
				if (def != null)
					f(def);
			case EMeta(name, args, e):
				if (args != null)
					for (a in args)
						f(a);
				f(e);
			case ECheckType(e, _):
				f(e);
			case ECast(e, _):
				f(e);
		}
	}

	/**
	 * Rebuilds `e` with `f` applied to each immediate sub-expression, preserving structure and
	 * position (a shallow transform used to rewrite trees).
	 *
	 * @param e The expression to transform.
	 * @param f The mapping applied to every direct child expression.
	 * @return A new expression with the mapped children.
	 */
	public static function map(e:Expr, f:Expr->Expr) {
		var edef = switch (expr(e)) {
			case EConst(_), EIdent(_), EBreak, EContinue, EImport(_, _), EUsing(_), EDecl(_): expr(e);
			case EVar(n, t, e): EVar(n, t, if (e != null) f(e) else null);
			case EParent(e): EParent(f(e));
			case EBlock(el): EBlock([for (e in el) f(e)]);
			case EField(e, fi): EField(f(e), fi);
			case EBinop(op, e1, e2): EBinop(op, f(e1), f(e2));
			case EUnop(op, pre, e): EUnop(op, pre, f(e));
			case ECall(e, args): ECall(f(e), [for (a in args) f(a)]);
			case EIf(c, e1, e2): EIf(f(c), f(e1), if (e2 != null) f(e2) else null);
			case EWhile(c, e): EWhile(f(c), f(e));
			case EDoWhile(c, e): EDoWhile(f(c), f(e));
			case EFor(v, it, e): EFor(v, f(it), f(e));
			case EForGen(it, e): EForGen(f(it), f(e));
			case EFunction(args, e, name, t): EFunction(args, f(e), name, t);
			case EReturn(e): EReturn(if (e != null) f(e) else null);
			case EArray(e, i): EArray(f(e), f(i));
			case EArrayDecl(el): EArrayDecl([for (e in el) f(e)]);
			case ENew(cl, el): ENew(cl, [for (e in el) f(e)]);
			case EThrow(e): EThrow(f(e));
			case ETry(e, v, t, c, extra): ETry(f(e), v, t, f(c), extra == null ? null : [for (cc in extra) {v: cc.v, t: cc.t, expr: f(cc.expr)}]);
			case EObject(fl): EObject([for (fi in fl) {name: fi.name, e: f(fi.e)}]);
			case ETernary(c, e1, e2): ETernary(f(c), f(e1), f(e2));
			case ESwitch(e, cases, def): ESwitch(f(e), [for (c in cases) {values: [for (v in c.values) f(v)], expr: f(c.expr)}], def == null ? null : f(def));
			case EMeta(name, args, e): EMeta(name, args == null ? null : [for (a in args) f(a)], f(e));
			case ECheckType(e, t): ECheckType(f(e), t);
			case ECast(e, t): ECast(f(e), t);
		}
		return mk(edef, e.pos);
	}

	/**
	 * Unwraps an expression to its definition.
	 *
	 * @param e The positioned expression.
	 * @return Its inner `ExprDef`.
	 */
	public static inline function expr(e:Expr):ExprDef {
		return e.e;
	}

	/**
	 * Wraps an expression definition with a copy of a position.
	 *
	 * @param e The expression definition.
	 * @param pos The position to attach (copied).
	 * @return The positioned expression.
	 */
	public static inline function mk(e:ExprDef, pos:Position) {
		return {
			e: e,
			pos: {
				pmin: pos.pmin,
				pmax: pos.pmax,
				origin: pos.origin,
				line: pos.line,
				column: pos.column
			}
		};
	}

	/**
	 * Recognises a key-value iteration head (`k => v in iter`) and reports its parts.
	 *
	 * @param e The iterator expression.
	 * @param callb Receives the key name, value name (both null for a plain `in`), and the iterated expression.
	 * @return Whatever `callb` returns.
	 */
	public static inline function getKeyIterator<T>(e:Expr, callb:String->String->Expr->T) {
		var key = null, value = null, it = e;
		switch (expr(it)) {
			case EBinop("in", ekv, eiter):
				switch (expr(ekv)) {
					case EBinop("=>", v1, v2):
						switch ([expr(v1), expr(v2)]) {
							case [EIdent(v1), EIdent(v2)]:
								key = v1;
								value = v2;
								it = eiter;
							default:
						}
					default:
				}
			default:
		}
		return callb(key, value, it);
	}

	/**
	 * Joins a package and name into a dotted path.
	 *
	 * @param name The type or field name.
	 * @param pack The package segments; may be null or empty.
	 * @return `pack.name`, or just `name` when the package is empty.
	 */
	public static inline function pathToString(name:String, ?pack:Array<String>):String {
		var pack:String = (pack?.join('.') ?? '');
		return (pack.length > 0 ? '$pack.$name' : name);
	}

	/**
	 * Heuristic for whether an identifier names a type (starts with an upper-case letter).
	 *
	 * @param id The identifier.
	 * @return True if it looks like a type name.
	 */
	public static inline function isTypeIdentifier(id:String):Bool {
		return (id.charAt(0) == id.charAt(0).toUpperCase());
	}

	/**
	 * Resolves a dotted path to a runtime type, trying (in order) a scripted type in the environment,
	 * an abstract, a class, then an enum. Rewrites the path to its compile path first if the
	 * collection knows it.
	 *
	 * @param path The type path to resolve.
	 * @param env An optional world to consult for scripted types.
	 * @return The resolved type, or null if unknown.
	 */
	public static inline function resolve(path:String, ?env:Environment):Dynamic {
		var info = (TypeCollection.main.fromPath(path) ?? env?.types.fromPath(path));
		if (info != null)
			path = TypeCollection.compilePath(info[0]);

		var type:Dynamic = env?.resolve(path);
		type ??= AbstractTools.resolve(path);
		type ??= TypeProxy.resolveClass(path);
		type ??= TypeProxy.resolveEnum(path);

		return type;
	}

	/**
	 * Lists the importable types at a path (a package's types, or a single module/type). Classes,
	 * enums, and abstracts pass through; supported typedefs are included, while unsupported ones warn
	 * (unless suppressed).
	 *
	 * @param path The package, module, or type path.
	 * @param fromPack Whether `path` names a package (list all its types) rather than a single module/type.
	 * @param canIgnoreWarnings Suppress the "unsupported import" warnings.
	 * @param collection The collection to search; defaults to the global one.
	 * @return The importable type infos, or null if the path is unknown.
	 */
	public static inline function listTypes(path:String, fromPack:Bool = false, canIgnoreWarnings:Bool = false, ?collection:TypeCollection):Array<TypeInfo> {
		var typeInfos:Array<TypeInfo> = [];

		collection ??= TypeCollection.main;
		if (fromPack) {
			typeInfos = collection.fromPackage(path);
		} else {
			typeInfos = (collection.fromModule(path) ?? collection.fromPath(path) ?? collection.fromCompilePath(path));
		}

		if (typeInfos == null)
			return null;

		var mainAttraction:Dynamic = (collection.fromPath(path) ?? collection.fromCompilePath(path));
		var types:Dynamic = [];
		for (type in typeInfos) {
			if (type.kind == 'class' || type.kind == 'enum' || type.kind == 'abstract') {
				types.push(type);
			} else if (mainAttraction != null && type == mainAttraction[0] && !canIgnoreWarnings) {
				if (type.kind == 'typedef') {
					if (type.typedefType != null) {
						types.push(type);
					} else if (!(type.structural == true)) {
						// Structural typedefs erase to Dynamic; importing one registers nothing
						// but is not an error. Only a broken alias is worth warning about.
						trace('(${type.fullPath()}) this typedef\'s target type is unsupported');
					}
					continue;
				}

				trace('(${type.fullPath()}) ${type.kind} import is currently unsupported');
			}
		}

		return types;
	}

	/**
	 * Like `listTypes`, but searches several collections and concatenates the results.
	 *
	 * @param path The package, module, or type path.
	 * @param fromPack Whether `path` names a package rather than a single module/type.
	 * @param canIgnoreWarnings Suppress the "unsupported import" warnings.
	 * @param collections The collections to search (nulls are skipped).
	 * @return The combined type infos, or null if none matched.
	 */
	public static inline function listTypesEx(path:String, fromPack:Bool = false, canIgnoreWarnings:Bool = false,
			collections:Array<TypeCollection>):Array<TypeInfo> {
		var types:Array<TypeInfo> = null;

		for (collection in collections) {
			if (collection == null)
				continue;

			var newTypes:Array<TypeInfo> = listTypes(path, fromPack, canIgnoreWarnings, collection);
			if (newTypes == null)
				continue;

			types = (types == null ? newTypes : types.concat(newTypes));
		}

		return types;
	}
}
