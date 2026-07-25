package insanity.backend.types;

import insanity.custom.InsanityReflect;
import insanity.custom.InsanityType;
import insanity.backend.Interp;
import insanity.backend.Expr;
import insanity.Environment;
import insanity.Module;

using StringTools;
using insanity.backend.TypeCollection;

/** Helpers for resolving the types a scripted class extends or implements. */
class ScriptedTools {
	/** Every native class that has a generated scripting bridge, keyed by class name. */
	public static var scriptedClasses(default, never):Map<String, Class<IInsanityScripted>> = insanity.backend.macro.ScriptedMacro.listScriptedClasses();

	/**
	 * Resolves an `extends`/`implements` type reference against the declaring module's
	 * imports first, then the interpreter's, then the compiled type collection.
	 *
	 * @param t The type reference to resolve.
	 * @param module The declaring module whose imports take priority, if any.
	 * @param interp The interpreter whose imports/environment are consulted next, if any.
	 * @return The resolved type.
	 * @throws String If the type cannot be found or the reference is not a path.
	 */
	public static function resolveType(t:CType, ?module:Module, ?interp:Interp):Dynamic {
		return switch (t) {
			case CTPath(path, _):
				var p:String = path.join('.');

				var type = (module?.interp.imports.get(p) ?? interp?.imports.get(p) ?? Tools.resolve(p, interp?.environment));
				if (type == null)
					throw 'Type not found: $p';

				type;
			case null:
				null;
			default:
				throw 'Invalid type $t';
				null;
		}
	}

	/**
	 * Like `resolveType`, but for `implements` entries. A native interface that the
	 * runtime can't hand back as a value still names a valid contract -- the generated
	 * bridge is what satisfies it -- so a known-but-unresolvable interface returns null
	 * instead of throwing. An outright unknown name still throws.
	 *
	 * @param t The interface reference to resolve.
	 * @param module The declaring module whose imports take priority, if any.
	 * @param interp The interpreter whose imports/environment are consulted next, if any.
	 * @return The resolved interface, or null for a known-but-unresolvable native interface.
	 * @throws String If the name is outright unknown or the reference is not a path.
	 */
	public static function resolveInterface(t:CType, ?module:Module, ?interp:Interp):Dynamic {
		var p:String = switch (t) {
			case CTPath(path, _): path.join('.');
			default: throw 'Invalid interface $t';
		}

		var type = (module?.interp.imports.get(p) ?? interp?.imports.get(p) ?? Tools.resolve(p, interp?.environment));
		if (type != null)
			return type;

		if (TypeCollection.main.fromPath(p) == null && interp?.environment?.types.fromPath(p) == null)
			throw 'Type not found: $p';

		return null;
	}

	/**
	 * Resolves a base type to something a scripted class can extend: either an already-scripted
	 * class, or a native class that has a generated bridge.
	 *
	 * @param t The base type (a scripted class or a native class).
	 * @return The scripted class, or the bridge class for a native base.
	 * @throws String If the native class has no scripting bridge.
	 */
	public static function resolve(t:Dynamic):Dynamic {
		if (t is InsanityScriptedClass)
			return cast t;

		var cls:String = Type.getClassName(t);
		if (scriptedClasses.exists(cls))
			return scriptedClasses.get(cls);

		throw 'Class $cls can\'t be extended for scripting';
		return null;
	}
}

/** Access helper for reaching the scripted class behind an instance or class value. */
@:access(insanity.backend.types.IInsanityScripted)
class ScriptedAccess {
	/**
	 * The scripted class an instance (or a class value) belongs to, if any.
	 *
	 * @param o An instance or class value.
	 * @return The scripted class, or null if `o` isn't scripted.
	 */
	public static function declaringClass(o:Dynamic):InsanityScriptedClass {
		if (o is IInsanityScripted)
			return o.__base;
		if (o is InsanityScriptedClass)
			return cast o;

		return null;
	}
}

/**
 * The runtime representation of a script-declared `class`. It holds the class's own interpreter
 * (for statics and shared state), resolves its base and interfaces, and implements the reflection
 * and type interfaces so `InsanityType`/`InsanityReflect` treat it like a native class. Instances
 * are backed by a generated bridge that forwards native calls into this scripted definition.
 */
@:access(insanity.backend.Interp)
@:access(insanity.backend.types.IInsanityScripted)
class InsanityScriptedClass implements IInsanityType implements ICustomReflection implements ICustomClassType {
	/** The class's fully-qualified path. */
	public var path:String;

	/** The class's short name. */
	public var name:String;

	/** The module that declares this class. */
	public var module:Module;

	/** The class's package segments. */
	public var pack:Array<String>;

	/** When true, instance-method errors are caught and reported instead of thrown (see `onInstanceError`). */
	public var safe:Bool = false;

	/** When true, all statics are snapshotted on reload (as if every one were `@:snapshot`). */
	public var snapshotAll:Bool = false;

	/** The class's own interpreter, hosting its statics and initializer. */
	public var interp:Interp;

	/** The resolved base (a scripted class or a native class), resolved lazily and cached. */
	public var extending(get, never):Dynamic;

	/** The concrete class used to allocate instances (the base's instance class or the generated bridge). */
	public var instanceClass(get, never):Dynamic;

	/** Resolved `implements` entries: scripted interfaces and native interface classes. */
	public var interfaces(default, null):Array<Dynamic> = [];

