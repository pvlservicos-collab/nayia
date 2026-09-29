-- =====================================================================
-- 158 — OS DADOS DA PLANILHA GERAL E DO SITE ANTIGO NO CADASTRO (28/09/2026)
--
-- Pedro: "você não sincronizou todas as informações do imóvel daquela nossa
-- planilha geral, tá faltando número do apartamento, endereço certinho, e o
-- status que mudou"; depois "corrige todos os dados"; e "ponha todos os
-- campos do site antigo mas sem ser obrigatório, põe só as informações que
-- tivermos".
--
-- ORDEM DE QUEM VALE MAIS (Pedro): captação > site antigo (a planilha que ele
-- puxou) > site novo. Aqui entram as duas fontes do site antigo -- nada da
-- captação (essa lista vai para ele ver antes):
--
--   1. a PLANILHA GERAL (26/09), pelo plano medido em
--      scratchpad/planilha/plano_sincronizacao.csv (carregado em /tmp/plano_158.csv):
--        - a rua separada do endereço inteiro (4.385) -- só se ninguém mexeu depois
--        - cidade, estado, bairro, número onde estava vazio
--        - vagas: as 644 que a importação de 26/09 zerou voltam ao valor de antes
--        - vagas cobertas (a coluna "Vagas" da planilha é a coberta do admin antigo)
--        - apartamento e torre -> imovel_privado
--   2. a FICHA DO ADMIN ANTIGO (08/09, imoveis_admin_detalhe) e o que a raspagem
--      do site antigo deixou no `extras`: o que o imóvel ainda não tinha.
--
-- NUNCA SOBRESCREVE: só preenche o que está vazio (a rua separada e as vagas
-- zeradas conferem o valor de hoje contra o que foi medido no plano).
--
-- O NÚMERO DA CASA DE RUA NÃO VAI PARA O ENDEREÇO (regra do Tel, 01/09: "o
-- número é o que identifica a casa"). O cartão do site mostra "rua, número -
-- bairro" a qualquer um; por isso esse número vai para imovel_privado.casa.
--
-- A SITUAÇÃO que o Tel mandou pelo WhatsApp e a importação de 26/09 desfez:
-- 1850 ("1850 alugado", 09/09), 2943 ("Alugado 2943", 25/09) e 5374
-- ("Alugado 5374", 26/09) voltam a Alugado, fora do site e da Nay. O gatilho
-- enfileira o aviso de saída no grupo Easy; 2943 e 5374 já foram avisados lá
-- e o 1850 fica para o Pedro decidir -- os três saem marcados como avisados.
--
-- NÃO APLICA o aluguel do 3210 (o banco mudou em 27/09, depois da planilha).
--
-- Cópia de antes em privado.imoveis_antes_158 e privado.imovel_privado_antes_158
-- (fora do public: o /api/tabelas não enxerga).
--
-- Rodar: o CSV em /tmp/plano_158.csv DENTRO do container nay-postgres; com
-- -v ensaio=1 tudo é desfeito no fim e só as contagens ficam na tela.
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout = '3s';
SET LOCAL statement_timeout = '120s';

-- 0) a cópia de antes, fora do public
CREATE TABLE privado.imoveis_antes_158 AS SELECT * FROM imoveis;
CREATE TABLE privado.imovel_privado_antes_158 AS SELECT * FROM imovel_privado;

CREATE TEMP TABLE mercado_antes ON COMMIT DROP AS
SELECT count(*) FILTER (WHERE nay_esta_no_mercado(disponivel, bloqueado, publicado_no_site) AND NOT coalesce(e_parceiro, false)) AS nossos_no_mercado,
       count(*) FILTER (WHERE nay_esta_no_mercado(disponivel, bloqueado, publicado_no_site) AND coalesce(e_parceiro, false)) AS parceiros_no_mercado
  FROM imoveis;

-- 1) o plano da planilha
CREATE TEMP TABLE plano (codigo int, coluna text, valor_hoje text, valor_proposto text,
                         regra text, status_hoje text, origem text) ON COMMIT DROP;
\copy plano FROM '/tmp/plano_158.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

DO $$
BEGIN
  IF (SELECT count(*) FROM plano) <> 21323 THEN
    RAISE EXCEPTION 'o plano tem % linhas, esperava 21323', (SELECT count(*) FROM plano);
  END IF;
END $$;

