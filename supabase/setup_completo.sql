-- =====================================================================
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

grant usage on schema public to anon, authenticated, service_role;
grant all on all tables in schema public to postgres, anon, authenticated, service_role;
grant all on all sequences in schema public to postgres, anon, authenticated, service_role;
grant all on all routines in schema public to postgres, anon, authenticated, service_role;
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

-- Inserção de dados dos lotes
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  1, 'A6', 'A', '2002', '1416', 'Gleba 03', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  312.55, 82.55, 312.55, 0.0, '9611', 'Req #1698', 'Carlos Eduardo Vasconcelos Sousa',
  'ITBI em Andamento', 'Cadastrado / BCI Emitido', 'Em Análise', '2025-01-15', '2025-07-16', '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.395895560764046 -2.8847506457725864, -40.39561443931505 -2.8847524661315838, -40.39560679013905 -2.8848430805385856, -40.39588722511405 -2.8848412646155914, -40.395895560764046 -2.8847506457725864))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (1, 1, 'PF', 'Daniel de Vasconcelos Teixeira', '(85) 98953-6987', 'egilando0874@gmail.com', 'Rua 206, 442, Bairro São Cristovão');
insert into processos (lote_id, data_solicitacao) values (1, '2025-01-15');
insert into historico (lote_id, acao, detalhes) values (1, 'iniciar_processo', jsonb_build_object('data_solicitacao', '2025-01-15'));
insert into etapas_lote (lote_id, etapa_id, status, data_evento) values (1, 1, 'concluida', '2025-01-15');
insert into etapas_lote (lote_id, etapa_id, status, data_evento) values (1, 2, 'concluida', '2025-01-15');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  2, 'E7', 'E', '1658', '1418', 'Gleba 17', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  295.95, 79.55, 295.95, 0.0, '9610', 'Req #2445 / #2078', 'Luciano Glaysson / Carlos Eduardo',
  'ITBI Quitado - Pronto p/ Registro', 'Cadastrado / BCI Emitido', 'Quitado / Pago', '2025-01-15', '2025-10-03', '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39843969525205 -2.884922835452596, -40.39817105531605 -2.88492472882658, -40.39817162190005 -2.8850143616695885, -40.39844021407205 -2.885012468622594, -40.39843969525205 -2.884922835452596))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (2, 1, 'PF', 'Jordão Trindade Santana', '(85) 99757-2000', 'jordaosantana@gmail.com', 'R. Bárbara de Sousa Costa, n° 100, Casa 12, bairro Lagoa Redonda, CEP 60.831-083');
insert into processos (lote_id, data_solicitacao) values (2, '2025-01-15');
insert into historico (lote_id, acao, detalhes) values (2, 'iniciar_processo', jsonb_build_object('data_solicitacao', '2025-01-15'));
insert into etapas_lote (lote_id, etapa_id, status, data_evento) values (2, 1, 'concluida', '2025-01-15');
insert into etapas_lote (lote_id, etapa_id, status, data_evento) values (2, 2, 'concluida', '2025-01-15');
insert into etapas_lote (lote_id, etapa_id, status, data_evento) values (2, 3, 'concluida', '2025-10-03');
insert into etapas_lote (lote_id, etapa_id, status, data_evento) values (2, 4, 'concluida', '2025-10-03');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  3, 'A5', 'A', '2001', '1416', 'Gleba 02', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  310.51, 82.45, 310.51, 0.0, '9703', 'Req #2340 / #1722', 'Luciano Glaysson / Carlos Eduardo',
  'ITBI em Andamento', 'Cadastrado / BCI Emitido', 'DAM ITBI Emitido', '2025-01-15', '2025-09-24', '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39590383798105 -2.884660662187582, -40.39562314253605 -2.8846624797785947, -40.39561443931505 -2.8847524661315838, -40.395895560764046 -2.8847506457725864, -40.39590383798105 -2.884660662187582))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (3, 1, 'PF', 'Daniel de Vasconcelos Teixeira', '(85) 99941-1000', 'cirlianefalcao@hotmail.com', 'Rua Dr. João de Deus, 291, Bairro de Fátima');