	/** Members declared `private`, or null when the class declares none. */
	public var privateFields(default, null):Array<String> = null;

	/** The parsed class declaration. */
	var decl:ClassDecl;

	/** Static variable slots, keyed by name. */
	var __vars:Map<String, Variable> = [];

	/** Cached resolved base type. */
	var _extending:Dynamic = null;

	/** Whether `_extending` has been resolved yet. */
	var _extendingResolved:Bool = false;

	/** True if initialization failed. */
	public var failed:Bool = false;

	/** True once the class has finished initializing. */
	public var initialized:Bool = false;

	/** True while the class is initializing (guards re-entrancy). */
	public var initializing:Bool = false;

	/**
	 * Creates the runtime class from its declaration and gives it a deferring interpreter.
	 *
	 * @param decl The parsed class declaration.
	 * @param module The declaring module, if any.
	 */
	public function new(decl:ClassDecl, ?module:Module) {
		this.name = decl.name;
		this.pack = (module?.pack ?? []);
		this.module = module;
		this.decl = decl;

		path = Tools.pathToString(name, pack);

		interp = Type.createInstance(Config.interpClass, []);
		interp.canDefer = true;
	}

	/**
	 * Initializes the class: reads its metadata, evaluates and installs its static fields (restoring
	 * snapshots and deferring initializers that aren't ready yet), and verifies that every `override`
	 * matches an inherited member (and that no non-overriding field shadows one).
	 *
	 * @param env The world the class initializes against, if any.
	 * @param baseInterp An interpreter whose imports/usings/variables are inherited, if any.
	 * @param restore Whether to restore `@:snapshot` statics from a previous run.
	 */
	public function init(?env:Environment, ?baseInterp:Interp, restore:Bool = true):Void {
		_extending = null;
		_extendingResolved = false;

		privateFields = null;
		for (field in decl.fields) {
			if (!field.access.contains(APrivate))
				continue;

			if (privateFields == null)
				privateFields = [];
			privateFields.push(field.name);
		}

		interp.environment = env;
		interp.ownerClass = this;
		interp.setDefaults(true, baseInterp == null);

		if (baseInterp != null) {
			for (u in baseInterp.usings)
				interp.usings.push(u);
			for (k => i in baseInterp.imports)
				interp.imports.set(k, i);
			for (k => v in baseInterp.variables)
				if (!interp.variables.exists(k))
					interp.variables.set(k, v);
		}

		interp.pushStack(insanity.backend.CallStack.StackItem.SModule(module?.path ?? name));

		safe = false;
		snapshotAll = false;
		for (meta in decl.meta) {
			safe = (safe || meta.name == ':safe');
			snapshotAll = (snapshotAll || meta.name == ':snapshot');
		}

		var overridingFields:Array<String> = [];
		var knownFields:Array<String> = [];

		for (field in decl.fields) {
			var f:String = field.name;

			if (f == 'new')
				continue;

			if (insanity.backend.macro.ScriptedMacro.ignoreFields.contains(f)) {
				throw 'Field $f reserved for internal use!!! - HScriptInsanity';
			} else if (knownFields.contains(f)) {
				throw 'Duplicate class field declaration: $name.$f';
			} else {
				knownFields.push(f);
				if (field.access.contains(AOverride))
					overridingFields.push(f);
			}

			if (!field.access.contains(AStatic))
				continue;

			var l:Variable = {r: null, access: field.access};

			switch (field.kind) {
				default:
				case KVar(v):
					if (v.get != null)
						l.get = v.get;
					if (v.set != null)
						l.set = v.set;
					if (v.isFinal != null)
						l.isFinal = v.isFinal;
			}

			interp.locals.set(f, l);
		}

		for (field in decl.fields) {
			var f:String = field.name;

			if (f == 'new' || !field.access.contains(AStatic))
				continue;

			switch (field.kind) {
				case KFunction(fun):
					interp.locals.get(f).r = interp.buildFunction(f, fun.args, fun.expr, fun.ret, interp.locals);

				case KVar(v):
					if (restore) {
						var snapshot:Bool = snapshotAll;
						if (!snapshot)
							for (meta in field.meta)
								snapshot = (snapshot || meta.name == ':snapshot');

						if (snapshot && Module.snapshots.exists(path)) {
							var fields:Map<String, Dynamic> = Module.snapshots.get(path);
							if (fields.exists(f)) {
								interp.locals.get(f).r = fields.get(f);
								continue;
							}
						}
					}

					try {
						interp.locals.get(f).r = (v.expr == null ? null : interp.exprReturn(v.expr, v.type));
					} catch (d:Defer) {
						var signal = (env?.onInitialized ?? module.onInitialized);

						signal.push(function(_) {
							try {
								interp.locals.get(f).r = interp.exprReturn(v.expr, v.type);
							} catch (e:haxe.Exception) {
								onExpressionError(e, f, v.expr);
							}

							return false;
						});
					} catch (e:haxe.Exception) {
						onExpressionError(e, f, v.expr);
					}
			}

			__vars.set(f, interp.locals.get(f));
		}

		var foundOverridingFields:Array<String> = [];
		var inheritedFields:Array<String> = [];
		function overrideFieldCheck(extending:Dynamic) {
			if (extending is InsanityScriptedClass) {
				var extend:InsanityScriptedClass = cast extending;

				if (extend.module != null && !extend.initializing && !extend.initialized && !extend.failed) {
					if (!extend.module.starting && !extend.module.started)
						extend.module.start(env);

					extend.module.startType(env, extend);
				}

				for (field in extend.decl.fields) {
					var f:String = field.name;

					if (f == 'new' || field.access.contains(AStatic))
						continue;

					if (!inheritedFields.contains(f))
						inheritedFields.push(f);

					if (overridingFields.contains(f)) {
						if (!foundOverridingFields.contains(f))
							foundOverridingFields.push(f);
					} else if (knownFields.contains(f)) {
						throw 'Field $f should be declared with \'override\' since it is inherited from superclass ${extend.name}';
					}
				}

				if (extend.extending != null)
					overrideFieldCheck(extend.extending);
			} else {
				var cls = instanceClass;
				if (cls == null)
					return;

				var instanceFields:Array<String> = (cls.instanceFields ?? Type.getInstanceFields(cast cls));
				var inlinedFields:Array<String> = cls.inlinedFields;
				var unexposedFields:Array<String> = cls.unexposedFields;

				for (field in instanceFields) {
					if (insanity.backend.macro.ScriptedMacro.ignoreFields.contains(field))
						continue;

					if (!inheritedFields.contains(field))
						inheritedFields.push(field);

					if (overridingFields.contains(field)) {
						if (inlinedFields?.contains(field)) {
							throw 'Field $field is inlined and cannot be overridden';
						} else if (unexposedFields?.contains(field)) {
							throw 'Field $field is unexposed and cannot be overridden';
						}

						if (!foundOverridingFields.contains(field))
							foundOverridingFields.push(field);
					} else if (knownFields.contains(field)) {
						throw 'Field $field should be declared with \'override\' since it is inherited from superclass ${cls.getBaseClass()}';
					}
				}
			}
		}
		// A declared `new` that never reaches the native constructor would leave the
		// instance half-built, so hold it to the same rule Haxe does.
		if (decl.extend != null && instanceClass != InsanityDummyClass) {
			for (field in decl.fields) {
				if (field.name != 'new')
					continue;

				switch (field.kind) {
					case KFunction(fun):
						if (!callsSuper(fun.expr))
							throw 'Missing super constructor call in $name.new';
					default:
				}
			}
		}

		overrideFieldCheck(extending);
		if (foundOverridingFields.length < overridingFields.length) {
			for (f in overridingFields) {
				if (!foundOverridingFields.contains(f))
					throw 'Field $f is declared \'override\' but doesn\'t override any field';
			}
		}

		interfaces = [];
		if (decl.implement != null) {
			for (t in decl.implement) {
				var i:Dynamic = ScriptedTools.resolveInterface(t, module, interp);
				if (i == null)
					continue;

				if (i is InsanityScriptedInterface) {
					var scripted:InsanityScriptedInterface = cast i;

					if (scripted.module != null && !scripted.initializing && !scripted.initialized && !scripted.failed)
						scripted.module.startType(env, scripted);

					for (f in scripted.requiredFields()) {
						if (!knownFields.contains(f) && !inheritedFields.contains(f))
							throw 'Field $f needed by ${scripted.name} is missing';
					}
				}

				interfaces.push(i);
			}
		}
	}

