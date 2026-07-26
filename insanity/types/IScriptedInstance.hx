package insanity.types;

import insanity.proxy.ReflectProxy;
import insanity.proxy.TypeProxy;
import insanity.runtime.Interp;
import insanity.runtime.Variable;

using StringTools;
using insanity.types.TypeCollection;

/**
 * The interface a generated bridge class implements so a native instance can behave as a scripted
 * one: it carries the scripted class, the instance's interpreter and variables, safe-mode flags, and
 * the constructor entry point. Built automatically by `ScriptedMacro` on any implementor.
 */
@:autoBuild(insanity.macro.ScriptedMacro.build())
interface IScriptedInstance extends ICustomReflection extends ICustomClassType {
	/** The scripted class this instance is an instance of. */
	private var __base:ScriptedClass;

	/** The instance's interpreter (its method/field scope). */
	private var __interp:insanity.runtime.Interp;

	/** The instance's variable slots. */
	private var __vars:Map<String, insanity.runtime.Variable>;

	/** Whether instance-method errors are caught rather than thrown. */
	private var __safe:Bool;

	/** The name of the method currently executing (for error reports). */
	private var __func:String;

	/** The instance's field names. */
	private var __fields:Array<String>;

	/**
	 * Runs the scripted constructor on a freshly-allocated instance.
	 *
	 * @param base The scripted class being instantiated.
	 * @param arguments Constructor arguments.
	 */
	private function __construct(base:ScriptedClass, arguments:Array<Dynamic>):Void;
}
