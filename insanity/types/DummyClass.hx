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

/** The empty host class scripted classes with no native base are allocated from. */
class DummyClass implements IScriptedInstance {
	public function new() {}
}