	/**
	 * The class that declares `field` as private, or null if no class in the chain does.
	 *
	 * @param field The field name.
	 * @return The declaring class, or null.
	 */
	public function privateOwnerOf(field:String):InsanityScriptedClass {
		if (privateFields != null && privateFields.indexOf(field) >= 0)
			return this;

		var ext:Dynamic = extending;
		if (ext is InsanityScriptedClass)
			return cast(ext, InsanityScriptedClass).privateOwnerOf(field);

		return null;
	}

	/**
	 * Whether this class is `other`, or extends it.
	 *
	 * @param other The class to test against.
	 * @return True if this class is or descends from `other`.
	 */
	public function isOrExtends(other:InsanityScriptedClass):Bool {
		var c:InsanityScriptedClass = this;

		while (c != null) {
			if (c == other)
				return true;

			var ext:Dynamic = c.extending;
			c = (ext is InsanityScriptedClass) ? cast ext : null;
		}

		return false;
	}

	/**
	 * Whether this class, or anything it extends, implements `i` (directly or through a parent interface).
	 *
	 * @param i The scripted interface to test for.
	 * @return True if this class satisfies `i`.
	 */
	public function implementsInterface(i:InsanityScriptedInterface):Bool {
		for (own in interfaces) {
			if (own == i)
				return true;
			if (own is InsanityScriptedInterface && cast(own, InsanityScriptedInterface).extendsInterface(i))
				return true;
		}

		var ext:Dynamic = extending;
		if (ext is InsanityScriptedClass)
			return cast(ext, InsanityScriptedClass).implementsInterface(i);

		return false;
	}

	/**
	 * Whether an expression tree contains a `super(...)` call.
	 *
	 * @param e The expression to scan.
	 * @return True if a super-constructor call is present.
	 */
	static function callsSuper(e:Expr):Bool {
		if (e == null)
			return false;

		var found:Bool = false;
		function walk(e:Expr):Void {
			if (found || e == null)
				return;

			switch (e.e) {
				case ECall({e: EIdent('super')}, _):
					found = true;
				default:
					Tools.iter(e, walk);
			}
		}
		walk(e);

		return found;
	}

