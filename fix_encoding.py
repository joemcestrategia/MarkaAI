# -*- coding: utf-8 -*-
"""
Fix UTF-8 Mojibake in Dart files using direct string replacement.
Uses a comprehensive table of known garbled->correct mappings.
Safe: only replaces known bad sequences, never touches valid text.
"""
import os, sys

TARGET_DIR = r'c:\src\MarkaAI\lib'

# Build replacement table programmatically from byte values
# Mojibake happens when UTF-8 bytes are read as latin-1 characters
# For 2-byte UTF-8 sequences (U+0080..U+07FF):
#   byte1 = 0xC0..0xDF, byte2 = 0x80..0xBF
#   When read as latin-1, these appear as two chars: chr(byte1) + chr(byte2)
def build_table():
    table = {}
    # 2-byte sequences: C2xx and C3xx are most common (Latin-1 supplement + Latin Extended-A)
    for b1 in range(0xC2, 0xC6):
        for b2 in range(0x80, 0xC0):
            garbled = chr(b1) + chr(b2)
            try:
                correct = bytes([b1, b2]).decode('utf-8')
                if correct != garbled:  # only add if different
                    table[garbled] = correct
            except Exception:
                pass

    # 3-byte sequences starting with E2 (common: em-dash, ellipsis, smart quotes, etc.)
    for b2 in range(0x80, 0xC0):
        for b3 in range(0x80, 0xC0):
            garbled = chr(0xE2) + chr(b2) + chr(b3)
            try:
                correct = bytes([0xE2, b2, b3]).decode('utf-8')
                if correct != garbled:
                    table[garbled] = correct
            except Exception:
                pass

    # 4-byte sequences starting with F0 (emojis)
    # Most common emoji prefix: F0 9F xx xx
    for b2 in [0x9F]:
        for b3 in range(0x80, 0xC0):
            for b4 in range(0x80, 0xC0):
                garbled = chr(0xF0) + chr(b2) + chr(b3) + chr(b4)
                try:
                    correct = bytes([0xF0, b2, b3, b4]).decode('utf-8')
                    if correct != garbled:
                        table[garbled] = correct
                except Exception:
                    pass

    # Sort by descending length so longer sequences are replaced first
    return sorted(table.items(), key=lambda x: -len(x[0]))

TABLE = build_table()
print(f"Built replacement table with {len(TABLE)} entries")

def fix_mojibake(text):
    for garbled, correct in TABLE:
        if garbled in text:
            text = text.replace(garbled, correct)
    return text

def needs_fix(text):
    # Quick check: look for the most common pt-BR garbled patterns
    checks = ['\xc3\xa3', '\xc3\xa7', '\xc3\xa9', '\xc3\xa1',
              '\xc3\xad', '\xc3\xb5', '\xc3\xba', '\xc3\xa2',
              '\xc3\x83', '\xc3\x87', '\xc3\x89', '\xf0\x9f']
    return any(c in text for c in checks)

fixed_count = 0
error_count = 0
all_files = []

for root, dirs, files in os.walk(TARGET_DIR):
    dirs[:] = [d for d in dirs if d not in ['.dart_tool', 'build', '.pub-cache']]
    for f in files:
        if f.endswith('.dart'):
            all_files.append(os.path.join(root, f))

print(f"Scanning {len(all_files)} Dart files...")

for path in all_files:
    try:
        with open(path, 'r', encoding='utf-8') as fh:
            original = fh.read()

        if not needs_fix(original):
            continue

        fixed = fix_mojibake(original)

        if fixed == original:
            continue

        with open(path, 'w', encoding='utf-8') as fh:
            fh.write(fixed)

        fixed_count += 1
        rel = path.replace(TARGET_DIR, '')
        print(f'FIXED: {rel}')

    except Exception as e:
        error_count += 1
        print(f'ERROR: {path}: {e}', file=sys.stderr)

print(f'\nDone. Fixed {fixed_count} files. Errors: {error_count}')
