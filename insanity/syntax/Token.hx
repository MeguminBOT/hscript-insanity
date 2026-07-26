package insanity.syntax;

import insanity.syntax.Expr;

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