	/** Saves this class's `@:snapshot` (or all, if `@:snapshot` on the class) statics into `Module.snapshots`. */
	public function snapshot():Void {
		for (field in decl.fields) {
			if (field.name == 'new' || !field.access.contains(AStatic))
				continue;

			var snapshot:Bool = snapshotAll;
			if (!snapshot)
				for (meta in field.meta)
					snapshot = (snapshot || meta.name == ':snapshot');
			if (!snapshot)
				continue;

			switch (field.kind) {
				case KFunction(_):
				case KVar(_):
					var fields:Map<String, Dynamic> = (Module.snapshots.get(path) ?? []);
					fields.set(field.name, interp.getLocal(field.name));
					Module.snapshots.set(path, fields);
			}
		}
	}

	/** @return The resolved base (scripted class or native class), resolving and caching it on first access. */
	function get_extending():Dynamic {
		if (_extendingResolved)
			return _extending;

		_extendingResolved = true;

		var type:Dynamic = ScriptedTools.resolveType(decl.extend, module, interp);
		return _extending = (type == null ? null : ScriptedTools.resolve(type));
	}

	/** @return The concrete class used to allocate instances: the base's instance class, or the dummy host when there is no base. */
	function get_instanceClass():Dynamic {
		if (extending is InsanityScriptedClass) {
			return cast(extending, InsanityScriptedClass).instanceClass;
		} else if (extending == null) {
			return InsanityDummyClass;
		} else {
			return extending;
		}
	}

	/** @return The script's own `toString` result if it defines one, else a debug string. */
	public function toString():String {
		if (interp.locals?.exists('toString'))
			return interp.locals.get('toString').r();

		return 'InsanityScriptedClass<$path>';
	}

	/**
	 * Allocates an instance and runs its scripted constructor.
	 *
	 * @param arguments Constructor arguments.
	 * @return The new instance.
	 * @throws String If the class is not initialized.
	 */
	public function typeCreateInstance(arguments:Array<Dynamic>):Dynamic {
		if (!initialized)
			throw 'Type $path is not initialized';

		var inst:IInsanityScripted = Type.createEmptyInstance(instanceClass);
		inst.__construct(this, arguments);
		return inst;
	}

	/**
	 * Allocates an instance without running any constructor.
	 *
	 * @return The uninitialized instance.
	 * @throws String If the class is not initialized.
	 */
	public function typeCreateEmptyInstance():Dynamic {
		if (!initialized)
			throw 'Type $path is not initialized';

		return Type.createEmptyInstance(instanceClass);
	}

	/** @return Null; a scripted class has no separate native class object. */
	public function typeGetClass():Dynamic {
		return null;
	}

	/** @return The static field names (this class's own statics). */
	public function typeGetClassFields():Array<String> {
		var fields:Array<String> = [for (loc => _ in interp.locals) loc];
		return fields;
	}

	/** @return The instance field names, gathered up the whole class/base chain. */
	public function typeGetInstanceFields():Array<String> {
		var fields:Array<String> = [];

		function getFields(c:Dynamic) {
			if (c is InsanityScriptedClass) {
				for (field in cast(c, InsanityScriptedClass).decl.fields) {
					var f:String = field.name;
					if (f == 'new' || field.access.contains(AStatic))
						continue;
					if (!fields.contains(f))
						fields.push(f);
				}

				var instance = c.instanceClass;
				if (instance != InsanityScriptedClass)
					getFields(instance);

				if (c.extending != null) {
					getFields(c.extending);
				}
			} else if (c is Class) {
				for (f in Type.getInstanceFields(c)) {
					if (!fields.contains(f) && !insanity.backend.macro.ScriptedMacro.ignoreFields.contains(f))
						fields.push(f);
				}
			}
		}

		getFields(this);

		return fields;
	}

	/** Reflection over statics: whether a static field exists. @param field The field name. @return True if present. */
	public function reflectHasField(field:String):Bool {
		return (__vars.exists(field));
	}

	/** Reflection over statics: read a static field. @param field The field name. @return Its value, or null. */
	public function reflectGetField(field:String):Dynamic {
		return (__vars.exists(field) ? __vars.get(field).r : null);
	}

	/**
	 * Reflection over statics: write a static field.
	 *
	 * @param field The field name.
	 * @param value The value to store.
	 * @return The stored value, or null if the field doesn't exist.
	 */
	public function reflectSetField(field:String, value:Dynamic):Dynamic {
		return (__vars.exists(field) ? __vars.get(field).r = value : null);
	}

	/** Reflection over statics: read a static property via its getter. @param property The property name. @return Its value, or null. */
	public function reflectGetProperty(property:String):Dynamic {
		return (__vars.exists(property) ? interp.getLocal(property, __vars) : null);
	}

	/**
	 * Reflection over statics: write a static property via its setter.
	 *
	 * @param property The property name.
	 * @param value The value to store.
	 * @return The stored value, or null if the property doesn't exist.
	 */
	public function reflectSetProperty(property:String, value:Dynamic):Dynamic {
		return (__vars.exists(property) ? interp.setLocal(property, value, __vars) : null);
	}

	/** @return The static field names. */
	public function reflectListFields():Array<String> {
		return [for (field in __vars.keys()) field];
	}

	/**
	 * Overridable hook: a static field's initializer threw. Defaults to tracing.
	 *
	 * @param error The thrown value.
	 * @param field The field being initialized.
	 * @param expr The initializer expression, if available.
	 */
	public dynamic function onExpressionError(error:Dynamic, field:String, ?expr:Expr):Void {
		trace('Error on field $field of $path: $error');
	}

