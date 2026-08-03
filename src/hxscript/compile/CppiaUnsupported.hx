package hxscript.compile;

#if hxscript_cppia
import hxscript.syntax.Expr;

/**
 * Raised when a construct has no cppia spelling, so its module falls back to the interpreter. A
 * normal outcome rather than a failure.
 */
class CppiaUnsupported {
	/** What could not be emitted. */
	public var reason:String;

	/** Where it was, when a position was available. */
	public var pos:Null<Position>;

	public function new(reason:String, ?pos:Position) {
		this.reason = reason;
		this.pos = pos;
	}

	public function toString():String {
		if (pos == null)
			return 'cannot compile: ' + reason;
		return 'cannot compile: ' + reason + ' (' + pos.origin + ':' + pos.line + ')';
	}
}
#end
