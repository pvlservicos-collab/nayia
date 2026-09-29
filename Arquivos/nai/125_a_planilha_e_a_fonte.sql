-- =====================================================================
-- 125 — A PLANILHA É A FONTE (26/09/2026)
--
-- Tel: "esse banco de dados vai ser o nosso permanente agora" e "quero que
-- importe os de todos os status pq vou querer filtrar eles la por imoveis
-- depois".
--
-- A importação gravou o status real de 5.664 imóveis em `imoveis.status`. Só
-- que a TELA não via isso: a `vw_imoveis_todos` montava o status por
-- adivinhação -- olhava se o imóvel estava publicado, e se não estivesse ia
-- catando em seis tabelas antigas (vendidos, arquivados, removidos,
-- rascunho, revisão, snapshot). Resultado: 307 imóveis que a planilha diz
-- DISPONÍVEL apareciam como "Fora do site", e 24 vendidos apareciam como
-- "Indisponível".
--
-- Aqui a planilha passa a mandar. E as duas coisas que estavam grudadas numa
-- só ficam separadas, como precisam ser:
--
--   SITUAÇÃO  -> Disponível, Alugado, Vendido, Removido, Arquivado...
--                é o que acontece com o imóvel no mundo.
--   ANÚNCIO   -> está no site ou não (`publicado_no_site`).
--                é decisão nossa, imóvel por imóvel.
--
-- Antes um imóvel disponível e fora do site virava "Fora do site" e perdia a
-- situação. Agora ele é "Disponível, não anunciado" -- que é a verdade.
--
-- NÃO MEXE em `e_parceiro`, `bloqueado` nem `publicado_no_site`: a regra de
-- nunca mandar imóvel de parceiro para a Nay continua exatamente onde está.
-- A conta no fim do arquivo prova isso.
-- =====================================================================
\set ON_ERROR_STOP on

BEGIN;

-- ---------------------------------------------------------------------
-- 1) O BAIRRO QUE O CONDOMÍNIO JÁ SABIA
--
-- A planilha veio com endereço e condomínio, sem bairro. 3.312 imóveis
-- ficaram sem bairro -- e sem bairro o filtro de localização não serve para
-- nada, que é justamente como o corretor procura.
--
-- O bairro vem do condomínio, casando pelo nome sem acento. É seguro: nenhum
-- nome de condomínio aparece em dois bairros diferentes (conferido antes).
-- Só preenche onde está vazio; bairro já escrito fica como está.
-- ---------------------------------------------------------------------
UPDATE imoveis i
   SET bairro = c.bairro
  FROM condominios c
 WHERE coalesce(i.bairro, '') = ''
   AND coalesce(c.bairro, '') <> ''
   AND lower(nay_sem_acento(c.nome)) = lower(nay_sem_acento(coalesce(i.condominio_nome, '')));

