import sys

files = [
    r'c:\src\MarkaAI\lib\modules\public\public_shop_page.dart',
    r'c:\src\MarkaAI\lib\core\utils\responsive_helper.dart',
]
for path in files:
    with open(path, 'rb') as f:
        raw = f.read(200)
    print(f'File: {path}')
    print(f'First 30 bytes hex: {raw[:30].hex()}')
    line1 = raw.split(b'\n')[0]
    print(f'Line 1 bytes: {line1[:80].hex()}')
    print(f'Line 1 text: {line1[:80]}')
    # Find non-ascii bytes in whole file
    with open(path, 'rb') as f:
        full = f.read()
    non_ascii = [(i, full[i]) for i in range(min(len(full), 5000)) if full[i] > 127]
    print(f'Non-ASCII bytes in first 5000: {len(non_ascii)}')
    for pos, b in non_ascii[:5]:
        ctx = full[max(0,pos-10):pos+20]
        print(f'  pos={pos} byte=0x{b:02x} context={ctx}')
    print()
