package insanity.custom;

import insanity.custom.InsanityType;

class InsanityReflect {
	public inline static function hasField(o:Dynamic, field:String):Bool {
		if (o is ICustomReflection) {
			return cast(o, ICustomReflection).reflectHasField(field);
		} else {
			return Reflect.hasField(o, field);
		}
	}

	public inline static function field(o:Dynamic, field:String):Dynamic {
		if (o is ICustomReflection) {
			return cast(o, ICustomReflection).reflectGetField(field);
		} else {
			return Reflect.field(o, field);
		}
	}

	public inline static function setField(o:Dynamic, field:String, value:Dynamic):Void {
		if (o is ICustomReflection) {
			cast(o, ICustomReflection).reflectSetField(field, value);
		} else {
			Reflect.setField(o, field, value);
		}
	}

	public inline static function getProperty(o:Dynamic, field:String):Dynamic {
		if (o is ICustomReflection) {
			return cast(o, ICustomReflection).reflectGetProperty(field);
		} else {
			return Reflect.getProperty(o, field);
		}
	}

	public inline static function setProperty(o:Dynamic, field:String, value:Dynamic):Void {
		if (o is ICustomReflection) {
			cast(o, ICustomReflection).reflectSetProperty(field, value);
		} else {
			Reflect.setProperty(o, field, value);
		}
	}

	public inline static function fields(o:Dynamic):Array<String> {
		if (o is ICustomReflection) {
			return cast(o, ICustomReflection).reflectListFields();
		} else {
			return Reflect.fields(o);
		}
	}

	public inline static function callMethod(o:Dynamic, func:haxe.Constraints.Function, args:Array<Dynamic>):Dynamic {
		return Reflect.callMethod(o, func, args);
	}

	public inline static function isFunction(f:Dynamic):Bool {
		return Reflect.isFunction(f);
	}

	public inline static function compare<T>(a:T, b:T):Int {
		return Reflect.compare(a, b);
	}

	public inline static function compareMethods(f1:Dynamic, f2:Dynamic):Bool {
		return Reflect.compareMethods(f1, f2);
	}

	public inline static function isObject(v:Dynamic):Bool {
		return Reflect.isObject(v);
	}

	public inline static function isEnumValue(v:Dynamic):Bool {
		if (v is ICustomEnumValueType)
			return true;
		return Reflect.isEnumValue(v);
	}

	public inline static function deleteField(o:Dynamic, field:String):Bool {
		return Reflect.deleteField(o, field);
	}

	public inline static function copy<T>(o:Null<T>):Null<T> {
		return Reflect.copy(o);
	}

	@:overload(function(f:Array<Dynamic>->Void):Dynamic {})
	public static function makeVarArgs(f:Array<Dynamic>->Dynamic):Dynamic {
		return Reflect.makeVarArgs(f);
	}
}

interface ICustomReflection {
	public function reflectHasField(field:String):Bool;

	public function reflectGetField(field:String):Dynamic;
	public function reflectSetField(field:String, value:Dynamic):Dynamic;

	public function reflectGetProperty(property:String):Dynamic;
	public function reflectSetProperty(property:String, value:Dynamic):Dynamic;

	public function reflectListFields():Array<String>;
}