insert into processos (lote_id, data_solicitacao) values (3, '2025-01-15');
insert into historico (lote_id, acao, detalhes) values (3, 'iniciar_processo', jsonb_build_object('data_solicitacao', '2025-01-15'));
insert into etapas_lote (lote_id, etapa_id, status, data_evento) values (3, 1, 'concluida', '2025-01-15');
insert into etapas_lote (lote_id, etapa_id, status, data_evento) values (3, 2, 'concluida', '2025-01-15');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  4, 'B10', 'B', '2012', '1416', 'Gleba 13', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  297.4, 80.14, 297.4, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39648483010005 -2.885109146187589, -40.39621324842005 -2.8851103659375954, -40.39620480295005 -2.8851998212115895, -40.39647568042305 -2.885198198841588, -40.39648483010005 -2.885109146187589))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (4, 1, 'PF', 'Aderson José Alves Jardim Bonfim', '(88) 98163-4228', 'aderson.bonfim@gmail.com', 'Vila Preá, Cruz/CE');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  5, 'B9', 'B', '2013', '1416', 'Gleba 14', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  299.61, 80.34, 299.61, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39649272004205 -2.885019576133585, -40.39622079363805 -2.885020481046588, -40.39621324842005 -2.8851103659375954, -40.39648483010005 -2.885109146187589, -40.39649272004205 -2.885019576133585))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (5, 1, 'PF', 'Daniela e Olimpio', '(88) 98103-2130', 'danirodrod9800@gmail.com', 'Vila Preá, Cruz/CE');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  6, 'B8', 'B', '2014', '1416', 'Gleba 15', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  300.95, 80.5, 300.95, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.396501328627046 -2.8849296826895867, -40.396228822601046 -2.884930433960592, -40.39622079363805 -2.885020481046588, -40.39649272004205 -2.885019576133585, -40.396501328627046 -2.8849296826895867))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (6, 1, 'PF', 'Daniela e Olimpio', '(88) 98103-2130', 'danirodrod9800@gmail.com', 'Vila Preá, Cruz/CE');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  7, 'B5 - B6 - B7', 'B', '2015', '1416', 'Gleba 16', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  901.9, 120.48, 901.9, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39652339994305 -2.8846586201455944, -40.39625295696205 -2.8846597604245807, -40.39623684568005 -2.8848404528825835, -40.396228822601046 -2.884930433960592, -40.396501328627046 -2.8849296826895867, -40.39650759451405 -2.884838956769591, -40.39651564684205 -2.8847491606445903, -40.39652339994305 -2.8846586201455944))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (7, 1, 'PF', 'Tatiane Ferreira Moraes Valdivino', '(12) 99181-3905', 'tatianemoraes72@yahoo.com.br', 'Rua Angela Aparecida Ramos, R.02, 84, Jardim Santa Marina, Jacareí/SP');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  8, 'B4', 'B', '2016', '1416', 'Gleba 17', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  300.15, 80.16, 300.15, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39653116003305 -2.884568309320587, -40.39626102120405 -2.884569317772586, -40.39625295696205 -2.8846597604245807, -40.39652339994305 -2.8846586201455944, -40.39653116003305 -2.884568309320587))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (8, 1, 'PF', 'Lana Araujo Medeiros de Oliveira', '(12) 98153-0065', 'lanaaraujo203@gmail.com', 'Rua Itapecerica n° 229, bairro Bosque dos Eucaliptos, S. José dos Campos/SP');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  9, 'B3', 'B', '2017', '1416', 'Gleba 18', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  297.52, 80.02, 297.52, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39653978657505 -2.8844786530175837, -40.39626899289305 -2.8844799131535925, -40.39626102120405 -2.884569317772586, -40.39653116003305 -2.884568309320587, -40.39653978657505 -2.8844786530175837))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (9, 1, 'PF', 'Lana Araujo Medeiros de Oliveira', '(12) 98153-0065', 'lanaaraujo203@gmail.com', 'Rua Itapecerica n° 229, bairro Bosque dos Eucaliptos, S. José dos Campos/SP');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  10, 'A12 - B2', 'A', '2018', '1416', 'Gleba 19', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  600.83, 140.35, 600.83, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39654773798705 -2.8843883014615805, -40.39627705261705 -2.884389521215583, -40.39600673294205 -2.884390739257583, -40.39599878131705 -2.8844811705165943, -40.39626899289305 -2.8844799131535925, -40.39653978657505 -2.8844786530175837, -40.39654773798705 -2.8843883014615805))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (10, 1, 'PF', 'Gabrielle Gadelha Costa', '(85) 99632-6425', 'gabigcosta@hotmail.com', 'Rua Tomas Acioli, 1100, Ap 403, Bairro Dionisio Torres');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  11, 'A13', 'A', '2007', '1416', 'Gleba 08', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  296.52, 79.92, 296.52, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39626899289305 -2.8844799131535925, -40.39599878131705 -2.8844811705165943, -40.39599061609805 -2.884570327153592, -40.39626102120405 -2.884569317772586, -40.39626899289305 -2.8844799131535925))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (11, 1, 'PF', 'Yago Gadelha Costa', '(85) 99201-6731', 'yagogadelhacosta@gmail.com', 'Rua Tomas Acioli, 1100, Ap 403, Bairro Dionisio Torres');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  12, 'A14', 'A', '2008', '1416', 'Gleba 09', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  300.62, 80.2, 300.62, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39626102120405 -2.884569317772586, -40.39599061609805 -2.884570327153592, -40.39598270847105 -2.884660899819584, -40.39625295696205 -2.8846597604245807, -40.39626102120405 -2.884569317772586))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (12, 1, 'PF', 'Dimitrios Luiz Lins Pereira Christakou', '(61) 99333-9569', 'dimi.christak@hotmail.com', 'SHIS QL 2, Conjunto 1, casa 12 - Brasilia/DF');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  13, 'A15 - A16', 'A', '2009', '1416', 'Gleba 10', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  600.43, 100.25, 600.43, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39625295696205 -2.8846597604245807, -40.39598270847105 -2.884660899819584, -40.39597481291505 -2.8847511204145873, -40.39596652606805 -2.8848419465585824, -40.39623684568005 -2.8848404528825835, -40.39625295696205 -2.8846597604245807))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (13, 1, 'PF', 'João Matias', '(85) 99244-0604', 'joaomatiasvs@gmail.com', 'Av. Sargento Herminio Sampaio, 1819, Ap. 503 (Torre Sul), Bairro Monte Castelo');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  14, 'A17 - A18', 'A', '2010', '1416', 'Gleba 11', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  596.16, 99.95, 596.16, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39623684568005 -2.8848404528825835, -40.39596652606805 -2.8848419465585824, -40.39595901903705 -2.884931177716595, -40.39595092435205 -2.885021379051589, -40.39622079363805 -2.885020481046588, -40.396228822601046 -2.884930433960592, -40.39623684568005 -2.8848404528825835))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (14, 1, 'PF', 'Ivanisia Maria Victor de Souza', '(33) 66689-7368', 'ivanisia111@gmail.com', 'Av. Sargento Herminio Sampaio, 1819, Ap. 503 (Torre Sul), Bairro Monte Castelo');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  15, 'A19 - A20', 'A', '2011', '1416', 'Gleba 12', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  596.03, 99.92, 596.03, 0.0, NULL, '#1721', 'Carlos Eduardo Vasconcelos Sousa',
  'BCI Cadastrado na Prefeitura', 'Cadastro Concluído na SEFIN', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39622079363805 -2.885020481046588, -40.39595092435205 -2.885021379051589, -40.39594327302905 -2.8851115784095844, -40.39593478943705 -2.8852014383425812, -40.39620480295005 -2.8851998212115895, -40.39621324842005 -2.8851103659375954, -40.39622079363805 -2.885020481046588))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (15, 1, 'PF', 'Fernando Antonio Oliveira Silva Filho', '(85) 99927-4090', 'faosf@hotmail.com', 'Av. Senador Virgilio Tavora, 1525, Ap. 102, Bairro Aldeota');
insert into processos (lote_id, data_solicitacao) values (15, '2025-01-15');
insert into historico (lote_id, acao, detalhes) values (15, 'iniciar_processo', jsonb_build_object('data_solicitacao', '2025-01-15'));
insert into etapas_lote (lote_id, etapa_id, status, data_evento) values (15, 1, 'concluida', '2025-01-15');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  16, 'A9 - A10', 'A', '2005', '1416', 'Gleba 06', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  622.26, 102.46, 622.26, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39587067748405 -2.8850211579195895, -40.39559051001306 -2.885022972126589, -40.395582214432046 -2.8851139164465915, -40.39557373081005 -2.8852037763905893, -40.39585404615805 -2.8852019612085926, -40.39587067748405 -2.8850211579195895))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (16, 1, 'PF', 'Yuri Martins de Borba', '(85) 98763-2000', 'yuri@bbmadvogados.net', 'Rua Bento Albuquerque, 3300, Ap. 1601 (MB), Bairro Manoel Dias Branco');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  17, 'A8', 'A', '2004', '1416', 'Gleba 05', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  308.74, 82.22, 308.74, 0.0, '9705', '#1724', 'Carlos Eduardo Vasconcelos Sousa',
  'BCI Cadastrado na Prefeitura', 'Cadastrado com BCI', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39587892862205 -2.8849314577845897, -40.39559870199605 -2.884933272366589, -40.39559051001306 -2.885022972126589, -40.39587067748405 -2.8850211579195895, -40.39587892862205 -2.8849314577845897))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (17, 1, 'PF', 'Jose Edson Cavalcante Junior', '(85) 98852-0710', 'edsoncavalcanteadv@hotmail.com', 'R. Vilebaldo Aguiar, 2315, Ap 1403, Torre 1, Cocó, Fortaleza/CE');
insert into processos (lote_id, data_solicitacao) values (17, '2025-01-15');
insert into historico (lote_id, acao, detalhes) values (17, 'iniciar_processo', jsonb_build_object('data_solicitacao', '2025-01-15'));
insert into etapas_lote (lote_id, etapa_id, status, data_evento) values (17, 1, 'concluida', '2025-01-15');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  18, 'A7', 'A', '2003', '1416', 'Gleba 04', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  310.59, 82.36, 310.59, 0.0, NULL, '#1723', 'Carlos Eduardo Vasconcelos Sousa',
  'BCI Cadastrado na Prefeitura', 'Cadastro Concluído na SEFIN', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39588722511405 -2.8848412646155914, -40.39560679013905 -2.8848430805385856, -40.39559870199605 -2.884933272366589, -40.39587892862205 -2.8849314577845897, -40.39588722511405 -2.8848412646155914))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (18, 1, 'PF', 'Victor Meneses Soares', '(85) 99652-5858', 'victormsoares@hotmail.com', 'Rua Julio Azevedo, 590');
