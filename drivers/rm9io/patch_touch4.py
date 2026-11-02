p = '<RM9_WORKDIR>/drv/rm9io/rm9io.c'
s = open(p, encoding='utf-8', newline='').read()
crlf = '\r\n' in s
s = s.replace('\r\n', '\n')
for a, b in (
    ('    Dly.QuadPart = -50000;      // 5 ms\n',
     '    Dly.QuadPart = -20000;      // 2 ms; with the 1 ms system timer resolution requested in TouchStart this really is ~2 ms (15.6 ms otherwise -> 61 Hz)\n'),
    ('    g_TouchStop = 0;\n    g_Touch.Running = 1;\n',
     '    g_TouchStop = 0;\n    g_Touch.Running = 1;\n    if (!g_TimerRes) {\n        ExSetTimerResolution(10000, TRUE);\n        g_TimerRes = TRUE;\n    }\n'),
    ('static VOID TouchStopAndWait(VOID)\n{\n    g_TouchStop = 1;\n',
     'static VOID TouchStopAndWait(VOID)\n{\n    g_TouchStop = 1;\n    if (g_TimerRes) {\n        ExSetTimerResolution(10000, FALSE);\n        g_TimerRes = FALSE;\n    }\n'),
    ('static volatile LONG g_TouchStop;\n', 'static volatile LONG g_TouchStop;\nstatic BOOLEAN g_TimerRes;\n'),
):
    assert a in s, a
    s = s.replace(a, b, 1)
if crlf:
    s = s.replace('\n', '\r\n')
open(p, 'w', encoding='utf-8', newline='').write(s)
print('ok')
