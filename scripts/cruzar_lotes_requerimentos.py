import json
import sqlite3
import pandas as pd
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent

# 1. Carregar lotes da base atual
con = sqlite3.connect(RAIZ / "lotes_base_projeto.gpkg")
con.row_factory = sqlite3.Row
lotes = con.execute("SELECT id, codigo, quadra, matricula, adquirente_nome, bci_inscricao, protocolo_prefeitura, atendente_prefeitura, etapa FROM lotes ORDER BY id").fetchall()
con.close()

# 2. Carregar dados extraídos dos requerimentos
with open(RAIZ / "dados antigos" / "Requerimentos" / "requerimentos_extraidos.json", "r", encoding="utf-8") as f:
    reqs = json.load(f)

# Criar mapa por matrícula
mapa_reqs_por_mat = {}
for r in reqs:
    mats = r["matriculas"]
    for m in mats:
        if m in ["1108", "1416", "1417", "1418"]: # matrículas-mãe
            continue
        if m not in mapa_reqs_por_mat:
            mapa_reqs_por_mat[m] = []
        mapa_reqs_por_mat[m].append(r)

print("Cruzamento Matrícula -> Requerimentos:")
for l in lotes:
    mat = str(l["matricula"]).strip() if l["matricula"] else ""
    reqs_encontrados = mapa_reqs_por_mat.get(mat, [])
    if reqs_encontrados:
        nums_req = [f"#{x['requisicao']}" for x in reqs_encontrados]
        bcis = [b for x in reqs_encontrados for b in x['bcis']]
        atends = list(set([x['atendente'] for x in reqs_encontrados if x['atendente']]))
        print(f"Lote: {l['codigo']:10s} | Mat: {mat:5s} | Req Atual: {str(l['protocolo_prefeitura']):15s} | Req Encontrados: {str(nums_req):20s} | BCIs: {str(bcis):15s} | Nome: {str(l['adquirente_nome'])}")