CREATE TEMP TABLE pv ON COMMIT DROP AS
SELECT codigo,
  max(valor_proposto) FILTER (WHERE coluna = 'logradouro' AND regra LIKE 'separar endereco%') AS rua,
  max(valor_hoje)     FILTER (WHERE coluna = 'logradouro' AND regra LIKE 'separar endereco%') AS rua_hoje,
  max(valor_proposto) FILTER (WHERE coluna = 'cidade' AND regra = 'preencher vazio') AS cidade,
  max(valor_proposto) FILTER (WHERE coluna = 'estado' AND regra = 'preencher vazio') AS estado,
  max(valor_proposto) FILTER (WHERE coluna = 'bairro' AND regra = 'preencher vazio') AS bairro,
  max(valor_proposto) FILTER (WHERE coluna = 'numero' AND regra = 'preencher vazio') AS numero,
  max(valor_proposto) FILTER (WHERE coluna = 'numero' AND regra LIKE 'CONFIRMAR COM O TEL (casa de rua%') AS numero_casa,
  max(valor_proposto) FILTER (WHERE coluna = 'vagas_cobertas') AS vagas_cobertas,
  max(valor_proposto) FILTER (WHERE coluna = 'vagas' AND regra LIKE 'voltar ao valor%') AS vagas,
  max(valor_hoje)     FILTER (WHERE coluna = 'vagas' AND regra LIKE 'voltar ao valor%') AS vagas_hoje,
  max(valor_proposto) FILTER (WHERE coluna = 'imovel_privado.unidade') AS unidade,
  max(valor_proposto) FILTER (WHERE coluna = 'imovel_privado.torre') AS torre
  FROM plano GROUP BY codigo;

-- 1a) endereço, vagas: uma passada só
UPDATE imoveis i SET
  logradouro = CASE WHEN pv.rua IS NOT NULL AND btrim(i.logradouro) = btrim(pv.rua_hoje) THEN pv.rua ELSE i.logradouro END,
  cidade = CASE WHEN pv.cidade IS NOT NULL AND NULLIF(btrim(i.cidade), '') IS NULL THEN pv.cidade ELSE i.cidade END,
  estado = CASE WHEN pv.estado IS NOT NULL AND NULLIF(btrim(i.estado), '') IS NULL THEN pv.estado ELSE i.estado END,
  bairro = CASE WHEN pv.bairro IS NOT NULL AND NULLIF(btrim(i.bairro), '') IS NULL THEN pv.bairro ELSE i.bairro END,
  -- o número da CASA de rua não: vai para o privado, logo abaixo
  numero = CASE WHEN pv.numero IS NOT NULL AND NULLIF(btrim(i.numero), '') IS NULL AND coalesce(i.tipo, '') <> 'Casa'
                THEN pv.numero ELSE i.numero END,
  vagas_cobertas = CASE WHEN pv.vagas_cobertas IS NOT NULL AND i.vagas_cobertas IS NULL
                        THEN NULLIF(btrim(pv.vagas_cobertas), '')::numeric::int ELSE i.vagas_cobertas END,
  vagas = CASE WHEN pv.vagas IS NOT NULL AND i.vagas::text = pv.vagas_hoje
               THEN NULLIF(btrim(pv.vagas), '')::numeric::int ELSE i.vagas END
  FROM pv
 WHERE pv.codigo = i.codigo
   AND ( (pv.rua IS NOT NULL AND btrim(i.logradouro) = btrim(pv.rua_hoje))
      OR (pv.cidade IS NOT NULL AND NULLIF(btrim(i.cidade), '') IS NULL)
      OR (pv.estado IS NOT NULL AND NULLIF(btrim(i.estado), '') IS NULL)
      OR (pv.bairro IS NOT NULL AND NULLIF(btrim(i.bairro), '') IS NULL)
      OR (pv.numero IS NOT NULL AND NULLIF(btrim(i.numero), '') IS NULL AND coalesce(i.tipo, '') <> 'Casa')
      OR (pv.vagas_cobertas IS NOT NULL AND i.vagas_cobertas IS NULL)
      OR (pv.vagas IS NOT NULL AND i.vagas::text = pv.vagas_hoje));

