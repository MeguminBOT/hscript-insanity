package insanity;

import insanity.backend.types.Scripted;
import insanity.backend.TypeCollection;

class Environment {
	public var modules:Map<String, Module> = [];
	public var types:TypeCollection;

	public var variables:Map<String, Dynamic> = [];
	public var onInitialized:Array<Map<String, IInsanityType>->Bool> = [];

	public function new(?modules:Array<Module>) {
		if (modules != null) {
			for (module in modules)
				this.modules.set(module.path, module);
		}

		rebuildTypes();
	}

	public function addModule(module:Module):Module {
		modules.set(module.path, module);
		rebuildTypes();
		return module;
	}

	public function removeModule(module:Module):Module {
		modules.remove(module.path);
		rebuildTypes();
		return module;
	}

	public function resolve(path:String):IInsanityType {
		for (module in modules) {
			if (module.types.exists(path))
				return module.types.get(path);
		}

		return null;
	}

	public function start():Void {
		var allTypes:Map<String, IInsanityType> = [];

		for (module in modules)
			module.init(this);

		for (module in modules)
			module.start(this);

		for (module in modules) {
			module.startTypes(this);

			for (n => t in module.types)
				allTypes.set(n, t);
		}

		var i:Int = onInitialized.length;
		while (--i >= 0) {
			if (!onInitialized[i](allTypes))
				onInitialized.remove(onInitialized[i]);
		}
	}

	public function snapshot():Void {
		for (module in modules)
			module.snapshot();
	}

	public function rebuildTypes():TypeCollection {
		var map:TypeMap = {
			byPackage: [],
			byModule: [],
			byPath: [],
			byCompilePath: [],
			all: []
		};

		function makeTypeInfo(module:Module) {
			var pack:String = module.pack.join('.');

			for (type in module.types) {
				var k:String = 'class';
				var isInterface:Bool = false;
				var structural:Bool = false;

				if (type is InsanityScriptedEnum)
					k = 'enum';
				else if (type is InsanityScriptedInterface)
					isInterface = true;
				else if (type is InsanityScriptedTypedef) {
					k = 'typedef';
					structural = cast(type, InsanityScriptedTypedef).structural;
				}

				var info:TypeInfo = {
					kind: k,
					module: module.path,
					pack: type.pack,
					name: type.name,
					isInterface: isInterface,
					structural: structural,
				};

				var tp:Array<String> = info.pack.copy();
				tp.push(info.name);

				map.all.push(info);

				map.byCompilePath[tp.join('.')] = [info];
				map.byPath[info.module + (info.module.length == 0 ? '' : '.') + info.name] = [info];

				map.byModule[info.module] ??= [];
				map.byModule[info.module].push(info);

				map.byPackage[pack] ??= [];
				map.byPackage[pack].push(info);
			}
		}

		for (module in modules)
			makeTypeInfo(module);

		return types = new TypeCollection(map);
	}
}
