import os
import re
import json
from pathlib import Path
from bs4 import BeautifulSoup
import pandas as pd

RAIZ = Path(__file__).resolve().parent.parent
REQ_DIR = RAIZ / "dados antigos" / "Requerimentos"

html_files = sorted(REQ_DIR.glob("*.html"), key=lambda p: float(re.findall(r"[\d\.]+", p.stem)[0]) if re.findall(r"[\d\.]+", p.stem) else p.stem)

resultados = []

for f in html_files:
    with open(f, "r", encoding="utf-8", errors="ignore") as fp:
        html = fp.read()
    
    soup = BeautifulSoup(html, "html.parser")
    text = soup.get_text(" ", strip=True)
    
    # 1. Número da requisição
    req_match = re.search(r"Requisi[çc][ãa]o\s*#?\s*(\d+)", text, re.IGNORECASE)
    req_num = req_match.group(1) if req_match else None
    
    # 2. Requerente
    reqte_match = re.search(r"Requerente[:\s]+([^\|\n\r\t]+?)(?:CPF|CNPJ|Telefone|E-mail|Endereço|Assunto|Atendente|Data|$)", text, re.IGNORECASE)
    requerente = reqte_match.group(1).strip() if reqte_match else None
    
    # 3. Atendente
    atend_match = re.search(r"Atendente[:\s]+([^\|\n\r\t]+?)(?:Data|Situa[çc][ãa]o|Status|Assunto|$)", text, re.IGNORECASE)
    atendente = atend_match.group(1).strip() if atend_match else None
    
    # 4. Situação / Status
    status_match = re.search(r"Situa[çc][ãa]o[:\s]+([^\|\n\r\t]+?)(?:Data|Atendente|Assunto|Prioridade|$)", text, re.IGNORECASE)
    situacao = status_match.group(1).strip() if status_match else None
    
    # 5. Data
    data_match = re.search(r"Data[:\s]+(\d{2}/\d{2}/\d{4}(?:\s+\d{2}:\d{2}(?::\d{2})?)?)", text, re.IGNORECASE)
    data_req = data_match.group(1).strip() if data_match else None

    # 6. Assunto
    assunto_match = re.search(r"Assunto[:\s]+([^\|\n\r\t]+?)(?:Descri[çc][ãa]o|Mensagem|Anexos|$)", text, re.IGNORECASE)
    assunto = assunto_match.group(1).strip() if assunto_match else None

    # 7. Buscar todas as ocorrências de Matrícula
    matriculas = list(set(re.findall(r"(?:matr[íi]cula|matr\.?)\s*[:#\s]*(\d+)", text, re.IGNORECASE)))
    # Excluir matrículas genéricas se houver
    matriculas = [m for m in matriculas if len(m) >= 3 and len(m) <= 5]

    # 8. Buscar BCI
    bcis = list(set(re.findall(r"(?:BCI|inscri[çc][ãa]o\s*imobili[áa]ria)\s*[:#\s]*(\d+)", text, re.IGNORECASE)))

    # 9. Buscar Lotes / Quadras
    lotes = list(set(re.findall(r"\b([A-Fa-f]\s*\d+(?:\s*[\-\/]\s*[A-Fa-f]?\s*\d+)*)\b", text)))
    # Filtrar padrões válidos como A5, B11-B12, C9-C10, etc.
    lotes_validos = []
    for l in lotes:
        l_clean = re.sub(r"\s+", "", l).upper()
        if re.match(r"^[A-F]\d+.*", l_clean) and len(l_clean) <= 12:
            lotes_validos.append(l_clean)

    # 10. Procurar termos no corpo do texto / mensagens / despachos
    # Vamos pegar trechos onde aparecem palavras-chave
    mensagens = []
    # Procurar divs de mensagens / timeline / despachos
    msgs_div = soup.find_all(class_=re.compile(r"message|comment|timeline|despacho|historico|card-body|ticket", re.IGNORECASE))
    for m in msgs_div:
        txt = m.get_text(" ", strip=True)
        if len(txt) > 20 and ("deferid" in txt.lower() or "cadastr" in txt.lower() or "dam" in txt.lower() or "itbi" in txt.lower() or "bci" in txt.lower()):
            mensagens.append(txt[:150])

    res = {
        "arquivo": f.name,
        "requisicao": req_num,
        "data": data_req,
        "requerente": requerente,
        "atendente": atendente,
        "situacao": situacao,
        "assunto": assunto,
        "matriculas": matriculas,
        "bcis": bcis,
        "lotes": lotes_validos,
        "trecho_relevante": " | ".join(mensagens[:2]) if mensagens else text[:200]
    }
    resultados.append(res)

df = pd.DataFrame(resultados)
print(df[["arquivo", "requisicao", "matriculas", "bcis", "lotes", "situacao"]].to_string())

with open(RAIZ / "dados antigos" / "Requerimentos" / "requerimentos_extraidos.json", "w", encoding="utf-8") as fp:
    json.dump(resultados, fp, ensure_ascii=False, indent=2)

print("\nArquivo salvo: requerimentos_extraidos.json")
