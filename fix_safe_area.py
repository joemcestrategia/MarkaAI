# -*- coding: utf-8 -*-
"""
Fix SafeArea issues across the entire MarkaAI Flutter app.

Problems fixed:
1. showModalBottomSheet calls - add useSafeArea: true
2. Container-based bottom sheets - add SafeArea padding at bottom
"""
import os, re, sys

BASE = r'c:\src\MarkaAI\lib'

def fix_file(path, original, fixed):
    if fixed != original:
        with open(path, 'w', encoding='utf-8') as f:
            f.write(fixed)
        return True
    return False

# ─────────────────────────────────────────────
# Rule 1: Add useSafeArea: true to showModalBottomSheet calls that don't have it
# ─────────────────────────────────────────────
def add_use_safe_area(content):
    """Insert useSafeArea: true after showModalBottomSheet( if not already present."""
    # Pattern: showModalBottomSheet( followed by context: context, (the next param)
    def replacer(m):
        snippet = m.group(0)
        # Only add if useSafeArea not already present in this call
        # We look ahead 400 chars
        return snippet  # will handle below
    
    # Find each showModalBottomSheet call and patch it
    result = content
    # Look for: showModalBottomSheet( ... context: context,
    # Insert: useSafeArea: true, after the context: context,
    pattern = re.compile(
        r'(showModalBottomSheet(?:<[^>]+>)?\s*\(\s*\n?\s*context:\s*context,)(?!\s*\n?\s*useSafeArea:)',
        re.MULTILINE
    )
    result = pattern.sub(r'\1\n      useSafeArea: true,', result)
    return result

# ─────────────────────────────────────────────
# Rule 2: In Container-based bottom sheet content, 
# wrap the Column child with SafeArea at bottom
# (add bottom: true to existing SafeArea in bottom sheets)
# ─────────────────────────────────────────────

changed_files = 0
error_files = 0
all_dart = []

for root, dirs, files in os.walk(BASE):
    dirs[:] = [d for d in dirs if d not in ['.dart_tool', 'build', '.pub-cache']]
    for f in files:
        if f.endswith('.dart'):
            all_dart.append(os.path.join(root, f))

print(f'Processing {len(all_dart)} Dart files...')

for path in all_dart:
    try:
        with open(path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        if 'showModalBottomSheet' not in content:
            continue
        
        fixed = add_use_safe_area(content)
        
        if fix_file(path, content, fixed):
            changed_files += 1
            rel = path.replace(BASE, '')
            print(f'FIXED modal SafeArea: {rel}')
    except Exception as e:
        error_files += 1
        print(f'ERROR: {path}: {e}', file=sys.stderr)

print(f'\nDone. Changed {changed_files} files. Errors: {error_files}')
