package insanity.runtime;

import insanity.syntax.Expr;

/** A pending field resolution, deferred until the base value is known. */
enum Resolve {
	/** Resolve field `f` (errors if missing). */
	RNormal(f:String);

	/** Resolve field `f` null-safely (yields null if missing). */
	RMaybe(f:String);

	/** Resolve by evaluating an expression. */
	RExpr(e:Expr);
}
