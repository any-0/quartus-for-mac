# Rewrites every `ffreep %st(0)` (df c0) in an x86_64 ELF file to `fstp %st(0)` (dd d8),
# which also pops the x87 stack. Rosetta in macOS 26 doesn't implement ffreep.
#   python3 ffreep.py file    reads `llvm-objdump -d` of file on stdin, patches file in place
import struct
import sys

path = sys.argv[1]
with open(path, "rb") as f:
    data = bytearray(f.read())

# virtual address -> file offset, from the PT_LOAD program headers
phoff, = struct.unpack_from("<Q", data, 0x20)
phentsize, phnum = struct.unpack_from("<HH", data, 0x36)
loads = []
for i in range(phnum):
    p_type, _, p_offset, p_vaddr, _, p_filesz = struct.unpack_from("<IIQQQQ", data, phoff + i * phentsize)
    if p_type == 1:
        loads.append((p_vaddr, p_offset, p_filesz))


def offset(addr):
    for vaddr, off, size in loads:
        if vaddr <= addr < vaddr + size:
            return addr - vaddr + off
    sys.exit(f"{path}: {addr:#x} isn't in a loaded segment")


count = 0
for line in sys.stdin:
    # compilers only emit ffreep %st(0); other forms are data bytes disassembled as code
    if "ffreep\t%st(0)" not in line:
        continue
    off = offset(int(line.split(":")[0], 16))
    if data[off : off + 2] != b"\xdf\xc0":
        sys.exit(f"{path}: no ffreep at {off:#x}")
    data[off : off + 2] = b"\xdd\xd8"
    count += 1

with open(path, "wb") as f:
    f.write(data)
print(f"{path}: patched {count} ffreep")
