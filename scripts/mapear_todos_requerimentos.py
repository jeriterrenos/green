import re
import json
from pathlib import Path
from bs4 import BeautifulSoup
import pandas as pd

RAIZ = Path(__file__).resolve().parent.parent
REQ_DIR = RAIZ / "dados antigos" / "Requerimentos"

html_files = sorted(REQ_DIR.glob("*.html"), key=lambda p: float(re.findall(r"[\d\.]+", p.stem)[0]) if re.findall(r"[\d\.]+", p.stem) else p.stem)

registros = []

for f in html_files:
    with open(f, "r", encoding="utf-8", errors="ignore") as fp:
        html = fp.read()
    
    soup = BeautifulSoup(html, "html.parser")
    text = soup.get_text(" ", strip=True)
    
    # 1. Requisição
    req_m = re.search(r"Requisi[çc][ãa]o\s*#?\s*(\d+)", text, re.I)
    req_num = req_m.group(1) if req_m else None
    
    # 2. Atendentes encontrados
    atendentes = []
    if "LUCIANO GLAYSSON" in text.upper():
        atendentes.append("Luciano Glaysson Carvalho")
    if "CARLOS EDUARDO" in text.upper():
        atendentes.append("Carlos Eduardo Vasconcelos Sousa")
    if "VINICIUS NASCIMENTO" in text.upper():
        atendentes.append("Vinicius Nascimento Brandão")
    atendente_str = " / ".join(atendentes) if atendentes else None
    
    # 3. Status / Encerramento
    status = "Em Andamento"
    if "Atendimento finalizado" in text or "ENCERRAMENTO DE REQUISIÇÃO" in text:
        status = "Finalizado / Concluído"
    elif "ESTA EM ANALISE" in text or "em análise" in text.lower():
        status = "Em Análise"
    
    # 4. Matrículas mencionadas no texto e nos nomes dos anexos
    # Procurar padrões MAT_XXXX, MAT - XXXX, Matrícula XXXX
    mats_encontradas = set(re.findall(r"(?:MATR[ÍI]CULA|MAT\.?)\s*[:#\-_ ]*(\d{4})", text, re.I))
    # Também procurar no HTML por nomes de arquivos com MAT
    mats_anexos = set(re.findall(r"MAT[_\-\s]*(\d{4})", html, re.I))
    todas_mats = list(mats_encontradas.union(mats_anexos))
    
    # 5. BCIs mencionados
    bcis_encontrados = set(re.findall(r"(?:BCI|inscri[çc][ãa]o imobili[áa]ria)\s*[:#\-_ ]*(\d{4,5})", text, re.I))
    
    # 6. Procurar nomes de pessoas e referências específicas
    nomes_encontrados = []
    for nome in [
        "Jordão Trindade", "Daniel de Vasconcelos", "Caroline Bitencourt", "Ricardo Manfredini",
        "Fernando Luiz Bacalow", "Rafael Madeira Dantas Paiva", "Otacilio Aureliano",
        "Lara Lima de Menezes", "Osmar Lima de Menezes", "Reno Alencar Araripe",
        "Alice Lima de Menezes", "Andreza Pereira Coutinho", "Pedro Gabriel", "Breno",
        "Gabrielle Gadelha", "Yago Gadelha", "Robson Martins", "Thiago Facanha",
        "Alysson", "Frivaldo", "Josiane", "Thomas Vieira", "Michael Gueiros"
    ]:
        if re.search(rf"\b{re.escape(nome)}\b", text, re.I):
            nomes_encontrados.append(nome)
            
    # 7. Buscar datas
    datas = re.findall(r"\b(\d{2}/\d{2}/\d{4})\b", text)
    data_recente = datas[0] if datas else None
    
    registros.append({
        "arquivo": f.name,
        "requisicao": req_num,
        "matriculas": sorted(list(todas_mats)),
        "bcis": sorted(list(bcis_encontrados)),
        "nomes": nomes_encontrados,
        "atendente": atendente_str,
        "status": status,
        "data": data_recente
    })

df = pd.DataFrame(registros)
for idx, r in df.iterrows():
    print(f"Arq: {r['arquivo']:8s} | Req: #{str(r['requisicao']):5s} | Mats: {str(r['matriculas']):15s} | BCIs: {str(r['bcis']):10s} | Nomes: {str(r['nomes']):30s} | Atendente: {str(r['atendente'])}")
