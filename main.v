import readline
import term

enum Op { eof uneg ident assign obr cbr num add sub mul div mod }

struct Lexer {
	line string
mut:
	pos int
	tok Op
	tok_lit string
	peek Op
	peek_lit string
}

fn (mut l Lexer) get() !(Op, string) {
	for l.pos < l.line.len {
		mut ch := l.line[l.pos]
		l.pos++
		if ch.is_space() { continue }

		mut word := ''
		op := match ch {
			`+` { Op.add    }
			`-` { Op.sub    }
			`*` { Op.mul    }
			`/` { Op.div    }
			`%` { Op.mod    }
			`=` { Op.assign }
			`(` { Op.obr    }
			`)` { Op.cbr    }
			else {
				mut isnum := true

				l.pos--
				start := l.pos
				ch = l.line[l.pos]
				if !((ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`) || (ch >= `0` && ch <= `9`) || ch == `_`) {
					return error("Syntax Error: unknown character `${ch.ascii_str()}`")
				}
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

fn (mut l Lexer) next() !Op {
	l.tok, l.tok_lit = l.peek, l.peek_lit
	l.peek, l.peek_lit = l.get()!
	return l.tok
}

struct Expr {
	lhs &Expr = unsafe { nil }
	rhs &Expr = unsafe { nil }
	op  Op
	val string
}

fn perror(msg string)! {
	return error(msg)
}

fn expr(mut l Lexer, min_bp int) !&Expr {
	l.next()!
	mut lhs := match l.tok {
		.num, .ident {
			&Expr{op: l.tok, val: l.tok_lit}
		}
		.obr {
			o_lhs := expr(mut l, 0)!
			if l.next()! != .cbr {
				perror("Syntax Error: expected closing brace")!
			}
			o_lhs
		}
		else {
			match l.tok {
				.sub {
					r_bp := 7
					&Expr{
						rhs: expr(mut l, r_bp)!,
						op: .uneg
					}
				}
				else {
					perror("Syntax Error: expected identifier or number")!
					0
				}
			}
		}
	}

	for {
		if l.peek in [.eof, .obr, .cbr] {
			break
		}
		l_bp, r_bp := match l.peek {
			.assign {
				if lhs.op != .ident {
					return error("Syntax Error: cannot assign to a value literal")
				}
				2, 1
			}
			.add, .sub       { 3, 4 }
			.mul, .div, .mod { 5, 6 }
			else {
				perror("Syntax Error: expected operator")!
				0, 0
				// return error("Syntax Error: expected operator after value literal")
			}
		}
		if l_bp < min_bp {
			break
		}
		l.next()!
		
		op := l.tok
		lhs = &Expr{
			lhs: lhs,
			rhs: expr(mut l, r_bp)!,
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

struct Box[T] {
	v T
}

fn var_to_rax(mut prg JitProgram, mut symtable map[string]&Box[i64], val string) {
	prg.mov64_rax(voidptr(symtable[val]))
	prg.comments.last().comment = 'mov rax, &${val}'
	prg.comment("mov rax, [rax]")
	prg.code << [u8(0x48), 0x8B, 0x00]
}

fn gen(node &Expr, mut prg JitProgram, mut symtable map[string]&Box[i64])! {
	match node.op {
		.num {
			prg.mov64_rax(node.val.i64())
			return
		}
		.assign {
			gen(node.rhs, mut prg, mut symtable)!
			if node.lhs.val !in symtable {
				symtable[node.lhs.val] = &Box[i64]{ v: 0 }
			}
			prg.mov64_rcx(voidptr(&symtable[node.lhs.val].v))
			prg.comments.last().comment = 'mov rcx, &${node.lhs.val}'

			prg.comment('mov [rcx], rax')
			prg.code << [u8(0x48), 0x89, 0x01]
			return
		}
		.ident {
			if node.val !in symtable {
				return error("Gen: identifier `${node.val}` not defined")
			}

			var_to_rax(mut prg, mut symtable, node.val)
			return
		}
		else {}
	}
	if !isnil(node.rhs) {
		gen(node.rhs, mut prg, mut symtable)!

		if !isnil(node.lhs) {
			if node.lhs.op == .num {
				prg.comment('mov rcx, rax')
				prg.code << [u8(0x48), 0x89, 0xC1]

				prg.mov64_rax(node.lhs.val.i64())
			} else if node.lhs.op == .ident {
				prg.comment('mov rcx, rax')
				prg.code << [u8(0x48), 0x89, 0xC1]

				var_to_rax(mut prg, mut symtable, node.lhs.val)
			} else {
				prg.comment('push rax')
				prg.code << 0x50
				
				gen(node.lhs, mut prg, mut symtable)!

				prg.comment('pop rcx')
				prg.code << 0x59
			}
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
			.div, .mod {
				prg.comment('cqo')
				prg.code << [u8(0x48), 0x99]
				prg.comment('idiv rcx')
				prg.code << [u8(0x48), 0xF7, 0xF9]
				if node.op == .mod {
					prg.comment('mov rax, rdx')
					prg.code << [u8(0x48), 0x89, 0xD0]
				}
			}
			.uneg {
				prg.comment('neg rax')
				prg.code << [u8(0x48), 0xF7, 0xD8]
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
	mut symtable := map[string]&Box[i64]
	mut showast := false

	println("jitcalc  Copyright (C) 2022  l-m.dev")
	println(term.magenta("Type `help` for more information.\n"))

	for {
		line := r.read_line(">>> ") or {
			break
		}
		match line.trim_space() {
			'clear' { term.clear() continue }
			'reset' { symtable.clear() continue }
			'ast'   { showast = !showast continue }
			'exit'  { break }
			'help'  {
				println(term.magenta(" clear   | Clear the screen."))
				println(term.magenta(" reset   | Undeclare all variables."))
				println(term.magenta(" ast     | Toggle printing AST representation."))
				println(term.magenta(" help    | Show this message."))
				println(term.magenta(" exit    | Goodbye!"))
				continue
			}
			else {}
		}
		mut l := Lexer {
			line: line
		}
		l.next()!
		if l.peek == .eof {
			continue
		}
		root := expr(mut l, 0) or {
			println(term.fail_message(err.str()))
			continue
		}
		if l.peek != .eof {
			panic("ee")
		}
		gen(root, mut prg, mut symtable) or {
			println(term.fail_message(err.str()))
			prg.reset()
			continue
		}
		if showast {
			march(root, 0)
			println(term.cyan('------------------------------------------------------------'))
		}
		prg.ret()
		prg.hexdump()

		fnptr := prg.finalise()
		value := fnptr()

		if root.op != .assign {
			println("${term.bold(term.green(value.str()))}")
		}

		prg.reset()
	}
	println("goodbye!")
}