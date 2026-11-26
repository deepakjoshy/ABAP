import io, re, collections
p='ydj_sxml_stream_demo.abap'
lines=io.open(p,encoding='utf-8').read().split('\n')

def code(l):
    t=l.strip()
    return '' if (t.startswith('"') or t.startswith('*')) else t

cl=[code(l) for l in lines]
body='\n'.join(cl)
U=body.upper()

def cnt(pat):
    return len(re.findall(pat,U,re.M))

pairs=[('CLASS','ENDCLASS'),('METHOD','ENDMETHOD'),('\\bDO\\b','ENDDO'),
       ('\\bIF\\b','ENDIF'),('\\bTRY\\b','ENDTRY'),('LOOP AT','ENDLOOP'),
       ('\\bCASE\\b','ENDCASE')]
print("--- block balance ---")
print("CLASS DEFINITION :", cnt(r'^CLASS\s+\w+\s+DEFINITION'))
print("CLASS IMPLEMENT. :", cnt(r'^CLASS\s+\w+\s+IMPLEMENTATION'))
print("ENDCLASS         :", cnt(r'^ENDCLASS\.'))
print("METHOD (impl)    :", cnt(r'^METHOD\s+\w+\.'))
print("ENDMETHOD        :", cnt(r'^ENDMETHOD\.'))
print("DO / ENDDO       :", cnt(r'^DO\.'), '/', cnt(r'^ENDDO\.'))
print("IF / ENDIF       :", cnt(r'^IF\b|^ELSEIF\b') , '/', cnt(r'^ENDIF\.'), "(IF+ELSEIF vs ENDIF)")
print("  plain IF only  :", cnt(r'^IF\b'))
print("TRY / ENDTRY     :", cnt(r'^TRY\.'), '/', cnt(r'^ENDTRY\.'))
print("LOOP / ENDLOOP   :", cnt(r'^LOOP AT'), '/', cnt(r'^ENDLOOP\.'))
print("CASE / ENDCASE   :", cnt(r'^CASE\b'), '/', cnt(r'^ENDCASE\.'))

decl=set(re.findall(r'CLASS-METHODS\s+(\w+)', body))
for m in re.findall(r'CLASS-METHODS:?\s*$', body, re.M): pass
impl=re.findall(r'(?m)^\s*METHOD\s+(\w+)\.', body)
print("\n--- methods ---")
print("declared :", len(decl), sorted(decl))
print("implemented:", len(impl), sorted(impl))
print("declared not implemented:", sorted(decl-set(impl)))
print("implemented not declared:", sorted(set(impl)-decl))
dup=[k for k,v in collections.Counter(impl).items() if v>1]
print("duplicate implementations:", dup)

print("\n--- safety (executable code only) ---")
for kw in ['SELECT','INSERT','UPDATE','MODIFY','COMMIT WORK','ROLLBACK',
           'CALL FUNCTION','SUBMIT','OPEN DATASET','ENQUEUE','MESSAGE',
           'EXPORT','IMPORT','CALL TRANSFORMATION','AUTHORITY-CHECK']:
    hits=[(i+1,cl[i]) for i in range(len(cl)) if kw in cl[i].upper()]
    print(f"{kw:20} {len(hits)}", hits if hits else '')

print("\n--- inline DATA( ) uniqueness per method ---")
cur=None; seen=collections.defaultdict(list)
for i,t in enumerate(cl):
    m=re.match(r'METHOD\s+(\w+)\.',t)
    if m: cur=m.group(1); continue
    if t.startswith('ENDMETHOD'): cur=None; continue
    if cur:
        for n in re.findall(r'\bDATA\(\s*(\w+)\s*\)', t): seen[(cur,n)].append(i+1)
        for n in re.findall(r'(?:^|\s)DATA\s+(\w+)\s+TYPE', t): seen[(cur,n)].append(i+1)
bad={k:v for k,v in seen.items() if len(v)>1}
print("redeclared names:", bad if bad else "none")

print("\n--- hygiene ---")
print("non-ASCII lines :", [i+1 for i,l in enumerate(lines) if any(ord(c)>127 for c in l)])
print("tabs            :", [i+1 for i,l in enumerate(lines) if '\t' in l])
print("trailing WS     :", [i+1 for i,l in enumerate(lines) if l!=l.rstrip()])
print("max line length :", max(len(l) for l in lines), "at", max(range(len(lines)),key=lambda i:len(lines[i]))+1)
print("lines > 80      :", [i+1 for i,l in enumerate(lines) if len(l)>80])
print("placeholders    :", [i+1 for i,l in enumerate(lines) if re.search(r'TODO|FIXME|XXX|\.\.\.$',l)])
print("\n--- functional calls inside WRITE lists ---")
print([(i+1,cl[i]) for i in range(len(cl)) if cl[i].upper().startswith('WRITE') and re.search(r'\w+\(\s*[^)]*\)',cl[i]) ])
