package insanity.custom;

import insanity.custom.InsanityType;

/**
 * A drop-in replacement for `Reflect`, aliased as `Reflect` inside the interpreter. Field/property
 * access and listing dispatch to an object's own `ICustomReflection` implementation when present
 * (so scripted instances expose their script fields); everything else forwards to native `Reflect`.
 */
class InsanityReflect {
	/**
	 * Tests whether an object has a field.
	 *
	 * @param o The object.
	 * @param field The field name.
	 * @return True if the field exists.
	 */
	public inline static function hasField(o:Dynamic, field:String):Bool {
		if (o is ICustomReflection) {
			return cast(o, ICustomReflection).reflectHasField(field);
		} else {
			return Reflect.hasField(o, field);
		}
	}

	/**
	 * Reads a field's value.
	 *
	 * @param o The object.
	 * @param field The field name.
	 * @return The field value, or null if absent.
	 */
	public inline static function field(o:Dynamic, field:String):Dynamic {
		if (o is ICustomReflection) {
			return cast(o, ICustomReflection).reflectGetField(field);
		} else {
			return Reflect.field(o, field);
		}
	}

	/**
	 * Writes a field's value.
	 *
	 * @param o The object.
	 * @param field The field name.
	 * @param value The value to store.
	 */
	public inline static function setField(o:Dynamic, field:String, value:Dynamic):Void {
		if (o is ICustomReflection) {
			cast(o, ICustomReflection).reflectSetField(field, value);
		} else {
			Reflect.setField(o, field, value);
		}
	}

	/**
	 * Reads a property, honouring getters.
	 *
	 * @param o The object.
	 * @param field The property name.
	 * @return The property value.
	 */
	public inline static function getProperty(o:Dynamic, field:String):Dynamic {
		if (o is ICustomReflection) {
			return cast(o, ICustomReflection).reflectGetProperty(field);
		} else {
			return Reflect.getProperty(o, field);
		}
	}

	/**
	 * Writes a property, honouring setters.
	 *
	 * @param o The object.
	 * @param field The property name.
	 * @param value The value to store.
	 */
	public inline static function setProperty(o:Dynamic, field:String, value:Dynamic):Void {
		if (o is ICustomReflection) {
			cast(o, ICustomReflection).reflectSetProperty(field, value);
		} else {
			Reflect.setProperty(o, field, value);
		}
	}

	/**
	 * Lists an object's field names.
	 *
	 * @param o The object.
	 * @return The field names.
	 */
	public inline static function fields(o:Dynamic):Array<String> {
		if (o is ICustomReflection) {
			return cast(o, ICustomReflection).reflectListFields();
		} else {
			return Reflect.fields(o);
		}
	}

	/**
	 * Calls a function with an explicit receiver and argument array.
	 *
	 * @param o The receiver (`this`).
	 * @param func The function to call.
	 * @param args The arguments.
	 * @return The call result.
	 */
	public inline static function callMethod(o:Dynamic, func:haxe.Constraints.Function, args:Array<Dynamic>):Dynamic {
		return Reflect.callMethod(o, func, args);
	}

	/**
	 * Tests whether a value is a function.
	 *
	 * @param f The value.
	 * @return True if `f` is callable.
	 */
	public inline static function isFunction(f:Dynamic):Bool {
		return Reflect.isFunction(f);
	}

	/**
	 * Compares two values for ordering.
	 *
	 * @param a The first value.
	 * @param b The second value.
	 * @return A negative, zero, or positive result as `a` is less than, equal to, or greater than `b`.
	 */
	public inline static function compare<T>(a:T, b:T):Int {
		return Reflect.compare(a, b);
	}

	/**
	 * Tests whether two values reference the same method closure.
	 *
	 * @param f1 The first function.
	 * @param f2 The second function.
	 * @return True if they are the same method.
	 */
	public inline static function compareMethods(f1:Dynamic, f2:Dynamic):Bool {
		return Reflect.compareMethods(f1, f2);
	}

	/**
	 * Tests whether a value is an anonymous object or class instance.
	 *
	 * @param v The value.
	 * @return True if it is an object.
	 */
	public inline static function isObject(v:Dynamic):Bool {
		return Reflect.isObject(v);
	}

	/**
	 * Tests whether a value is an enum value, including scripted ones.
	 *
	 * @param v The value.
	 * @return True if it is an enum value.
	 */
	public inline static function isEnumValue(v:Dynamic):Bool {
		if (v is ICustomEnumValueType)
			return true;
		return Reflect.isEnumValue(v);
	}

	/**
	 * Removes a field from an anonymous object.
	 *
	 * @param o The object.
	 * @param field The field name.
	 * @return True if the field existed and was removed.
	 */
	public inline static function deleteField(o:Dynamic, field:String):Bool {
		return Reflect.deleteField(o, field);
	}

	/**
	 * Shallow-copies an object.
	 *
	 * @param o The object to copy.
	 * @return A shallow copy, or null if `o` is null.
	 */
	public inline static function copy<T>(o:Null<T>):Null<T> {
		return Reflect.copy(o);
	}

	/**
	 * Wraps a function taking an argument array as a variadic callable.
	 *
	 * @param f The function receiving all arguments as an array.
	 * @return A callable that collects its arguments and forwards them to `f`.
	 */
	@:overload(function(f:Array<Dynamic>->Void):Dynamic {})
	public static function makeVarArgs(f:Array<Dynamic>->Dynamic):Dynamic {
		return Reflect.makeVarArgs(f);
	}
}

/** Implemented by a scripted instance so `InsanityReflect` can read/write/list its script fields. */
interface ICustomReflection {
	/**
	 * @param field The field name.
	 * @return True if the field exists.
	 */
	public function reflectHasField(field:String):Bool;

	/**
	 * @param field The field name.
	 * @return The field value.
	 */
	public function reflectGetField(field:String):Dynamic;

	/**
	 * @param field The field name.
	 * @param value The value to store.
	 * @return The stored value.
	 */
	public function reflectSetField(field:String, value:Dynamic):Dynamic;

	/**
	 * @param property The property name.
	 * @return The property value (via its getter, if any).
	 */
	public function reflectGetProperty(property:String):Dynamic;

	/**
	 * @param property The property name.
	 * @param value The value to store (via its setter, if any).
	 * @return The stored value.
	 */
	public function reflectSetProperty(property:String, value:Dynamic):Dynamic;

	/** @return The instance's field names. */
	public function reflectListFields():Array<String>;
}