insert into processos (lote_id, data_solicitacao) values (18, '2025-01-15');
insert into historico (lote_id, acao, detalhes) values (18, 'iniciar_processo', jsonb_build_object('data_solicitacao', '2025-01-15'));
insert into etapas_lote (lote_id, etapa_id, status, data_evento) values (18, 1, 'concluida', '2025-01-15');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  19, 'C20', 'C', '1850', '1417', 'Gleba 21', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  347.16, 88.79, 347.16, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39719478721805 -2.8851051230735885, -40.39718765302505 -2.885197048097589, -40.39749690716805 -2.885197075114587, -40.39750138450405 -2.8851055592175827, -40.39719478721805 -2.8851051230735885))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (19, 1, 'PF', 'Thiago Marques de Miranda', '(85) 99865-3969', 'movimentonias@gmail.com', 'Av. Zezé Diogo, 3070');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  20, 'C19', 'C', '1849', '1417', 'Gleba 20', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  336.59, 87.67, 336.59, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39720296446405 -2.885015296077581, -40.39719478721805 -2.8851051230735885, -40.39750138450405 -2.8851055592175827, -40.39750578276305 -2.8850156596925856, -40.39720296446405 -2.885015296077581))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (20, 1, 'PF', 'Angela Cristina Sales Silva', '(85) 98106-1234', 'angelacsales55@gmail.com', 'R. Nadir Saboia, 980, casa 35, Sapiranga, CEP 60833-344');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  21, 'C18', 'C', '1848', '1417', 'Gleba 19', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  332.13, 86.82, 332.13, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39721116460305 -2.8849257210135946, -40.39720296446405 -2.885015296077581, -40.39750578276305 -2.8850156596925856, -40.39751018641105 -2.8849256500795812, -40.39721116460305 -2.8849257210135946))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (21, 1, 'PF', 'Antonio Cesar de Oliveira Carmo', '(38) 98848-6735', 'carmocesar65@gmail.com', 'Av. Pedro Alvares Cabral, 1859, Bloco B, Apt. 7, bairro Marambaia, Belem-PA');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  22, 'C17', 'C', '1847', '1417', 'Gleba 18', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  329.43, 86.08, 329.43, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39721905695006 -2.884835408293579, -40.39721116460305 -2.8849257210135946, -40.39751018641105 -2.8849256500795812, -40.39751458950905 -2.884835651787589, -40.39721905695006 -2.884835408293579))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (22, 1, 'PF', 'RAFAEL RAMOS SEGHROUCHNI IDRISSI', '(85) 98120-3353', 'rafaelidrissi@icloud.com', 'Av. Rogaciano Leite, 200, bairro Salinas, Apto 704');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  23, 'C16', 'C', '1846', '1417', 'Gleba 17', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  325.0, 85.24, 325.0, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39722742235105 -2.88474557046159, -40.39721905695006 -2.884835408293579, -40.39751458950905 -2.884835651787589, -40.39751900768905 -2.8847453452405905, -40.39722742235105 -2.88474557046159))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (23, 1, 'PF', 'Sebastiao Tarcisio Ramos Neto', '(85) 99121-3000', 'tarcisioramosneto@gmail.com', 'Av. Desembargador Moreira, 246, Apto 300, Meireles');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  24, 'C15', 'C', '1845', '1417', 'Gleba 16', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  319.42, 84.26, 319.42, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39752341409105 -2.8846552795205924, -40.39723623207005 -2.8846560120755886, -40.39722742235105 -2.88474557046159, -40.39751900768905 -2.8847453452405905, -40.39752341409105 -2.8846552795205924))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (24, 1, 'PF', 'Abelmar Ribeiro da Cunha Neto', '(85) 99837-9000', 'Abelmarneto@yahoo.com.br', 'Rua República do Líbano, 710, Apto. 600, Meireles');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  25, 'C14', 'C', '1844', '1417', 'Gleba 15', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  314.38, 83.32, 314.38, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39752781525005 -2.8845653210125937, -40.39724434401405 -2.8845666396655854, -40.39723623207005 -2.8846560120755886, -40.39752341409105 -2.8846552795205924, -40.39752781525005 -2.8845653210125937))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (25, 1, 'PF', 'Victor Siqueira Nocrato', '(85) 99980-4450', 'victorsnocrato@hotmail.com', 'Rua Dr. Jose Teles, 1650, Ed. Juan Gris, Ap. 1300, Guararapes, CEP 60810-210');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  26, 'C13', 'C', '1843', '1417', 'Gleba 14', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  309.91, 82.48, 309.91, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39753217211305 -2.8844762679525844, -40.39725218655505 -2.8844766655995873, -40.39724434401405 -2.8845666396655854, -40.39752781525005 -2.8845653210125937, -40.39753217211305 -2.8844762679525844))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (26, 1, 'PF', 'Vitor Guilherme Albuquerque Lopes', '(85) 99263-8830', 'vitorguilhermeadv@outlook.com.br', 'Ezequiel Martins Campina, 973, casa 5, Tamatanduba, Eusebio, CEP 61760-000');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  27, 'C11 - C12', 'C', '1842', '1417', 'Gleba 13', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  617.8, 101.82, 617.8, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39754106568905 -2.8842944859205897, -40.39726707113305 -2.8842954139925894, -40.39725970640405 -2.884386168340587, -40.39725218655505 -2.8844766655995873, -40.39753217211305 -2.8844762679525844, -40.39754106568905 -2.8842944859205897))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (27, 1, 'PF', 'Pedro Ernesto Bezerra Lima', '(85) 99922-1328', 'pedroernesto_@hotmail.com', 'Av. Litorânea, 2040, Qd. 03, Lote 11 - Alphaville FORTALEZA, EUSEBIO- CE');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  28, 'C1 - C3', 'C', '1841', '1417', 'Gleba 12', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  875.27, 118.54, 875.27, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39691496667305 -2.8842969319265936, -40.396897185554046 -2.8844772560025937, -40.39688986363205 -2.8845650833505863, -40.39715508794405 -2.884565873258582, -40.39716373170105 -2.884472490295587, -40.39717117459805 -2.884385807019583, -40.39718000755805 -2.8842974626235898, -40.39691496667305 -2.8842969319265936))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (28, 1, 'PF', 'Margarete Mendes Leone', '(11) 98911-1093', 'lmargarete@yahoo.com.br', 'Rua Cipriano Barata, 926, Ap 123, bairro Ipiranga, São Paulo/SP');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  29, 'C4', 'C', '1840', '1417', 'Gleba 11', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  297.17, 79.2, 297.17, 0.0, '9769', '#2067', 'Carlos Eduardo Vasconcelos Sousa',
  'BCI Cadastrado na Prefeitura', 'Cadastrado com BCI', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39688986363205 -2.8845650833505863, -40.39688152725905 -2.884657242864592, -40.39714653541405 -2.884656115834594, -40.39715508794405 -2.884565873258582, -40.39688986363205 -2.8845650833505863))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (29, 1, 'PF', 'Alice Lima de Menezes Vasconcelos (Cyrleide)', '(85) 99944-5052', 'alice24.doc@gmail.com', 'Rua Tomas Acioli, 1100, Ap 1001, Dionisio Torres, CEP 60.125-001, Fortaleza/CE');
