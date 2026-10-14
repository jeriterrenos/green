from pathlib import Path
from bs4 import BeautifulSoup

for fname in ['1.html', '11.html', '12.html', '24.html', '26.html']:
    p = Path('dados antigos/Requerimentos') / fname
    with open(p, 'r', encoding='utf-8', errors='ignore') as fp:
        soup = BeautifulSoup(fp.read(), 'html.parser')
    print(f"==================================================")
    print(f"ARQUIVO: {fname}")
    print(f"==================================================")
    for div in soup.find_all(['div', 'p', 'tr']):
        t = div.get_text(' ', strip=True)
        if any(w in t.lower() for w in ['inscrição', 'requisição', 'matrícula', 'bci', 'lote', 'dam', 'itbi', 'córrego', 'solicit']):
            if len(t) < 400 and len(t) > 20:
                print(" -", t)
