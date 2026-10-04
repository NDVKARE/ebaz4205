"""Recover an unsigned, unencrypted Zynq FSBL as a single-segment ARM ELF."""
from pathlib import Path
import struct

root = Path(__file__).resolve().parent.parent
image = (root / "images/BOOT.BIN").read_bytes()
word = lambda offset: struct.unpack_from("<I", image, offset)[0]
assert word(0x20) == 0xAA995566 and word(0x24) == 0x584C4E58
assert word(0x28) == 0, "Encrypted image is unsupported"
assert sum(word(i) for i in range(0x20, 0x4C, 4)) & 0xFFFFFFFF == 0xFFFFFFFF
offset, size, load, entry, total = (word(i) for i in range(0x30, 0x44, 4))
assert 0 < size == total and offset + size <= len(image)
assert load + size <= 0x30000, "Unexpected FSBL OCM address range"
assert load <= entry < load + size
payload = image[offset:offset + size]
ident = b"\x7fELF\x01\x01\x01" + bytes(9)
data_offset = 0x100
names = b"\x00.text\x00.shstrtab\x00"
names_offset = data_offset + size
sections_offset = (names_offset + len(names) + 3) & ~3
header = struct.pack("<16sHHIIIIIHHHHHH", ident, 2, 40, 1, entry,
                     52, sections_offset, 0x05000000, 52, 32, 1, 40, 3, 2)
program = struct.pack("<8I", 1, data_offset, load, load, size, size, 7, 0x100)
elf = bytearray(sections_offset + 120)
elf[:52] = header
elf[52:84] = program
elf[data_offset:data_offset + size] = payload
elf[names_offset:names_offset + len(names)] = names
elf[sections_offset + 40:sections_offset + 80] = struct.pack(
    "<10I", 1, 1, 7, load, data_offset, size, 0, 0, 4, 0)
elf[sections_offset + 80:sections_offset + 120] = struct.pack(
    "<10I", 7, 3, 0, 0, names_offset, len(names), 0, 0, 1, 0)
(root / "fsbl-from-original.elf").write_bytes(elf)
(root / "uboot-test.bif").write_text(
    "the_ROM_image:\n{\n    [bootloader] fsbl-from-original.elf\n    u-boot.elf\n}\n")
print(f"Recovered {size} bytes; load=0x{load:X}; entry=0x{entry:X}")