	/**
	 * Overridable hook: an instance method threw while the class is in `safe` mode. Defaults to tracing.
	 *
	 * @param error The thrown value.
	 * @param fun The method that threw.
	 * @param instance The instance it ran on, if available.
	 */
	public dynamic function onInstanceError(error:Dynamic, fun:String, ?instance:IInsanityScripted):Void {
		trace('Error on function $fun of $path: $error');
	}
}

/**
 * A script-declared `interface`. Carries no implementation: it exists so classes can
 * be checked against a contract, and so `x is IFoo` answers for scripted types the way
 * a native interface does for compiled ones.
 */
@:access(insanity.backend.Interp)
@:access(insanity.backend.types.InsanityScriptedClass)
class InsanityScriptedInterface implements IInsanityType implements ICustomReflection {
	/** The interface's fully-qualified path. */
	public var path:String;

	/** The interface's short name. */
	public var name:String;

	/** The module that declares this interface. */
	public var module:Module;

	/** The interface's package segments. */
	public var pack:Array<String>;

	/** The interface's own interpreter (used to resolve its parents). */
	public var interp:Interp;

	/** Resolved parent interfaces (scripted or native). */
	public var parents(default, null):Array<Dynamic> = [];

	/** The parsed interface declaration. */
	var decl:ClassDecl;

	/** True if initialization failed. */
	public var failed:Bool = false;

	/** True once initialized. */
	public var initialized:Bool = false;

	/** True while initializing (guards re-entrancy). */
	public var initializing:Bool = false;

	/**
	 * Creates the runtime interface from its declaration.
	 *
	 * @param decl The parsed interface declaration.
	 * @param module The declaring module, if any.
	 */
	public function new(decl:ClassDecl, ?module:Module) {
		this.name = decl.name;
		this.pack = (module?.pack ?? []);
		this.module = module;
		this.decl = decl;

		path = Tools.pathToString(name, pack);

		interp = Type.createInstance(Config.interpClass, []);
	}

	/**
	 * Resolves the interface's parents.
	 *
	 * @param env The world it initializes against, if any.
	 * @param baseInterp An interpreter whose imports/usings/variables are inherited, if any.
	 * @param restore Unused; present for interface-uniform signatures.
	 */
	public function init(?env:Environment, ?baseInterp:Interp, restore:Bool = true):Void {
		interp.environment = env;
		interp.setDefaults(true, baseInterp == null);

		if (baseInterp != null) {
			for (u in baseInterp.usings)
				interp.usings.push(u);
			for (k => i in baseInterp.imports)
				interp.imports.set(k, i);
			for (k => v in baseInterp.variables)
				if (!interp.variables.exists(k))
					interp.variables.set(k, v);
		}

		parents = [];
		if (decl.implement == null)
			return;

		for (t in decl.implement) {
			var parent:Dynamic = ScriptedTools.resolveType(t, module, interp);

			if (parent is InsanityScriptedInterface) {
				var scripted:InsanityScriptedInterface = cast parent;

				if (scripted.module != null && !scripted.initializing && !scripted.initialized && !scripted.failed)
					scripted.module.startType(env, scripted);
			}

			parents.push(parent);
		}
	}

	/**
	 * Member names this interface requires, including everything inherited from parents.
	 *
	 * @return The required (non-static) member names.
	 */
	public function requiredFields():Array<String> {
		var fields:Array<String> = [];

		for (field in decl.fields) {
			if (field.access.contains(AStatic))
				continue;
			if (!fields.contains(field.name))
				fields.push(field.name);
		}

		for (parent in parents) {
			if (!(parent is InsanityScriptedInterface))
				continue;

			for (f in cast(parent, InsanityScriptedInterface).requiredFields())
				if (!fields.contains(f))
					fields.push(f);
		}

		return fields;
	}

	/**
	 * Whether this interface is, or inherits from, `i`.
	 *
	 * @param i The interface to test against.
	 * @return True if this interface is or extends `i`.
	 */
	public function extendsInterface(i:InsanityScriptedInterface):Bool {
		if (i == this)
			return true;

		for (parent in parents) {
			if (parent == i)
				return true;
			if (parent is InsanityScriptedInterface && cast(parent, InsanityScriptedInterface).extendsInterface(i))
				return true;
		}

		return false;
	}

	/** @return A debug string identifying this interface. */
	public function toString():String {
		return 'InsanityScriptedInterface<$path>';
	}

	/** An interface carries no fields. @param field Unused. @return Always false. */
	public function reflectHasField(field:String):Bool {
		return false;
	}

	/** An interface carries no fields. @param field Unused. @return Always null. */
	public function reflectGetField(field:String):Dynamic {
		return null;
	}

	/** An interface carries no fields. @param field Unused. @param value Unused. @return Always null. */
	public function reflectSetField(field:String, value:Dynamic):Dynamic {
		return null;
	}

	/** An interface carries no properties. @param property Unused. @return Always null. */
	public function reflectGetProperty(property:String):Dynamic {
		return null;
	}

	/** An interface carries no properties. @param property Unused. @param value Unused. @return Always null. */
	public function reflectSetProperty(property:String, value:Dynamic):Dynamic {
		return null;
	}

	/** @return The interface's required member names. */
	public function reflectListFields():Array<String> {
		return requiredFields();
	}

	/** No-op: an interface has no state to snapshot. */
	public function snapshot():Void {}
}

/**
 * A script-declared `typedef`. An alias to a named type resolves to that type; a structural typedef
 * (anonymous structure or function) has no runtime class and erases to `Dynamic`.
 */
