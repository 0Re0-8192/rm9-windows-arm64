from pathlib import Path

p = Path(r"<RM9_WORKDIR>\refs\MuChain.c")
t = p.read_text(encoding="utf-8")
t = t.replace("STATIC BOOLEAN mInEbs = FALSE;\n", "", 1)
if "STATIC BOOLEAN mInEbs" not in t:
    t = t.replace("#define MAX_HOOKS       512", "#define MAX_HOOKS       512\nSTATIC BOOLEAN mInEbs = FALSE;", 1)
p.write_text(t, encoding="utf-8")
print("ok", t.count("mInEbs"))
