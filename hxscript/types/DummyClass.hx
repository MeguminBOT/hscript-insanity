package hxscript.types;

using StringTools;
using hxscript.types.TypeCollection;

/** The empty host class scripted classes with no native base are allocated from. */
class DummyClass implements IScriptedInstance {
	/** Creates the placeholder host instance. */
	public function new() {}
}
