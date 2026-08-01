package hxscript.proxy;

/**
 * First-class value tokens for the `StdTypes` primitives, registered as the `Int`/`Float`/`Bool`
 * identifiers so scripts can use them as values (`x is Int`, `Std.isOfType(x, Int)`, `cast(x, Int)`).
 * They are needed because those types have no runtime value and, unlike `String` or `Array`, are
 * sub-types of `StdTypes` that the root wildcard import skips. `StdProxy`/`Interp` recognise these
 * tokens and dispatch to the real runtime check.
 */
enum CoreType {
	/** The `Int` type token. */
	CTInt;

	/** The `Float` type token. */
	CTFloat;

	/** The `Bool` type token. */
	CTBool;
}
