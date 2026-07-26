package insanity.macro;

#if macro
import haxe.macro.Compiler;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import Type as HaxeType;

using haxe.macro.ExprTools;
using haxe.macro.TypeTools;
using haxe.macro.ComplexTypeTools;
#end

/**
 * Build macro applied to abstract implementation classes so scripts can use abstracts at runtime.
 * An abstract has no runtime representation of its own, so this emits an `AbstractValue_*` wrapper
 * class that boxes the underlying value and re-exposes the abstract's fields, operators, and
 * `from`/`to` conversions (and, for an `enum abstract`, its constants) in a reflectable form.
 * Standard-library and core-type abstracts are left untouched.
 */
class AbstractMacro {
	/**
	 * Generates the runtime wrapper for the abstract being built.
	 *
	 * @return The fields of the generated wrapper (or the original fields for a skipped abstract).
	 */
	public static macro function build():Array<Field> {
		var pos = Context.currentPos();
		var type = Context.getLocalType();
		var fields = Context.getBuildFields();
		var imports = Context.getLocalImports();

		var ab = null;

		switch (type) {
			case TInst(r, _):
				var c = r.get();

				c.meta.add(':keep', [], pos);

				switch (c.kind) {
					case KAbstractImpl(a):
						ab = a.get();

						switch (ab.pack[0]) {
							case 'haxe', 'hl', 'cpp', 'neko', 'js', 'cs', 'lua', 'php', 'macro', 'java', 'flash', 'python':
								return fields;
							default:
						}

						if (ab.meta.has(':coreType') || ab.type == null || ab.pack[1] == 'Contraints') return fields;
					default:
						return fields;
				}
			default:
				return fields;
		}

		var fullPath = ab.pack.copy();
		fullPath.push(ab.name);
		var isEnum = ab.meta.has(':enum');

		var cls = macro class extends AbstractValue {
			public static var impl(default, never):String = $v{fullPath.join('.')};
		}
		cls.pack = ab.pack;
		cls.name = 'AbstractValue_${fullPath.join('_')}';
		cls.meta.push({name: ':keep', pos: pos});
		cls.fields.push({
			name: 'isEnum',
			pos: pos,
			access: [APublic, AStatic],
			kind: FProp('default', 'never', macro :Bool, macro $v{isEnum})
		});

		// The generated wrapper extends AbstractValue and calls AbstractTools; these used to live in one
		// module, so both must be imported explicitly now that they are separate.
		for (dep in ['insanity.types.AbstractValue', 'insanity.types.AbstractTools']) {
			imports.push({
				path: [for (v in dep.split('.')) {name: v, pos: pos}],
				mode: INormal
			});
		}
		/* imports.push({
			path: [for (v in (ab.module + (ab.module != '' ? '.' : '') + ab.name).split('.')) {name: v, pos: pos}],
			mode: INormal
		});*/

		function getTypePath(tt:Dynamic, ?ty:Dynamic) {
			if (tt.isPrivate || tt.name.length <= 1 || tt.name == ty?.name)
				return null;

			return (tt.module + (tt.module.length > 0 ? '.' : '') + tt.name);
		}
		function tryImport(ty:Dynamic):Bool {
			var pack:Array<String> = ty.module.split('.');
			for (t in Context.getModule(pack.join('.'))) {
				var p = null;

				switch (t) {
					case TEnum(r, _):
						p = getTypePath(r.get(), ty);
					case TInst(r, _):
						p = getTypePath(r.get(), ty);
					case TType(r, _):
						p = getTypePath(r.get(), ty);
					case TAbstract(r, _):
						p = getTypePath(r.get(), ty);
					default:
				}
				if (p == null)
					return false;

				imports.push({
					path: [for (v in p.split('.')) {name: v, pos: pos}],
					mode: INormal
				});
			}

			return true;
		}
		function stripComplex(?t:ComplexType):ComplexType { // just strip the params
			if (t == null)
				return null;
			return switch (t) {
				case TPath(p):
					if (p.name.length <= 1) macro :Dynamic; else TPath({name: p.name, pack: p.pack.copy(), sub: p.sub});
				case TOptional(t):
					TOptional(stripComplex(t));
				default:
					throw 'Invalid $t';
			}
		}
		function toComplex(t:haxe.macro.Type, includeParams:Bool = false):ComplexType {
			function toTypeParam(params:Array<haxe.macro.Type>):Array<TypeParam> {
				return [for (t in params) TPType(toComplex(t))];
			}
			function stuff(r:Dynamic, p:Array<haxe.macro.Type>) {
				var ct = r.get();
				if (ct.name.length <= 1) { // constructible bs
					return macro :Dynamic;
				} else {
					return TPath({name: ct.name, pack: ct.pack, params: (includeParams ? toTypeParam(p) : null)});
				}
			}

			return switch (t) {
				case TInst(r, p): stuff(r, p);
				case TType(r, p): stuff(r, p);
				case TEnum(r, p): stuff(r, p);
				case TAbstract(r, p): stuff(r, p);
				case TDynamic(_): macro :Dynamic;
				default: macro :Dynamic; // throw 'Invalid $t'; TODO tfun??
			}
		}
		function getFullComplex(t:ComplexType, includeParams:Bool = false):ComplexType {
			if (t == null)
				return null;
			return toComplex(t.toType(), includeParams);
		}
		function ex(expr:ExprDef):Expr {
			return {pos: pos, expr: expr};
		}

		var tt = ab.type, t;
		tt = switch (tt) {
			case TType(r, _): r.get().type;
			default: tt;
		}
		var t = toComplex(tt);
		var st = macro $v{ComplexTypeTools.toString(t)};
		var castExpr = (isEnum ? macro if (!_enumValues.contains(v) && !_enumMap.exists(v))
			throw('Can\'t cast ' + AbstractTools.resolveName(v) + ' to ' + impl) : macro if (AbstractTools.resolveName(v) != $st) throw('Can\'t cast '
				+ AbstractTools.resolveName(v) + ' to ' + impl));

		var enumI = 0;
		var enumIndex:Array<Expr> = (isEnum ? [] : null);
		var enumMap:Map<String, Int> = (isEnum ? [] : null);
		var enumConstructors:Array<String> = (isEnum ? [] : null);
		cls.fields.push({
			name: 'tryCast',
			pos: pos,
			access: [AStatic],
			kind: FFun({
				args: [{name: 'v', type: macro :Dynamic}],
				params: [],
				ret: macro :Void,
				expr: castExpr
			})
		});

		var fromExpr = [macro return null];
		var toExpr = [macro return null];

		fromExpr.unshift(macro if (Type.getClass(v) == $p{[cls.name]}) return v.__a);
		toExpr.unshift(macro if (t == $v{fullPath.join('.')}) return __a);

		if (isEnum) {
			fromExpr.unshift(macro {
				if (_enumValues.contains(v))
					return v;
				else if (_enumMap.exists(v))
					return _enumValues[_enumMap.get(v)];
			});
		} else {
			for (from in ab.from) {
				if ((t = toComplex(from.t)) == null)
					continue;
				st = macro $v{ComplexTypeTools.toString(t)};
				fromExpr.unshift(macro if (AbstractTools.resolveName(v) == $st) return v);
			}
			for (to in ab.to) {
				if ((t = toComplex(to.t)) == null)
					continue;
				st = macro $v{ComplexTypeTools.toString(t)};
				toExpr.unshift(macro if (t == $st) return __a);
			}
		}

		var props = [];
		var implPath = ab.impl.get().pack.copy();
		implPath.push(ab.impl.get().name);
		var implStr = macro $v{implPath.join('.')};

		var rabstractT = {name: ab.name, pack: ab.pack};
		var abstractT = {name: cls.name, pack: ab.pack};

		function afield(expr, typeIsAbstract:Bool, ownReturn:Bool = false) {
			var newExpr;
			if (ownReturn) {
				newExpr = (typeIsAbstract ? macro {var r:Dynamic = $expr; return new $abstractT(r);} : macro {return $expr;});
			} else {
				newExpr = (typeIsAbstract ? macro new $abstractT($expr) : macro $expr);
			}

			return newExpr;
		}
		function func(expr, returnIsAbstract:Bool, ownReturn:Bool = false) {
			return macro return ${afield(expr, returnIsAbstract, ownReturn)};
		}
		function matchAbstract(t:ComplexType) {
			if (t == null)
				return false;

			return switch (t) {
				case TPath(r): (r.name == ab.name);
				default: false;
			}
		}

		// `@:op(A + B)` methods are reachable by name already; record which operator each one serves so
		// the interpreter can dispatch `a + b` to it.
		var opMap:Map<String, String> = [];
		var opPrinter = new haxe.macro.Printer();

		for (field in fields) {
			var name = field.name;
			if (name == '__init__')
				continue;

			if (field.access.contains(AOverload)) {
				// TODO: OPERATOR OVERLOAD
				continue;
			}
			if (field.access.contains(AStatic)) {
				switch (field.kind) {
					case FFun(f):
						var custom = false;
						for (meta in field.meta) {
							if (meta.name == ':from') {
								var ss;

								switch (f.args[0].type) {
									case TPath(p):
										var st = p.pack.copy();
										st.push(p.name);
										ss = macro $v{st.join('.')};
									case TFunction(_, _):
										continue;
									default:
										throw 'Invalid ${f.args[0].type}';
								}

								var fc = macro return Reflect.getProperty(Type.resolveClass($implStr), $v{name})(v);
								fromExpr.unshift(macro if (AbstractTools.resolveName(v) == $ss) $fc);

								custom = true;
								continue;
							}
						}

						if (custom)
							continue;

						var args = [];
						var stuff = [];
						for (i => arg in f.args) {
							if (i == 0 && props.contains(name))
								continue; // remove "this"

							args.push({
								value: arg.value,
								type: macro :Dynamic,
								opt: arg.opt,
								name: arg.name,
								meta: arg.meta
							});
							stuff.push(macro $p{[arg.name]});
						}

						var isSetter = (props.contains(name) && StringTools.startsWith(name, 'set_'));
						var setterField = StringTools.replace(name, 'set_', '');

						cls.fields.push({
							name: name,
							pos: pos,
							access: [AStatic, APublic],
							kind: FFun({
								args: args,
								params: [],
								expr: func(isSetter ? macro {
									var cls = Type.resolveClass($implStr);
									$p{[setterField]} = Reflect.callMethod(cls, Reflect.field(cls, $v{name}), $a{stuff});
								} : macro {
									var cls = Type.resolveClass($implStr);
									Reflect.callMethod(cls, Reflect.field(cls, $v{name}), $a{stuff});
									}, matchAbstract(f.ret))
							})
						});

					case FVar(t, e):
						if (field.access.contains(APrivate) || !field.access.contains(APublic))
							continue;

						var typeIsMe:Bool = matchAbstract(t);
						function mapIdent(e:Expr) {
							return switch (e.expr) {
								case EConst(CIdent(f)):
									var ee = e;
									for (field in fields) {
										if (f == field.name) {
											ee = {pos: pos, expr: EMeta({pos: pos, name: ':privateAccess'}, macro $p{fullPath}.$f)};
											break;
										}
									}
									ee;
								default:
									e.map(mapIdent);
							}
						}

						cls.fields.push({
							name: name,
							pos: pos,
							access: [AStatic, APublic],
							kind: FProp(typeIsMe ? 'get' : 'default', 'never', typeIsMe ? TPath(abstractT) : macro :Dynamic, typeIsMe ? null : e?.map(mapIdent))
						});

						if (typeIsMe) {
							cls.fields.push({
								name: 'get_$name',
								pos: pos,
								access: [AStatic],
								kind: FFun({
									args: [],
									ret: TPath(abstractT),
									expr: macro return new $abstractT($e)
								})
							});
						}

					default:
				}
			} else {
				switch (field.kind) {
					case FFun(f):
						var to = false;
						for (meta in field.meta) {
							if (meta.name == ':arrayAccess') {
								// One argument reads, two write, matching how Haxe picks them.
								opMap.set(f.args.length > 1 ? '[]=' : '[]', name);
								continue;
							}
							if (meta.name == ':op') {
								if (meta.params != null && meta.params.length > 0) {
									switch (meta.params[0].expr) {
										case EBinop(binop, _, _):
											opMap.set(opPrinter.printBinop(binop), name);
										case EUnop(unop, _, _):
											// Keyed apart from the binary operators, which share the symbols.
											opMap.set('u' + opPrinter.printUnop(unop), name);
										default:
									}
								}
								continue;
							}
							if (meta.name == ':to') {
								t = stripComplex(f.ret);
								if (t == null)
									continue;

								st = macro $v{ComplexTypeTools.toString(t)};
								var fc = macro return Reflect.getProperty(Type.resolveClass($implStr), $v{name})(__a);
								toExpr.unshift(macro if (t == $st) $fc);

								to = true;
								break;
							}
						}

						if (!to) {
							var args = [];
							var stuff = [macro __a];

							for (i => arg in f.args) {
								args.push({
									value: arg.value,
									type: macro :Dynamic,
									opt: arg.opt,
									name: arg.name,
									meta: arg.meta
								});
								stuff.push(macro $p{[arg.name]});
							}

							var setterExpr = null;
							var isSetter = StringTools.startsWith(name, 'set_');
							if (isSetter) {
								function transformThis(expr) {
									return switch (expr.expr) {
										case EVars(a):
											var vars = macro $expr;
											switch (vars.expr) {
												case EVars(a):
													for (i => v in a) {
														a[i] = {
															type: macro :Dynamic,
															namePos: v.namePos,
															name: v.name,
															meta: v.meta,
															isStatic: v.isStatic,
															isFinal: v.isFinal,
															expr: v.expr
														}
													}
												default:
											}
											vars;
										case EConst(CIdent('this')):
											{expr: EConst(CIdent('__a')), pos: expr.pos};
										default:
											ExprTools.map(expr, transformThis);
									}
								}

								setterExpr = macro ${f.expr};
								setterExpr = setterExpr.map(transformThis);
							}

							var returnsMe:Bool = matchAbstract(f.ret);
							cls.fields.push({
								name: name,
								pos: pos,
								access: [APublic],
								kind: FFun({
									args: args,
									params: [],
									expr: func(isSetter ? setterExpr : macro {
										var cls = Type.resolveClass($implStr);
										Reflect.callMethod(cls, Reflect.field(cls, $v{name}), $a{stuff});
									}, returnsMe, !isSetter),
									ret: (name == 'toString' ? macro :String : (returnsMe ? TPath(abstractT) : macro :Dynamic))
								})
							});
						}

					case FProp(get, set, _):
						props.push('get_$name');
						props.push('set_$name');

						cls.fields.push({
							name: name,
							pos: pos,
							kind: FProp(get, set, macro :Dynamic)
						});

					case FVar(t, e):
						if (isEnum) {
							enumConstructors.push(name);
							enumMap.set(name, enumI++);
							enumIndex.push(e);

							cls.fields.push({
								name: name,
								pos: pos,
								access: [APublic, AStatic],
								kind: FProp('get', 'never', TPath(abstractT))
							});
							cls.fields.push({
								name: 'get_$name',
								pos: pos,
								access: [APublic, AStatic],
								kind: FFun({args: [], ret: TPath(abstractT), expr: macro return new $abstractT($e)})
							});
						}

					default:
				}
			}
		}
		/*trace('FROM: ' + (macro $b {fromExpr}).toString());
			trace('TO: ' + (macro $b {toExpr}).toString());
			trace('--------------------------- finisched'); */

		cls.fields.push({
			name: 'set_value',
			pos: pos,
			access: [APrivate, AOverride],
			kind: FFun({
				args: [{name: 'v', type: macro :Dynamic}],
				params: [],
				expr: macro {
					var r = resolveFrom(v);
					if (r == null)
						throw('Can\'t cast ' + AbstractTools.resolveName(v) + ' to ' + impl);
					return __a = r;
				}
			})
		});
		cls.fields.push({
			name: 'resolveFrom',
			pos: pos,
			access: [APublic, AStatic],
			kind: FFun({
				args: [{name: 'v', type: macro :Dynamic}],
				params: [],
				expr: macro $b{fromExpr},
				ret: macro :Dynamic
			})
		});
		cls.fields.push({
			name: 'resolveTo',
			pos: pos,
			access: [APublic, AOverride],
			kind: FFun({
				args: [{name: 't', type: macro :String}],
				params: [],
				expr: macro $b{toExpr},
				ret: macro :Dynamic
			})
		});

		var opEntries:Array<Expr> = [];
		for (op => m in opMap)
			opEntries.push({pos: pos, expr: EBinop(OpArrow, macro $v{op}, macro $v{m})});

		cls.fields.push({
			name: '_ops',
			pos: pos,
			access: [APublic, AStatic],
			kind: FVar(macro :Map<String, String>, opEntries.length == 0 ? (macro new Map<String, String>()) : {
				pos: pos,
				expr: EArrayDecl(opEntries)
			})
		});
		cls.fields.push({
			name: '_enumMap',
			pos: pos,
			access: [APrivate, AStatic],
			kind: FProp('default', 'never', macro :Map<String, Int>, macro $v{enumMap})
		});
		cls.fields.push({
			name: '_enumConstructors',
			pos: pos,
			access: [APrivate, AStatic],
			kind: FProp('default', 'never', macro :Array<String>, macro $v{enumConstructors})
		});
		cls.fields.push({
			name: '_enumValues',
			pos: pos,
			access: [APrivate, AStatic],
			kind: FProp('default', 'never', macro :Array<Dynamic>, (isEnum ? macro $a{enumIndex} : null))
		});

		Context.defineModule(ab.pack.join('.') + (ab.pack.length > 0 ? '.' : '') + cls.name, [cls], imports);

		return fields;
	}
}
