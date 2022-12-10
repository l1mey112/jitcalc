$if !freestanding {
	#include <sys/mman.h>
	#include <unistd.h>
}

fn C.sysconf(int) i64
fn C.mmap(base voidptr, len usize, prot int, flags int, fd int, offset i64) voidptr
fn C.munmap(ptr voidptr, size usize) int
fn C.mprotect(addr voidptr, len usize, prot int) int

struct Program {
	len i64
	cap i64
mut:
	code &u8
}

fn create_program() Program {
	unsafe {
		len := C.sysconf(C._SC_PAGESIZE)
		ptr := C.mmap(nil, len, C.PROT_READ | C.PROT_WRITE, C.MAP_ANONYMOUS | C.MAP_PRIVATE, -1, 0)
		return Program {
			code: &u8(ptr)
			cap: len
		}
	}
}

fn (mut p Program) finalise() {
	if C.mprotect(p.code, p.len, C.PROT_READ | C.PROT_EXEC) != 0 {
		panic("mprotect() failed")
	}
}

fn (mut p Program) write(buf []u8) {
	if p.len + buf.len > p.cap {
		panic("Program.write() failed, exceeded capacity")
	}
	unsafe {
		vmemcpy(p.code + p.len, buf.data, buf.len)
		p.len += buf.len
	}
}

fn (mut p Program) free() {
	if C.munmap(p.code, p.len) != 0 {
		panic("munmap() failed")
	}
	p.code = unsafe { nil }
}