import readline

enum Op { eof ident num add sub mul div }

struct Lexer {
	line string
mut:
	pos int
	tok Op
	tok_lit string
	peek Op
	peek_lit string
}

fn (mut l Lexer) get() (Op, string) {
	for l.pos < l.line.len {
		mut ch := l.line[l.pos]
		l.pos++
		if ch.is_space() { continue }

		mut word := ''
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
				word = l.line[start..l.pos]

				if isnum {
					Op.num
				} else {
					Op.ident
				}
			}
		}
		return op, word
	}
	return Op.eof, ''
}

fn (mut l Lexer) next() Op {
	l.tok, l.tok_lit = l.peek, l.peek_lit
	l.peek, l.peek_lit = l.get()
	return l.tok
}

fn parse(mut o []Op, mut l &Lexer, min_bp int) {
	bbee := match l.next() {
		.ident, .num {
			l.tok_lit
		}
		else {
			panic("expected identifier or number")
		}
	}

	for {
		if l.peek == .eof {
			break
		}

		l_bp, r_bp := match l.peek {
			.add, .sub { 1, 2 }
			.mul, .div { 3, 4 }
			else {
				panic("expected operator")
			}
		}
		if l_bp < min_bp {
			break
		}

		println('${l.peek}')
		l.next()
		parse(mut o, mut l, r_bp)
	}
	println(bbee)
}

fn main1() {
	mut r := readline.Readline{}
	
	for {
		mut l := Lexer {
			line: r.read_line(">>> ") or {
				println("exit")
				break
			}
		}
		l.next()
		mut oparr := []Op{}
		parse(mut oparr, mut &l, 0)
	}
}

fn main() {
	mut prg := create_program()

	prg.write([u8(0xc3)])

	prg.finalise()
	prg.free()
	println(prg)
}