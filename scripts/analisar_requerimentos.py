import os
import re
from pathlib import Path
from bs4 import BeautifulSoup

RAIZ = Path(__file__).resolve().parent.parent
REQ_DIR = RAIZ / "dados antigos" / "Requerimentos"

html_files = sorted(REQ_DIR.glob("*.html"), key=lambda p: float(re.findall(r"[\d\.]+", p.stem)[0]) if re.findall(r"[\d\.]+", p.stem) else p.stem)

print(f"Total de arquivos HTML encontrados: {len(html_files)}")

for f in html_files:
    try:
        with open(f, "r", encoding="utf-8", errors="ignore") as fp:
            text = fp.read()
            soup = BeautifulSoup(text, "html.parser")
            title = soup.title.string.strip() if soup.title and soup.title.string else "Sem título"
            
            # Procurar padrões como Requisição #XXXX, Protocolo, Lote, Matrícula, BCI, Interessado, Assunto
            text_plain = soup.get_text(" ", strip=True)
            
            # Buscar número da requisição
            req_match = re.findall(r"Requisi[çc][ãa]o\s*#?\s*(\d+)", text_plain, re.IGNORECASE)
            # Buscar protocolo
            prot_match = re.findall(r"Protocolo[:\s]*#?\s*([\d\.\-]+)", text_plain, re.IGNORECASE)
            # Buscar lote
            lote_match = re.findall(r"Lote\s*([A-Za-z0-9\s\-\_]+)", text_plain, re.IGNORECASE)
            # Buscar matrícula
            mat_match = re.findall(r"Matr[íi]cula[:\s]*(\d+)", text_plain, re.IGNORECASE)
            # Buscar BCI
            bci_match = re.findall(r"BCI[:\s]*(\d+)", text_plain, re.IGNORECASE)
            
            print(f"Arquivo: {f.name:10s} | Título: {title[:40]:40s} | Req: {req_match[:2]} | Matr: {mat_match[:2]} | BCI: {bci_match[:2]}")
    except Exception as e:
        print(f"Erro em {f.name}: {e}")