insert into processos (lote_id, data_solicitacao) values (29, '2025-01-15');
insert into historico (lote_id, acao, detalhes) values (29, 'iniciar_processo', jsonb_build_object('data_solicitacao', '2025-01-15'));
insert into etapas_lote (lote_id, etapa_id, status, data_evento) values (29, 1, 'concluida', '2025-01-15');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  30, 'C5', 'C', '1839', '1417', 'Gleba 10', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  294.5, 79.08, 294.5, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39714653541405 -2.884656115834594, -40.39688152725905 -2.884657242864592, -40.39687336786205 -2.8847474459275806, -40.39713957147805 -2.8847463933615902, -40.39714653541405 -2.884656115834594))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (30, 1, 'PF', 'Adriana Meneguzzi', '(66) 99974-3769', 'panificadora_confeipan@hotmail.com', 'Av. Brasil, 1690, Centro, CEP: 78.870-000, Paranatinga/MT');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  31, 'C6', 'C', '1838', '1417', 'Gleba 09', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  292.82, 79.06, 292.82, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39713957147805 -2.8847463933615902, -40.39687336786205 -2.8847474459275806, -40.39686526764905 -2.8848369947175927, -40.39713132714005 -2.884835942713592, -40.39713957147805 -2.8847463933615902))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (31, 1, 'PF', 'Liliane Pereira das Neves', '(66) 99923-6296', 'neveslilianne@hotmail.com', 'Rua São João, 253, Centro, CEP: 78.870-000, Paranatinga/MT');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  32, 'C7 - C8', 'C', '1837', '1417', 'Gleba 08', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  587.14, 99.02, 587.14, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39713132714005 -2.884835942713592, -40.39686526764905 -2.8848369947175927, -40.39684899382305 -2.8850169038235958, -40.39711448597505 -2.88501564004158, -40.39713132714005 -2.884835942713592))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (32, 1, 'PF', 'Adelia Marcia de Jesus Vieira', '(92) 99116-2459', 'avieira1924@gmail.com', 'Rua Guerreiro Antony, 12, Bairro São Francisco, CEP: 69079100, Manaus/AM');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  33, 'C9 - C10', 'C', '1836', '1417', 'Gleba 07', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  591.86, 99.28, 591.86, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39711448597505 -2.88501564004158, -40.39684899382305 -2.8850169038235958, -40.39683266355505 -2.8851974369985864, -40.39709899954105 -2.8851968529235923, -40.397107561212046 -2.8851057381415965, -40.39711448597505 -2.88501564004158))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (33, 1, 'PF', 'Alysson M. Uchoa e Frivaldo Uchoa', '(85) 99973-8441', 'alyssonuchoa@hotmail.com', 'R. João Batista Rios, 66, Passaré');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  34, 'B17 - B20', 'B', '1835', '1417', 'Gleba 06', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  1190.93, 139.79, 1190.93, 0.0, '9746', '#2066', 'Carlos Eduardo Vasconcelos Sousa',
  'BCI Cadastrado na Prefeitura', 'Cadastrado com BCI', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39686526764905 -2.8848369947175927, -40.396596093086046 -2.884838058975594, -40.39658796803005 -2.8849278708385815, -40.39657999338405 -2.885018511301583, -40.39657164349505 -2.885108444952582, -40.39656378084905 -2.885198026595584, -40.39683266355505 -2.8851974369985864, -40.39684899382305 -2.8850169038235958, -40.39686526764905 -2.8848369947175927))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (34, 1, 'PF', 'Andreza Pereira Coutinho', '(88) 99483-8334', 'andrezawww@yahoo.com.br', 'Rua Inácio Rodrigues Lima, 8, Bairro Parque Silvana II, Juazeiro do Norte/Ce');
insert into processos (lote_id, data_solicitacao) values (34, '2025-01-15');
insert into historico (lote_id, acao, detalhes) values (34, 'iniciar_processo', jsonb_build_object('data_solicitacao', '2025-01-15'));
insert into etapas_lote (lote_id, etapa_id, status, data_evento) values (34, 1, 'concluida', '2025-01-15');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  35, 'B16', 'B', '1834', '1417', 'Gleba 05', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  295.93, 79.69, 295.93, 0.0, '9745', '#2065', 'Carlos Eduardo Vasconcelos Sousa',
  'BCI Cadastrado na Prefeitura', 'Cadastrado com BCI', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39687336786205 -2.8847474459275806, -40.39660462969706 -2.884748508451587, -40.396596093086046 -2.884838058975594, -40.39686526764905 -2.8848369947175927, -40.39687336786205 -2.8847474459275806))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (35, 1, 'PF', 'Lara Lima de Menezes Vasconcelos (Cyrleide)', '(85) 99977-4611', 'laralmv@hotmail.com', 'R. Tomás Acioli, 1100, Ap. 1001, Bairro Dionísio Torres');
insert into processos (lote_id, data_solicitacao) values (35, '2025-01-15');
insert into historico (lote_id, acao, detalhes) values (35, 'iniciar_processo', jsonb_build_object('data_solicitacao', '2025-01-15'));
insert into etapas_lote (lote_id, etapa_id, status, data_evento) values (35, 1, 'concluida', '2025-01-15');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  36, 'B15', 'B', '1833', '1417', 'Gleba 04', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  298.01, 79.82, 298.01, 0.0, NULL, '#2064', 'Carlos Eduardo Vasconcelos Sousa',
  'BCI Cadastrado na Prefeitura', 'Cadastro Concluído na SEFIN', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39688152725905 -2.884657242864592, -40.39661225604005 -2.884658387960589, -40.39660462969706 -2.884748508451587, -40.39687336786205 -2.8847474459275806, -40.39688152725905 -2.884657242864592))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (36, 1, 'PF', 'Reno Alencar Araripe Ribeiro', '(85) 99622-7722', 'renoribeiro@hotmail.com', 'Rua Leonardo Mota, 715, Ap. 801, Meireles, Fortaleza');
insert into processos (lote_id, data_solicitacao) values (36, '2025-01-15');
insert into historico (lote_id, acao, detalhes) values (36, 'iniciar_processo', jsonb_build_object('data_solicitacao', '2025-01-15'));
insert into etapas_lote (lote_id, etapa_id, status, data_evento) values (36, 1, 'concluida', '2025-01-15');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  37, 'B14', 'B', '1832', '1417', 'Gleba 03', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  301.11, 80.1, 301.11, 0.0, NULL, '#2063', 'Carlos Eduardo Vasconcelos Sousa',
  'BCI Cadastrado na Prefeitura', 'Cadastro Concluído na SEFIN', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39688986363205 -2.8845650833505863, -40.39662035444205 -2.884568535471582, -40.39661225604005 -2.884658387960589, -40.39688152725905 -2.884657242864592, -40.39688986363205 -2.8845650833505863))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (37, 1, 'PF', 'Osmar Lima de Menezes Vasconcelos (Cyrleide)', '(85) 99643-0053', 'menezesosmar@hotmail.com', 'R. Tomas Acioly, 1100, Apt 1001, Joaquim Tavora');
