import os
import re
from pathlib import Path
from bs4 import BeautifulSoup

RAIZ = Path(__file__).resolve().parent.parent
REQ_DIR = RAIZ / "dados antigos" / "Requerimentos"

html_files = sorted(REQ_DIR.glob("*.html"), key=lambda p: float(re.findall(r"[\d\.]+", p.stem)[0]) if re.findall(r"[\d\.]+", p.stem) else p.stem)

for f in html_files:
    with open(f, "r", encoding="utf-8", errors="ignore") as fp:
        soup = BeautifulSoup(fp.read(), "html.parser")
    
    text = soup.get_text("\n", strip=True)
    lines = [l.strip() for l in text.split("\n") if l.strip()]
    
    # Encontrar número da requisição
    req = None
    for l in lines:
        m = re.search(r"Requisi[çc][ãa]o\s*#?\s*(\d+)", l, re.IGNORECASE)
        if m:
            req = m.group(1)
            break
            
    print(f"\n==================== ARQUIVO: {f.name} (Req #{req}) ====================")
    # Pegar as linhas chave
    for i, l in enumerate(lines):
        if any(k in l.lower() for k in ["requerente", "atendente", "assunto", "situação", "status", "mensagem", "matrícula", "bci", "dam", "imposto", "lote", "terreno"]):
            # Imprimir linha e próximas 2
            trecho = " // ".join(lines[max(0, i-1):min(len(lines), i+3)])
            print(f"  -> {trecho[:180]}")
