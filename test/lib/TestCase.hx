/**
 * Shared assertions, output and exit code for the test suite.
 *
 * Every test used to carry its own `pass`/`fail` pair and its own `eq`, copy-pasted about fifteen
 * times with small differences in what each one printed. That was survivable while the suite was run
 * by eye, and stopped being so once it had to run across nine targets: a runner cannot read fifteen
 * dialects of "did it work", and none of those copies set an exit code, so every test reported
 * success whatever happened.
 *
 * The counters are static and shared on purpose. An aggregate runs many tests in one process and
 * reports once at the end, so the totals have to survive across them.
 */
class TestCase {
	/** Assertions that held. */
	public static var pass:Int = 0;

	/** Assertions that did not. */
	public static var fail:Int = 0;

	/**
	 * Constructs a probe found missing, which is not the same as a failure.
	 *
	 * The probes exist to be read rather than passed: `SweepProbe`'s `regex replace` reports a gap on
	 * compiled targets because nothing in the probe calls `EReg.replace` from compiled code, so DCE
	 * removes it. That is a fact about the probe's own build, not a defect, and counting it as a
	 * failure would leave the suite permanently red for a thing nobody should fix.
	 */
	public static var gaps:Int = 0;

	/**
	 * Compares by rendered value rather than with `==`, which is what the suite has always done: the
	 * results are `Dynamic` coming back from a script, and two equal arrays are not `==` on any
	 * target.
	 *
	 * @param name What is being checked, printed either way.
	 * @param got The value the script produced.
	 * @param want The value it should have produced.
	 */
	public static function eq(name:String, got:Dynamic, want:Dynamic):Void {
		if (Std.string(got) == Std.string(want)) {
			pass++;
			log('  ok   $name = $got');
		} else {
			fail++;
			log('  FAIL $name got $got want $want');
		}
	}

	/**
	 * @param name What is being checked.
	 * @param cond Whether it held.
	 */
	public static function ok(name:String, cond:Bool):Void {
		if (cond) {
			pass++;
			log('  ok   $name');
		} else {
			fail++;
			log('  FAIL $name');
		}
	}

	/**
	 * Records a failure that is not a comparison, for a test that threw where it should not have.
	 *
	 * @param name What was being checked.
	 * @param why The reason.
	 */
	public static function bad(name:String, why:String):Void {
		fail++;
		log('  FAIL $name : $why');
	}

	/**
	 * Records a probe result, where a miss is reported and counted but is not a failure.
	 *
	 * Same shape as `eq`, different verdict. Use it for the probes, which sweep a broad surface
	 * looking for gaps, and `eq` for a test that asserts one thing.
	 *
	 * @param name The construct being probed.
	 * @param got What it produced.
	 * @param want What it should have produced.
	 */
	public static function gap(name:String, got:Dynamic, want:Dynamic):Void {
		if (Std.string(got) == Std.string(want)) {
			pass++;
			log('  ok    $name => $got');
		} else {
			gaps++;
			log('  GAP   $name => $got   (want $want)');
		}
	}

	/**
	 * @param name A heading for the group of checks that follows.
	 */
	public static function section(name:String):Void {
		log('-- $name --');
	}

	/**
	 * Writes one line, on whichever target this is.
	 *
	 * `Sys` does not exist on js, flash or lua-without-sys, and `trace` carries a source position
	 * that makes the output noisy everywhere else, so neither works alone.
	 *
	 * @param s The line.
	 */
	public static function log(s:String):Void {
		#if sys
		Sys.println(s);
		#else
		trace(s);
		#end
	}

	/** Prints the totals without ending the process, for an aggregate reporting between tests. */
	public static function summary():Void {
		log('== $pass passed, $fail failed ==' + (gaps > 0 ? ', $gaps gaps' : ''));
	}

	/**
	 * Prints the totals and ends the process, non-zero when anything failed.
	 *
	 * The exit code is the whole point: a runner driving nine targets cannot parse fifteen different
	 * summary lines, and a suite that always exits 0 reports success while failing.
	 *
	 * js has no `Sys.exit`. Setting `process.exitCode` rather than calling `process.exit()` lets
	 * pending output flush, and is inert in a browser, where there is no code to return to anyone.
	 */
	public static function exit():Void {
		summary();

		var code:Int = fail == 0 ? 0 : 1;

		#if sys
		Sys.exit(code);
		#elseif js
		untyped process.exitCode = code;
		#end
	}
}
