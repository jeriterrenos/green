"""Script oficial de conferência, correção cadastral e limpeza dos lotes Green Terrenos.

Gera os seguintes arquivos estruturados e limpos:
1. lotes_base_projeto.gpkg (raiz)
2. dados antigos/Projeto QGIS/LATITUDE - greenterrenos/lotes_base_projeto.gpkg
3. dados antigos/Projeto QGIS/LATITUDE - greenterrenos/lotes_green_terrenos_atualizado.gpkg
4. dados antigos/Projeto QGIS/LATITUDE - greenterrenos/INPUT/lotes_base_projeto.gpkg
5. dados antigos/Projeto QGIS/LATITUDE - greenterrenos/INPUT/lotes_green_terrenos_atualizado.gpkg
6. dados antigos/Projeto QGIS/LATITUDE - greenterrenos/lotes_green_terrenos_atualizado.xlsx
7. public/mock/lotes.geojson

Exigências:
- "Não quero dados em observação" -> observacoes e obs estritamente None (sem changelogs/logs técnicos).
- Campos organizados em colunas estruturadas.
- Conferência integral dos 79 lotes.
- E2 (ID 41) -> Matrícula 1663, Bernardo Pinto Pontes.
- D10 (ID 52) -> Matrícula 1651, Francisco Geyson Fontenele Albuquerque.
"""
import json
import re
import shutil
from pathlib import Path
import geopandas as gpd
import pandas as pd
from shapely.geometry import mapping

RAIZ = Path(__file__).resolve().parent.parent
DIR_QGIS = RAIZ / "dados antigos" / "Projeto QGIS" / "LATITUDE - greenterrenos"
DIR_INPUT = DIR_QGIS / "INPUT"
GPKG_FONTE = RAIZ / "lotes_base_projeto.gpkg"

def formatar_telefone(tel):
    if not tel or pd.isna(tel):
        return None
    s = str(tel).strip()
    if s.lower() in ("none", "nan", "-", "", "tia bruno mallio"):
        return None
    if "+1" in s or "1619" in s:
        nums = re.sub(r"\D", "", s)
        if nums.startswith("1"):
            nums = nums[1:]
        if len(nums) == 10:
            return f"+1 ({nums[:3]}) {nums[3:6]}-{nums[6:]}"
        return "+1 (619) 757-8863"
    if "+41" in s:
        nums = re.sub(r"\D", "", s)
        if nums.startswith("41"):
            nums = nums[2:]
        return f"+41 {nums[:2]} {nums[2:5]} {nums[5:7]} {nums[7:]}".strip()
    
    nums = re.sub(r"\D", "", s)
    if len(nums) == 11:
        return f"({nums[:2]}) {nums[2:7]}-{nums[7:]}"
    elif len(nums) == 10:
        return f"({nums[:2]}) {nums[2:6]}-{nums[6:]}"
    elif len(nums) == 9:
        return f"(85) {nums[:5]}-{nums[5:]}"
    elif len(nums) == 8:
        return f"(85) 9{nums[:4]}-{nums[4:]}"
    return s

