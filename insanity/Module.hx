package insanity;

import insanity.backend.types.Scripted;
import insanity.backend.Exception;
import insanity.backend.Parser;
import insanity.backend.Interp;
import insanity.backend.Expr;
import insanity.tools.Tools;

class Module {
	public static var snapshots:Map<String, Map<String, Dynamic>> = [];

	public var name:String;
	public var origin:String;
	public var pack:Array<String>;
	public var path(get, never):String;

	public var parser:Parser = new Parser();
	public var interp:Interp = null;

	public var decls:Array<ModuleDecl> = [];
	public var types:Map<String, IInsanityType> = [];
	public var moduleFields:InsanityScriptedClass = null;
	public var onInitialized:Array<Map<String, IInsanityType>->Bool> = [];

	public var subModules:Array<Module> = [];

	public var starting:Bool = false;
	public var started:Bool = false;

	public var variables(get, never):Map<String, Dynamic>;

	inline function get_variables():Map<String, Dynamic> {
		return interp.variables;
	}

	public function new(string:String, name:String = 'Module', pack:Array<String>, origin:String = 'hscript'):Void {
		parser.allowTypes = parser.allowJSON = true;
		interp = Type.createInstance(Config.interpClass, [null, this]);

		this.origin = origin;
		this.name = name;
		this.pack = pack;

		parse(string);
	}

	public function parse(string:String):Array<ModuleDecl> {
		decls.resize(0);
		types.clear();

		try {
			var declList:Array<ModuleDecl> = parser.parseModule(string, origin, pack);
			for (decl in declList) {
				decls.push(decl);

				var type:IInsanityType = loadType(decl);

				if (type != null)
					types.set(Tools.pathToString(type.name, pack), type);
			}
		} catch (e:haxe.Exception) {
			onParsingError(e);
		}

		return decls;
	}

	public function loadType(decl):IInsanityType {
		return switch (decl.d) {
			default:
				null;
			case DClass(m):
				new InsanityScriptedClass(m, this);
			case DInterface(m):
				new InsanityScriptedInterface(m, this);
			case DEnum(m):
				new InsanityScriptedEnum(m, this);
			case DTypedef(m):
				new InsanityScriptedTypedef(m, this);
			case DField(m):
				var fieldsPath:String = Tools.pathToString('_$name.${name}_Fields_', pack);
				var t:InsanityScriptedClass = cast types.get(fieldsPath);

				var d:FieldDecl = {
					name: m.name,
					meta: m.meta,
					kind: m.kind,
					access: (m.isPrivate ? [AStatic, APrivate] : [AStatic, APublic])
				};

				if (t == null) { // creates Dummy class for the module level fields
					var fieldsModule:ClassDecl = {
						name: '${name}_Fields_',
						params: [],
						meta: [],
						fields: [d],
						isExtern: false,
						isPrivate: false,
						implement: null,
						extend: null,
					};

					var cl = new InsanityScriptedClass(fieldsModule, this);
					cl.pack = cl.pack.copy();
					cl.pack.push('_$name');
					cl.path = Tools.pathToString(cl.name, cl.pack);

					moduleFields = cl;

					types.set(fieldsPath, cl);
				} else {
					@:privateAccess t.decl.fields.push(d);
				}

				null;
		}
	}

	public function init(?environment:Environment):Void {
		interp.environment = environment;
		setDefaults();

		if (environment != null) {
			for (k => v in environment.variables)
				if (!variables.exists(k))
					variables.set(k, v);
		}

		for (type in types) {
			interp.imports.set(type.name, type);

			// Enums declared in this module expose their constructors unqualified, the
			// same way Haxe does for same-module enums.
			if (type is InsanityScriptedEnum) {
				var e:InsanityScriptedEnum = cast type;

				for (i => v in e.constructNames())
					interp.imports.set(v, Mirror.MEnumValue(e, i));
			} else if (type is InsanityScriptedClass) {
				// An enum abstract desugars to a class of static constants; expose those
				// constants unqualified too, the same way enum constructors are.
				var c:InsanityScriptedClass = cast type;
				var enumAbstract:Bool = false;
				for (m in @:privateAccess c.decl.meta)
					if (m.name == ':enumAbstract')
						enumAbstract = true;

				if (enumAbstract) {
					for (field in @:privateAccess c.decl.fields)
						if (field.access.contains(AStatic))
							interp.imports.set(field.name, Mirror.MProperty(c, field.name));
				}
			}
		}
	}

	public function start(?environment:Environment):Void {
		try {
			if (decls.length == 0)
				throw 'Module is uninitialized';

			starting = true;

			for (module in subModules) {
				if (module is ImportModule) {
					module.start(environment);

					for (u in module.interp.usings)
						interp.usings.push(u);
					for (n => i in module.interp.imports)
						interp.imports.set(n, i);
				} else {
					var mainType:IInsanityType = module.types.get(module.path);

					if (mainType != null)
						module.interp.imports.set(mainType.name, mainType);
				}
			}

			interp.canInit = true;
			interp.executeModule(decls, path);

			starting = false;
			started = true;
		} catch (e:haxe.Exception) {
			onProgramError(e);
		}
	}

	public function startType(?environment:Environment, type:IInsanityType):IInsanityType {
		if (type.initializing || type.initialized || type.failed)
			return type;

		if (starting)
			return type;
		if (!started)
			start(environment);

		try {
			type.initializing = true;

			type.init(environment, interp);

			type.initializing = false;
			type.initialized = true;
		} catch (e:haxe.Exception) {
			type.failed = true;
			type.initialized = false;
			type.initializing = false;

			onTypeError(e, type);
		}

		return type;
	}

	public function startTypes(?environment:Environment):Map<String, IInsanityType> {
		if (moduleFields != null) {
			startType(environment, moduleFields);

			for (field in insanity.custom.InsanityReflect.fields(moduleFields))
				interp.imports.set(field, MProperty(moduleFields, field));
		}

		for (type in types)
			startType(environment, type);

		var i:Int = onInitialized.length;
		while (--i >= 0) {
			if (!onInitialized[i](types))
				onInitialized.remove(onInitialized[i]);
		}

		return types;
	}

	public function snapshot():Void {
		for (type in types)
			type.snapshot();
	}

	public function setDefaults():Void {
		interp.setDefaults();

		variables.set('module', this);
	}

	public dynamic function onParsingError(e:haxe.Exception):Void {
		trace('Failed to initialize module program!\n' + e.details());
	}

	public dynamic function onProgramError(e:haxe.Exception):Void {
		trace('Module program stopped unexpectedly!\n' + e.details());
	}

	public dynamic function onTypeError(e:haxe.Exception, type:IInsanityType):Void {
		trace('Failed to load type ${type.name} for module $path!\n' + e.details());
	}

	function get_path():String {
		var path:String = pack.join('.');

		if (path.length > 0) {
			return ('$path.$name');
		} else {
			return name;
		}
	}
}
