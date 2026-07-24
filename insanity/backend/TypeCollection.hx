package insanity.backend;

#if (!macro)
import insanity.backend.macro.TypeCollectionMacro;
import insanity.Environment;
#end

typedef TypeInfo = {
	var kind:String;
	var name:String;
	var module:String;
	var pack:Array<String>;

	var ?abstractImpl:TypeInfo;
	var ?typedefType:TypeInfo;
	var ?isInterface:Bool;
	var ?structural:Bool;
}

typedef TypeMap = {
	var byCompilePath:Map<String, Array<TypeInfo>>;
	var byPackage:Map<String, Array<TypeInfo>>;
	var byModule:Map<String, Array<TypeInfo>>;
	var byPath:Map<String, Array<TypeInfo>>;
	var all:Array<TypeInfo>;
}

class TypeCollection {
	#if (!macro)
	public static var main(default, never):TypeCollection = new TypeCollection(TypeCollectionMacro.build());

	public var types:TypeMap;

	public function new(?map:TypeMap) {
		this.types = map;
	}

	public inline function fromPath(path:String, moduleCheck:Bool = true):Array<TypeInfo> {
		var t = types.byPath.get(path);

		if (t == null && moduleCheck) {
			var name = path.substring(path.lastIndexOf('.'));
			return fromPath(path + name, false);
		}

		return t;
	}

	public inline function fromModule(path:String):Array<TypeInfo> {
		return types.byModule.get(path);
	}

	public inline function fromPackage(path:String):Array<TypeInfo> {
		return types.byPackage.get(path);
	}

	public inline function fromCompilePath(path:String):Array<TypeInfo> {
		return types.byCompilePath.get(path);
	}

	public static function compilePath(info:TypeInfo):String {
		var typePath:Array<String> = info.pack.copy();
		typePath.push(info.name);
		return typePath.join('.');
	}

	public static function fullPath(info:TypeInfo):String {
		return (info.module + (info.module.length > 0 ? '.' : '') + info.name);
	}

	public static function resolve(info:TypeInfo, ?env:Environment):Dynamic {
		if (info.typedefType != null)
			return Tools.resolve(compilePath(info.typedefType), env);
		return Tools.resolve(compilePath(info), env);
	}
	#end
}