insert into processos (lote_id, data_solicitacao) values (37, '2025-01-15');
insert into historico (lote_id, acao, detalhes) values (37, 'iniciar_processo', jsonb_build_object('data_solicitacao', '2025-01-15'));
insert into etapas_lote (lote_id, etapa_id, status, data_evento) values (37, 1, 'concluida', '2025-01-15');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  38, 'B13', 'B', '1831', '1417', 'Gleba 02', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  293.07, 79.42, 293.07, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.396897185554046 -2.8844772560025937, -40.39663010910805 -2.884478471181588, -40.39662035444205 -2.884568535471582, -40.39688986363205 -2.8845650833505863, -40.396897185554046 -2.8844772560025937))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (38, 1, 'PF', 'Kelsen dos Santos Sales', '(85) 99922-3315', 'sales.kelsen@gmail.com', 'R. Vicente Leite, 1820, Ap. 401');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  39, 'B11 - B12', 'B', '1830', '1417', 'Gleba 01', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  593.69, 99.68, 593.69, 0.0, '9730', '#2062', 'Carlos Eduardo Vasconcelos Sousa',
  'BCI Cadastrado na Prefeitura', 'Cadastrado com BCI', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39691496667305 -2.8842969319265936, -40.396644632430046 -2.884299082613582, -40.39663010910805 -2.884478471181588, -40.396897185554046 -2.8844772560025937, -40.39691496667305 -2.8842969319265936))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (39, 1, 'PF', 'Otacilio Aureliano de Paiva', '(85) 98761-1808', 'otaciliopaiva@hotmail.com', 'Av. Santos Dumont, 6400, Apt 1203, Bloco B, Cocó, CEP: 60.192-022');
insert into processos (lote_id, data_solicitacao) values (39, '2025-01-15');
insert into historico (lote_id, acao, detalhes) values (39, 'iniciar_processo', jsonb_build_object('data_solicitacao', '2025-01-15'));
insert into etapas_lote (lote_id, etapa_id, status, data_evento) values (39, 1, 'concluida', '2025-01-15');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  40, 'E1', 'E', '1664', '1418', 'Gleba 23', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  597.17, 99.83, 597.17, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39843667449905 -2.8842911814105894, -40.39816705742505 -2.884292252776589, -40.39816819421005 -2.8844720977605856, -40.39843874228105 -2.8844710955715827, -40.39843667449905 -2.8842911814105894))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (40, 1, 'PF', 'Thais Angelica Gurjao Barbosa Praxedes', '(85) 98180-7799', 'angelicagurjao@hotmail.com', 'R. Bahia, n° 26, Bloco B, Ap. 402, bairro Parque Havai, Eusebio/CE, CEP 61.760-000');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  41, 'E2', 'E', '1663', '1418', 'Gleba 22', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  301.0, 80.14, 301.0, 0.0, NULL, NULL, NULL,
  'Sem processo', 'Pendente', 'Não iniciado', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39843874228105 -2.8844710955715827, -40.39816819421005 -2.8844720977605856, -40.39816876753805 -2.8845628002345944, -40.39843889853305 -2.884561560647587, -40.39843874228105 -2.8844710955715827))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (41, 1, 'PF', 'Bernardo Pinto Pontes', '(21) 97693-1460', 'bp@bernardopontes.com.br', 'R. Dona Mariana, 185, Ap 304, Botafogo, Rio de Janeiro/RJ, CEP 22.280-020');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  42, 'E3', 'E', '1662', '1418', 'Gleba 21', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  300.51, 80.05, 300.51, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39843889853305 -2.884561560647587, -40.39816876753805 -2.8845628002345944, -40.39816933996205 -2.884653359073594, -40.39843914801705 -2.884652120957582, -40.39843889853305 -2.884561560647587))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (42, 1, 'PF', 'Ricardo Burgos Andrade', '(71) 99271-1441', 'ricardo.burgos@ambev.com.br', 'R. Vilebaldo Aguiar, n° 2315, Ap. 1804, Torre 2, bairro Cocó, CEP 60.192-035');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  43, 'E4', 'E', '1661', '1418', 'Gleba 20', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  299.67, 79.93, 299.67, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39843914801705 -2.884652120957582, -40.39816933996205 -2.884653359073594, -40.398169911660055 -2.8847438024685883, -40.39843921670605 -2.8847425680695955, -40.39843914801705 -2.884652120957582))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (43, 1, 'PF', 'Ricardo Burgos Andrade', '(71) 99271-1441', 'ricardo.burgos@ambev.com.br', 'R. Vilebaldo Aguiar, n° 2315, Ap. 1804, Torre 2, bairro Cocó, CEP 60.192-035');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  44, 'E5', 'E', '1660', '1418', 'Gleba 19', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  301.7, 80.02, 301.7, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39843921670605 -2.8847425680695955, -40.398169911660055 -2.8847438024685883, -40.39817048340905 -2.884834253412585, -40.398439662782046 -2.8848344479515897, -40.39843921670605 -2.8847425680695955))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (44, 1, 'PF', 'Bruno Mallio Brandao de Oliveira', '(85) 98666-0052', 'brunomallio@hotmail.com', 'R. Nunes Valente, 136, Ap 403, Meireles, CEP: 60.125-070');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  45, 'E6', 'E', '1659', '1418', 'Gleba 18', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  295.6, 79.57, 295.6, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39817048340905 -2.884834253412585, -40.39817105531605 -2.88492472882658, -40.39843969525205 -2.884922835452596, -40.398439662782046 -2.8848344479515897, -40.39817048340905 -2.884834253412585))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (45, 1, 'PF', 'Bruce Mallio Brandao de Oliveira', '(85) 99953-6200', 'bruceoliveira@hotmail.com', 'R. Marcos Macedo, 1555, Ap 2103, Aldeota, CEP: 60.150-190');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  46, 'E8', 'E', '1657', '1418', 'Gleba 16', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  600.94, 99.98, 600.94, 0.0, '9770', '#2070', 'Carlos Eduardo Vasconcelos Sousa',
  'BCI Cadastrado na Prefeitura', 'Cadastrado com BCI', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39844021407205 -2.885012468622594, -40.39817162190005 -2.8850143616695885, -40.39817276911905 -2.8851958482385953, -40.39844166317005 -2.88519481900458, -40.39844021407205 -2.885012468622594))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (46, 1, 'PF', 'Ricardo Manfredini', '(11) 99847-9989', 'manfredomed@hotmail.com', 'R. Marcos Fernandes, 185, Ap 111, bairro Jardim da Saude, CEP 04.149-120 SÃO PAULO-SP');