@:access(insanity.backend.Interp)
class InsanityScriptedTypedef implements IInsanityType {
	/** The typedef's short name. */
	public var name:String;

	/** The module that declares this typedef. */
	public var module:Module;

	/** The typedef's package segments. */
	public var pack:Array<String>;

	/** The typedef's fully-qualified path. */
	public var path:String;

	/** The resolved aliased type, for a non-structural typedef. */
	public var alias:Dynamic;

	/** True for structural (anonymous-structure or function) typedefs, which have no runtime class;
		they are matched by shape (see `structFields`) rather than by identity. */
	public var structural:Bool = false;

	/**
	 * For an anonymous-structure typedef, the names of the fields it requires; null for a function
	 * typedef (which has no matchable shape). Used by `matchesStructure` for `is`/`cast`.
	 */
	public var structFields:Array<String> = null;

	/** The parsed typedef declaration. */
	var decl:TypeDecl;

	/** True if initialization failed. */
	public var failed:Bool = false;

	/** True once initialized. */
	public var initialized:Bool = false;

	/** True while initializing (guards re-entrancy). */
	public var initializing:Bool = false;

	/**
	 * Creates the runtime typedef from its declaration.
	 *
	 * @param decl The parsed typedef declaration.
	 * @param module The declaring module, if any.
	 */
	public function new(decl:TypeDecl, ?module:Module) {
		this.name = decl.name;
		this.pack = (module?.pack ?? []);
		this.module = module;
		this.decl = decl;

		path = Tools.pathToString(name, pack);
	}

	/**
	 * Resolves the alias: a named type becomes `alias`, a `Map<...>` is specialized to the right map
	 * implementation from its key type, and any other structural shape sets `structural`.
	 *
	 * @param env The world used to resolve the target, if any.
	 * @param baseInterp An interpreter whose imports help resolve the target.
	 * @param restore Unused; present for interface-uniform signatures.
	 * @throws String If the target type is unknown or an unsupported `Map` shape.
	 */
	public function init(?env:Environment, ?baseInterp:Interp, restore:Bool = true):Void {
		alias = null;
		structural = false;

		switch (decl.t) {
			case insanity.backend.Expr.CType.CTPath(path, params):
				var fullPath:String = path.join('.');

				if (fullPath == 'Map') { // infer from parameters
					if (params == null || params.length < 2)
						throw 'Not enough type parameters for Map'; // we dont really care about the value type , but whatever
					else if (params.length > 2)
						throw 'Too many type parameters for Map';

					switch (params[0]) {
						case CTAnon(_):
							alias = haxe.ds.ObjectMap;
						case CTPath(path, _):
							var fullPath:String = path.join('.');

							if (fullPath == 'String') {
								alias = haxe.ds.StringMap;
							} else if (fullPath == 'Int') {
								alias = haxe.ds.IntMap;
							} else {
								var type:TypeInfo = null;
								var r = (Tools.resolve(fullPath, env) ?? baseInterp.imports.get(fullPath));
								if (r is Class) {
									type = TypeCollection.main.fromCompilePath(InsanityType.getClassName(r))[0];
								} else if (r == null) {
									throw Printer.errorToString(EUnknownType(fullPath));
								}

								if (type?.kind == 'class') {
									alias = haxe.ds.ObjectMap;
								}
							}
						default:
					}

					if (alias == null) {
						var p = new Printer();
						throw 'Map of type <${p.typeToString(params[0])}, ${p.typeToString(params[1])}> is not accepted';
					}
				} else {
					alias = baseInterp.resolve(fullPath);
				}

				if (alias == null)
					throw Printer.errorToString(EUnknownType(fullPath));

			case CTAnon(fields):
				// Anonymous-structure typedef: no runtime class, matched by field shape.
				structural = true;
				structFields = [for (f in fields) f.name];

			default:
				// Function (and other) structural typedefs have no matchable shape; they erase.
				structural = true;
		}
	}

	/**
	 * Whether a value satisfies this typedef's structure: it has every required field. Only meaningful
	 * for an anonymous-structure typedef (`structFields` non-null); field types are not checked
	 * (structural presence only).
	 *
	 * @param value The value to test.
	 * @return True if `value` has all required fields.
	 */
	public function matchesStructure(value:Dynamic):Bool {
		if (value == null || structFields == null)
			return false;
		for (f in structFields)
			if (!InsanityReflect.hasField(value, f))
				return false;
		return true;
	}

	/** No-op: a typedef has no state to snapshot. */
	public function snapshot():Void {}
}

/**
 * The runtime representation of a script-declared `enum`. It knows its constructor names and, for
 * parameterized constructors, the builder functions that produce `InsanityScriptedEnumValue`s, and
 * implements the reflection/type interfaces so `InsanityType` treats it like a native enum.
 */
@:access(insanity.Module)
class InsanityScriptedEnum implements IInsanityType implements ICustomReflection implements ICustomEnumType {
	/** The enum's short name. */
	public var name:String;

	/** The module that declares this enum. */
	public var module:Module;

	/** The enum's package segments. */
	public var pack:Array<String>;

	/** The enum's fully-qualified path. */
	public var path:String;

	/** Constructor names in declaration order (populated by `init`). */
	public var values:Array<String>;

	/** Constructor declarations keyed by name (populated by `init`). */
	public var constructs:Map<String, EnumFieldDecl>;