-- 1b) apartamento, torre e o número da casa de rua -> imovel_privado (só onde vazio)
INSERT INTO imovel_privado (codigo, unidade, torre, casa)
SELECT pv.codigo, NULLIF(btrim(pv.unidade), ''), NULLIF(btrim(pv.torre), ''),
       CASE WHEN pv.numero_casa IS NOT NULL THEN NULLIF(btrim(pv.numero_casa), '')
            WHEN coalesce(i.tipo, '') = 'Casa' THEN NULLIF(btrim(pv.numero), '') END
  FROM pv JOIN imoveis i ON i.codigo = pv.codigo
 WHERE coalesce(NULLIF(btrim(pv.unidade), ''), NULLIF(btrim(pv.torre), ''), NULLIF(btrim(pv.numero_casa), ''),
                CASE WHEN coalesce(i.tipo, '') = 'Casa' THEN NULLIF(btrim(pv.numero), '') END) IS NOT NULL
ON CONFLICT (codigo) DO UPDATE SET
  unidade = coalesce(NULLIF(btrim(imovel_privado.unidade), ''), EXCLUDED.unidade),
  torre   = coalesce(NULLIF(btrim(imovel_privado.torre), ''), EXCLUDED.torre),
  casa    = coalesce(NULLIF(btrim(imovel_privado.casa), ''), EXCLUDED.casa);

-- 2) a ficha do admin antigo (08/09) e o extras da raspagem: o que ainda falta
-- 2a) a unidade
INSERT INTO imovel_privado (codigo, unidade, torre, bloco, casa, lote)
SELECT codigo, unidade, torre, bloco, casa, lote FROM (
  SELECT i.codigo,
         coalesce(NULLIF(btrim(d.apartamento), ''), NULLIF(btrim(i.extras->>'apartamento'), '')) AS unidade,
         coalesce(NULLIF(btrim(d.torre), ''), NULLIF(btrim(i.extras->>'torre'), '')) AS torre,
         coalesce(NULLIF(btrim(d.bloco), ''), NULLIF(btrim(i.extras->>'bloco'), '')) AS bloco,
         coalesce(NULLIF(btrim(d.casa), ''), NULLIF(btrim(i.extras->>'casa'), '')) AS casa,
         NULLIF(btrim(i.extras->>'numero do lote'), '') AS lote
    FROM imoveis i LEFT JOIN imoveis_admin_detalhe d ON d.codigo = i.codigo::text) f
 WHERE coalesce(unidade, torre, bloco, casa, lote) IS NOT NULL
ON CONFLICT (codigo) DO UPDATE SET
  unidade = coalesce(NULLIF(btrim(imovel_privado.unidade), ''), EXCLUDED.unidade),
  torre   = coalesce(NULLIF(btrim(imovel_privado.torre), ''), EXCLUDED.torre),
  bloco   = coalesce(NULLIF(btrim(imovel_privado.bloco), ''), EXCLUDED.bloco),
  casa    = coalesce(NULLIF(btrim(imovel_privado.casa), ''), EXCLUDED.casa),
  lote    = coalesce(NULLIF(btrim(imovel_privado.lote), ''), EXCLUDED.lote);

-- 2b) o locatário e as observações (dado de pessoa: schema privado)
INSERT INTO privado.imovel_ficha (codigo, locatario_nome, locatario_contato, observacao_aluguel, observacoes)
SELECT i.codigo, NULLIF(btrim(d.locatario_nome), ''), NULLIF(btrim(d.locatario_contato), ''),
       NULLIF(btrim(d.observacao_aluguel), ''), NULLIF(btrim(d.observacoes), '')
  FROM imoveis i JOIN imoveis_admin_detalhe d ON d.codigo = i.codigo::text
 WHERE coalesce(NULLIF(btrim(d.locatario_nome), ''), NULLIF(btrim(d.locatario_contato), ''),
                NULLIF(btrim(d.observacao_aluguel), ''), NULLIF(btrim(d.observacoes), '')) IS NOT NULL
ON CONFLICT (codigo) DO NOTHING;