insert into processos (lote_id, data_solicitacao) values (46, '2025-01-15');
insert into historico (lote_id, acao, detalhes) values (46, 'iniciar_processo', jsonb_build_object('data_solicitacao', '2025-01-15'));
insert into etapas_lote (lote_id, etapa_id, status, data_evento) values (46, 1, 'concluida', '2025-01-15');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  47, 'D16', 'D', '1656', '1418', 'Gleba 15', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  599.94, 99.98, 599.94, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39817162190005 -2.8850143616695885, -40.39790230311805 -2.8850162597755835, -40.397902930409046 -2.8851968810245916, -40.39817276911905 -2.8851958482385953, -40.39817162190005 -2.8850143616695885))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (47, 1, 'PF', 'Igor Nesralla Ribeiro', '(31) 99107-4408', 'nesralla@gmail.com', 'Rua Fernandes Tourinho, 818, Ap. 401, bairro Lourdes, Belo Horizonte/MG CEP: 30112-006');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  48, 'D15', 'D', '1655', '1418', 'Gleba 14', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  296.7, 79.7, 296.7, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39817105531605 -2.88492472882658, -40.39790178434005 -2.8849266265845848, -40.39790230311805 -2.8850162597755835, -40.39817162190005 -2.8850143616695885, -40.39817105531605 -2.88492472882658))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (48, 1, 'PF', 'Michael Gueiros Boaventura', '+1 (619) 757-8863', 'michaelgboaventura2020@gmail.com', 'Rua Leonardo Mota, 1645, Ap 1101, Aldeota, CEP 60.170-041');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  49, 'D13 - D14', 'D', '1654', '1418', 'Gleba 13', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  601.04, 100.06, 601.04, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.398169911660055 -2.8847438024685883, -40.39789965506105 -2.884745041165595, -40.39790178434005 -2.8849266265845848, -40.39817105531605 -2.88492472882658, -40.39817048340905 -2.884834253412585, -40.398169911660055 -2.8847438024685883))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (49, 1, 'PF', 'Marise Xavier Brandão', NULL, 'marisexb@hotmail.com', 'R. Carangola, 62, Ap 201, Santo Antonio, Belo Horizonte, CEP: 30.330-240');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  50, 'D12', 'D', '1653', '1418', 'Gleba 12', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  300.26, 80.05, 300.26, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39816933996205 -2.884653359073594, -40.39789940883705 -2.884654597688594, -40.39789965506105 -2.884745041165595, -40.398169911660055 -2.8847438024685883, -40.39816933996205 -2.884653359073594))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (50, 1, 'PF', 'Éder Ramon Feitoza Ledo', NULL, NULL, NULL);
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  51, 'D11', 'D', '1652', '1418', 'Gleba 11', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  300.29, 80.01, 300.29, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39816876753805 -2.8845628002345944, -40.39789915156505 -2.8845640373945862, -40.39789940883705 -2.884654597688594, -40.39816933996205 -2.884653359073594, -40.39816876753805 -2.8845628002345944))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (51, 1, 'PF', 'Jonathan Gomes Brito', '(88) 99716-6620', 'jonathan.creative2009@gmail.com', 'R. Juvenal Galeno, 98, bairro Estação, Granja/CE, CEP: 62.430-000');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  52, 'D10', 'D', '1651', '1418', 'Gleba 10', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  301.0, 80.03, 301.0, 0.0, NULL, NULL, NULL,
  'Sem processo', 'Pendente', 'Não iniciado', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39816819421005 -2.8844720977605856, -40.39789855659005 -2.884473096512591, -40.39789915156505 -2.8845640373945862, -40.39816876753805 -2.8845628002345944, -40.39816819421005 -2.8844720977605856))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (52, 1, 'PF', 'Francisco Geyson Fontenele Albuquerque', '(88) 98818-2960', 'geyson_albuquerque@hotmail.com', 'Av. Dom José, 26, Centro, Coreau/CE, CEP 62.160-000');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  53, 'D9', 'D', '1650', '1418', 'Gleba 09', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  596.35, 99.75, 596.35, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39816705742505 -2.884292252776589, -40.39789705328405 -2.8842933256175907, -40.39789855659005 -2.884473096512591, -40.39816819421005 -2.8844720977605856, -40.39816705742505 -2.884292252776589))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (53, 1, 'PF', 'Liliane Katia Romao', '(62) 98603-7566', 'lilromao@hotmail.com', 'Rua 3, SN, QD 3, Lote 25, bairro Jardim Primavera, Goianapolis/GO, CEP 75.170-000');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  54, 'D1', 'D', '1642', '1418', 'Gleba 01', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  604.32, 100.34, 604.32, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39780813102905 -2.884293581255582, -40.39754106568905 -2.8842944859205897, -40.39753217211305 -2.8844762679525844, -40.397805312831046 -2.8844758799595867, -40.39780813102905 -2.884293581255582))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (54, 1, 'PF', 'Rafael/Ricardo', NULL, NULL, NULL);
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  55, 'D2', 'D', '1643', '1418', 'Gleba 02', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  301.87, 81.25, 301.87, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.397805312831046 -2.8844758799595867, -40.39753217211305 -2.8844762679525844, -40.39752781525005 -2.8845653210125937, -40.39780911573805 -2.8845640123865954, -40.397805312831046 -2.8844758799595867))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (55, 1, 'PF', 'João Mario Boaventura Gomes', '(88) 98847-2745', 'johnfsa030983@gmail.com', 'Av Principal do Preá, 721, Pousada Horizonte Azul, Cruz/CE - 62.595-000');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  56, 'D3', 'D', '1644', '1418', 'Gleba 03', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  314.76, 83.06, 314.76, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39780911573805 -2.8845640123865954, -40.39752781525005 -2.8845653210125937, -40.39752341409105 -2.8846552795205924, -40.39780966423405 -2.8846545492695945, -40.39780911573805 -2.8845640123865954))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (56, 1, 'PF', 'Rafael Madeira', NULL, NULL, NULL);
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  57, 'D4', 'D', '1645', '1418', 'Gleba 04', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  320.24, 84.12, 320.24, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39780966423405 -2.8846545492695945, -40.39752341409105 -2.8846552795205924, -40.39751900768905 -2.8847453452405905, -40.39780971910105 -2.8847451206185806, -40.39780966423405 -2.8846545492695945))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (57, 1, 'PF', 'Ivan Manoel Vicente', '(11) 96503-0166', 'ivanmanoelvivente@gmail.com', 'Rua Egilio Vitorello, n° 91, bairro Parque Santa Tereza, Carapicuíba/SP');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  58, 'D5', 'D', '1646', '1418', 'Gleba 05', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  326.16, 85.2, 326.16, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39751900768905 -2.8847453452405905, -40.39751458950905 -2.884835651787589, -40.39781003096505 -2.8848358951285915, -40.39780971910105 -2.8847451206185806, -40.39751900768905 -2.8847453452405905))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (58, 1, 'PF', 'Sebastiao Manoel Rodrigues Lima', '(88) 99452-2005', 'dimereluz@bol.com.br', 'Rua Coronel Antonio Mendes Carneiro, 516, Centro, Sobral/CE');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  59, 'D6', 'D', '1647', '1418', 'Gleba 06', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  328.81, 86.08, 328.81, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39751458950905 -2.884835651787589, -40.39751018641105 -2.8849256500795812, -40.39781026941905 -2.8849255788145842, -40.39781003096505 -2.8848358951285915, -40.39751458950905 -2.884835651787589))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (59, 1, 'PF', 'Cristiano Fontenele Fernandes Pereira', '(85) 99868-0083', 'cristianoffp@hotmail.com', 'Rua Silva Jatahy, 1400, Ap 1301, Meireles, Fortaleza, CEP 60.165-070');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  60, 'D7', 'D', '1648', '1418', 'Gleba 07', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  335.45, 87.21, 335.45, 0.0, '9768', '#2069', 'Carlos Eduardo Vasconcelos Sousa',
  'BCI Cadastrado na Prefeitura', 'Cadastrado com BCI', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39751018641105 -2.8849256500795812, -40.39750578276305 -2.8850156596925856, -40.39781064073905 -2.8850160256745934, -40.39781026941905 -2.8849255788145842, -40.39751018641105 -2.8849256500795812))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (60, 1, 'PF', 'Fernando Luiz Bacalow da Silva', '(11) 97229-7940', 'bacalow@gmail.com', 'Rua Enio Azambuja Neves, 278, Jardim D''Abril, Osasco/SP, CEP: 06.038-060');
