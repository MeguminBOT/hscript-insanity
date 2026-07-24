package insanity.backend;

import insanity.backend.Interp;

typedef Stack = {
	var locals:Map<String, Variable>;
	var item:StackItem;
}

class CallStack {
	public var stack:Array<Stack>;

	public var length(get, never):Int;

	inline function get_length():Int
		return stack.length;

	public inline function last() {
		return stack[stack.length - 1];
	}

	public inline function first() {
		return stack[0];
	}

	public function toString():String {
		var b = new StringBuf();
		for (s in stack) {
			b.add('\nCalled from ');
			itemToString(b, s.item);
		}
		return b.toString();
	}

	public function new() {
		stack = [];
	}

	public function subtract(stack:CallStack):CallStack {
		var startIndex = -1;
		var i = -1;
		while (++i < this.length) {
			for (j in 0...stack.length) {
				if (equalItems(this.stack[i].item, stack.stack[j].item)) {
					if (startIndex < 0)
						startIndex = i;
					++i;
					if (i >= this.length)
						break;
				} else {
					startIndex = -1;
				}
			}
			if (startIndex >= 0)
				break;
		}
		if (startIndex >= 0)
			this.stack = this.stack.slice(0, startIndex);
		return this;
	}

	public inline function copy():CallStack {
		var copy:CallStack = new CallStack();
		copy.stack = stack.copy();
		return copy;
	}

	static function equalItems(item1:Null<StackItem>, item2:Null<StackItem>):Bool {
		return switch ([item1, item2]) {
			case [null, null]: true;
			case [SScript(m1), SScript(m2)]:
				m1 == m2;
			case [SModule(m1), SModule(m2)]:
				m1 == m2;
			case [SFilePos(item1, file1, line1, col1), SFilePos(item2, file2, line2, col2)]: file1 == file2 && line1 == line2 && col1 == col2 && equalItems(item1,
					item2);
			case [SMethod(class1, method1), SMethod(class2, method2)]: class1 == class2 && method1 == method2;
			case [SLocalFunction(v1), SLocalFunction(v2)]:
				v1 == v2;
			case _: false;
		}
	}

	static function itemToString(b:StringBuf, s) {
		switch (s) {
			case SScript(s):
				b.add('script ');
				b.add(s);
			case SModule(m):
				b.add('module ');
				b.add(m);
			case SFilePos(s, file, line, col):
				if (s != null) {
					itemToString(b, s);
					b.add(' (');
				}
				b.add(file);
				b.add(' line ');
				b.add(line);
				if (col != null) {
					b.add(' column ');
					b.add(col);
				}
				if (s != null)
					b.add(')');
			case SMethod(cname, method):
				b.add(cname == null ? '<unknown>' : cname);
				b.add('.');
				b.add(method);
			case SLocalFunction(n):
				b.add('local function #');
				b.add(n);
		}
	}
}

enum StackItem {
	SScript(s:String);
	SModule(m:String);
	SFilePos(s:Null<StackItem>, file:String, line:Int, ?column:Int);
	SMethod(classname:Null<String>, method:String);
	SLocalFunction(?v:Int);
}
