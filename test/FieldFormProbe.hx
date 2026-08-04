import hxscript.compile.Cppia;
import hxscript.compile.CppiaInput;
import hxscript.compile.CppiaResult;
import hxscript.syntax.Parser;

/**
 * Compiles a directory of scripted classes and reports which field form the emitter chose.
 *
 * A benchmark says what an optimisation is worth where it applies. It cannot say whether it applies
 * to the code someone actually wrote, and those are different questions -- the second one is
 * answered by counting the tokens that came out.
 */
class FieldFormProbe {
	public static function main():Void {
		var root:String = Sys.args()[0];
		var files:Array<String> = [];
		walk(root, files);

		var inputs:Array<CppiaInput> = [];
		for (file in files) {
			var name:String = file.split('/').pop().split('.').shift();
			var pack:Array<String> = packOf(file, root);
			try {
				inputs.push({name: name, decls: new Parser().parseModule(sys.io.File.getContent(file), name, 0, pack)});
			} catch (e:Dynamic) {
				Sys.println('parse failed: ' + file + ' -- ' + e);
			}
		}

		var result:CppiaResult = Cppia.compile(inputs, ambient());
		Sys.println('modules: ' + inputs.length + '   compiled: ' + result.compiled.length + '   skipped: ' + result.skipped.length);
		for (s in result.skipped)
			Sys.println('  skipped ' + s.name + ' -- ' + s.reason);

		if (result.bytes == null)
			return;

		var text:String = result.bytes.toString();
		Sys.println('');
		Sys.println('FLINK      ' + count(text, 'FLINK'));
		Sys.println('FTHISINST  ' + count(text, 'FTHISINST'));
		Sys.println('FNAME      ' + count(text, 'FNAME'));
		Sys.println('FTHISNAME  ' + count(text, 'FTHISNAME'));
	}

	static function count(text:String, token:String):Int {
		var n:Int = 0;
		var at:Int = text.indexOf(token);
		while (at >= 0) {
			n++;
			at = text.indexOf(token, at + token.length);
		}
		return n;
	}

	static function packOf(file:String, root:String):Array<String> {
		var rel:String = file.substr(root.length + 1);
		var parts:Array<String> = rel.split('/');
		parts.pop();
		return parts;
	}

	static function walk(dir:String, into:Array<String>):Void {
		for (entry in sys.FileSystem.readDirectory(dir)) {
			var full:String = dir + '/' + entry;
			if (sys.FileSystem.isDirectory(full))
				walk(full, into);
			else if (StringTools.endsWith(entry, '.hx'))
				into.push(full);
		}
	}

	static function ambient():Array<String> {
		return [
			'FlxG',
			'FlxSprite',
			'FlxStrip',
			'FlxText',
			'FlxCamera',
			'FlxColor',
			'FlxGraphic',
			'BitmapData',
			'Paths',
			'ScriptDraw',
			'ScriptCompiler',
			'MusicBeatState',
			'Point',
			'Rectangle',
			'Matrix',
			'Mods',
			'CoolUtil',
			'ClientPrefs',
			'Conductor',
			'FlxMath',
			'FlxSort',
			'FlxTween',
			'FlxEase',
			'File',
			'FileSystem',
			'Lib',
			'Bytes',
			'Std',
			'Math',
			'StringTools',
			'Reflect',
			'Type'
		];
	}
}
