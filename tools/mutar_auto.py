"""Mutaciones automáticas de operadores sobre Core.lua: cambia un operador por vez, corre luajit tests/run.lua en una
copia y anota las mutaciones que ninguna prueba detecta («vivas»). Sirve para encontrar huecos en las pruebas.

Uso: python tools/mutar_auto.py [--desde N] [--hasta N]   (desde la raíz del repo)
Escribe el avance en <TEMP>/wowc-mutar-auto/latido.txt y el resultado en <TEMP>/wowc-mutar-auto/vivas.txt.
"""
import os, re, shutil, subprocess, sys, time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = os.path.join(os.environ.get('TEMP') or os.environ.get('TMPDIR') or '/tmp', 'wowc-mutar-auto')
COPIA = os.path.join(BASE, 'copia')

# Reemplazos de a uno; cada ocurrencia en una línea es una mutación distinta.
OPERADORES = [
    (r'==', '~='), (r'~=', '=='), (r'<=', '<'), (r'>=', '>'), (r'(?<![<>=~])<(?![=])', '<='),
    (r'(?<![<>=~-])>(?![=])', '>='), (r'\band\b', 'or'), (r'\bor\b', 'and'), (r'\btrue\b', 'false'),
    (r'\bfalse\b', 'true'), (r'(?<![\w.])(\d+)(?![\w.])', None),
]

def mutaciones(lineas):
    for n, linea in enumerate(lineas):
        codigo = linea.split('--', 1)[0]
        if not codigo.strip():
            continue
        # Fuera de los textos entre comillas, para no mutar el contenido de los mensajes.
        mascara = re.sub(r"'[^']*'|\"[^\"]*\"", lambda m: 'X' * len(m.group(0)), codigo)
        for patron, nuevo in OPERADORES:
            for m in re.finditer(patron, mascara):
                a, b = m.span()
                reemplazo = str(int(m.group(1)) + 1) if nuevo is None else nuevo
                yield n, linea[:a] + reemplazo + linea[b:], f'{m.group(0)} -> {reemplazo}'

def correr():
    try:
        r = subprocess.run(['luajit', 'tests/run.lua'], cwd=COPIA, capture_output=True, timeout=60)
        return r.returncode
    except subprocess.TimeoutExpired:
        return 'timeout'

def main():
    desde = int(sys.argv[sys.argv.index('--desde') + 1]) if '--desde' in sys.argv else 0
    hasta = int(sys.argv[sys.argv.index('--hasta') + 1]) if '--hasta' in sys.argv else 10 ** 9
    os.makedirs(BASE, exist_ok=True)
    if os.path.isdir(COPIA):
        shutil.rmtree(COPIA)
    shutil.copytree(REPO, COPIA, ignore=shutil.ignore_patterns('.git', 'media', 'tools', 'docs'))
    ruta = os.path.join(COPIA, 'Core.lua')
    original = open(ruta, encoding='utf-8').read()
    lineas = original.split('\n')
    lista = list(mutaciones(lineas))[desde:hasta]
    vivas, inicio = [], time.time()
    latido = os.path.join(BASE, 'latido.txt')
    for i, (n, mutada, desc) in enumerate(lista):
        copia = list(lineas)
        copia[n] = mutada
        open(ruta, 'w', encoding='utf-8', newline='').write('\n'.join(copia))
        if correr() == 0:
            vivas.append(f'Core.lua:{n + 1} | {desc} | {lineas[n].strip()[:140]}')
        with open(latido, 'w', encoding='utf-8') as f:
            f.write(f'{i + 1}/{len(lista)} vivas={len(vivas)} segundos={int(time.time() - inicio)} {time.strftime("%H:%M:%S")}\n')
    open(ruta, 'w', encoding='utf-8', newline='').write(original)
    with open(os.path.join(BASE, 'vivas.txt'), 'w', encoding='utf-8') as f:
        f.write(f'{len(lista)} mutaciones, {len(vivas)} vivas, {int(time.time() - inicio)} s\n')
        f.write('\n'.join(vivas) + '\n')
    print(f'{len(lista)} mutaciones, {len(vivas)} vivas')

if __name__ == '__main__':
    main()
