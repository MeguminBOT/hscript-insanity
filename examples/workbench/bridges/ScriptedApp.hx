package bridges;

import host.App;

/**
 * The bridge that lets a script write `class BlockDrop extends App`.
 *
 * That is the entire declaration. The `@:autoBuild` on `hxscript.IScripted` generates an override of
 * every method `App` declares, each dispatching to the script when it defines that method and
 * falling through to `super` when it does not.
 *
 * `App` is small on purpose: a bridge costs one generated override per inherited method, so a base
 * scripts extend should carry only what they actually need from the host.
 */
class ScriptedApp extends App implements hxscript.IScripted {}
