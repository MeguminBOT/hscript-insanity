package insanity.backend;

import haxe.Exception;
import insanity.backend.Expr;
import insanity.backend.CallStack;

/** A runtime error raised while interpreting, carrying the interpreter's own call stack. */
class InterpException extends Exception {
	/** The interpreter-level call stack captured when the error was raised. */
	var customStack:CallStack;

	/** Whether to print the full native stack; on by default only in debug builds. */
	var fullStack:Bool = #if debug true #else false #end;

	/**
	 * Creates an interpreter exception.
	 *
	 * @param stack The interpreter call stack at the point of failure.
	 * @param message The error message.
	 * @param previous The underlying exception being wrapped, if any.
	 */
	public function new(stack:CallStack, message:String, ?previous:Exception) {
		super(message, previous);

		customStack = stack;
	}

	/**
	 * Renders the message with the interpreter stack, and (unless `fullStack`) trims leading native
	 * frames inside the interpreter's own package so the trace points at the script.
	 *
	 * @return The detailed error text.
	 */
	public override function details():String {
		var b:StringBuf = new StringBuf();
		b.add('Exception: ${toString()}$customStack');

		var stack:haxe.CallStack = stack?.copy();
		if (stack != null) {
			if (!fullStack && stack.length > 0) {
				while (true) {
					switch (stack[0]) {
						case FilePos(s, file, line, col):
							if (StringTools.startsWith(file, 'insanity/')) { // hide the interpreter's own frames from script traces
								stack.asArray().shift();
							} else {
								break;
							}
						default:
							break;
					}
				}
			}
			b.add(Std.string(stack));
		}

		return b.toString();
	}
}

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

/** Every parse/interpret error kind, rendered to text by `Printer.errorToString`. */
enum Error {
	/** A non-import statement appeared in an `import.hx` prelude. */
	EImportHx;

	/** `super` was used where the current class has no super-class. */
	EHasNoSuper;

	/** A switch pattern the interpreter can't match. */
	EUnrecognizedPattern(e:Expr);

	/** Field `f` does not exist on object `o`. */
	EUnknownField(o:Dynamic, f:String);

	/** Type `t` could not be resolved. */
	EUnknownType(t:String);

	/** An invalid character in the source. */
	EInvalidChar(c:Int);

	/** An unexpected token. */
	EUnexpected(s:String);

	/** A string literal was not closed. */
	EUnterminatedString;

	/** A block comment was not closed. */
	EUnterminatedComment;

	/** A regex literal was not closed. */
	EUnterminatedRegex;

	/** A malformed `#if`/`#elseif` conditional. */
	EInvalidPreprocessor(msg:String);

	/** Identifier `v` is not defined. */
	EUnknownVariable(v:String);

	/** Value `v` cannot be iterated. */
	EInvalidIterator(v:String);

	/** Operator `op` is not valid here. */
	EInvalidOp(op:String);

	/** Field `f` cannot be accessed (e.g. a `private` violation). */
	EInvalidAccess(f:String);

	/** An arbitrary message. */
	ECustom(msg:String);
}
