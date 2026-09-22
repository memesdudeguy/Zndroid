#!/usr/bin/env python3
"""End-to-end proof: compile Counter.tj.java, load the bytecode, run it."""
import sys
from tinyj_compiler import compile_source, pack_tjc
from tinyj_vm_ref import unpack_tjc, Obj, run_method

with open("example_counter.tj.java") as f:
    src = f.read()

compiled = compile_source(src)
blob = pack_tjc(compiled)
klass = unpack_tjc(blob)
by_name = {m.name: m for m in klass.methods}

obj = Obj(klass)
obj.fields[1] = 5   # limit = 5

print("value=0, limit=5")
for i in range(6):
    is_max = run_method(klass, obj, by_name["isMax"], [])
    print(f"  step {i}: value={obj.fields[0]} isMax()={is_max}")
    run_method(klass, obj, by_name["increment"], [])

obj.fields[0] = 10  # value = 10, to test sumUpTo (0+1+...+9 = 45)
total = run_method(klass, obj, by_name["sumUpTo"], [])
print(f"sumUpTo() with value=10 -> {total} (expected 45)")

assert total == 45, "sumUpTo mismatch!"
print("\nOK: compiler + VM semantics check out.")