	/** Builder functions for parameterized constructors, keyed by name. */
	var constructFunctions:Map<String, Array<Dynamic>->InsanityScriptedEnumValue>;

	/** The parsed enum declaration. */
	var decl:EnumDecl;

	/** True if initialization failed. */
	public var failed:Bool = false;

	/** True once initialized. */
	public var initialized:Bool = false;

	/** True while initializing (guards re-entrancy). */
	public var initializing:Bool = false;

	/**
	 * Creates the runtime enum from its declaration.
	 *
	 * @param decl The parsed enum declaration.
	 * @param module The declaring module, if any.
	 */
	public function new(decl:EnumDecl, ?module:Module) {
		this.name = decl.name;
		this.pack = (module?.pack ?? []);
		this.module = module;
		this.decl = decl;

		path = Tools.pathToString(name, pack);
	}

	/**
	 * Populates the constructor names/declarations and builds a validating var-args builder for each
	 * parameterized constructor.
	 *
	 * @param env Unused; present for interface-uniform signatures.
	 * @param baseInterp Unused; present for interface-uniform signatures.
	 * @param restore Unused; present for interface-uniform signatures.
	 */
	public function init(?env:Environment, ?baseInterp:Interp, restore:Bool = true):Void {
		values = decl.names.copy();
		constructs = decl.constructs.copy();
		constructFunctions = new Map();

		for (name => construct in constructs) {
			var params = construct.arguments;
			if (params != null) {
				var minParams:Int = 0;
				for (i => p in params) {
					if (!p.opt)
						minParams = (i + 1);
				}

				constructFunctions.set(name, Reflect.makeVarArgs(function(args:Array<Dynamic>) {
					if (args.length < minParams) {
						var arg = params[args.length];
						var argType:String = arg.name;
						if (arg.t != null)
							argType += (':' + new Printer().typeToString(arg.t));

						throw 'Not enough arguments, expected $argType';
					}
					if (args.length > params.length && params.length > 0) {
						throw 'Too many arguments';
					}

					return new InsanityScriptedEnumValue(this, values.indexOf(name), args);
				}));
			}
		}
	}

	/**
	 * Constructor names, readable before `init` has run (falls back to the declaration).
	 *
	 * @return The constructor names, or null if unavailable.
	 */
	public function constructNames():Array<String> {
		return (values ?? (decl != null ? decl.names : null));
	}

	/**
	 * Whether the constructor at index `i` takes parameters.
	 *
	 * @param i The constructor index.
	 * @return True if that constructor is parameterized.
	 */
	public function constructorHasArgs(i:Int):Bool {
		if (constructFunctions == null && decl != null)
			init();

		var names:Array<String> = constructNames();
		if (names == null || i < 0 || i >= names.length)
			return false;

		var name:String = names[i];
		var c:EnumFieldDecl = (constructs != null ? constructs.get(name) : (decl != null
			&& decl.constructs != null ? decl.constructs.get(name) : null));
		return c != null && c.arguments != null;
	}

	/** @return A debug string identifying this enum. */
	public function toString():String {
		return 'InsanityScriptedEnum<$path>';
	}

	/** @return The enum's fully-qualified path. */
	public function typeGetEnumName():String {
		return path;
	}

	/**
	 * Constructs a value by constructor name (calling its builder for a parameterized constructor).
	 *
	 * @param constr The constructor name.
	 * @param arguments Constructor arguments, if any.
	 * @return The enum value, or null if the constructor is unknown.
	 */
	public function typeCreateEnum(constr:String, ?arguments:Array<Dynamic>):Dynamic {
		var construct:EnumFieldDecl = constructs.get(constr);
		if (construct != null) {
			if (constructFunctions.exists(constr)) {
				return Reflect.callMethod(this, constructFunctions.get(constr), arguments ?? []);
			} else {
				return new InsanityScriptedEnumValue(this, values.indexOf(constr));
			}
		}
		return null;
	}

	/**
	 * Constructs a value by constructor index.
	 *
	 * @param index The constructor index.
	 * @param arguments Constructor arguments, if any.
	 * @return The enum value, or null if the index is out of range.
	 */
	public function typeCreateEnumIndex(index:Int, ?arguments:Array<Dynamic>):Dynamic {
		return typeCreateEnum(values[index], arguments);
	}

	/** @return A copy of the constructor names. */
	public function typeGetEnumConstructs():Array<String> {
		return (values?.copy() ?? []);
	}

	/** @return A value for every parameterless constructor. */
	public function typeAllEnums():Array<Dynamic> {
		var enums:Array<InsanityScriptedEnumValue> = [];

		for (index => constr in values) {
			if (constructs.get(constr).arguments == null)
				enums.push(new InsanityScriptedEnumValue(this, index));
		}

		return enums;
	}

	/** An enum has no reflectable fields. @param field Unused. @return Always false. */
	public function reflectHasField(field:String):Bool {
		return false;
	}

	/**
	 * Resolves a constructor name to its value or builder (this is how `Enum.Ctor` reads).
	 *
	 * @param field The constructor name.
	 * @return The value (or builder for a parameterized constructor), or null if unknown.
	 */
	public function reflectGetField(field:String):Dynamic {
		var construct:EnumFieldDecl = constructs.get(field);
		if (construct != null) {
			if (constructFunctions.exists(field)) {
				return constructFunctions.get(field);
			} else {
				return new InsanityScriptedEnumValue(this, values.indexOf(field));
			}
		}
		return null;
	}