-- ---------------------------------------------------------------------
-- 2) A VISÃO QUE A TELA LÊ
--
-- `status` sai de `imoveis.status` (a planilha). Só cai na adivinhação antiga
-- quando a planilha não falou nada daquele código -- são 17 imóveis.
-- 'Revisão' virou 'Em revisão' porque é esse o nome que a tela usa.
--
-- É DROP e não CREATE OR REPLACE porque as colunas novas entram no meio da
-- lista, e o Postgres só deixa acrescentar no fim. Nada depende desta visão
-- (nenhuma outra visão, nenhuma função -- conferido), mas o DROP leva os
-- GRANT embora: por isso eles voltam logo abaixo, os mesmos dois que havia.
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS vw_imoveis_todos;
CREATE VIEW vw_imoveis_todos AS
WITH cods AS (
         SELECT codigo FROM imoveis
   UNION SELECT codigo::integer FROM imoveis_admin_snapshot WHERE codigo ~ '^[0-9]+$'
   UNION SELECT codigo::integer FROM imoveis_admin_detalhe  WHERE codigo ~ '^[0-9]+$'
   UNION SELECT codigo FROM imoveis_vendidos
   UNION SELECT codigo FROM imoveis_arquivados
   UNION SELECT codigo FROM imoveis_removidos
   UNION SELECT codigo FROM imoveis_rascunho
   UNION SELECT codigo FROM imoveis_revisao
), fot AS (
  SELECT codigo, count(*) AS n,
         min(url) FILTER (WHERE e_capa) AS capa_marcada,
         (array_agg(url ORDER BY ordem NULLS LAST, id))[1] AS primeira
    FROM imovel_fotos WHERE coalesce(url, '') <> '' GROUP BY codigo
)
SELECT c.codigo,
       -- a planilha primeiro; a adivinhação antiga só para quem ela não cita
       CASE
         WHEN i.status = 'Revisão' THEN 'Em revisão'
         WHEN coalesce(i.status, '') <> '' THEN i.status
         WHEN s.status_admin IS NOT NULL THEN s.status_admin
         WHEN v.codigo  IS NOT NULL THEN 'Vendido'
         WHEN a.codigo  IS NOT NULL THEN 'Arquivado'
         WHEN r.codigo  IS NOT NULL THEN 'Removido'
         WHEN ra.codigo IS NOT NULL THEN 'Rascunho'
         WHEN rv.codigo IS NOT NULL THEN 'Em revisão'
         WHEN i.codigo IS NOT NULL AND i.disponivel AND i.publicado_no_site THEN 'Disponível'
         WHEN i.codigo IS NOT NULL AND NOT coalesce(i.disponivel, true) THEN 'Indisponível'
         ELSE 'Fora do site'
       END AS status,
       i.codigo IS NOT NULL AS no_catalogo,
       coalesce(i.tipo, d.tipo) AS tipo,
       CASE
         WHEN coalesce(i.tipo, d.tipo) ~* '^(apartamento|cobertura|flat|kitnet|studio)' THEN 'apartamento'
         WHEN coalesce(i.tipo, d.tipo) ~* '^casa' THEN 'casa'
         WHEN coalesce(i.tipo, d.tipo) IS NULL THEN 'sem_tipo'
         ELSE 'outros'
       END AS grupo_tipo,
       coalesce(nullif(btrim(i.condominio_nome), ''), nullif(btrim(d.condominio), ''),
                nullif(btrim(coalesce(v.condominio, a.condominio, r.condominio, ra.condominio, rv.condominio)), '')) AS condominio,
       coalesce(i.condo_id, d.condominio_id) AS condo_id,
       coalesce(nullif(i.bairro, ''), nullif(d.bairro, '')) AS bairro,
       coalesce(nullif(concat_ws(', ', nullif(i.logradouro, ''), nullif(i.numero, '')), ''),
                nullif(concat_ws(', ', nullif(d.logradouro, ''), nullif(d.numero, '')), ''),
                coalesce(v.endereco, a.endereco, r.endereco, ra.endereco, rv.endereco)) AS endereco,
       coalesce(i.valor_venda, d.valor_venda) AS valor_venda,
       coalesce(i.valor_aluguel, d.valor_aluguel) AS valor_aluguel,
       coalesce(v.valor, a.valor, r.valor, ra.valor, rv.valor) AS valor_texto,
       coalesce(i.quartos, d.quartos) AS quartos,
       coalesce(i.vagas, d.vagas) AS vagas,
       coalesce(i.area_util, d.area) AS area,
       -- as colunas novas, o que a tela de imóveis passou a mostrar
       i.suites, i.banheiros, coalesce(i.area_total, i.area_util, d.area) AS area_total,
       coalesce(fot.n, 0) AS fotos,
       coalesce(fot.capa_marcada, fot.primeira) AS capa,
       coalesce(i.precisa_confirmacao, false) AS precisa_confirmacao,
       coalesce(i.e_parceiro, false)
         OR nai_dono_e_parceiro(coalesce(pn.nome, pa.nome, v.proprietario_nome, a.proprietario_nome,
                                         r.proprietario_nome, ra.proprietario_nome, rv.proprietario_nome)) AS e_parceiro,
       CASE
         WHEN coalesce(i.extras ->> 'aceita financiamento', d.financiamento, '') ~* '^s' THEN 'Sim'
         WHEN coalesce(i.extras ->> 'aceita financiamento', d.financiamento, '') ~* '^n' THEN 'Não'
         ELSE '—'
       END AS financia,
       coalesce(i.publicado_no_site, false) AS publicado_no_site,
       coalesce(i.bloqueado, false) AS bloqueado,
       ct.vencimento,
       -- o dono importado da planilha manda; o do admin antigo é o reserva
       coalesce(pn.nome, pa.nome, v.proprietario_nome, a.proprietario_nome,
                r.proprietario_nome, ra.proprietario_nome, rv.proprietario_nome) AS proprietario_nome,
       i.proprietario_id,
       coalesce(i.criado_em, d.captado_em::timestamptz, s.coletado_em, v.extraido_em,
                a.extraido_em, r.extraido_em, ra.extraido_em, rv.extraido_em) AS criado
  FROM cods c
  LEFT JOIN imoveis i                 ON i.codigo = c.codigo
  LEFT JOIN imoveis_admin_snapshot s  ON s.codigo = c.codigo::text
  LEFT JOIN imoveis_admin_detalhe d   ON d.codigo = c.codigo::text
  LEFT JOIN imoveis_vendidos v        ON v.codigo = c.codigo
  LEFT JOIN imoveis_arquivados a      ON a.codigo = c.codigo
  LEFT JOIN imoveis_removidos r       ON r.codigo = c.codigo
  LEFT JOIN imoveis_rascunho ra       ON ra.codigo = c.codigo
  LEFT JOIN imoveis_revisao rv        ON rv.codigo = c.codigo
  LEFT JOIN contratos_locacao ct      ON ct.codigo = c.codigo::text
  LEFT JOIN proprietarios_admin pa    ON pa.id = s.proprietario_id
  LEFT JOIN proprietarios pn          ON pn.id = i.proprietario_id
  LEFT JOIN fot                       ON fot.codigo = c.codigo;

-- os mesmos GRANT de antes do DROP
GRANT SELECT ON vw_imoveis_todos TO nay_leitura;
GRANT SELECT ON vw_imoveis_todos TO nay_site_leitura;

COMMIT;

\echo '=== bairro: quantos passaram a ter ==='
SELECT count(*) FILTER (WHERE coalesce(bairro, '') <> '') AS com_bairro, count(*) AS total FROM imoveis;

\echo '=== situação (a planilha) x anúncio (nossa decisão) ==='
SELECT status,
       count(*) AS imoveis,
       count(*) FILTER (WHERE publicado_no_site) AS no_site,
       count(*) FILTER (WHERE fotos > 0) AS com_foto
  FROM vw_imoveis_todos GROUP BY 1 ORDER BY 2 DESC;

\echo '=== A PAREDE DO PARCEIRO NÃO MUDOU (tem de continuar 259) ==='
SELECT count(*) AS a_nay_ve FROM imoveis i
 WHERE nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
   AND NOT coalesce(i.e_parceiro, false);
