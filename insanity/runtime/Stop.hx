package insanity.runtime;

/** Internal control-flow signal thrown to unwind loops and functions. */
enum Stop {
	/** A `break`. */
	SBreak;

	/** A `continue`. */
	SContinue;

	/** A `return`. */
	SReturn;
}
