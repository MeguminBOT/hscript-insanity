package hxscript.types;

using StringTools;
using hxscript.types.TypeCollection;

/** Sentinel thrown when a static initializer can't run yet, so it is retried after initialization. */
enum Defer {
	/** Defer this initializer until dependencies are ready. */
	DDefer;
}
