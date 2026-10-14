"""Gera o script SQL mestre para setup e carga completa no Supabase.

Cria:
- supabase/setup_completo.sql
Contendo:
1. Extensão PostGIS e tipos
2. Tabelas (perfis, etapas, lotes, adquirentes, processos, etapas_lote, historico)
3. Índices espaciais e relacionais
4. View vw_lotes_mapa
5. Funções security definer (iniciar_processo, concluir_etapa, desfazer_ultima_etapa, is_admin, is_usuario)
6. Trigger de auditoria cadastral
7. Políticas de RLS
8. Carga do catálogo das 9 etapas
9. Carga oficial dos 79 lotes com geometrias PostGIS, matrículas, adquirentes e etapas
"""
import json
import sqlite3
from pathlib import Path
import geopandas as gpd
import pandas as pd

RAIZ = Path(__file__).resolve().parent.parent
GPKG = RAIZ / "lotes_base_projeto.gpkg"
SAIDA_SQL = RAIZ / "supabase" / "setup_completo.sql"
SAIDA_SQL.parent.mkdir(parents=True, exist_ok=True)

from gerar_mock import ler_gpkg_geom

def escape_sql(val):
    if val is None or pd.isna(val):
        return "NULL"
    s = str(val).replace("'", "''")
    return f"'{s}'"

