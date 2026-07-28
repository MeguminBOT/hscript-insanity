package insanity.syntax;

import insanity.syntax.Expr;

/**
 * One pushed-back token and the span it came from.
 *
 * A `@:structInit` class rather than an anonymous structure, for the same reason as `Variable` and
 * `StackFrame`: anonymous structures resolve their fields by name at runtime on static targets, and
 * a recursive-descent parser pushes a token back on every lookahead that does not match, which is
 * most of them. Keeps the `{t: ..., min: ..., max: ...}` construction syntax.
 */
@:structInit
class TokenEntry {
	/** The token itself. */
	public var t:Token;

	/** Start offset of its span. */
	public var min:Int;

	/** End offset of its span. */
	public var max:Int;
}

/** The lexer's token kinds. */
enum Token {
	/** End of input. */
	TEof;

	/** A literal constant. */
	TConst(c:Const);

	/** An identifier or keyword. */
	TId(s:String);

	/** An operator. */
	TOp(s:String);

	/** `(`. */
	TPOpen;

	/** `)`. */
	TPClose;

	/** `{`. */
	TBrOpen;

	/** `}`. */
	TBrClose;

	/** `.`. */
	TDot;

	/** `?.`. */
	TQuestionDot;

	/** `,`. */
	TComma;

	/** `;`. */
	TSemicolon;

	/** `[`. */
	TBkOpen;

	/** `]`. */
	TBkClose;

	/** `?`. */
	TQuestion;

	/** `:`. */
	TDoubleDot;

	/** A metadata token `@name`. */
	TMeta(s:String);

	/** A preprocessor token `#name`. */
	TPrepro(s:String);
}
