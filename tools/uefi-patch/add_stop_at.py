from pathlib import Path
p = Path(r"<RM9_WORKDIR>_extra\codex_work\files-mentioned-by-the-user-01\outputs\bringup-20261012-ufs\prepare_probe.py")
s = p.read_text(encoding="utf-8")

# 1) add the --stop-at argument
old_arg = "parser.add_argument('--stop-after-ufs', action='store_true', help='Re-arm the guard and halt at the Block IO checkpoint before later USB dispatch')"
new_arg = (old_arg +
           "\nparser.add_argument('--stop-at', default='UFSDxe/UFSDxe.inf', "
           "help='[OpenCode] APRIORI anchor line for the StorageCheckpointDxe insertion (default: UFSDxe)')")
assert old_arg in s, "arg pattern"
s = s.replace(old_arg, new_arg, 1)

# 2) use the anchor in the APRIORI insertion (two places: the stop insert)
old_ins = " index=next(i for i,line in enumerate(lines) if 'UFSDxe/UFSDxe.inf' in line)\n lines[index+1:index+1]=['  INF nx769jPkg/Drivers/StorageCheckpointDxe/StorageCheckpointDxe.inf\\n']"
new_ins = " index=next(i for i,line in enumerate(lines) if args.stop_at in line)\n lines[index+1:index+1]=['  INF nx769jPkg/Drivers/StorageCheckpointDxe/StorageCheckpointDxe.inf\\n']"
assert old_ins in s, "insert pattern"
s = s.replace(old_ins, new_ins, 1)

# 3) status printout
old_print = "print('Stop after UFS for RAM capture=',args.stop_after_ufs)"
new_print = "print('Stop for RAM capture=',args.stop_after_ufs,'anchor=',args.stop_at)"
assert old_print in s, "print pattern"
s = s.replace(old_print, new_print, 1)

p.write_text(s, encoding="utf-8")
import ast
ast.parse(s)
print("prepare_probe.py: --stop-at added, syntax OK")
