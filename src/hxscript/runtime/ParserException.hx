package hxscript.runtime;

import hxscript.syntax.Printer;

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
	public function new(e:Error, pmin:Int, pmax:Int, origin:String, line:Int) {
		// Before the assignments, not after: Java and C# require `super()` to be the first statement
		// when the base class is a native one, so the message is built from the parameters rather
		// than by calling `toString()` once the fields are set.
		super(Printer.errorAt(e, origin, line));

		this.e = e;
		this.pmin = pmin;
		this.pmax = pmax;
		this.origin = origin;
		this.line = line;
	}

	/** @return The error formatted with its source position. */
	public override function toString():String {
		return Printer.errorToString(this.e, this);
	}
}