insert into processos (lote_id, data_solicitacao) values (60, '2025-01-15');
insert into historico (lote_id, acao, detalhes) values (60, 'iniciar_processo', jsonb_build_object('data_solicitacao', '2025-01-15'));
insert into etapas_lote (lote_id, etapa_id, status, data_evento) values (60, 1, 'concluida', '2025-01-15');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  61, 'D8', 'D', '1649', '1418', 'Gleba 08', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  689.88, 108.91, 689.88, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39750578276305 -2.8850156596925856, -40.39750138450405 -2.8851055592175827, -40.39749690716805 -2.885197075114587, -40.39781094471005 -2.8851971024625898, -40.39781123359705 -2.8851059999035793, -40.39781064073905 -2.8850160256745934, -40.39750578276305 -2.8850156596925856))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (61, 1, 'PF', 'Fernando Luiz Bacalow da Silva', '(11) 97229-7940', 'bacalow@gmail.com', 'Rua Enio Azambuja Neves, 278, Jardim D''Abril, Osasco/SP, CEP: 06.038-060');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  62, 'F1', 'F', '1822', '1108', 'Gleba 15', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  875.46, 127.7, 875.46, 0.0, '9709', '#1728', 'Carlos Eduardo Vasconcelos Sousa',
  'BCI Cadastrado na Prefeitura', 'Cadastrado com BCI', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39919848940905 -2.8842889152995856, -40.39879657282805 -2.884290364678589, -40.39879787793405 -2.8844708797885894, -40.39918507186505 -2.88446948347358, -40.39919848940905 -2.8842889152995856))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (62, 1, 'PF', 'Josiane', NULL, NULL, NULL);
insert into processos (lote_id, data_solicitacao) values (62, '2025-01-15');
insert into historico (lote_id, acao, detalhes) values (62, 'iniciar_processo', jsonb_build_object('data_solicitacao', '2025-01-15'));
insert into etapas_lote (lote_id, etapa_id, status, data_evento) values (62, 1, 'concluida', '2025-01-15');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  63, 'F2', 'F', '1821', '1108', 'Gleba 14', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  416.52, 104.86, 416.52, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39918507186505 -2.88446948347358, -40.39879787793405 -2.8844708797885894, -40.39879852054106 -2.884559760917592, -40.39917854603705 -2.8845573056195954, -40.39918507186505 -2.88446948347358))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (63, 1, 'PF', 'Ricardo - Pai', NULL, NULL, NULL);
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  64, 'F3', 'F', '1820', '1108', 'Gleba 13', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  429.41, 104.22, 429.41, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39917854603705 -2.8845573056195954, -40.39879852054106 -2.884559760917592, -40.39879919186005 -2.884652612786589, -40.39917164283105 -2.884650206412596, -40.39917854603705 -2.8845573056195954))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (64, 1, 'PF', 'Guilherme Neves Barbosa', '(21) 98350-5155', 'guibarbosa07@gmail.com', 'R. Humberto de Campos, 827. Ap 129, Leblon, Rio de Janeiro/RJ CEP 22.430-190');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  65, 'F4', 'F', '1819', '1108', 'Gleba 12', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  408.24, 101.94, 408.24, 0.0, '9708', '#1727', 'Carlos Eduardo Vasconcelos Sousa',
  'BCI Cadastrado na Prefeitura', 'Cadastrado com BCI', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39917164283105 -2.884650206412596, -40.39879919186005 -2.884652612786589, -40.39879983665405 -2.884741795470581, -40.39916488192505 -2.88474119222359, -40.39917164283105 -2.884650206412596))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (65, 1, 'PF', 'Caroline Bitencourt Cardoso de Souza', '(11) 94732-0003', 'bitencourt.c@gmail.com', 'R. Barbara Knippelberg Loureiro, 103, Ap 1702, Vila Ema, São José dos Campos/SP, 12.243-040');
insert into processos (lote_id, data_solicitacao) values (65, '2025-01-15');
insert into historico (lote_id, acao, detalhes) values (65, 'iniciar_processo', jsonb_build_object('data_solicitacao', '2025-01-15'));
insert into etapas_lote (lote_id, etapa_id, status, data_evento) values (65, 1, 'concluida', '2025-01-15');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  66, 'F5', 'F', '1818', '1108', 'Gleba 11', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  400.29, 100.31, 400.29, 0.0, '9707', '#1726', 'Carlos Eduardo Vasconcelos Sousa',
  'BCI Cadastrado na Prefeitura', 'Cadastrado com BCI', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39916488192505 -2.88474119222359, -40.39879983665405 -2.884741795470581, -40.39880049122105 -2.8848323293775833, -40.39915821535905 -2.884830908463583, -40.39916488192505 -2.88474119222359))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (66, 1, 'PF', 'Caroline Bitencourt Cardoso de Souza', '(11) 94732-0003', 'bitencourt.c@gmail.com', 'R. Barbara Knippelberg Loureiro, 103, Ap 1702, Vila Ema, São José dos Campos/SP, 12.243-040');
insert into processos (lote_id, data_solicitacao) values (66, '2025-01-15');
insert into historico (lote_id, acao, detalhes) values (66, 'iniciar_processo', jsonb_build_object('data_solicitacao', '2025-01-15'));
insert into etapas_lote (lote_id, etapa_id, status, data_evento) values (66, 1, 'concluida', '2025-01-15');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  67, 'F6', 'F', '1817', '1108', 'Gleba 10', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  392.32, 98.69, 392.32, 0.0, '9706', 'Req #1725', 'Carlos Eduardo Vasconcelos Sousa',
  'Disponível', 'Cadastrado / BCI Emitido', 'Não aplicável (Disponível)', NULL, NULL, NULL, NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39915821535905 -2.884830908463583, -40.39880049122105 -2.8848323293775833, -40.39880114371605 -2.884922576148592, -40.39915152156605 -2.8849209911475806, -40.39915821535905 -2.884830908463583))', 4326))
);
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  68, 'F7', 'F', '1816', '1108', 'Gleba 09', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  386.3, 97.16, 386.3, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39915152156605 -2.8849209911475806, -40.39880114371605 -2.884922576148592, -40.39880179758405 -2.8850130123565965, -40.39914476693105 -2.8850118926455837, -40.39915152156605 -2.8849209911475806))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (68, 1, 'PF', 'Leticia Vontobel', '(85) 98156-4131', 'leticiavontobel@gmail.com', 'R. Vilebaldo Aguiar, 2315, Ap 1904 T2, Cocó, CEP 60.192-035');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  69, 'F8', 'F', '1815', '1108', 'Gleba 08', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  729.17, 113.76, 729.17, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39914476693105 -2.8850118926455837, -40.39880179758405 -2.8850130123565965, -40.39880310423705 -2.8851937335875815, -40.398827229913046 -2.885193654824586, -40.39913198353905 -2.8851839271475805, -40.39914476693105 -2.8850118926455837))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (69, 1, 'PF', 'Tiago Paes de Almeida', '+41 78 748 88 61', 'tiago.paesdealmeida@gmail.com', 'Av. Dr. Afonso Vergueiro, n° 2221, bairro Vila Augusta, Sorocaba/SP, CEP 18.040-000');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  70, 'E16', 'E', '1814', '1108', 'Gleba 07', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  599.88, 100.01, 599.88, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39880179758405 -2.8850130123565965, -40.39853210782105 -2.8850138927545808, -40.398532691402046 -2.885194616366584, -40.39880310423705 -2.8851937335875815, -40.39880179758405 -2.8850130123565965))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (70, 1, 'PF', 'Thomas Vieira Acioly', '(85) 98807-8247', 'thomasaccioly@hotmail.com', 'Rua Bento Albuquerque, n° 1133, Ap. 1202, bairro Cocó, Fortaleza/CE, CEP 60.192-055');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  71, 'E15', 'E', '1813', '1108', 'Gleba 06', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  299.66, 80.01, 299.66, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39880114371605 -2.884922576148592, -40.39853067258405 -2.8849237996015913, -40.39853210782105 -2.8850138927545808, -40.39880179758405 -2.8850130123565965, -40.39880114371605 -2.884922576148592))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (71, 1, 'PF', 'Yaskara Natasha Dias Marinho', '(85) 99649-2222', 'yaskaramarinho@hotmail.com', 'R. Suécia, n° 418, bairro Itaperi, Fortaleza/CE, CEP 60.714-140');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  72, 'E14', 'E', '1812', '1108', 'Gleba 05', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  300.5, 80.15, 300.5, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39880049122105 -2.8848323293775833, -40.39852962726105 -2.8848334051995836, -40.39853067258405 -2.8849237996015913, -40.39880114371605 -2.884922576148592, -40.39880049122105 -2.8848323293775833))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (72, 1, 'PF', 'Jamil Elias Farah Neto', '(85) 99905-7385', 'jamilfarah@hotmail.com', 'Rua São Pedro, 668, Loja 1, Flecheiras, Trairi - CE');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  73, 'E13', 'E', '1811', '1108', 'Gleba 04', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  302.26, 80.27, 302.26, 0.0, '9700', '#1729, #2053', 'Carlos Eduardo Vasconcelos Sousa',
  'BCI Cadastrado na Prefeitura', 'Cadastrado com BCI', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39879983665405 -2.884741795470581, -40.39852934956105 -2.8847422423815936, -40.39852962726105 -2.8848334051995836, -40.39880049122105 -2.8848323293775833, -40.39879983665405 -2.884741795470581))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (73, 1, 'PF', 'RAFAEL MADEIRA DANTAS PAIVA', NULL, NULL, NULL);
