package hxre;

import haxe.macro.Context;
import haxe.macro.Expr;
import hxre.Types;

class Specializer {
	macro public static function build(s : String, ?flags : Flags) : Array<Field> {
		var fields = Context.getBuildFields();
		var ast = Parser.parse(s);
		var prog = Compiler.compile(ast);
		var nturnstile = prog.nturnstile;
		if (flags == null) {
			flags = {
				ignoreCase: false,
				multiline: false,
				global: false,
			};
		}

		var lc = Context.getLocalClass().get();

		if (!lc.isPrivate) {
			var typepath = {
				pack: lc.module.split(".").slice(0, -1),
				name: lc.name,
				sub: null,
				params: []
			};

			var fieldRegex = {
				name: "regex",
				doc: null,
				meta: [],
				access: [APublic, AStatic],
				kind: FProp("default", "null", macro : hxre.Regex, macro new $typepath()),
				pos: Context.currentPos()
			}
			fields.push(fieldRegex);
		}

		var fieldNew = {
			name: "new",
			doc: null,
			meta: [],
			access: [APublic],
			kind: FFun({
				params: null,
				args: [],
				ret: null,
				expr: macro {
					super(null, $v{flags});
					ncap = $v{prog.ncap};
					turnstile = [for (i in 0 ... $v{prog.nturnstile}) false];
				}
			}),
			pos: Context.currentPos()
		};
		fields.push(fieldNew);

		var fieldRun = {
			name: "run",
			doc: null,
			meta: [],
			access: [AOverride, APublic],
			kind: FFun({
				params: null,
				args: [{name: "t", type: macro : hxre.Thread, opt: null, value: null}],
				ret: null,
				expr: new Specializer(prog, flags).assemble()
			}),
			pos: Context.currentPos()
		};
		fields.push(fieldRun);

		return fields;
	}

	var prog : Program;
	var flags : Flags;

	function new(prog : Program, flags : Flags) {
		this.prog = prog;
		this.flags = flags;
	}

	function assemble() {
		var insts = prog.insts;
		var l = new Map();
		for (i in 0 ... insts.length) {
			switch (insts[i]) {
				case AddThread:
					l.set(i + 1, true);
				case Jump(x):
					l.set(x, true);
				case Split(x, y):
					l.set(x, true);
					l.set(y, true);
				default:
			}
		}
		var s = [];
		var ss = new Map();
		var b = 0;
		for (i in 0 ... insts.length) {
			s.push(mInst(i, insts[i]));
			if (l.exists(i + 1)) {
				s.push(macro t.pc = $v{i + 1});
				s.push(macro return run(t));
				ss.set(b, s);
				b = i + 1;
				s = [];
			}
		}
		s.push(macro t.savedend[0] = w.index);
		if (flags.global) {
			s.push(macro lastIndex = w.index);
		}
		s.push(macro matchedThread = haxe.ds.Option.Some(t));
		s.push(macro return true);
		ss.set(b, s);
		var sw = macro switch (t.pc) {
			default: throw "BUG: jump to invalid line";
		};
		switch (sw.expr) {
			case ESwitch(_, cases, _):
				for (k in ss.keys()) {
					cases.push({values: [macro $v{k}], expr: macro $b{ss.get(k)}});
				}
			default:
		}
		return sw;
	}

	function mInst(i : Index<Inst>, inst : Inst) {
		switch (inst) {
			case AddThread:
				return mAddThread(i);
			case Jump(x):
				return mJump(x);
			case Split(x, y):
				return mSplit(x, y);
			case PassTurnstile(i):
				return mPassTurnstile(i);
			case SaveBegin(i):
				return mSaveBegin(i);
			case SaveEnd(i):
				return mSaveEnd(i);
			case OneChar(c):
				return mAssert(mOneChar(c));
			case CharClass(ranges):
				return mAssert(mCharClass(ranges));
			case NegCharClass(ranges):
				return mAssert(mNegCharClass(ranges));
			case Begin:
				return mAssert(mBegin());
			case End:
				return mAssert(mEnd());
		}
	}

	function mAddThread(i) {
		return macro {
			t.pc = $v{i + 1}
			nts.push(t);
			return false;
		};
	}

	function mOneChar(c : Char) {
		return macro !w.terminal() && w.curr == $v{c};
	}

	function mCharClass(ranges : Array<Range<Char>>) {
		function mOr(es : Iterable<Expr>) {
			var i = macro false;
			for (e in es) {
				i = macro ${e} || ${i}
			}
			return i;
		}
		return macro {
			var curr = w.curr;
			!w.terminal() && ${
				mOr([
					for(range in ranges)
						macro $v{range.begin} <= curr && curr < $v{range.end}
				])
			};
		};
	}

	function mNegCharClass(ranges) {
		return macro !${mCharClass(ranges)};
	}

	function mBegin() {
		return macro w.prev == None;
	}

	function mEnd() {
		return macro w.terminal();
	}

	function mAssert(prop) {
		return macro if (!${prop}) {
			return false;
		};
	}

	function mJump(x : Index<Inst>) {
		return macro {
			t.pc = $v{x};
			return run(t);
		};
	}

	function mSplit(x : Index<Inst>, y : Index<Inst>) {
		return macro {
			var t1 = t.copy();
			t1.pc = $v{x};
			if (run(t1)) {
				return true;
			}
			t.pc = $v{y};
			return run(t);
		};
	}

	function mPassTurnstile(i : Index<Bool>) {
		return macro {
			if (turnstile[$v{i}]) {
				return false;
			}
			turnstile[$v{i}] = true;
		};
	}

	function mSaveBegin(i : Index<Index<Char>>) {
		return macro t.savedbegin[$v{i}] = w.index;
	}

	function mSaveEnd(i : Index<Index<Char>>) {
		return macro t.savedend[$v{i}] = w.index;
	}
}
