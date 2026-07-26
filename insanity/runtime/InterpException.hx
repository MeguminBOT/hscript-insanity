package insanity.runtime;

import haxe.Exception;
import insanity.runtime.CallStack;
import insanity.syntax.Printer;

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
