package bridges;

import game.Entity;

/**
 * Makes `Entity` extendable from a script. Declaring the class is the whole job: the `@:autoBuild`
 * on `insanity.IScripted` generates an override of every inherited method that routes to the script
 * when it defines one, and falls through to `super` when it does not.
 *
 * Nothing references this class, so it must be forced into the build: `--macro include('bridges')`.
 *
 * This is the manual form. `macros/BridgeMacro.hx` generates the identical thing from a list, and
 * bridges `game.Component` that way in this same build, so the two can be compared.
 */
class ScriptedEntity extends Entity implements insanity.IScripted {}
