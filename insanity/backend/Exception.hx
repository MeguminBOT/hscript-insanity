package insanity.backend;

import haxe.Exception;
import insanity.backend.Expr;
import insanity.backend.CallStack;

class InterpException extends Exception {
	var customStack:CallStack;

	var fullStack:Bool = #if debug true #else false #end;

	public function new(stack:CallStack, message:String, ?previous:Exception) {
		super(message, previous);

		customStack = stack;
	}

	public override function details():String {
		var b:StringBuf = new StringBuf();
		b.add('Exception: ${toString()}$customStack');

		var stack:haxe.CallStack = stack?.copy();
		if (stack != null) {
			if (!fullStack && stack.length > 0) {
				while (true) {
					switch (stack[0]) {
						case FilePos(s, file, line, col):
							if (StringTools.startsWith(file, 'insanity/')) { // bit of a dirty solution but whatever
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

class ParserException extends haxe.Exception {
	public var e:Error;
	public var pmin:Int;
	public var pmax:Int;
	public var origin:String;
	public var line:Int;

	public function new(e, pmin, pmax, origin, line) {
		this.e = e;
		this.pmin = pmin;
		this.pmax = pmax;
		this.origin = origin;
		this.line = line;

		super(toString());
	}

	public override function toString():String {
		return Printer.errorToString(this.e, this);
	}
}

enum Error {
	EImportHx;
	EHasNoSuper;
	EUnrecognizedPattern(e:Expr);
	EUnknownField(o:Dynamic, f:String);
	EUnknownType(t:String);
	EInvalidChar(c:Int);
	EUnexpected(s:String);
	EUnterminatedString;
	EUnterminatedComment;
	EUnterminatedRegex;
	EInvalidPreprocessor(msg:String);
	EUnknownVariable(v:String);
	EInvalidIterator(v:String);
	EInvalidOp(op:String);
	EInvalidAccess(f:String);
	ECustom(msg:String);
}
