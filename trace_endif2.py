lines = open('android/app/src/main/cpp/inc/webserver/mongoose.h', 'r').readlines()
stack = []
seen_open = []

for i, line in enumerate(lines, 1):
    s = line.strip()
    if s.startswith('#endif'):
        if stack:
            open_ln, _ = stack.pop()
            if open_ln == 544:
                print(f"Line {i}: closing #endif -> pops L544 (WIN32)")
            if open_ln == 20:
                print(f"Line {i}: closing #endif -> pops L20 (GUARD!)")
    elif s.startswith('#if') or s.startswith('#ifdef') or s.startswith('#ifndef'):
        stack.append((i, s[:60]))
        if i >= 540 and i <= 725:
            print(f"Line {i}: OPEN, depth={len(stack)}, stack_tops={[x[0] for x in stack[-3:]]}, text={s[:60]}")
