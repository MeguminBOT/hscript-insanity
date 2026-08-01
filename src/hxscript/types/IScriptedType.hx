package hxscript.types;

import hxscript.runtime.Interp;
import hxscript.Environment;
import hxscript.Module;

using StringTools;
using hxscript.types.TypeCollection;

/** The common contract every runtime scripted type (class, interface, enum, typedef) satisfies. */
interface IScriptedType {
	/** The type's short name. */
	public var name:String;

	/** The declaring module. */
	public var module:Module;

	/** The type's package segments. */
	public var pack:Array<String>;

	/** The type's fully-qualified path. */
	public var path:String;

	/** Whether initialization failed. */
	public var failed:Bool;

	/** Whether the type has finished initializing. */
	public var initialized:Bool;

	/** Whether the type is currently initializing. */
	public var initializing:Bool;

	/**
	 * Initializes the type.
	 *
	 * @param env The world it initializes against, if any.
	 * @param baseInterp An interpreter whose scope is inherited, if any.
	 * @param restore Whether to restore any snapshotted state.
	 */
	public function init(?env:Environment, ?baseInterp:Interp, restore:Bool = true):Void;

	/** Saves any snapshottable state for a later reload. */
	public function snapshot():Void;
}
