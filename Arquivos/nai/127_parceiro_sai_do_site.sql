-- =====================================================================
-- 127 — PARCEIRO E INDISPONÍVEL SAEM DO SITE (27/09/2026)
--
-- Tel, perguntado com o número na frente: "tudo publicado mesmo sem fotos, a
-- diferença é que os de parceria e indisponivel ficam so dentro do admin" ->
-- e, confirmando, "tirar do site como você disse".
--
-- ISTO MUDA UMA REGRA ANTIGA DELE. Até hoje valia o contrário: imóvel de
-- parceiro ficava visível no site e só nunca era mandado pela Nay ("parceria
-- nunca sai: 908 imóveis de parceiro, SÓ NO SITE"). Agora parceiro existe só
-- dentro do admin. Perguntei antes justamente porque as duas regras se
-- contradiziam, e ele escolheu esta.
--
-- O QUE SAI DO AR: 574 anúncios -- 567 de parceiro e 11 que não estão
-- disponíveis. O site fica com 269, todos nossos e disponíveis.
--
-- A NAY NÃO MUDA. Ela já não via nenhum desses: parceiro é barrado no gatilho
-- da caixa de saída, e indisponível não passa por `nay_esta_no_mercado`.
-- Continua em 270, e a conta no fim prova.
--
-- DÁ PARA VOLTAR: `imoveis_despublicados_20260927` guarda o código de cada um
-- que saiu. Para reverter, é um UPDATE de volta a partir dela.
-- =====================================================================
\set ON_ERROR_STOP on

BEGIN;

-- Quem sai, guardado antes de sair
CREATE TABLE IF NOT EXISTS imoveis_despublicados_20260927 AS
SELECT i.codigo,
       coalesce(i.e_parceiro, false) AS era_parceiro_na_coluna,
       v.e_parceiro AS era_parceiro_na_visao,
       v.status,
       now() AS saiu_em
  FROM imoveis i
  JOIN vw_imoveis_todos v USING (codigo)
 WHERE i.publicado_no_site
   AND (v.e_parceiro OR v.status <> 'Disponível');

UPDATE imoveis i
   SET publicado_no_site = false, sincronizado_em = now()
 WHERE i.publicado_no_site
   AND i.codigo IN (SELECT codigo FROM imoveis_despublicados_20260927);

COMMIT;

\echo '=== quantos saíram, e por quê ==='
SELECT count(*) FILTER (WHERE era_parceiro_na_visao) AS de_parceiro,
       count(*) FILTER (WHERE NOT era_parceiro_na_visao) AS indisponiveis,
       count(*) AS total
  FROM imoveis_despublicados_20260927;

\echo '=== o site agora ==='
SELECT count(*) FILTER (WHERE publicado_no_site) AS no_site FROM imoveis;
SELECT count(*) AS no_site_e_de_parceiro
  FROM imoveis i JOIN vw_imoveis_todos v USING (codigo)
 WHERE i.publicado_no_site AND v.e_parceiro;

\echo '=== A NAY NÃO PODE TER MUDADO (tem de continuar 270) ==='
SELECT count(*) AS nay_ve FROM imoveis i
 WHERE nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
   AND NOT coalesce(i.e_parceiro, false);
