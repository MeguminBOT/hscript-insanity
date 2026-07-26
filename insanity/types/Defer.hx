package insanity.types;

import insanity.proxy.ReflectProxy;
import insanity.proxy.TypeProxy;
import insanity.runtime.Interp;
import insanity.runtime.Variable;
import insanity.syntax.Expr;
import insanity.Environment;
import insanity.Module;

using StringTools;
using insanity.types.TypeCollection;

/** Sentinel thrown when a static initializer can't run yet, so it is retried after initialization. */
enum Defer {
	/** Defer this initializer until dependencies are ready. */
	DDefer;
}
