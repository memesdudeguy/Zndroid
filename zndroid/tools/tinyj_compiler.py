#!/usr/bin/env python3
"""
tinyj_compiler.py — host-side compiler for the TinyJ language (Zndroid).

Compiles a small Java-like single-class subset into TinyJ bytecode (.tjc).
This runs on your PC, never on the calculator — same split as javac/dex vs
an Android phone. Only the *interpreter* (tinyjvm.asm) runs on-device.

Supported grammar (deliberately small):

    class Name {
        int field1;
        int field2;

        void methodName(int a, int b) {
            int local1;
            local1 = a + b;
            if (local1 > 10) {
                field1 = local1;
            } else {
                field1 = 0;
            }
        }

        int methodName2() {
            int i;
            int sum;
            i = 0;
            sum = 0;
            while (i < field1) {
                sum = sum + i;
                i = i + 1;
            }
            return sum;
        }
    }

Not supported (by design — see the design doc): inheritance across multiple
classes, floats, strings-as-objects, exceptions, generics.
"""

import re
import struct
import sys

# --- Opcodes (must match tinyjvm.asm's dispatch table order) ---
OP = {
    "NOP": 0x00, "ICONST": 0x01, "ILOAD": 0x02, "ISTORE": 0x03,
    "IADD": 0x04, "ISUB": 0x05, "IMUL": 0x06, "IDIV": 0x07,
    "ICMP_LT": 0x08, "ICMP_LE": 0x09, "ICMP_GT": 0x0A, "ICMP_GE": 0x0B,
    "ICMP_EQ": 0x0C, "ICMP_NE": 0x0D,
    "IFEQ": 0x0E, "GOTO": 0x0F,
    "GETFIELD": 0x10, "PUTFIELD": 0x11,
    "INVOKEVIRTUAL": 0x12, "RETURN": 0x13, "IRETURN": 0x14,
    "NEW": 0x15, "LOAD_THIS": 0x16, "SYSCALL": 0x17,
    "HALT": 0xFF,
}

# ---------------- Tokenizer ----------------
TOKEN_RE = re.compile(r"""
    \s*(?:
        (?P<num>-?\d+)
      | (?P<id>[A-Za-z_][A-Za-z0-9_]*)
      | (?P<op><=|>=|==|!=|[{}()=+\-*/<>;,])
    )""", re.VERBOSE)

def tokenize(src):
    tokens = []
    pos = 0
    while pos < len(src):
        m = TOKEN_RE.match(src, pos)
        if not m or m.end() == pos:
            if src[pos:pos+1].isspace():
                pos += 1
                continue
            raise SyntaxError(f"bad token near: {src[pos:pos+20]!r}")
        pos = m.end()
        if m.lastgroup == "num":
            tokens.append(("num", int(m.group("num"))))
        elif m.lastgroup == "id":
            tokens.append(("id", m.group("id")))
        elif m.lastgroup == "op":
            tokens.append(("op", m.group("op")))
    tokens.append(("eof", None))
    return tokens