	/** An enum's constructors are read-only. @param field Unused. @param value Unused. @return Always null. */
	public function reflectSetField(field:String, value:Dynamic):Dynamic {
		return null;
	}

	/** Alias of `reflectGetField`. @param property The constructor name. @return The value or builder. */
	public function reflectGetProperty(property:String):Dynamic {
		return reflectGetField(property);
	}

	/** An enum's constructors are read-only. @param property Unused. @param value Unused. @return Always null. */
	public function reflectSetProperty(property:String, value:Dynamic):Dynamic {
		return null;
	}

	/** @return Null; an enum exposes constructors, not fields. */
	public function reflectListFields():Array<String> {
		return null;
	}

	/** No-op: an enum has no state to snapshot. */
	public function snapshot():Void {}
}

/** One value of a script-declared enum: its enum, constructor index/name, and any arguments. */
class InsanityScriptedEnumValue implements ICustomEnumValueType {
	/** The enum this value belongs to. */
	var base:InsanityScriptedEnum;

	/** The constructor index. */
	public var index:Int;

	/** The constructor name. */
	public var constructor:String;

	/** The constructor arguments, or null for a parameterless constructor. */
	public var arguments:Array<Dynamic>;

	/**
	 * Creates an enum value.
	 *
	 * @param base The enum it belongs to.
	 * @param index The constructor index.
	 * @param arguments The constructor arguments, if any.
	 */
	public function new(base:InsanityScriptedEnum, index:Int, ?arguments:Array<Dynamic>) {
		this.base = base;
		this.arguments = arguments;

		this.index = index;
		this.constructor = (base != null && base.values != null && index >= 0 && index < base.values.length) ? base.values[index] : null;
	}

	/** @return `Ctor` or `Ctor(arg,arg)` source-like text. */
	public function toString():String {
		if (arguments != null)
			return '$constructor(${arguments.join(',')})';

		return constructor;
	}

	/** @return The enum this value belongs to. */
	public function typeGetEnum():Dynamic {
		return base;
	}

	/**
	 * Structural equality: same constructor and equal arguments, matching values of the same enum
	 * even across a reload (compared by enum path).
	 *
	 * @param o The value to compare with.
	 * @return True if equal.
	 */
	public function eq(o:ICustomEnumValueType):Bool {
		if (!(o is InsanityScriptedEnumValue))
			return false;

		var o:InsanityScriptedEnumValue = cast o;
		// Same instance, or two instances of the same enum path (one can be a reload of the
		// other); either way equal constructors compare equal.
		if (o.base == base || (o.base != null && base != null && o.base.path == base.path)) {
			if (index != o.index)
				return false;
			if (o.arguments == null || arguments == null)
				return (o.arguments == arguments);

			if (arguments.length != o.arguments.length)
				return false;
			for (i => argument in arguments) {
				if (argument != o.arguments[i])
					return false;
			}

			return true;
		}

		return false;
	}
}

/** The empty host class scripted classes with no native base are allocated from. */
class InsanityDummyClass implements IInsanityScripted {
	public function new() {}
}

/** The common contract every runtime scripted type (class, interface, enum, typedef) satisfies. */
interface IInsanityType {
	/** The type's short name. */
	public var name:String;

	/** The declaring module. */
	public var module:Module;

	/** The type's package segments. */
	public var pack:Array<String>;

	/** The type's fully-qualified path. */
	public var path:String;

	/** Whether initialization failed. */
	public var failed:Bool;

	/** Whether the type has finished initializing. */
	public var initialized:Bool;

	/** Whether the type is currently initializing. */
	public var initializing:Bool;

	/**
	 * Initializes the type.
	 *
	 * @param env The world it initializes against, if any.
	 * @param baseInterp An interpreter whose scope is inherited, if any.
	 * @param restore Whether to restore any snapshotted state.
	 */
	public function init(?env:Environment, ?baseInterp:Interp, restore:Bool = true):Void;

	/** Saves any snapshottable state for a later reload. */
	public function snapshot():Void;
}

/**
 * The interface a generated bridge class implements so a native instance can behave as a scripted
 * one: it carries the scripted class, the instance's interpreter and variables, safe-mode flags, and
 * the constructor entry point. Built automatically by `ScriptedMacro` on any implementor.
 */
@:autoBuild(insanity.backend.macro.ScriptedMacro.build())
interface IInsanityScripted extends ICustomReflection extends ICustomClassType {
	/** The scripted class this instance is an instance of. */
	private var __base:InsanityScriptedClass;

	/** The instance's interpreter (its method/field scope). */
	private var __interp:insanity.backend.Interp;

	/** The instance's variable slots. */
	private var __vars:Map<String, insanity.backend.Interp.Variable>;

	/** Whether instance-method errors are caught rather than thrown. */
	private var __safe:Bool;

	/** The name of the method currently executing (for error reports). */
	private var __func:String;

	/** The instance's field names. */
	private var __fields:Array<String>;

	/**
	 * Runs the scripted constructor on a freshly-allocated instance.
	 *
	 * @param base The scripted class being instantiated.
	 * @param arguments Constructor arguments.
	 */
	private function __construct(base:InsanityScriptedClass, arguments:Array<Dynamic>):Void;
}

/** Sentinel thrown when a static initializer can't run yet, so it is retried after initialization. */
enum Defer {
	/** Defer this initializer until dependencies are ready. */
	DDefer;
}
