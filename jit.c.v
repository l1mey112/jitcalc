$if !freestanding {
	#include <sys/mman.h>
	#include <unistd.h>
}

fn C.sysconf(int) i64
fn C.mmap(base voidptr, len usize, prot int, flags int, fd int, offset i64) voidptr
fn C.munmap(ptr voidptr, size usize) int
fn C.mprotect(addr voidptr, len usize, prot int) int

struct JitProgram {
mut:
	code []u8
}

fn create_program() JitProgram {
	len := C.sysconf(C._SC_PAGESIZE)

	code := unsafe {
		array {
			element_size: 1
			data: C.mmap(0, len, C.PROT_READ | C.PROT_WRITE, C.MAP_ANONYMOUS | C.MAP_PRIVATE, -1, 0)
			cap: int(len)
			flags: .noshrink | .nogrow | .nofree // i added this :)
		}
	}

	return JitProgram {
		code: code
	}
}

type JitProgramTyp = fn () i64

fn (mut p JitProgram) finalise() JitProgramTyp {
	if C.mprotect(p.code.data, p.code.len, C.PROT_READ | C.PROT_EXEC) != 0 {
		panic("mprotect() failed")
	}
	return unsafe { JitProgramTyp(p.code.data) }
}

fn (mut p JitProgram) free() {
	if C.munmap(p.code.data, p.code.len) != 0 {
		panic("munmap() failed")
	}
	unsafe { p.code.data =  nil }
}

fn (mut p JitProgram) ret() {
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
	p.code << 0x48
	p.code << 0xb8
	p.write64(val)
}