package insanity.runtime;

import insanity.runtime.Variable;

/**
 * A deferred, non-value reference stored in the imports/variables tables and materialized on lookup.
 * It lets a bare name stand for something that is not a plain value: a super call, a property, or an
 * enum constructor.
 */
enum Mirror {
	/** A `super` reference carrying the captured locals and constructor to invoke. */
	MSuper(?locals:Map<String, Variable>, ?constructor:Dynamic);

	/** A property `f` on target `t`, resolved through getters/setters on access. */
	MProperty(t:Dynamic, f:String);

	/** Enum `t`'s constructor at index `i`, materialized to the value (or a builder) on use. */
	MEnumValue(t:Dynamic, i:Int);

	/** Enum-abstract `t`'s constant at index `i`. */
	MAbstractEnumValue(t:Dynamic, i:Int);
}