-- 2c) as colunas vazias e as chaves do site antigo que o extras não tem
CREATE TEMP TABLE novo_admin ON COMMIT DROP AS
SELECT i.codigo,
  coalesce(NULLIF(btrim(i.sol), ''), NULLIF(btrim(d.sol), '')) AS sol,
  coalesce(NULLIF(btrim(i.andar), ''), NULLIF(btrim(d.andar), '')) AS andar,
  coalesce(NULLIF(btrim(i.cep), ''), NULLIF(btrim(d.cep), '')) AS cep,
  coalesce(i.taxa_condominio, NULLIF(d.taxa_condominio, 0)) AS taxa_condominio,
  coalesce(i.iptu, NULLIF(d.iptu, 0)) AS iptu,
  coalesce(i.vagas_cobertas, d.vagas_cobertas) AS vagas_cobertas,
  CASE WHEN coalesce(cardinality(i.caracteristicas), 0) = 0 AND NULLIF(btrim(d.caracteristicas), '') IS NOT NULL
       THEN ARRAY(SELECT c FROM (SELECT btrim(x) AS c, min(n) AS n
                                   FROM unnest(string_to_array(d.caracteristicas, ',')) WITH ORDINALITY u(x, n)
                                  WHERE btrim(x) <> '' GROUP BY btrim(x)) s ORDER BY n)
       ELSE i.caracteristicas END AS caracteristicas,
  coalesce(NULLIF(btrim(i.captado_em), ''), to_char(d.captado_em, 'DD/MM/YYYY')) AS captado_em,
  coalesce(i.extras, '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
    'aceita financiamento', CASE WHEN NULLIF(btrim(i.extras->>'aceita financiamento'), '') IS NULL THEN NULLIF(btrim(d.financiamento), '') END,
    'incluso no aluguel',   CASE WHEN NULLIF(btrim(i.extras->>'incluso no aluguel'), '') IS NULL THEN NULLIF(btrim(d.incluso), '') END,
    'garantia de aluguel',  CASE WHEN NULLIF(btrim(i.extras->>'garantia de aluguel'), '') IS NULL
                                 THEN (SELECT string_agg(g, ', ' ORDER BY n) FROM (
                                         SELECT btrim(x) AS g, min(n) AS n
                                           FROM unnest(string_to_array(d.garantia, ',')) WITH ORDINALITY u(x, n)
                                          WHERE btrim(x) <> '' GROUP BY btrim(x)) s) END,
    'area construida',      CASE WHEN NULLIF(btrim(i.extras->>'area construida'), '') IS NULL AND d.area_construida > 0
                                 THEN trim_scale(d.area_construida)::text || ' m2' END,
    'tamanho do terreno',   CASE WHEN NULLIF(btrim(i.extras->>'tamanho do terreno'), '') IS NULL AND d.terreno > 0
                                 THEN trim_scale(d.terreno)::text || ' m2' END,
    'lances de escada',     CASE WHEN NULLIF(btrim(i.extras->>'lances de escada'), '') IS NULL THEN d.lances_escada::text END,
    'inspecionado por',     CASE WHEN NULLIF(btrim(i.extras->>'inspecionado por'), '') IS NULL THEN NULLIF(btrim(d.inspecionado_por), '') END
  )) AS extras
  FROM imoveis i JOIN imoveis_admin_detalhe d ON d.codigo = i.codigo::text;

UPDATE imoveis i SET
  sol = n.sol, andar = n.andar, cep = n.cep, taxa_condominio = n.taxa_condominio, iptu = n.iptu,
  vagas_cobertas = n.vagas_cobertas, caracteristicas = n.caracteristicas, captado_em = n.captado_em, extras = n.extras
  FROM novo_admin n
 WHERE n.codigo = i.codigo
   AND (i.sol, i.andar, i.cep, i.taxa_condominio, i.iptu, i.vagas_cobertas, i.caracteristicas, i.captado_em, i.extras)
       IS DISTINCT FROM
       (n.sol, n.andar, n.cep, n.taxa_condominio, n.iptu, n.vagas_cobertas, n.caracteristicas, n.captado_em, n.extras);

-- 3) a situação que o Tel mandou pelo WhatsApp
UPDATE imoveis SET status = 'Alugado', disponivel = false, publicado_no_site = false
 WHERE codigo IN (1850, 2943, 5374) AND status = 'Disponível';
-- o gatilho enfileirou o aviso no grupo Easy: 2943 e 5374 já foram avisados
-- lá; o 1850 espera a decisão do Pedro (para mandar: avisado_em = NULL)
UPDATE aviso_de_saida
   SET avisado_em = now(),
       motivo = CASE codigo WHEN '1850' THEN 'Alugado (Tel, 09/09) -- aviso segurado na 158, esperando o Pedro'
                            ELSE 'Alugado (Tel pelo WhatsApp) -- já avisado no grupo Easy' END
 WHERE codigo IN ('1850', '2943', '5374') AND avisado_em IS NULL;

