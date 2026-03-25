import subprocess

# Usa shell=True para rodar o flutter.bat no Windows
cmd = 'flutter analyze lib/modules/clients/client_home_page.dart'
print("Running:", cmd)
res = subprocess.run(cmd, capture_output=True, text=True, cwd='c:/src/MarkaAI', shell=True)

with open('c:/src/MarkaAI/tmp/analyze_errors_full.txt', 'w', encoding='utf-8') as f:
    f.write("=== STDOUT ===\n")
    f.write(res.stdout)
    f.write("\n=== STDERR ===\n")
    f.write(res.stderr)

print("Output saved to tmp/analyze_errors_full.txt")
print("Stdout First 500 chars:", res.stdout[:500])