# ---------------- Parser (recursive descent -> simple AST) ----------------
class Parser:
    def __init__(self, tokens):
        self.toks = tokens
        self.i = 0

    def peek(self):
        return self.toks[self.i]

    def next(self):
        t = self.toks[self.i]
        self.i += 1
        return t

    def expect(self, kind, val=None):
        t = self.next()
        if t[0] != kind or (val is not None and t[1] != val):
            raise SyntaxError(f"expected {kind} {val}, got {t}")
        return t

    def parse_class(self):
        self.expect("id", "class")
        name = self.expect("id")[1]
        self.expect("op", "{")
        fields = []
        methods = []
        while self.peek() != ("op", "}"):
            typ = self.expect("id")[1]          # 'int' or 'void'
            ident = self.expect("id")[1]
            if self.peek() == ("op", "("):
                methods.append(self.parse_method(typ, ident))
            else:
                self.expect("op", ";")
                fields.append(ident)
        self.expect("op", "}")
        return {"name": name, "fields": fields, "methods": methods}

    def parse_method(self, ret_type, name):
        self.expect("op", "(")
        params = []
        if self.peek() != ("op", ")"):
            while True:
                self.expect("id")            # param type, ignored (int-only)
                params.append(self.expect("id")[1])
                if self.peek() == ("op", ","):
                    self.next()
                else:
                    break
        self.expect("op", ")")
        self.expect("op", "{")
        locals_ = []
        body = []
        # local declarations must come first (simple, C89-style)
        while self.peek()[0] == "id" and self.peek()[1] == "int" and \
              self.toks[self.i+2] != ("op", "("):
            self.next()  # 'int'
            locals_.append(self.expect("id")[1])
            self.expect("op", ";")
        while self.peek() != ("op", "}"):
            body.append(self.parse_stmt())
        self.expect("op", "}")
        return {"name": name, "ret": ret_type, "params": params,
                "locals": locals_, "body": body}

    def parse_stmt(self):
        if self.peek() == ("id", "if"):
            self.next(); self.expect("op", "(")
            cond = self.parse_expr(); self.expect("op", ")")
            then_b = self.parse_block()
            else_b = []
            if self.peek() == ("id", "else"):
                self.next()
                else_b = self.parse_block()
            return ("if", cond, then_b, else_b)
        if self.peek() == ("id", "while"):
            self.next(); self.expect("op", "(")
            cond = self.parse_expr(); self.expect("op", ")")
            body = self.parse_block()
            return ("while", cond, body)
        if self.peek() == ("id", "return"):
            self.next()
            if self.peek() == ("op", ";"):
                self.next()
                return ("return", None)
            e = self.parse_expr()
            self.expect("op", ";")
            return ("return", e)
        # assignment or bare expr statement
        name = self.expect("id")[1]
        self.expect("op", "=")
        e = self.parse_expr()
        self.expect("op", ";")
        return ("assign", name, e)

    def parse_block(self):
        self.expect("op", "{")
        stmts = []
        while self.peek() != ("op", "}"):
            stmts.append(self.parse_stmt())
        self.expect("op", "}")
        return stmts

    # expr precedence: comparison > additive > multiplicative > primary
    def parse_expr(self):
        left = self.parse_add()
        if self.peek()[0] == "op" and self.peek()[1] in ("<", "<=", ">", ">=", "==", "!="):
            op = self.next()[1]
            right = self.parse_add()
            return ("cmp", op, left, right)
        return left

    def parse_add(self):
        left = self.parse_mul()
        while self.peek()[0] == "op" and self.peek()[1] in ("+", "-"):
            op = self.next()[1]
            right = self.parse_mul()
            left = ("bin", op, left, right)
        return left

    def parse_mul(self):
        left = self.parse_primary()
        while self.peek()[0] == "op" and self.peek()[1] in ("*", "/"):
            op = self.next()[1]
            right = self.parse_primary()
            left = ("bin", op, left, right)
        return left

    def parse_primary(self):
        t = self.next()
        if t[0] == "num":
            return ("num", t[1])
        if t[0] == "id":
            if self.peek() == ("op", "("):
                self.next()
                args = []
                if self.peek() != ("op", ")"):
                    args.append(self.parse_expr())
                    while self.peek() == ("op", ","):
                        self.next()
                        args.append(self.parse_expr())
                self.expect("op", ")")
                return ("call", t[1], args)
            return ("name", t[1])
        if t == ("op", "("):
            e = self.parse_expr()
            self.expect("op", ")")
            return e
        raise SyntaxError(f"unexpected token {t}")