-- 4) o que mudou
\echo '== colunas mudadas (imoveis)'
SELECT count(*) FILTER (WHERE a.logradouro IS DISTINCT FROM i.logradouro) AS rua,
       count(*) FILTER (WHERE a.numero IS DISTINCT FROM i.numero) AS numero,
       count(*) FILTER (WHERE a.bairro IS DISTINCT FROM i.bairro) AS bairro,
       count(*) FILTER (WHERE a.cidade IS DISTINCT FROM i.cidade) AS cidade,
       count(*) FILTER (WHERE a.estado IS DISTINCT FROM i.estado) AS estado,
       count(*) FILTER (WHERE a.cep IS DISTINCT FROM i.cep) AS cep,
       count(*) FILTER (WHERE a.vagas IS DISTINCT FROM i.vagas) AS vagas,
       count(*) FILTER (WHERE a.vagas_cobertas IS DISTINCT FROM i.vagas_cobertas) AS vagas_cob,
       count(*) FILTER (WHERE a.sol IS DISTINCT FROM i.sol) AS sol,
       count(*) FILTER (WHERE a.andar IS DISTINCT FROM i.andar) AS andar,
       count(*) FILTER (WHERE a.taxa_condominio IS DISTINCT FROM i.taxa_condominio) AS taxa,
       count(*) FILTER (WHERE a.iptu IS DISTINCT FROM i.iptu) AS iptu,
       count(*) FILTER (WHERE a.caracteristicas IS DISTINCT FROM i.caracteristicas) AS caract,
       count(*) FILTER (WHERE a.captado_em IS DISTINCT FROM i.captado_em) AS captado_em,
       count(*) FILTER (WHERE a.extras IS DISTINCT FROM i.extras) AS extras,
       count(*) FILTER (WHERE a.status IS DISTINCT FROM i.status) AS situacao
  FROM imoveis i JOIN privado.imoveis_antes_158 a USING (codigo);
\echo '== chaves novas no extras'
SELECT k, count(*) FROM imoveis i JOIN privado.imoveis_antes_158 a USING (codigo),
       jsonb_object_keys(i.extras) k
 WHERE NOT coalesce(a.extras, '{}'::jsonb) ? k GROUP BY 1 ORDER BY 2 DESC;
\echo '== a unidade (imovel_privado)'
SELECT (SELECT count(*) FROM imovel_privado) - (SELECT count(*) FROM privado.imovel_privado_antes_158) AS linhas_novas,
       count(*) FILTER (WHERE a.unidade IS DISTINCT FROM p.unidade) AS apartamento,
       count(*) FILTER (WHERE a.torre IS DISTINCT FROM p.torre) AS torre,
       count(*) FILTER (WHERE p.bloco IS NOT NULL) AS bloco,
       count(*) FILTER (WHERE p.casa IS NOT NULL) AS casa,
       count(*) FILTER (WHERE p.lote IS NOT NULL) AS lote
  FROM imovel_privado p LEFT JOIN privado.imovel_privado_antes_158 a USING (codigo);
\echo '== locatario e observacoes (privado.imovel_ficha)'
SELECT count(*) AS linhas, count(locatario_nome) AS locatario, count(locatario_contato) AS contato,
       count(observacoes) AS observacoes, count(observacao_aluguel) AS obs_aluguel FROM privado.imovel_ficha;
\echo '== na oferta (antes x depois)'
SELECT a.nossos_no_mercado AS nossos_antes,
       (SELECT count(*) FROM imoveis WHERE nay_esta_no_mercado(disponivel, bloqueado, publicado_no_site) AND NOT coalesce(e_parceiro, false)) AS nossos_depois,
       a.parceiros_no_mercado AS parceiros_antes,
       (SELECT count(*) FROM imoveis WHERE nay_esta_no_mercado(disponivel, bloqueado, publicado_no_site) AND coalesce(e_parceiro, false)) AS parceiros_depois
  FROM mercado_antes a;
\echo '== os tres e a fila de aviso'
SELECT i.codigo, i.status, i.disponivel, i.publicado_no_site, s.avisado_em IS NOT NULL AS aviso_segurado
  FROM imoveis i LEFT JOIN aviso_de_saida s ON s.codigo = i.codigo::text WHERE i.codigo IN (1850, 2943, 5374);
\echo '== conferencia: a casa de rua ficou sem numero publico'
SELECT count(*) AS casas_que_ganharam_numero_publico FROM imoveis i JOIN privado.imoveis_antes_158 a USING (codigo)
 WHERE i.tipo = 'Casa' AND a.numero IS DISTINCT FROM i.numero;

\if :{?ensaio}
  \echo '>>> ENSAIO: desfazendo tudo'
  ROLLBACK;
\else
  COMMIT;
\endif
