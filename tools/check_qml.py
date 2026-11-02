import sys


def check_balance(path):
    src = open(path, 'r', encoding='utf-8').read()
    stack = []
    in_string = False
    escape = False
    string_char = ''
    line = 1
    i = 0
    while i < len(src):
        ch = src[i]
        if ch == '\n':
            line += 1
        if in_string:
            if escape:
                escape = False
                i += 1
                continue
            if ch == '\\':
                escape = True
                i += 1
                continue
            if ch == string_char:
                in_string = False
                string_char = ''
            i += 1
            continue
        if ch in '"\'':
            in_string = True
            string_char = ch
            i += 1
            continue
        if ch == '/' and i + 1 < len(src) and src[i + 1] == '/':
            while i < len(src) and src[i] != '\n':
                i += 1
            line += 1
            continue
        if ch in '{([':
            stack.append((ch, line))
        elif ch in '})]':
            expected = {'}': '{', ')': '(', ']': '['}[ch]
            if not stack:
                print(f'UNBALANCED at line {line}: got {ch} but stack empty')
                return False
            top = stack.pop()
            if top[0] != expected:
                print(f'UNBALANCED at line {line}: got {ch} expected {top[0]} (opened line {top[1]})')
                return False
        i += 1
    if stack:
        print('UNBALANCED open:', ', '.join(f'{c}@line{l}' for c, l in stack))
        return False
    print(f'OK: {path} balanced ({len(src)} chars, {line} lines)')
    return True


if __name__ == '__main__':
    ok = True
    for f in sys.argv[1:]:
        ok = check_balance(f) and ok
    sys.exit(0 if ok else 1)
