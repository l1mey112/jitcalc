import readline

enum Op { eof ident num add sub mul div }

struct Lexer {
	line string
mut:
	pos int
	tok_lit string
	tok Op
}

fn (mut l Lexer) next() Op {
	for l.pos < l.line.len {
		mut ch := l.line[l.pos]
		l.pos++
		if ch.is_space() { continue }

		op := match ch {
			`+` { Op.add }
			`-` { Op.sub }
			`*` { Op.mul }
			`/` { Op.div }
			else {
				mut isnum := true

				start := l.pos - 1
				for l.pos < l.line.len {
					ch = l.line[l.pos]
					if (ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`) || (ch >= `0` && ch <= `9`) || ch == `_` {				
						l.pos++
						if isnum && !(ch >= `0` && ch <= `9`) {
							isnum = false
						}
						continue
					}
					break
				}
				l.tok_lit = l.line[start..l.pos]

				if isnum {
					Op.num
				} else {
					Op.ident
				}
			}
		}
		l.tok = op
		return op
	}
	l.tok = .eof
	return .eof
}

fn main() {
	mut r := readline.Readline{}
	
	for {
		mut l := Lexer {
			line: r.read_line(">>> ") or {
				println("goodbye!")
				break
			}
		}
		for l.next() != .eof {
			println(l.tok)
			if l.tok in [.num, .ident] {
				println("\t`${l.tok_lit.bytes()}`")
			}
		}
	}
}