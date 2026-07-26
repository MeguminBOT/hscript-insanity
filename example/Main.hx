import game.Battle;
import game.Entity;
import game.Mods;

/**
 * The app the library is embedded into: a tiny turn-based battle.
 *
 * The host owns the rules -- health, damage, turn order, who wins -- and knows nothing about what
 * fights in them. It never names a script: it asks the loaded world which classes are entities and
 * which side each one put itself on. Dropping a new file into `scripts/` puts a new creature in the
 * fight without changing a line here.
 *
 * Run it:
 *
 *     haxe -cp . -cp example -main Main --macro include('bridges') --macro macros.BridgeMacro.generate() --interp
 */
class Main {
	static function main():Void {
		Mods.setup('example/scripts');

		var battle:Battle = new Battle(20260726);

		// The one fighter the host itself provides, so the mix is visible in the log.
		battle.add(new Entity('knight', 96, 15, true));

		for (e in Mods.roster('party'))
			battle.add(e);
		for (e in Mods.roster('enemy'))
			battle.add(e);

		Sys.println('a fight breaks out');
		for (e in battle.entities)
			Sys.println('  ${e.friendly ? "party" : "enemy"}  ${e.name} (${e.health} hp)');

		battle.run(20);
	}
}
