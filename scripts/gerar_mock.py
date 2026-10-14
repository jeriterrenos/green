"""Gera o GeoJSON de lotes usado pelo site a partir do GeoPackage do projeto.

Uso:
    python scripts/gerar_mock.py [caminho_gpkg] [--mock]

Sem --mock: exporta os DADOS REAIS para public/dados-locais/lotes.geojson
            (pasta no .gitignore — usada só ao rodar localmente, nunca publicada).
Com --mock: gera nomes e telefones FICTÍCIOS em public/mock/lotes.geojson
            (versão que pode ir para o repositório público).
"""
import json
import random
import sqlite3
import struct
import sys
from datetime import date, timedelta
from pathlib import Path

from shapely import wkb
from shapely.geometry import mapping

RAIZ = Path(__file__).resolve().parent.parent
SAIDA_REAL = RAIZ / "public" / "dados-locais" / "lotes.geojson"
SAIDA_MOCK = RAIZ / "public" / "mock" / "lotes.geojson"
GPKG_PADRAO = RAIZ / "dados antigos" / "Projeto QGIS" / "LATITUDE - greenterrenos" / "lotes_green_terrenos_atualizado.gpkg"

NOMES_MOCK = [
    "Ana Ribeiro", "Bruno Carvalho", "Carla Mendes", "Diego Fontes", "Elisa Prado",
    "Fábio Nogueira", "Gabriela Torres", "Heitor Lacerda", "Isabela Moraes", "João Vidal",
    "Karina Bastos", "Lucas Aragão", "Mariana Paiva", "Nelson Furtado", "Olívia Sampaio",
    "Paulo Damasceno", "Quésia Leal", "Rafael Brandão", "Sabrina Rocha", "Tiago Quental",
    "Úrsula Freitas", "Vinícius Holanda", "Wesley Pinheiro", "Yasmin Cordeiro", "Zeca Moreira",
    "Aline Barreto", "Caio Magalhães", "Débora Siqueira", "Enzo Campelo", "Flávia Teles",
    "Gustavo Benevides", "Helena Arruda", "Igor Matos", "Júlia Saraiva", "Leandro Viana",
    "Mirela Cavalcante", "Otávio Peixoto", "Priscila Montenegro", "Renato Távora", "Sílvia Gurgel",
]


def ler_gpkg_geom(blob: bytes):
    """Converte o blob de geometria do GeoPackage (cabeçalho GP + WKB) em shapely."""
    flags = blob[3]
    envelope = {0: 0, 1: 32, 2: 48, 3: 48, 4: 64}[(flags >> 1) & 0x07]
    return wkb.loads(blob[8 + envelope:])


