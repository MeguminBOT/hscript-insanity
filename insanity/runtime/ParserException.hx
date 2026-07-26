package insanity.runtime;

import insanity.syntax.Printer;

/** A parse error, carrying the error kind and its source position. */
class ParserException extends haxe.Exception {
	/** The specific error. */
	public var e:Error;

	/** Start byte offset of the offending token. */
	public var pmin:Int;

	/** End byte offset of the offending token. */
	public var pmax:Int;

	/** The source origin (file path or script name). */
	public var origin:String;

	/** The 1-based line number. */
	public var line:Int;

	/**
	 * Creates a parser exception.
	 *
	 * @param e The error kind.
	 * @param pmin Start byte offset of the offending token.
	 * @param pmax End byte offset of the offending token.
	 * @param origin The source origin.
	 * @param line The 1-based line number.
	 */
	public function new(e, pmin, pmax, origin, line) {
		this.e = e;
		this.pmin = pmin;
		this.pmax = pmax;
		this.origin = origin;
		this.line = line;

		super(toString());
	}

	/** @return The error formatted with its source position. */
	public override function toString():String {
		return Printer.errorToString(this.e, this);
	}
}
