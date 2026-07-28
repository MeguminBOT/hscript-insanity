package insanity.runtime;

/**
 * One name-to-type binding produced by a wildcard import, remembered so the type resolution behind
 * it runs once per world instead of once per interpreter.
 *
 * A `@:structInit` class rather than an anonymous structure, for the same reason as `Variable`:
 * anonymous structures resolve their fields by name at runtime on static targets.
 */
@:structInit
class ImportEntry {
	/** The name the type is bound under. */
	public var name:String;

	/** The resolved type, or null when the path resolved to nothing. */
	public var type:Dynamic;
}
