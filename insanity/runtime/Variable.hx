package insanity.runtime;

import insanity.syntax.Expr;
import insanity.types.AbstractValue;

/** A variable slot: its value plus optional abstract box, finality, access flags, and accessors. */
typedef Variable = {
	/** The stored value. */
	var r:Dynamic;

	/** The abstract wrapper, when the value is a boxed abstract. */
	var ?a:AbstractValue;

	/** Whether the binding is `final`. */
	var ?isFinal:Bool;

	/** The field's access modifiers, when it is a class field. */
	var ?access:Array<FieldAccess>;

	/** The getter accessor name, when it is a property. */
	var ?get:String;

	/** The setter accessor name, when it is a property. */
	var ?set:String;
}