insert into processos (lote_id, data_solicitacao) values (73, '2025-01-15');
insert into historico (lote_id, acao, detalhes) values (73, 'iniciar_processo', jsonb_build_object('data_solicitacao', '2025-01-15'));
insert into etapas_lote (lote_id, etapa_id, status, data_evento) values (73, 1, 'concluida', '2025-01-15');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  74, 'E12', 'E', '1810', '1108', 'Gleba 03', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  294.21, 79.69, 294.21, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39879919186005 -2.884652612786589, -40.39852896658905 -2.884654358611584, -40.39852934956105 -2.8847422423815936, -40.39879983665405 -2.884741795470581, -40.39879919186005 -2.884652612786589))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (74, 1, 'PF', 'Roger Magno Capibaribe de Arruda', '(85) 99711-6354', 'roger_arruda@hotmail.com', 'R. Pedro Rufino, n° 100, Ap. 902, Bloco A, bairro Varjota, CEP 60.175-100');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  75, 'E10 - E11', 'E', '1809', '1108', 'Gleba 02', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  604.56, 100.34, 604.56, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39879787793405 -2.8844708797885894, -40.39852777826605 -2.8844718537545853, -40.39852856196405 -2.8845615050085827, -40.39852896658905 -2.884654358611584, -40.39879919186005 -2.884652612786589, -40.39879852054106 -2.884559760917592, -40.39879787793405 -2.8844708797885894))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (75, 1, 'PF', 'Roney Silveira Gonçalves', '(85) 99101-6421', 'compras@granos.com.br', 'R. Pedro Rufino, n° 100, Ap. 902, Bloco A, bairro Varjota, CEP 60.175-100');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  76, 'E9', 'E', '1808', '1108', 'Gleba 01', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  599.66, 100.01, 599.66, 0.0, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39879657282805 -2.884290364678589, -40.39852616087305 -2.88429133974958, -40.39852777826605 -2.8844718537545853, -40.39879787793405 -2.8844708797885894, -40.39879657282805 -2.884290364678589))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (76, 1, 'PF', 'Rafael Canuto Gonçalves', '(85) 99699-8771', 'rafael@mahalopoke.com.br', 'R. Vilebaldo Aguiar, n° 2315, Ap. 1604, Torre 3, bairro Cocó, CEP 60.192-035');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  77, 'B1', 'B', '2019', '1416', 'Gleba 20', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  359.48, 84.21, 296.38, 63.1, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39655698854447 -2.884276345147396, -40.39628641766816 -2.8842849996862627, -40.39627705261705 -2.884389521215583, -40.39654773798705 -2.884388301461597, -40.39655698854447 -2.884276345147396))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (77, 1, 'PF', 'Thiago Facanha Xenofonte Rocha', '(85) 98180-2412', 'thiago@mulatocomunicacao.com.br', 'Rua General Tertuliano Potiguara, 1199, Ap 1503, ALDEOTA CEP 60.135-280');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  78, 'A11', 'A', '2006', '1416', 'Gleba 07', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  334.93, 82.59, 296.16, 38.77, NULL, NULL, NULL,
  'Matrícula OK / Sem Processo Iniciado', 'Pendente de Protocolo', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39628641766816 -2.8842849996862627, -40.3960152170798 -2.88429365493881, -40.39600673294205 -2.884390739257583, -40.39627705261705 -2.884389521215583, -40.39628641766816 -2.8842849996862627))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (78, 1, 'PF', 'Robson Martins Pascoal', '(85) 99688-5154', 'robson28pascoal@gmail.com', 'Rua João Cordeiro, 1095, Ap. 1701 (Orbetello), Bairro Aldeota');
insert into lotes (id, codigo, quadra, matricula, matricula_mae, gleba, cartorio,
  area_m2, perimetro_m, area_projeto_m2, dif_area_m2, bci_inscricao, protocolo_prefeitura, atendente_prefeitura,
  status_geral, status_bci, status_itbi, data_compra, data_itbi, data_ultimo_contato, observacoes, geom)
overriding system value values (
  79, 'A1 - A2 - A3 - A4', 'A', '2000', '1416', 'Gleba 01', 'Cartório Mozart Sales - Comarca de Cruz/CE (CNS 01.971-1)',
  1247.59, 142.79, 1242.31, 5.28, NULL, '#3532', 'Luciano Glaysson Carvalho',
  'BCI Cadastrado na Prefeitura', 'Cadastro Deferido / DAM Emitido', 'Pendente de Solicitação', '2025-01-15', NULL, '2025-10-15', NULL,
  ST_Multi(ST_GeomFromText('POLYGON ((-40.39593736992005 -2.8842961286895847, -40.39565464763805 -2.884305153015591, -40.39562314253605 -2.88466247966259, -40.39590383798105 -2.8846606620715938, -40.39593736992005 -2.8842961286895847))', 4326))
);
insert into adquirentes (lote_id, ordem, tipo_pessoa, nome, telefone, email, endereco)
values (79, 1, 'PF', 'Pedro Gabriel Xavier D Alcantara', '(31) 99605-6771', 'pgalcantara@hotmail.com', 'Rua São Lazaro, 1154, Ap. 303, Sagrada Familia - Minas Gerais');
insert into processos (lote_id, data_solicitacao) values (79, '2025-01-15');
insert into historico (lote_id, acao, detalhes) values (79, 'iniciar_processo', jsonb_build_object('data_solicitacao', '2025-01-15'));
insert into etapas_lote (lote_id, etapa_id, status, data_evento) values (79, 1, 'concluida', '2025-01-15');

-- 10. REINICIA A SEQUÊNCIA DE IDS
select setval('lotes_id_seq', (select max(id) from lotes));

-- 11. NOTIFICA O SCHEMA CACHE
NOTIFY pgrst, 'reload schema';
