with open('android/app/src/main/cpp/inc/webserver/mongoose.h', 'r') as f:
    lines = f.readlines()

in_macro = False
for i, line in enumerate(lines, 1):
    s = line.rstrip('\n').rstrip('\r')
    if in_macro:
        if s.endswith('\\'):
            continue
        else:
            in_macro = False
    if s.strip().startswith('#define') and s.rstrip().endswith('\\'):
        in_macro = True
        continue
    if s.strip().startswith('#endif') and in_macro:
        print(f'FALSE ENDIF at line {i}')

# Now also do a proper count of #if/#endif
opens = 0
closes = 0
for i, line in enumerate(lines, 1):
    s = line.strip()
    if s.startswith('#endif'):
        closes += 1
    elif s.startswith('#if') or s.startswith('#ifdef') or s.startswith('#ifndef'):
        opens += 1

print(f'Opens: {opens}, Closes: {closes}, Diff: {opens - closes}')
