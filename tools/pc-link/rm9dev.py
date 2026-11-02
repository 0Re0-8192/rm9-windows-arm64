#!/usr/bin/env python
# High-level driver-work helpers on top of rm9link (all over the USB link; the phone's Windows must be up with the agent).
#   python rm9dev.py putdir <local dir> <remote dir>
#   python rm9dev.py getdir <remote dir> <local dir>
#   python rm9dev.py drv <local driver dir> [name.inf]   copy the package, `pnputil /add-driver /install`, report problem devices + new setupapi lines
#   python rm9dev.py collect [minutes]                    diagnostic bundle -> <RM9_WORKDIR>\winboot\collect_<time>\  (problem devices, events, setupapi, dumps)
#   python rm9dev.py sh <powershell command...>           run PowerShell on the phone (SYSTEM) and print the output
import base64, os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rm9link

HERE = os.path.dirname(os.path.abspath(__file__))
BS = chr(92)


def ps(L, script, timeout=120):
    enc = base64.b64encode(("$ProgressPreference='SilentlyContinue'; " + script).encode('utf-16le')).decode()
    code, out = L.exec('powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand ' + enc, timeout)
    return code, out.decode('utf-8', 'replace')


def putdir(L, local, remote):
    n = 0
    for root, _, files in os.walk(local):
        for f in files:
            lp = os.path.join(root, f)
            rp = remote.rstrip(BS) + BS + os.path.relpath(lp, local).replace('/', BS)
            L.put(lp, rp)
            n += 1
    return n


def getdir(L, remote, local):
    code, out = ps(L, "Get-ChildItem -Recurse -File '%s' | ForEach-Object { $_.FullName }" % remote)
    n = 0
    for line in out.splitlines():
        line = line.strip()
        if not line.lower().startswith(remote.lower()):
            continue
        rel = line[len(remote):].lstrip(BS)
        lp = os.path.join(local, rel)
        os.makedirs(os.path.dirname(lp), exist_ok=True)
        L.get(line, lp)
        n += 1
    return n


def drv(L, local, inf=None):
    name = os.path.basename(os.path.abspath(local))
    remote = 'C:' + BS + 'rm9' + BS + 'drvtest' + BS + name
    print('copied %d files to %s' % (putdir(L, local, remote), remote))
    if inf is None:
        infs = [f for f in os.listdir(local) if f.lower().endswith('.inf')]
        if not infs:
            raise SystemExit('no .inf in %s' % local)
        inf = infs[0]
    log = 'C:' + BS + 'Windows' + BS + 'INF' + BS + 'setupapi.dev.log'
    script = ("$mark = (Get-Content %s).Count; "
              "pnputil /add-driver '%s' /install | Out-String; "
              "'--- problem devices:'; pnputil /enum-devices /problem | Out-String; "
              "'--- setupapi (new lines, last 60):'; Get-Content %s | Select-Object -Skip $mark | Select-Object -Last 60") % (log, remote + BS + inf, log)
    code, out = ps(L, script)
    print(out)
    return code


def collect(L, minutes=30):
    L.put(os.path.join(HERE, 'winpe', 'collect.ps1'), 'C:' + BS + 'rm9' + BS + 'link' + BS + 'collect.ps1')
    code, out = L.exec('powershell -NoProfile -ExecutionPolicy Bypass -File C:' + BS + 'rm9' + BS + 'link' + BS + 'collect.ps1 -Minutes %d' % minutes, 180)
    dest = os.path.join(HERE, '..', 'winboot', 'collect_' + time.strftime('%Y%m%d_%H%M%S'))
    n = getdir(L, 'C:' + BS + 'rm9' + BS + 'collect', dest)
    print(out.decode('utf-8', 'replace'))
    print('%d files -> %s' % (n, os.path.abspath(dest)))
    return dest


def main(argv):
    try:
        sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    except Exception:
        pass
    if not argv:
        print(__doc__)
        return 2
    cmd, rest = argv[0], argv[1:]
    with rm9link.Link(wait=60) as L:
        if cmd == 'putdir':
            print('%d files' % putdir(L, rest[0], rest[1]))
        elif cmd == 'getdir':
            print('%d files' % getdir(L, rest[0], rest[1]))
        elif cmd == 'drv':
            return drv(L, rest[0], rest[1] if len(rest) > 1 else None)
        elif cmd == 'collect':
            collect(L, int(rest[0]) if rest else 30)
        elif cmd == 'sh':
            code, out = ps(L, ' '.join(rest))
            print(out)
            return code
        else:
            print(__doc__)
            return 2
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
