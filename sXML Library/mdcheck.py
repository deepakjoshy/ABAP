import io, re, os, urllib.parse, collections
s=io.open('README.md',encoding='utf-8').read()
lines=s.split('\n')
print("lines:", len(lines))
print("code fences:", s.count('```'), "(even => balanced)")
h=[l for l in lines if l.startswith('#')]
dup=[k for k,v in collections.Counter(h).items() if v>1]
print("headings:", len(h), "duplicates:", dup)
print("non-ASCII:", sorted({c for c in s if ord(c)>127}))
print("tabs:", s.count('\t'), " trailing WS lines:", [i+1 for i,l in enumerate(lines) if l!=l.rstrip()])
print("\n-- relative links --")
bad=[]
for m in re.finditer(r'\]\((\.\./[^)#]+)', s):
    t=urllib.parse.unquote(m.group(1))
    pth=os.path.normpath(os.path.join(os.getcwd(), t))
    ok=os.path.exists(pth)
    if not ok: bad.append(t)
    print(("OK   " if ok else "BAD  "), t)
print("\n-- same-folder links --")
for m in re.finditer(r'\]\((?!http|\.\./|#)([^)#]+)\)', s):
    t=urllib.parse.unquote(m.group(1))
    print(("OK   " if os.path.exists(t) else "BAD  "), t)
print("\nBAD TOTAL:", len(bad))
print("\n-- table row widths --")
for i,l in enumerate(lines):
    if l.startswith('|'):
        n=l.count('|')
        print(i+1, n) if False else None
rows=collections.defaultdict(list)
cur=None
for i,l in enumerate(lines):
    if l.startswith('|'):
        if cur is None: cur=i
        rows[cur].append(l.count('|'))
    else: cur=None
for k,v in rows.items():
    print(f"table at line {k+1}: pipe counts {sorted(set(v))} {'OK' if len(set(v))==1 else 'MISMATCH'}")
