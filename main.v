import readline
import term

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

struct Expr {
	lhs &Expr = unsafe { nil }
	rhs &Expr = unsafe { nil }
	op  Op
	val string
}

fn expr(mut prg JitProgram, mut l Lexer, min_bp int) &Expr {
	l.next()
	mut lhs := match l.tok {
		.num, .ident {
			&Expr{op: l.tok, val: l.tok_lit}
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
		l.next()
		
		op := l.tok
		lhs = &Expr{
			lhs: lhs,
			rhs: expr(mut prg, mut l, r_bp),
			op: op
		}
	}

	return lhs
}

fn march(node &Expr, dep int) {
	if dep != 0 {
		c := dep - 1
		print("${` `.repeat(c * 3)}└─ ")
	}
	match node.op {
		.num, .ident {
			println("`${node.val}`")
		}
		else {
			println(node.op)
		}
	}
	if !isnil(node.lhs) {
		march(node.lhs, dep + 1)
	}
	if !isnil(node.rhs) {
		march(node.rhs, dep + 1)
	}
}

fn gen(node &Expr, mut prg JitProgram) {
	match node.op {
		.num {
			prg.mov64_rax(node.val.i64())
			return
		}
		.ident {
			panic("IDENT UNIMPLEMENTED")
			return
		}
		else {}
	}
	if !isnil(node.rhs) {
		if node.rhs.op == .num && node.lhs.op == .num {
			prg.mov64_rcx(node.rhs.val.i64())
			prg.mov64_rax(node.lhs.val.i64())
		} else {
			gen(node.rhs, mut prg)

			prg.comment('push rax')
			prg.code << 0x50
			
			gen(node.lhs, mut prg)

			prg.comment('pop rcx')
			prg.code << 0x59
		}

		match node.op {
			.add {
				prg.comment('add rax, rcx')
				prg.code << [u8(0x48), 0x01, 0xC8]
			}
			.sub {
				prg.comment('sub rax, rcx')
				prg.code << [u8(0x48), 0x29, 0xC8]
			}
			.mul {
				prg.comment('imul rax, rcx')
				prg.code << [u8(0x48), 0x0F, 0xAF, 0xC1]
			}
			.div {
				prg.comment('cqo')
				prg.code << [u8(0x48), 0x99]
				prg.comment('idiv rcx')
				prg.code << [u8(0x48), 0xF7, 0xF9]
			}
			else {
				panic("unreachable")
			}
		}
	}
}

fn main() {
	mut r := readline.Readline{}
	mut prg := create_program()
	
	for {
		line := r.read_line(">>> ") or {
			println("exit")
			break
		}
		match line.trim_space() {
			'clear' { term.clear() continue }
			else {}
		}
		mut l := Lexer {
			line: line
		}
		l.next()
		if l.peek == .eof {
			continue
		}
		root := expr(mut prg, mut l, 0)
		march(root, 0)
		println(term.cyan(term.h_divider('-')))
		gen(root, mut prg)
		prg.ret()
		prg.hexdump()
		
		fnptr := prg.finalise()
		value := fnptr()

		println("${term.bold(term.green(value.str()))}")
		prg.reset()
	}
}