def main():
    usar_mock = "--mock" in sys.argv
    args = [a for a in sys.argv[1:] if a != "--mock"]

    if args:
        caminho = Path(args[0])
    else:
        caminho = GPKG_PADRAO

    if not caminho.exists():
        # Tenta no diretório de dados antigos
        caminho_alt = RAIZ / "lotes_base_projeto.gpkg"
        if caminho_alt.exists():
            caminho = caminho_alt
        else:
            sys.exit(f"Arquivo não encontrado: {caminho}")

    con = sqlite3.connect(f"file:{caminho}?mode=ro", uri=True)
    con.row_factory = sqlite3.Row

    # Detecta a camada principal
    tabelas = [r[0] for r in con.execute("select table_name from gpkg_contents where data_type='features'").fetchall()]
    camada = "lotes" if "lotes" in tabelas else (tabelas[0] if tabelas else "reprojetadoa")

    cur = con.execute(f'select * from "{camada}" order by id')
    linhas = cur.fetchall()

    rnd = random.Random(2026)
    nomes_rnd = NOMES_MOCK[:]
    rnd.shuffle(nomes_rnd)

    features = []
    for i, row in enumerate(linhas, start=1):
        g = ler_gpkg_geom(row["geom"])
        d = dict(row)

        lote_cod = (d.get("codigo") or d.get("lote") or f"S/N {i}").strip()
        matricula = str(d.get("matricula") or "")
        area = round(float(d.get("area_m2") or d.get("area") or 0), 2)
        perim = round(float(d.get("perimetro_m") or d.get("perimetro") or 0), 2)
        etapa = int(d.get("etapa") or 0)

        # Campos de titularidade e contato
        real_nome = d.get("adquirente_nome") or d.get("COMPRADOR")
        real_tel = d.get("adquirente_telefone") or d.get("telefone")
        real_email = d.get("adquirente_email") or d.get("email")
        real_end = d.get("adquirente_endereco") or d.get("endereco")
        real_bci = str(d.get("bci_inscricao") or d.get("BCI") or "").strip() or None
        real_obs = d.get("observacoes") or d.get("obs")
        real_compra = d.get("data_compra") or d.get("DATA")
        real_itbi = d.get("data_itbi") or d.get("DATA_IBTI")
        real_contato = d.get("data_ultimo_contato") or d.get("DATA_ULTIMO CONTATO")

        if usar_mock:
            vendido = (real_nome is not None and real_nome.strip().upper() != "DISPONIVEL")
            nome = nomes_rnd[i % len(nomes_rnd)] if vendido else None
            tel = f"(88) 90000-{i:04d}" if vendido else None
            email = None
            endereco = None
            bci = f"BCI-{10000 + i}" if etapa >= 1 else None
            compra = "2025-01-15" if vendido else None
            itbi = "2025-10-03" if etapa >= 4 else None
            contato = "2025-10-15" if vendido else None
        else:
            vendido = (real_nome is not None and real_nome.strip().upper() != "DISPONIVEL")
            nome = real_nome if vendido else None
            tel = real_tel if vendido else None
            email = real_email if vendido else None
            endereco = real_end if vendido else None
            bci = real_bci
            compra = real_compra
            itbi = real_itbi
            contato = real_contato

        nao_aplica_val = d.get("nao_aplica")
        if isinstance(nao_aplica_val, str) and nao_aplica_val.startswith("["):
            try:
                nao_aplica = json.loads(nao_aplica_val)
            except Exception:
                nao_aplica = []
        else:
            nao_aplica = []

        props = {
            "id": i,
            "codigo": lote_cod,
            "quadra": d.get("quadra") or lote_cod[0],
            "gleba": d.get("gleba"),
            "matricula": matricula if matricula else None,
            "matricula_mae": str(d.get("matricula_mae") or ""),
            "cartorio": d.get("cartorio") or "Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)",
            "area_m2": area,
            "perimetro_m": perim,
            "adquirente_nome": nome,
            "adquirente_telefone": tel,
            "adquirente_email": email,
            "adquirente_endereco": endereco,
            "data_compra": compra,
            "bci_inscricao": bci,
            "data_itbi": itbi,
            "data_ultimo_contato": contato,
            "observacoes": None,
            "etapa": max(etapa, 0),
            "nao_aplica": nao_aplica,
            "protocolo_prefeitura": d.get("protocolo_prefeitura"),
            "atendente_prefeitura": None if usar_mock else d.get("atendente_prefeitura"),
            "status_geral": d.get("status_geral"),
            "status_bci": d.get("status_bci"),
            "status_itbi": d.get("status_itbi"),
            "area_projeto_m2": float(d["area_projeto_m2"]) if d.get("area_projeto_m2") else None,
            "dif_area_m2": float(d["dif_area_m2"]) if d.get("dif_area_m2") else None,
        }

        features.append({"type": "Feature", "id": i, "properties": props, "geometry": mapping(g)})

    SAIDA = SAIDA_MOCK if usar_mock else SAIDA_REAL
    SAIDA.parent.mkdir(parents=True, exist_ok=True)
    fc = {"type": "FeatureCollection", "features": features}
    SAIDA.write_text(json.dumps(fc, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    modo_txt = "FICTÍCIOS (mock)" if usar_mock else "REAIS AUDITADOS"
    print(f"Sucesso: {len(features)} feições com dados {modo_txt} exportadas para {SAIDA}")


if __name__ == "__main__":
    main()
