-- 292 (05/10/2026, Pedro): "ela precisa identificar os imóveis que já mandou para cada corretor
-- para não mandar de novo, inclusive põe isso como um campo lá no card da conversa do corretor,
-- imóveis já enviados."
--
-- A Nay nova já não reenvia (nay-core 846067b: o imóvel que saiu para a pessoa só vai de novo se
-- ela disser que tem interesse, sem prazo). Esta função é o mesmo fato para a tela: os imóveis
-- que já saíram para a pessoa, por qualquer caminho, um por linha, do mais recente para o mais
-- antigo.
--   envios                  o publicador (o Tel mandando pelo comando), fora os posts de grupo
--   imovel_enviado_no_dia   a marca da Nay velha e do publicador (desde 27/09)
--   core_saida              a Nay nova: card e fotos que saíram de verdade
-- `dias` = em quantos dias diferentes (de Manaus) o imóvel saiu para a pessoa: 2 ou mais é
-- imóvel repetido. O histórico "O que já pediu, recebeu e visitou" do card (crm_contato_historico)
-- só lê `envios`; por isso o que a Nay mandava não aparecia lá como recebido.
--
-- Só leitura. O CRM chama pelo papel nay_disparo, que só enxerga funções: SECURITY DEFINER.
BEGIN;

CREATE OR REPLACE FUNCTION public.crm_imoveis_enviados(p_telefone text)
 RETURNS TABLE(codigo integer, imovel text, ultimo_em timestamp with time zone, primeiro_em timestamp with time zone, dias integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
  WITH p AS MATERIALIZED (SELECT * FROM crm_pessoas(ARRAY[p_telefone])),
  saiu AS (
    SELECT nullif(regexp_replace(coalesce(e.codigo, ''), '\D', '', 'g'), '')::int AS codigo, e.enviado_em AS em
      FROM envios e, p
     WHERE e.destino IS DISTINCT FROM 'grupo' AND nai_chave(e.telefone) = ANY (p.chaves)
    UNION ALL
    SELECT d.codigo, d.primeiro_em FROM imovel_enviado_no_dia d, p WHERE d.chave = ANY (p.chaves)
    UNION ALL
    SELECT s.codigo, coalesce(s.enviado_em, s.criado_em)
      FROM core_saida s, p
     WHERE s.chave_destino = ANY (p.chaves) AND s.codigo IS NOT NULL AND s.motivo IN ('card', 'foto')
       AND s.papel_destino = 'turno' AND s.estado = 'enviado'
  )
  SELECT x.codigo, nai_ref_imovel(x.codigo), max(x.em), min(x.em),
         count(DISTINCT (x.em AT TIME ZONE 'America/Manaus')::date)::int
    FROM saiu x
   WHERE x.codigo IS NOT NULL AND x.em IS NOT NULL
   GROUP BY x.codigo
   ORDER BY max(x.em) DESC
   LIMIT 80
$function$;

REVOKE ALL ON FUNCTION public.crm_imoveis_enviados(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crm_imoveis_enviados(text) TO nay_disparo;

COMMIT;