def executar():
    print(f"Lendo base do GeoPackage: {GPKG}")
    gdf = gpd.read_file(GPKG, layer="lotes")
    print(f"Total de registros: {len(gdf)}")

    linhas_sql = []
    
    # 1. Cabeçalho e Extensões
    linhas_sql.append("""-- =====================================================================
-- Green Terrenos · Setup Completo do Banco de Dados Supabase (PostgreSQL + PostGIS)
-- Empreendimento: Green Terrenos (Latitude) — Município de Cruz / CE
-- =====================================================================

-- 1. EXTENSÃO POSTGIS
create extension if not exists postgis;

-- 2. TIPOS ENUM
do $$ begin
  create type papel_usuario as enum ('admin', 'leitor');
exception when duplicate_object then null; end $$;

do $$ begin
  create type status_etapa as enum ('concluida', 'nao_aplica');
exception when duplicate_object then null; end $$;

-- 3. TABELAS
create table if not exists perfis (
  user_id uuid primary key references auth.users on delete cascade,
  nome    text not null,
  papel   papel_usuario not null default 'leitor'
);

create table if not exists etapas (
  id          smallint primary key,
  nome        text not null,
  nome_curto  text not null,
  icone       text not null,
  dispensavel boolean not null default false,
  descricao   text,
  documentos  text[] not null default '{}'
);

create table if not exists lotes (
  id                  bigint generated always as identity primary key,
  codigo              text not null,
  quadra              text not null,
  matricula           text not null unique,
  matricula_mae       text,
  gleba               text,
  cartorio            text,
  area_m2             numeric(10,2),
  perimetro_m         numeric(10,2),
  area_projeto_m2     numeric(10,2),
  dif_area_m2         numeric(10,2),
  bci_inscricao       text,
  protocolo_prefeitura text,
  atendente_prefeitura text,
  status_geral        text,
  status_bci          text,
  status_itbi         text,
  data_compra         date,
  data_itbi           date,
  data_ultimo_contato date,
  observacoes         text,
  geom                geometry(MultiPolygon, 4326) not null,
  atualizado_em       timestamptz not null default now(),
  atualizado_por      uuid references auth.users
);
create index if not exists lotes_geom_idx on lotes using gist (geom);

create table if not exists adquirentes (
  lote_id       bigint references lotes on delete cascade,
  ordem         smallint check (ordem in (1, 2)),
  tipo_pessoa   text not null default 'PF' check (tipo_pessoa in ('PF','PJ')),
  nome          text not null,
  documento     text,
  rg            text,
  rg_orgao      text,
  nacionalidade text,
  profissao     text,
  estado_civil  text,
  regime_bens   text,
  conjuge_nome  text,
  conjuge_cpf   text,
  conjuge_rg    text,
  telefone      text,
  email         text,
  endereco      text,
  primary key (lote_id, ordem)
);

create table if not exists processos (
  lote_id          bigint primary key references lotes on delete cascade,
  data_solicitacao date not null,
  iniciado_por     uuid references auth.users default auth.uid(),
  iniciado_em      timestamptz not null default now()
);

create table if not exists etapas_lote (
  lote_id       bigint references processos (lote_id) on delete cascade,
  etapa_id      smallint references etapas (id),
  status        status_etapa not null,
  data_evento   date,
  observacao    text,
  concluido_por uuid references auth.users default auth.uid(),
  concluido_em  timestamptz not null default now(),
  primary key (lote_id, etapa_id)
);

create table if not exists historico (
  id         bigint generated always as identity primary key,
  lote_id    bigint not null references lotes on delete cascade,
  acao       text not null check (acao in
             ('iniciar_processo','concluir_etapa','nao_aplica_etapa','desfazer_etapa','editar_cadastro')),
  etapa_id   smallint references etapas (id),
  detalhes   jsonb,
  usuario_id uuid references auth.users default auth.uid(),
  criado_em  timestamptz not null default now()
);
create index if not exists historico_lote_idx on historico (lote_id, criado_em desc);

-- 4. VIEW VW_LOTES_MAPA
create or replace view vw_lotes_mapa with (security_invoker = true) as
select
  l.id, l.codigo, l.quadra, l.matricula, l.matricula_mae, l.gleba, l.cartorio,
  l.area_m2, l.perimetro_m, l.area_projeto_m2, l.dif_area_m2,
  l.bci_inscricao, l.protocolo_prefeitura, l.atendente_prefeitura,
  l.status_geral, l.status_bci, l.status_itbi,
  l.data_compra, l.data_itbi, l.data_ultimo_contato, l.observacoes,
  p.data_solicitacao,
  coalesce(max(el.etapa_id), 0) as ultima_etapa,
  case
    when p.lote_id is null and (select count(*) from adquirentes a where a.lote_id = l.id) = 0 then 'disponivel'
    when p.lote_id is null then 'sem_processo'
    when coalesce(max(el.etapa_id), 0) >= 9 then 'concluido'
    when coalesce(max(el.etapa_id), 0) >= 4 then 'cartorio'
    else 'prefeitura'
  end as faixa,
  st_asgeojson(l.geom)::json as geometria
from lotes l
left join processos   p  on p.lote_id  = l.id
left join etapas_lote el on el.lote_id = l.id
group by l.id, p.lote_id, p.data_solicitacao;

-- 5. FUNÇÕES E REGRAS DE NEGÓCIO
create or replace function is_usuario() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from perfis where user_id = auth.uid());
$$;

create or replace function is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from perfis where user_id = auth.uid() and papel = 'admin');
$$;

create or replace function iniciar_processo(p_lote bigint, p_data date)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'Apenas administradores podem iniciar processos.'; end if;
  if p_data > current_date then raise exception 'A data não pode ser futura.'; end if;
  if (select count(*) from adquirentes where lote_id = p_lote) = 0 then
    raise exception 'Lote disponível: informe o adquirente antes de iniciar o processo.';
  end if;
  insert into processos (lote_id, data_solicitacao) values (p_lote, p_data);
  insert into historico (lote_id, acao, detalhes)
  values (p_lote, 'iniciar_processo', jsonb_build_object('data_solicitacao', p_data));
end $$;

create or replace function concluir_etapa(
  p_lote bigint, p_etapa smallint, p_data_evento date,
  p_observacao text default null, p_nao_aplica boolean default false)
returns void language plpgsql security definer set search_path = public as $$
declare v_ultima smallint;
begin
  if not is_admin() then raise exception 'Apenas administradores podem concluir etapas.'; end if;
  if p_data_evento is null or p_data_evento > current_date then
    raise exception 'Informe a data do evento (não pode ser futura).';
  end if;
  if not exists (select 1 from processos where lote_id = p_lote) then
    raise exception 'Processo não iniciado para este lote.';
  end if;
  select coalesce(max(etapa_id), 0) into v_ultima from etapas_lote where lote_id = p_lote;
  if p_etapa <> v_ultima + 1 then
    raise exception 'A próxima etapa a concluir é a %.', v_ultima + 1;
  end if;
  if p_nao_aplica and not (select dispensavel from etapas where id = p_etapa) then
    raise exception 'Esta etapa não pode ser marcada como "não se aplica".';
  end if;
  insert into etapas_lote (lote_id, etapa_id, status, data_evento, observacao)
  values (p_lote, p_etapa,
          case when p_nao_aplica then 'nao_aplica' else 'concluida' end::status_etapa,
          p_data_evento, p_observacao);
  insert into historico (lote_id, acao, etapa_id, detalhes)
  values (p_lote, case when p_nao_aplica then 'nao_aplica_etapa' else 'concluir_etapa' end, p_etapa,
          jsonb_build_object('data_evento', p_data_evento, 'observacao', p_observacao));
end $$;

create or replace function desfazer_ultima_etapa(p_lote bigint, p_motivo text)
returns void language plpgsql security definer set search_path = public as $$
declare v_ultima smallint;
begin
  if not is_admin() then raise exception 'Apenas administradores podem desfazer etapas.'; end if;
  if coalesce(trim(p_motivo), '') = '' then raise exception 'Informe o motivo.'; end if;
  select max(etapa_id) into v_ultima from etapas_lote where lote_id = p_lote;
  if v_ultima is null then raise exception 'Nenhuma etapa concluída.'; end if;
  delete from etapas_lote where lote_id = p_lote and etapa_id = v_ultima;
  insert into historico (lote_id, acao, etapa_id, detalhes)
  values (p_lote, 'desfazer_etapa', v_ultima, jsonb_build_object('motivo', p_motivo));
end $$;

-- 6. AUDITORIA CADASTRAL
create or replace function trg_lotes_auditoria() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_dif jsonb;
begin
  select jsonb_object_agg(n.key, jsonb_build_object('de', o.value, 'para', n.value))
    into v_dif
    from jsonb_each(to_jsonb(new) - 'geom' - 'atualizado_em' - 'atualizado_por') n
    join jsonb_each(to_jsonb(old)) o using (key)
   where n.value is distinct from o.value;
  new.atualizado_em := now();
  new.atualizado_por := auth.uid();
  if v_dif is not null then
    insert into historico (lote_id, acao, detalhes) values (new.id, 'editar_cadastro', v_dif);
  end if;
  return new;
end $$;

drop trigger if exists lotes_auditoria on lotes;
create trigger lotes_auditoria before update on lotes
for each row execute function trg_lotes_auditoria();

-- 7. ROW LEVEL SECURITY (RLS)
alter table perfis      enable row level security;
alter table etapas      enable row level security;
alter table lotes       enable row level security;
alter table adquirentes enable row level security;
alter table processos   enable row level security;
alter table etapas_lote enable row level security;
alter table historico   enable row level security;

-- Políticas de Leitura
drop policy if exists ler_etapas on etapas;
create policy ler_etapas on etapas for select to authenticated using (is_usuario());

drop policy if exists ler_lotes on lotes;
create policy ler_lotes on lotes for select to authenticated using (is_usuario());

drop policy if exists ler_adquirentes on adquirentes;
create policy ler_adquirentes on adquirentes for select to authenticated using (is_usuario());

drop policy if exists ler_processos on processos;
create policy ler_processos on processos for select to authenticated using (is_usuario());

drop policy if exists ler_etapas_lote on etapas_lote;
create policy ler_etapas_lote on etapas_lote for select to authenticated using (is_usuario());

drop policy if exists ler_historico on historico;
create policy ler_historico on historico for select to authenticated using (is_usuario());

drop policy if exists ler_perfis on perfis;
create policy ler_perfis on perfis for select to authenticated using (is_usuario());

-- Políticas de Edição (Admin)
drop policy if exists admin_edita_lotes on lotes;
create policy admin_edita_lotes on lotes for update to authenticated
  using (is_admin()) with check (is_admin());

drop policy if exists admin_edita_adquirentes on adquirentes;
create policy admin_edita_adquirentes on adquirentes for all to authenticated
  using (is_admin()) with check (is_admin());

grant execute on function iniciar_processo, concluir_etapa, desfazer_ultima_etapa to authenticated;

-- 8. SEED DAS 9 ETAPAS
insert into etapas (id, nome, nome_curto, icone, dispensavel, descricao, documentos) values
(1, 'Cadastro imobiliário (BCI)', 'BCI', 'home_work', false,
 'Protocolar no sistema da Prefeitura o cadastro ou a atualização do imóvel, conferindo endereço, área, lote, quadra, titularidade e inscrição com a matrícula e o levantamento técnico.',
 ARRAY['Requerimento', 'Matrícula do imóvel', 'Planta topográfica', 'Memorial descritivo', 'Arquivos vetoriais', 'Contrato social, quando houver pessoa jurídica', 'RG e CPF do representante', 'Comprovante de residência do representante (últimos 3 meses)', 'Procuração, se o protocolo for feito por terceiro', 'Comprovante do BCI ou inscrição imobiliária anterior, se disponível']),

(2, 'Solicitação de ITBI', 'ITBI', 'request_quote', false,
 'Protocolar a solicitação ou declaração do ITBI com a identificação da operação, do imóvel, do comprador e do vendedor.',
 ARRAY['Requerimento assinado pelo comprador e pelo vendedor', 'Contrato de compra e venda ou minuta do instrumento de transmissão', 'Matrícula do imóvel', 'BCI ou número da inscrição imobiliária', 'RG e CPF do comprador e do vendedor (pessoas físicas)', 'Certidão de nascimento/casamento', 'RG, CPF e comprovante de residência do representante', 'Contrato social e poderes (pessoa jurídica)', 'Procuração, se aplicável']),

(3, 'ITBI pago (BCI atualizado)', 'Pago', 'paid', false,
 'Pagar o ITBI no prazo, enviar o comprovante ao sistema da Prefeitura e conferir a atualização do BCI em nome do adquirente.',
 ARRAY['Documento de arrecadação do ITBI', 'Comprovante de pagamento', 'Protocolo ou comprovante de envio no sistema', 'BCI atualizado em nome do adquirente']),

(4, 'Guia de ITBI emitida', 'Guia', 'receipt_long', false,
 'Com o pagamento confirmado, a Prefeitura emite a guia de ITBI quitada. Conferir dados da guia.',
 ARRAY['Número da matrícula ou inscrição imobiliária', 'Nome e CPF/CNPJ das partes', 'Valor da operação ou base de cálculo', 'Valor do imposto pago', 'Código de validação, quando houver', 'Certidão ou declaração de quitação do ITBI']),

(5, 'Protocolo no Cartório (Registro de Imóveis)', 'Cartório', 'account_balance', false,
 'Protocolar o título de transmissão no Cartório de Registro de Imóveis, com a guia de ITBI quitada.',
 ARRAY['Escritura pública, contrato registrável ou outro título de transmissão', 'Guia de ITBI quitada', 'Comprovante ou certidão de quitação do ITBI', 'Matrícula atualizada', 'RG e CPF das partes', 'Certidões pessoais', 'Comprovante de residência', 'Contrato social, CNPJ e prova de poderes (pessoa jurídica)', 'Procuração, se aplicável']),

(6, 'Exigências cartorárias', 'Exigências', 'rule', true,
 'Etapa dispensável. Cumprir eventuais notas devolutivas ou exigências feitas pelo Cartório de Registro de Imóveis.',
 ARRAY['Nota devolutiva ou relação de exigências do Cartório', 'Documentos complementares, certidões atualizadas ou aditivos contratuais', 'Petição ou requerimento de cumprimento de exigências']),

(7, 'Registro concluído', 'Registro', 'verified', false,
 'O Oficial do Registro de Imóveis defere o registro da transmissão e averba a transferência na matrícula.',
 ARRAY['Certidão de inteiro teor da matrícula atualizada com o registro da transmissão', 'Comprovante de pagamento dos emolumentos cartorários', 'Termo de encerramento do protocolo']),

(8, 'Matrícula atualizada conferida', 'Matrícula', 'badge', false,
 'Conferir na certidão de inteiro teor da matrícula: nome, CPF/CNPJ, estado civil, regime de bens, lote, quadra, área e eventuais ônus.',
 ARRAY['Certidão de inteiro teor da matrícula emitida após o registro']),

(9, 'Entrega ao adquirente', 'Entrega', 'mark_email_read', false,
 'Entregar a certidão da matrícula registrada e o título registrado ao adquirente, arquivando cópia do comprovante de entrega.',
 ARRAY['Cópia da certidão da matrícula registrada entregue ao adquirente', 'Termo ou recibo de entrega assinado pelo adquirente', 'Cópia do título registrado'])
on conflict (id) do update set
  nome = excluded.nome,
  nome_curto = excluded.nome_curto,
  icone = excluded.icone,
  dispensavel = excluded.dispensavel,
  descricao = excluded.descricao,
  documentos = excluded.documentos;

-- 9. CARGA DOS 79 LOTES AUDITADOS
delete from historico;
delete from etapas_lote;
delete from processos;
delete from adquirentes;
delete from lotes;
""")

    # 2. Inserção dos 79 lotes
    linhas_sql.append("-- Inserção de dados dos lotes")
    for idx, row in gdf.iterrows():
        _id = int(row["id"])
        codigo = escape_sql(row["codigo"])
        quadra = escape_sql(row["quadra"])
        matricula = escape_sql(row["matricula"])
        matricula_mae = escape_sql(row["matricula_mae"])
        gleba = escape_sql(row["gleba"])
        cartorio = escape_sql(row["cartorio"])
        area_m2 = row["area_m2"] if pd.notna(row["area_m2"]) else "NULL"
        perimetro_m = row["perimetro_m"] if pd.notna(row["perimetro_m"]) else "NULL"
        area_projeto_m2 = row["area_projeto_m2"] if pd.notna(row["area_projeto_m2"]) else "NULL"
        dif_area_m2 = row["dif_area_m2"] if pd.notna(row["dif_area_m2"]) else "NULL"
        bci = escape_sql(row["bci_inscricao"])
        protocolo = escape_sql(row["protocolo_prefeitura"])
        atendente = escape_sql(row["atendente_prefeitura"])
        status_geral = escape_sql(row["status_geral"])
        status_bci = escape_sql(row["status_bci"])
        status_itbi = escape_sql(row["status_itbi"])
        data_compra = escape_sql(row["data_compra"])
        data_itbi = escape_sql(row["data_itbi"])
        data_contato = escape_sql(row["data_ultimo_contato"])
        observacoes = "NULL"  # Estritamente limpo!
        
        geom = row["geometry"]
        wkt = geom.wkt

        sql_lote = f"""insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  {_id}, {codigo}, {quadra}, {matricula}, {matricula_mae}, {gleba}, {cartorio},
  {area_m2}, {perimetro_m}, {area_projeto_m2}, {dif_area_m2}, {bci}, {protocolo}, {atendente},
  {status_geral}, {status_bci}, {status_itbi}, {data_compra}, {data_itbi}, {data_contato}, {observacoes},
  ST_Multi(ST_GeomFromText('{wkt}', 4326))
);"""
        linhas_sql.append(sql_lote)

        # Adquirente
        nome_comprador = row["adquirente_nome"]
        if pd.notna(nome_comprador) and str(nome_comprador).strip().upper() != "DISPONIVEL" and str(nome_comprador).strip() != "":
            tel = escape_sql(row["adquirente_telefone"])
            email = escape_sql(row["adquirente_email"])
            endereco = escape_sql(row["adquirente_endereco"])
            linhas_sql.append(f"""insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values ({_id}, 1, 'PF', {escape_sql(nome_comprador)}, {tel}, {email}, {endereco});""")

        # Processo e Etapas
        etapa_num = int(row["etapa"] or 0)
        if etapa_num > 0:
            solicitacao = row["data_compra"] or "2025-01-15"
            linhas_sql.append(f"""insert into processos (lote_id, data_solicitacao) values ({_id}, {escape_sql(solicitacao)});""")
            linhas_sql.append(f"""insert into historico (lote_id, acao, detalhes) values ({_id}, 'iniciar_processo', jsonb_build_object('data_solicitacao', {escape_sql(solicitacao)}));""")
            for ep in range(1, etapa_num + 1):
                dt_evento = escape_sql(row["data_itbi"]) if ep >= 3 and pd.notna(row["data_itbi"]) else escape_sql(solicitacao)
                linhas_sql.append(f"""insert into etapas_lote (lote_id, etapa_id, status, data_evento) values ({_id}, {ep}, 'concluida', {dt_evento});""")

    linhas_sql.append("""
-- 10. REINICIA A SEQUÊNCIA DE IDS
select setval('lotes_id_seq', (select max(id) from lotes));

-- 11. NOTIFICA O SCHEMA CACHE
NOTIFY pgrst, 'reload schema';
""")

    conteudo_final = "\n".join(linhas_sql)
    with open(SAIDA_SQL, "w", encoding="utf-8") as f:
        f.write(conteudo_final)
    print(f"Script de setup gerado com sucesso: {SAIDA_SQL} ({len(conteudo_final)} bytes)")

if __name__ == "__main__":
    executar()
