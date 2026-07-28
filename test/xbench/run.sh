#!/bin/sh
# Builds and runs the cross-library benchmark, one process per case.
#
#   LIBS=/path/to/checkouts sh test/xbench/run.sh
#
# `LIBS` must contain checkouts named: insanity-upstream, hscript, improved, iris, rulescript,
# hscript-rs (an hscript old enough for RuleScript; see docs/benchmarks.md). Anything missing is
# skipped rather than failing the run.
#
# One process per case on purpose: some libraries hang or crash on some inputs, and a single-process
# run would lose every case after the first one that dies.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
LIBS=${LIBS:-"$ROOT/../xbench-libs"}
BIN=${BIN:-"$ROOT/bin_xbench"}
OUT="$BIN/results.txt"

mkdir -p "$BIN"

build() { # name, classpath, main, [extra hxml]
  [ -d "$2" ] || { echo "skip $1 (no $2)" >&2; return; }
  haxe -cp "$HERE" -cp "$2" ${4:+"$4"} -main "$3" -cpp "$BIN/$1" >/dev/null 2>&1 \
    || { echo "skip $1 (build failed)" >&2; return; }
  echo "$1"
}

echo "building..." >&2
build ours "$ROOT" RunInsanity >/dev/null
build upstream "$LIBS/insanity-upstream" RunInsanity >/dev/null
build hscript "$LIBS/hscript" RunHscript >/dev/null
build improved "$LIBS/improved" RunHscript >/dev/null
build iris "$LIBS/iris" RunIris >/dev/null
# The same libraries again with position tracking on, which is what this fork always does. Without
# it they record no source positions at all, so the plain rows are not a like-for-like comparison.
build hscript-pos "$LIBS/hscript" RunHscript "$HERE/hscript-pos.hxml" >/dev/null
build improved-pos "$LIBS/improved" RunHscript "$HERE/hscript-pos.hxml" >/dev/null
build iris-pos "$LIBS/iris" RunIris "$HERE/hscript-pos.hxml" >/dev/null
if [ -d "$LIBS/rulescript" ] && [ -d "$LIBS/hscript-rs" ]; then
  haxe -cp "$HERE" -cp "$LIBS/rulescript" -cp "$LIBS/hscript-rs" "$HERE/rulescript-params.hxml" \
    -main RunRuleScript -cpp "$BIN/rulescript" >/dev/null 2>&1 || echo "skip rulescript" >&2
fi

: > "$OUT"
# tr -d '\r': the runners emit CRLF, and a case name carrying a trailing CR matches nothing
CASES=$("$BIN/ours/RunInsanity.exe" ours __list | tr -d '\r')

# The whole corpus is run at each of these scales. One scale cannot tell a real per-operation
# difference apart from a fixed setup cost or a warm-up artefact. Must be multiples of 1000, which is
# the array length `forArray` walks.
SCALES=${SCALES:-"25000 100000 500000"}

for entry in "ours:$BIN/ours/RunInsanity.exe" \
             "insanity-upstream:$BIN/upstream/RunInsanity.exe" \
             "hscript-pos:$BIN/hscript-pos/RunHscript.exe" \
             "hscript:$BIN/hscript/RunHscript.exe" \
             "hscript-improved-pos:$BIN/improved-pos/RunHscript.exe" \
             "hscript-improved:$BIN/improved/RunHscript.exe" \
             "hscript-iris-pos:$BIN/iris-pos/RunIris.exe" \
             "hscript-iris:$BIN/iris/RunIris.exe" \
             "rulescript:$BIN/rulescript/RunRuleScript.exe"; do
  lib=${entry%%:*}
  exe=${entry#*:}
  [ -x "$exe" ] || continue
  # Parse throughput does not scale with the loop count, so it is measured once per library.
  line=$(timeout 300 "$exe" "$lib" __parse 2>/dev/null | grep -E '^P\|') || true
  echo "${line:-P|$lib|0|crash}" >> "$OUT"
  for n in $SCALES; do
    for c in $CASES; do
      line=$(timeout 300 "$exe" "$lib" "$c" "$n" 2>/dev/null | grep -E '^R\|') || true
      echo "${line:-R|$lib|$c|?|$n|crash|-|process died}" >> "$OUT"
    done
    echo "$lib @ $n done" >&2
  done
done

python "$HERE/collate.py" "$OUT"
