package insanity.backend.types;

using insanity.backend.TypeCollection;

class AbstractTools {
	public static function resolve(path:String):Class<InsanityAbstract> {
		var t = (TypeCollection.main.fromPath(path) ?? TypeCollection.main.fromCompilePath(path));

		if (t != null) {
			var a = Type.resolveClass(t[0].pack.join('.') + (t[0].pack.length > 0 ? '.' : '') + 'InsanityAbstract_'
				+ StringTools.replace(t[0].compilePath(), '.', '_'));

			if (a != null)
				return cast a;
		}

		// trace('Can\'t resolve abstract $path');
		return null;
	}

	public static function resolveName(v:Dynamic):String {
		var vv:Dynamic = v;
		switch (Type.typeof(v)) {
			case TInt:
				return 'Int';
			case TFloat:
				return 'Float';
			case TBool:
				return 'Bool';
			case TObject:
				if (v is Enum)
					return Type.getEnumName(v);
			case TClass(c):
				vv = c;
			case TEnum(e):
				return Type.getEnumName(e);
			default:
				return 'unknown';
		}

		if (vv is Class) {
			if (Type.getSuperClass(vv) == InsanityAbstract) {
				return (vv.impl ?? 'unknown');
			} else {
				return Type.getClassName(vv);
			}
		}

		return 'unknown';
	}

	public static function getEnumConstructs(a:Class<InsanityAbstract>):Array<String> {
		var a:Dynamic = a;

		if (a.isEnum)
			return a._enumConstructors.copy();

		throw '${a?.impl ?? a} is not an enum abstract';
		return null;
	}

	public static function createEnum(a:Class<InsanityAbstract>, n:String):InsanityAbstract {
		var a:Dynamic = a;

		if (a.isEnum)
			return Type.createInstance(a, [a._enumValues[a._enumMap.get(n) ?? -1]]);

		throw '${a?.impl ?? a} is not an enum abstract';
		return null;
	}

	public static function createEnumIndex(a:Class<InsanityAbstract>, i:Int):InsanityAbstract {
		var a:Dynamic = a;

		if (a.isEnum)
			return Type.createInstance(a, [a._enumValues[i]]);

		throw '${a?.impl ?? a} is not an enum abstract';
		return null;
	}

	public static function isAbstract(o:Dynamic):Bool {
		return (o is InsanityAbstract);
	}
}

class InsanityAbstract {
	var value(get, set):Dynamic;
	var __a(default, null):Dynamic;

	public function new(v:Dynamic) {
		value = v;
	}

	// implemented in macro
	function get_value():Dynamic {
		return __a;
	}

	function set_value(v:Dynamic):Dynamic {
		return __a = v;
	}

	public function resolveTo(t:String):Dynamic {
		return null;
	}
}
