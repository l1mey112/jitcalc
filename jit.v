import term
import strings

$if !freestanding {
	#include <sys/mman.h>
	#include <unistd.h>
}

fn C.sysconf(name int) i64
fn C.mmap(base voidptr, len usize, prot int, flags int, fd int, offset i64) voidptr
fn C.munmap(ptr voidptr, size usize) int
fn C.mprotect(addr voidptr, len usize, prot int) int

struct Comment {
	comment string
	pos int
}

struct JitProgram {
mut:
	code []u8
	comments []Comment
}

fn create_program() JitProgram {
	len := C.sysconf(C._SC_PAGESIZE)
	if len == -1 {
		panic("create_program: sysconf() failed")
	}

	ptr := C.mmap(0, len, C.PROT_READ | C.PROT_WRITE, C.MAP_ANONYMOUS | C.MAP_PRIVATE, -1, 0)
	if ptr == -1 {
		panic("create_program: mmap() failed")
	}

	code := unsafe {
		array {
			element_size: 1
			data: ptr
			cap: int(len)
			flags: .noshrink | .nogrow | .nofree // i added `.nogrow | .nofree` !! :)
		}
	}

	return JitProgram {
		code: code
	}
}

fn (mut p JitProgram) comment(comment string) {
	p.comments << Comment {
		comment: comment
		pos: p.code.len
	}
}

fn (mut p JitProgram) reset() {
	if C.mprotect(p.code.data, p.code.cap, C.PROT_READ | C.PROT_WRITE) != 0 {
		panic("JitProgram.reset: mprotect() failed")
	}
	p.code.clear()
	p.comments.clear()
}

type JitProgramTyp = fn () i64

fn (mut p JitProgram) finalise() JitProgramTyp {
	if C.mprotect(p.code.data, p.code.cap, C.PROT_READ | C.PROT_EXEC) != 0 {
		panic("JitProgram.finalise: mprotect() failed")
	}
	return unsafe { JitProgramTyp(p.code.data) }
}

fn (mut p JitProgram) free() {
	if C.munmap(p.code.data, p.code.cap) != 0 {
		panic("JitProgram.free: munmap() failed")
	}
}

fn (mut p JitProgram) hexdump() {
	maxsize := 40
	mut sb := strings.new_builder(80)

	mut c := 1
	for idx, v in p.code {
		sb.write_string(v.hex())
		sb.write_u8(` `)
		if c < p.comments.len && p.comments[c].pos - 1 == idx {
			if sb.len < maxsize {
				sb.write_string(` `.repeat(maxsize - sb.len))
			}
			print(term.dim(sb.str()))
			println(term.bold(p.comments[c - 1].comment))
			c++
		}
	}
	if c - 1 < p.comments.len {
		if sb.len < maxsize {
			sb.write_string(` `.repeat(maxsize - sb.len))
		}
		print(term.dim(sb.str()))
		println(term.bold(p.comments[c - 1].comment))
	}
}

fn (mut p JitProgram) ret() {
	p.comment('ret')
	p.code << 0xc3
}

fn (mut p JitProgram) write64(n i64) {
	p.code << u8(n)
	p.code << u8(n >> 8)
	p.code << u8(n >> 16)
	p.code << u8(n >> 24)
	p.code << u8(n >> 32)
	p.code << u8(n >> 40)
	p.code << u8(n >> 48)
	p.code << u8(n >> 56)
}

fn (mut p JitProgram) mov64_rax(val i64) {
	p.comment('mov rax, ${val}')
	p.code << 0x48
	p.code << 0xb8
	p.write64(val)
}

fn (mut p JitProgram) mov64_rcx(val i64) {
	p.comment('mov rcx, ${val}')
	p.code << 0x48
	p.code << 0xc7
	p.code << 0xc1
	p.write64(val)
}

fn (mut p JitProgram) push_rax() {
	p.comment('push rax')
	p.code << 0x50
}

fn (mut p JitProgram) pop_rcx() {
	p.comment('pop rcx')
	p.code << 0x59
}

fn (mut p JitProgram) add() {
	p.comment('pop rcx')
	p.code << 0x59
}