package insanity.runtime;

import insanity.syntax.Expr;
import insanity.types.AbstractValue;

/**
 * A variable slot: its value plus optional abstract box, finality, access flags, and accessors.
 *
 * Declared as a `@:structInit` class rather than an anonymous structure so its fields compile to
 * direct member access. Anonymous structures are looked up by field name at runtime on static
 * targets, and this type is read on every variable access, so that cost lands in the interpreter's
 * hottest path. `@:structInit` keeps the `{r: value}` construction syntax used throughout.
 */
@:structInit
class Variable {
	/** The stored value. */
	public var r:Dynamic;

	/** The abstract wrapper, when the value is a boxed abstract. */
	public var a:AbstractValue = null;

	/** Whether the binding is `final`. */
	public var isFinal:Bool = false;

	/** The field's access modifiers, when it is a class field. */
	public var access:Array<FieldAccess> = null;

	/** The getter accessor name, when it is a property. */
	public var get:String = null;

	/** The setter accessor name, when it is a property. */
	public var set:String = null;
}
