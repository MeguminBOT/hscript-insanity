package hxscript.proxy;

#if hl
/**
 * HashLink stand-in for `Math`, aliased as `Math` inside the interpreter on that target. `Math` has
 * no runtime representation on HashLink, so its members can't be reflected on; the `HLMacro.build`
 * macro re-emits each one as a real reflectable field. Used only under `#if hl`.
 */
@:build(hxscript.macro.HLMacro.build(Math)) class HLMath {}
#end
