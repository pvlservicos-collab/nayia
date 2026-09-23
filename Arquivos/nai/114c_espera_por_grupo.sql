-- =====================================================================
-- NAI -- 114c: a espera e por IMOVEL, nao foto a foto (23/09/2026)
--
-- A 114b fez cada foto esperar as fotos da frente -- e ficou certo na ordem,
-- mas escalonado de 2,5 em 2,5 segundos. Como a agenda solta de minuto em
-- minuto, as fotos de um mesmo imovel cairiam em duas levas, com um buraco
-- de ate um minuto no meio. Ruim: parece que travou.
--
-- AGORA A CONTA E POR GRUPO. Grupo e o card e as fotos DELE. As fotos de um
-- imovel saem juntas; quem espera e o proximo grupo -- o card do segundo
-- imovel e as fotos dele -- e o fechamento, que espera todas.
--
--   card do Arezzo        agora
--   15 fotos do Arezzo    agora
--   card do Conquista     +37s   (15 fotos x 2,5)
--   14 fotos do Conquista +37s   (o card e texto: chega antes)
--   "Aqui as fotos..."    +72s   (as 29)
--
-- Card e foto marcados para o mesmo instante nao empatam: texto vai na hora,
-- foto tem que subir. O que desordenava antes agora poe na ordem.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION public.nai_espacar_depois_das_fotos(p_turno bigint)
 RETURNS integer LANGUAGE plpgsql
AS $function$
DECLARE
  v_seg numeric := coalesce(nullif(nai_cfg('segundos_por_foto', '2.5'), ''), '2.5')::numeric;
  n int := 0;
BEGIN
  WITH linhas AS (
    SELECT a.id, a.tipo, a.ordem,
           -- o grupo de cada linha: quantos TEXTOS vieram ate ela. O card
           -- abre o grupo, e as fotos dele ficam no mesmo numero.
           (SELECT count(*) FROM nai_saida b
             WHERE b.turno_id = a.turno_id AND b.tipo = 'texto' AND b.ordem <= a.ordem) AS grupo
      FROM nai_saida a
     WHERE a.turno_id = p_turno AND a.estado = 'pendente'
  ),
  espera AS (
    SELECT l.id,
           (SELECT count(*) FROM linhas f WHERE f.tipo = 'imagem' AND f.grupo < l.grupo) AS fotos_antes
      FROM linhas l
  )
  UPDATE nai_saida s
     SET enviar_apos = greatest(s.enviar_apos, now() + (v_seg * e.fotos_antes) * interval '1 second')
    FROM espera e
   WHERE s.id = e.id AND e.fotos_antes > 0;
  GET DIAGNOSTICS n = ROW_COUNT;

  IF n > 0 THEN
    PERFORM nai_anotar(p_turno, 21, 'espera_as_fotos', 'mudou',
                       n || ' mensagens esperando as fotos dos imóveis da frente');
  END IF;
  RETURN n;
END;
$function$;

COMMIT;
