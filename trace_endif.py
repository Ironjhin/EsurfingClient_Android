lines = open('android/app/src/main/cpp/inc/webserver/mongoose.h', 'r').readlines()

# Track all opens and their matching closes
stack = []  # (line_number, text)
matched_pairs = []

for i, line in enumerate(lines, 1):
    s = line.strip()
    if s.startswith('#endif'):
        if stack:
            open_ln, open_text = stack.pop()
            matched_pairs.append((open_ln, i, open_text))
        else:
            print(f"UNMATCHED #endif at line {i}")
    elif s.startswith('#if') or s.startswith('#ifdef') or s.startswith('#ifndef'):
        stack.append((i, s[:60]))

# Remaining unclosed opens
print("\n--- UNCLOSED #if/#ifdef/#ifndef ---")
for ln, text in stack:
    print(f"  Line {ln}: {text}")

# Check what the guard's #endif matched with
print("\n--- Checking guard #endif (line 3925) ---")
# The last matched pair whose close is at the end
if matched_pairs:
    last_pair = matched_pairs[-1]
    print(f"Last matched pair: open L{last_pair[0]} -> close L{last_pair[1]}")
