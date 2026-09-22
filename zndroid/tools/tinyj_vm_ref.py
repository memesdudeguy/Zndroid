#!/usr/bin/env python3
"""
tinyj_vm_ref.py — reference TinyJ VM, written in Python.

This is NOT what runs on the calculator. It exists to validate the bytecode
format and semantics *before* committing to a hand-written Z80 interpreter —
much cheaper to find a semantics bug here than after hand-assembling
tinyjvm.asm. tinyjvm.asm should be a straightforward instruction-for-instruction
port of the dispatch loop below.
"""

import struct
import sys

OP_NAMES = {
    0x00: "NOP", 0x01: "ICONST", 0x02: "ILOAD", 0x03: "ISTORE",
    0x04: "IADD", 0x05: "ISUB", 0x06: "IMUL", 0x07: "IDIV",
    0x08: "ICMP_LT", 0x09: "ICMP_LE", 0x0A: "ICMP_GT", 0x0B: "ICMP_GE",
    0x0C: "ICMP_EQ", 0x0D: "ICMP_NE",
    0x0E: "IFEQ", 0x0F: "GOTO",
    0x10: "GETFIELD", 0x11: "PUTFIELD",
    0x12: "INVOKEVIRTUAL", 0x13: "RETURN", 0x14: "IRETURN",
    0x15: "NEW", 0x16: "LOAD_THIS", 0x17: "SYSCALL",
    0xFF: "HALT",
}

def s8(b):
    return b - 256 if b >= 128 else b

class Method:
    def __init__(self, name, nargs, nlocals, code):
        self.name, self.nargs, self.nlocals, self.code = name, nargs, nlocals, code

class TJClass:
    def __init__(self, name, nfields, methods):
        self.name, self.nfields, self.methods = name, nfields, methods

def unpack_tjc(blob):
    assert blob[:4] == b"TJC1", "bad magic"
    pos = 4
    nfields = blob[pos]; pos += 1
    nmethods = blob[pos]; pos += 1
    methods = []
    for _ in range(nmethods):
        nlen = blob[pos]; pos += 1
        name = blob[pos:pos+nlen].decode(); pos += nlen
        nargs = blob[pos]; pos += 1
        nlocals = blob[pos]; pos += 1
        clen = blob[pos]; pos += 1
        code = blob[pos:pos+clen]; pos += clen
        methods.append(Method(name, nargs, nlocals, code))
    return TJClass("<class>", nfields, methods)

class Obj:
    def __init__(self, klass):
        self.klass = klass
        self.fields = [0] * klass.nfields

def syscall(id_, stack):
    """Native bridge stub — on the calculator this jumps into launcher/graphics
    code (draw icon, read key, etc). Here we just simulate a couple for testing."""
    if id_ == 1:  # SYS_PRINT_TOP: pop and print top of stack
        print("  [syscall print]", stack[-1])

def run_method(klass, obj, method, args, arena_note=None):
    locals_ = [0] * max(method.nlocals, 1 + method.nargs)
    locals_[0] = obj
    for i, a in enumerate(args):
        locals_[1 + i] = a
    stack = []
    pc = 0
    code = method.code
    steps = 0
    while True:
        steps += 1
        if steps > 1_000_000:
            raise RuntimeError("possible infinite loop (step limit hit)")
        op = code[pc]
        name = OP_NAMES[op]
        arg = None
        size = 1
        if name in ("ICONST", "ILOAD", "ISTORE", "IFEQ", "GOTO",
                     "GETFIELD", "PUTFIELD", "INVOKEVIRTUAL", "NEW", "SYSCALL"):
            arg = code[pc + 1]
            size = 2

        if name == "NOP":
            pass
        elif name == "ICONST":
            stack.append(s8(arg))
        elif name == "ILOAD":
            stack.append(locals_[arg])
        elif name == "ISTORE":
            locals_[arg] = stack.pop()
        elif name == "IADD":
            b = stack.pop(); a = stack.pop(); stack.append(a + b)
        elif name == "ISUB":
            b = stack.pop(); a = stack.pop(); stack.append(a - b)
        elif name == "IMUL":
            b = stack.pop(); a = stack.pop(); stack.append(a * b)
        elif name == "IDIV":
            b = stack.pop(); a = stack.pop(); stack.append(a // b if b else 0)
        elif name in ("ICMP_LT", "ICMP_LE", "ICMP_GT", "ICMP_GE", "ICMP_EQ", "ICMP_NE"):
            b = stack.pop(); a = stack.pop()
            res = {"ICMP_LT": a < b, "ICMP_LE": a <= b, "ICMP_GT": a > b,
                   "ICMP_GE": a >= b, "ICMP_EQ": a == b, "ICMP_NE": a != b}[name]
            stack.append(1 if res else 0)
        elif name == "IFEQ":
            v = stack.pop()
            if v == 0:
                pc = pc + size + s8(arg)
                continue
        elif name == "GOTO":
            pc = pc + size + s8(arg)
            continue
        elif name == "LOAD_THIS":
            stack.append(locals_[0])
        elif name == "GETFIELD":
            o = stack.pop()
            stack.append(o.fields[arg])
        elif name == "PUTFIELD":
            o = stack.pop()
            v = stack.pop()
            o.fields[arg] = v
        elif name == "INVOKEVIRTUAL":
            target = klass.methods[arg]
            callargs = [stack.pop() for _ in range(target.nargs)][::-1]
            callee_obj = stack.pop()
            ret = run_method(klass, callee_obj, target, callargs)
            if ret is not None:
                stack.append(ret)
        elif name == "RETURN":
            return None
        elif name == "IRETURN":
            return stack.pop()
        elif name == "SYSCALL":
            syscall(arg, stack)
        elif name == "HALT":
            return None
        else:
            raise NotImplementedError(name)
        pc += size

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: tinyj_vm_ref.py file.tjc")
        sys.exit(1)
    with open(sys.argv[1], "rb") as f:
        klass = unpack_tjc(f.read())
    obj = Obj(klass)
    by_name = {m.name: m for m in klass.methods}
    print(f"loaded class with methods: {list(by_name)}, {klass.nfields} fields")