def executar():
    print("Carregando base vetorial com GeoPandas...")
    gdf = gpd.read_file(GPKG_FONTE, layer="lotes")
    print(f"Camada carregada com {len(gdf)} registros. CRS: {gdf.crs}")

    # Processamento e conferência de cada linha
    for idx, row in gdf.iterrows():
        _id = int(row["id"])
        codigo = str(row["codigo"]).strip()
        quadra = str(row["quadra"]).strip()
        matricula = str(row["matricula"]).strip() if pd.notna(row["matricula"]) else None
        comprador = str(row["adquirente_nome"]).strip() if pd.notna(row["adquirente_nome"]) else None
        telefone = str(row["adquirente_telefone"]).strip() if pd.notna(row["adquirente_telefone"]) else None
        email = str(row["adquirente_email"]).strip() if pd.notna(row["adquirente_email"]) else None
        endereco = str(row["adquirente_endereco"]).strip() if pd.notna(row["adquirente_endereco"]) else None
        bci = str(row["bci_inscricao"]).strip() if pd.notna(row["bci_inscricao"]) else None
        etapa = int(row["etapa"]) if pd.notna(row["etapa"]) else 0
        protocolo = str(row["protocolo_prefeitura"]).strip() if pd.notna(row["protocolo_prefeitura"]) else None
        atendente = str(row["atendente_prefeitura"]).strip() if pd.notna(row["atendente_prefeitura"]) else None
        status_geral = str(row["status_geral"]).strip() if pd.notna(row["status_geral"]) else None
        status_bci = str(row["status_bci"]).strip() if pd.notna(row["status_bci"]) else None
        status_itbi = str(row["status_itbi"]).strip() if pd.notna(row["status_itbi"]) else None
        data_compra = str(row["data_compra"]).strip() if pd.notna(row["data_compra"]) else None
        data_itbi = str(row["data_itbi"]).strip() if pd.notna(row["data_itbi"]) else None
        data_contato = str(row["data_ultimo_contato"]).strip() if pd.notna(row["data_ultimo_contato"]) else None
        gleba = str(row["gleba"]).strip() if pd.notna(row["gleba"]) else None
        matricula_mae = str(row["matricula_mae"]).strip() if pd.notna(row["matricula_mae"]) else None
        cartorio = "Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)"

        # 1. Correção E2 / D10 (swap detectado e comprovado)
        if _id == 41:
            codigo = "E2"
            quadra = "E"
            matricula = "1663"
            comprador = "Bernardo Pinto Pontes"
            telefone = "(21) 97693-1460"
            email = "bp@bernardopontes.com.br"
            endereco = "R. Dona Mariana, 185, Ap 304, Botafogo, Rio de Janeiro/RJ, CEP 22.280-020"
            gleba = "Gleba 22"
            matricula_mae = "1418"
            bci = None
            protocolo = None
            atendente = None
            status_bci = "Pendente"
            status_itbi = "Não iniciado"
            status_geral = "Sem processo"
            etapa = 0

        elif _id == 52:
            codigo = "D10"
            quadra = "D"
            matricula = "1651"
            comprador = "Francisco Geyson Fontenele Albuquerque"
            telefone = "(88) 98818-2960"
            email = "geyson_albuquerque@hotmail.com"
            endereco = "Av. Dom José, 26, Centro, Coreau/CE, CEP 62.160-000"
            gleba = "Gleba 10"
            matricula_mae = "1418"
            bci = None
            protocolo = None
            atendente = None
            status_bci = "Pendente"
            status_itbi = "Não iniciado"
            status_geral = "Sem processo"
            etapa = 0

        # 2. Formatação de telefone
        telefone = formatar_telefone(telefone)
        if comprador and "Marise Xavier" in comprador:
            telefone = None

        # 3. Lotes específicos auditados
        if codigo == "A5":
            comprador = "Daniel de Vasconcelos Teixeira"
            matricula = "2001"
            bci = "9703"
            protocolo = "Req #2340 / #1722"
            atendente = "Luciano Glaysson / Carlos Eduardo"
            status_bci = "Cadastrado / BCI Emitido"
            status_itbi = "DAM ITBI Emitido"
            status_geral = "ITBI em Andamento"
            etapa = 2
        elif codigo == "A6":
            comprador = "Daniel de Vasconcelos Teixeira"
            matricula = "2002"
            bci = "9611"
            protocolo = "Req #1698"
            atendente = "Carlos Eduardo Vasconcelos Sousa"
            status_bci = "Cadastrado / BCI Emitido"
            status_itbi = "Em Análise"
            status_geral = "ITBI em Andamento"
            etapa = 2
        elif codigo == "E7":
            comprador = "Jordão Trindade Santana"
            matricula = "1658"
            bci = "9610"
            protocolo = "Req #2445 / #2078"
            atendente = "Luciano Glaysson / Carlos Eduardo"
            status_bci = "Cadastrado / BCI Emitido"
            status_itbi = "Quitado / Pago"
            status_geral = "ITBI Quitado - Pronto p/ Registro"
            etapa = 4
            data_itbi = "2025-10-03"
        elif codigo == "F6":
            comprador = None
            matricula = "1817"
            bci = "9706"
            protocolo = "Req #1725"
            atendente = "Carlos Eduardo Vasconcelos Sousa"
            status_bci = "Cadastrado / BCI Emitido"
            status_itbi = "Não aplicável (Disponível)"
            status_geral = "Disponível"
            etapa = 0

        # 4. "Não quero dados em observação" -> estritamente None
        observacoes = None

        # Atribuir de volta ao GeoDataFrame
        gdf.at[idx, "codigo"] = codigo
        gdf.at[idx, "lote"] = codigo
        gdf.at[idx, "quadra"] = quadra
        gdf.at[idx, "matricula"] = matricula
        gdf.at[idx, "matricula_mae"] = matricula_mae
        gdf.at[idx, "gleba"] = gleba
        gdf.at[idx, "cartorio"] = cartorio
        gdf.at[idx, "adquirente_nome"] = comprador
        gdf.at[idx, "COMPRADOR"] = comprador
        gdf.at[idx, "adquirente_telefone"] = telefone
        gdf.at[idx, "telefone"] = telefone
        gdf.at[idx, "adquirente_email"] = email
        gdf.at[idx, "email"] = email
        gdf.at[idx, "adquirente_endereco"] = endereco
        gdf.at[idx, "endereco"] = endereco
        gdf.at[idx, "bci_inscricao"] = bci
        gdf.at[idx, "BCI"] = bci
        gdf.at[idx, "etapa"] = etapa
        gdf.at[idx, "protocolo_prefeitura"] = protocolo
        gdf.at[idx, "atendente_prefeitura"] = atendente
        gdf.at[idx, "status_geral"] = status_geral
        gdf.at[idx, "status_bci"] = status_bci
        gdf.at[idx, "status_itbi"] = status_itbi
        gdf.at[idx, "data_compra"] = data_compra
        gdf.at[idx, "DATA"] = data_compra
        gdf.at[idx, "data_itbi"] = data_itbi
        gdf.at[idx, "DATA_IBTI"] = data_itbi
        gdf.at[idx, "data_ultimo_contato"] = data_contato
        gdf.at[idx, "DATA_ULTIMO CONTATO"] = data_contato
        gdf.at[idx, "observacoes"] = observacoes
        gdf.at[idx, "obs"] = observacoes

    # Gravar o novo GeoPackage em arquivo temporário e depois substituir com segurança
    tmp_gpkg = RAIZ / "lotes_base_temp.gpkg"
    if tmp_gpkg.exists():
        tmp_gpkg.unlink()

    print("Gravando GeoPackage estruturado...")
    gdf.to_file(tmp_gpkg, layer="lotes", driver="GPKG")

    # Substituir arquivo na raiz
    shutil.copy2(tmp_gpkg, GPKG_FONTE)
    print(f"GeoPackage raiz atualizado com sucesso: {GPKG_FONTE}")

    # Replicar para pastas do projeto
    destinos_gpkg = [
        DIR_QGIS / "lotes_base_projeto.gpkg",
        DIR_QGIS / "lotes_green_terrenos_atualizado.gpkg",
        DIR_INPUT / "lotes_base_projeto.gpkg",
        DIR_INPUT / "lotes_green_terrenos_atualizado.gpkg",
    ]
    for d in destinos_gpkg:
        d.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(tmp_gpkg, d)
        print(f"Copiado para: {d}")

    if tmp_gpkg.exists():
        tmp_gpkg.unlink()

    # Gerar planilha Excel limpa
    df_excel = pd.DataFrame(gdf.drop(columns=["geometry"]))
    excel_path = DIR_QGIS / "lotes_green_terrenos_atualizado.xlsx"
    df_excel.to_excel(excel_path, index=False)
    print(f"Planilha Excel atualizada: {excel_path}")

    # Gerar public/mock/lotes.geojson
    features = []
    for idx, row in gdf.iterrows():
        geom = row["geometry"]
        comprador = row["adquirente_nome"]
        vendido = (comprador is not None and str(comprador).strip().upper() != "DISPONIVEL" and str(comprador).strip() != "")

        nao_aplica_val = row.get("nao_aplica")
        if isinstance(nao_aplica_val, str) and nao_aplica_val.startswith("["):
            try:
                nao_aplica = json.loads(nao_aplica_val)
            except Exception:
                nao_aplica = []
        else:
            nao_aplica = []

        props = {
            "id": int(row["id"]),
            "codigo": str(row["codigo"]),
            "quadra": str(row["quadra"]),
            "gleba": str(row["gleba"]) if pd.notna(row["gleba"]) else None,
            "matricula": str(row["matricula"]) if pd.notna(row["matricula"]) else None,
            "matricula_mae": str(row["matricula_mae"]) if pd.notna(row["matricula_mae"]) else "",
            "cartorio": str(row["cartorio"]) if pd.notna(row["cartorio"]) else "Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)",
            "area_m2": round(float(row["area_m2"] or 0), 2),
            "perimetro_m": round(float(row["perimetro_m"] or 0), 2),
            "area_projeto_m2": round(float(row["area_projeto_m2"]), 2) if pd.notna(row.get("area_projeto_m2")) and row.get("area_projeto_m2") is not None else None,
            "dif_area_m2": round(float(row["dif_area_m2"]), 2) if pd.notna(row.get("dif_area_m2")) and row.get("dif_area_m2") is not None else None,
            "adquirente_nome": comprador if vendido else None,
            "adquirente_telefone": str(row["adquirente_telefone"]) if (vendido and pd.notna(row["adquirente_telefone"])) else None,
            "adquirente_email": str(row["adquirente_email"]) if (vendido and pd.notna(row["adquirente_email"])) else None,
            "adquirente_endereco": str(row["adquirente_endereco"]) if (vendido and pd.notna(row["adquirente_endereco"])) else None,
            "data_compra": str(row["data_compra"]) if (vendido and pd.notna(row["data_compra"])) else None,
            "bci_inscricao": str(row["bci_inscricao"]).strip() if pd.notna(row["bci_inscricao"]) else None,
            "data_itbi": str(row["data_itbi"]) if pd.notna(row["data_itbi"]) else None,
            "data_ultimo_contato": str(row["data_ultimo_contato"]) if (vendido and pd.notna(row["data_ultimo_contato"])) else None,
            "observacoes": None,  # ESTREITAMENTE LIMPO: SEM DADOS EM OBSERVAÇÃO
            "etapa": max(int(row["etapa"] or 0), 0),
            "nao_aplica": nao_aplica,
            "protocolo_prefeitura": str(row["protocolo_prefeitura"]) if pd.notna(row["protocolo_prefeitura"]) else None,
            "atendente_prefeitura": str(row["atendente_prefeitura"]) if pd.notna(row["atendente_prefeitura"]) else None,
            "status_geral": str(row["status_geral"]) if pd.notna(row["status_geral"]) else None,
            "status_bci": str(row["status_bci"]) if pd.notna(row["status_bci"]) else None,
            "status_itbi": str(row["status_itbi"]) if pd.notna(row["status_itbi"]) else None,
        }

        features.append({
            "type": "Feature",
            "id": int(row["id"]),
            "geometry": mapping(geom),
            "properties": props
        })

    geojson_obj = {
        "type": "FeatureCollection",
        "name": "lotes_green_terrenos",
        "crs": {
            "type": "name",
            "properties": {"name": "urn:ogc:def:crs:OGC:1.3:CRS84"}
        },
        "features": features
    }

    saida_geojson = RAIZ / "public" / "mock" / "lotes.geojson"
    with open(saida_geojson, "w", encoding="utf-8") as f:
        json.dump(geojson_obj, f, ensure_ascii=False, indent=2)
    print(f"Exportado GeoJSON limpo: {saida_geojson} (Total: {len(features)} feições)")

if __name__ == "__main__":
    executar()