# ---------------- Codegen ----------------
class Codegen:
    def __init__(self, klass):
        self.klass = klass
        self.field_idx = {f: i for i, f in enumerate(klass["fields"])}
        self.method_idx = {m["name"]: i for i, m in enumerate(klass["methods"])}
        self.method_arity = {m["name"]: len(m["params"]) for m in klass["methods"]}

    def compile_method(self, m):
        # slot 0 = this, then params, then locals
        slots = {"this": 0}
        n = 1
        for p in m["params"]:
            slots[p] = n; n += 1
        for l in m["locals"]:
            slots[l] = n; n += 1
        code = []          # list of (mnemonic, operand_or_None) plus label markers
        labels = {}
        self._label_ctr = 0

        def new_label():
            self._label_ctr += 1
            return f"L{self._label_ctr}"

        def emit(op, arg=None):
            code.append([op, arg])

        def gen_expr(e):
            if e[0] == "num":
                emit("ICONST", e[1])
            elif e[0] == "name":
                if e[1] in slots:
                    emit("ILOAD", slots[e[1]])
                elif e[1] in self.field_idx:
                    emit("LOAD_THIS")
                    emit("GETFIELD", self.field_idx[e[1]])
                else:
                    raise NameError(f"unknown identifier {e[1]}")
            elif e[0] == "bin":
                gen_expr(e[2]); gen_expr(e[3])
                emit({"+": "IADD", "-": "ISUB", "*": "IMUL", "/": "IDIV"}[e[1]])
            elif e[0] == "cmp":
                gen_expr(e[2]); gen_expr(e[3])
                emit({"<": "ICMP_LT", "<=": "ICMP_LE", ">": "ICMP_GT",
                      ">=": "ICMP_GE", "==": "ICMP_EQ", "!=": "ICMP_NE"}[e[1]])
            elif e[0] == "call":
                emit("LOAD_THIS")
                for a in e[2]:
                    gen_expr(a)
                emit("INVOKEVIRTUAL", self.method_idx[e[1]])
            else:
                raise NotImplementedError(e)

        def gen_stmt(s):
            if s[0] == "assign":
                gen_expr(s[2])
                if s[1] in slots:
                    emit("ISTORE", slots[s[1]])
                elif s[1] in self.field_idx:
                    emit("LOAD_THIS")
                    # stack currently: [value] -> need [value, this] for PUTFIELD(pop this, pop value)
                    # simplest: reorder by defining PUTFIELD as pop this then pop value
                    emit("PUTFIELD", self.field_idx[s[1]])
                else:
                    raise NameError(s[1])
            elif s[0] == "if":
                gen_expr(s[1])
                else_l = new_label(); end_l = new_label()
                emit("IFEQ", else_l)
                for st in s[2]:
                    gen_stmt(st)
                emit("GOTO", end_l)
                labels[else_l] = len(code)
                emit("NOP", ("label", else_l))
                for st in s[3]:
                    gen_stmt(st)
                labels[end_l] = len(code)
                emit("NOP", ("label", end_l))
            elif s[0] == "while":
                top_l = new_label(); end_l = new_label()
                labels[top_l] = len(code)
                emit("NOP", ("label", top_l))
                gen_expr(s[1])
                emit("IFEQ", end_l)
                for st in s[2]:
                    gen_stmt(st)
                emit("GOTO", top_l)
                labels[end_l] = len(code)
                emit("NOP", ("label", end_l))
            elif s[0] == "return":
                if s[1] is not None:
                    gen_expr(s[1])
                    emit("IRETURN")
                else:
                    emit("RETURN")
            else:
                raise NotImplementedError(s)

        for st in m["body"]:
            gen_stmt(st)
        if m["ret"] == "void":
            emit("RETURN")

        # second pass: resolve label operands on branch ops to relative byte offsets
        # first compute byte offset of each instruction (NOP-label markers are 0-size)
        offsets = []
        pc = 0
        for op, arg in code:
            offsets.append(pc)
            if op == "NOP" and isinstance(arg, tuple) and arg[0] == "label":
                continue  # zero-size marker
            pc += 1 + (1 if arg is not None else 0)
        label_pc = {}
        for idx, (op, arg) in enumerate(code):
            if op == "NOP" and isinstance(arg, tuple) and arg[0] == "label":
                label_pc[arg[1]] = offsets[idx]

        out = bytearray()
        listing = []
        for op, arg in code:
            if op == "NOP" and isinstance(arg, tuple):
                continue
            start = len(out)
            if op in ("IFEQ", "GOTO"):
                target = label_pc[arg]
                rel = target - (start + 2)   # relative to end of this 2-byte instr
                out.append(OP[op])
                out.append(rel & 0xFF)
                listing.append(f"{start:3d}: {op} {arg} (rel {rel})")
            elif arg is not None:
                out.append(OP[op])
                out.append(arg & 0xFF)
                listing.append(f"{start:3d}: {op} {arg}")
            else:
                out.append(OP[op])
                listing.append(f"{start:3d}: {op}")
        return bytes(out), listing, n  # n = total local slot count

    def compile(self):
        methods_out = []
        for m in self.klass["methods"]:
            code, listing, nlocals = self.compile_method(m)
            methods_out.append({
                "name": m["name"], "nargs": len(m["params"]),
                "nlocals": nlocals, "code": code, "listing": listing,
            })
        return {
            "name": self.klass["name"],
            "nfields": len(self.klass["fields"]),
            "fields": self.klass["fields"],
            "methods": methods_out,
        }

def compile_source(src):
    ast = Parser(tokenize(src)).parse_class()
    return Codegen(ast).compile()

def pack_tjc(compiled):
    """Pack into a small binary .tjc blob: this is illustrative, not a byte-for-byte
    final spec — the real on-device loader format should be finalized alongside
    tinyjvm.asm's loader."""
    out = bytearray()
    out += b"TJC1"
    out.append(compiled["nfields"])
    out.append(len(compiled["methods"]))
    for m in compiled["methods"]:
        name_b = m["name"].encode()[:15]
        out.append(len(name_b))
        out += name_b
        out.append(m["nargs"])
        out.append(m["nlocals"])
        out.append(len(m["code"]))
        out += m["code"]
    return bytes(out)

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("usage: tinyj_compiler.py in.tj.java out.tjc")
        sys.exit(1)
    with open(sys.argv[1]) as f:
        src = f.read()
    compiled = compile_source(src)
    blob = pack_tjc(compiled)
    with open(sys.argv[2], "wb") as f:
        f.write(blob)
    print(f"compiled {compiled['name']}: {len(compiled['methods'])} methods, "
          f"{compiled['nfields']} fields, {len(blob)} bytes -> {sys.argv[2]}")
    for m in compiled["methods"]:
        print(f"\n-- {m['name']}({m['nargs']} args, {m['nlocals']} locals) --")
        for line in m["listing"]:
            print("   ", line)
