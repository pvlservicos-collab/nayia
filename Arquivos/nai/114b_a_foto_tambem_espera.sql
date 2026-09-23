-- =====================================================================
-- NAI -- 114b: a foto do segundo imovel tambem espera (23/09/2026)
--
-- ACHADO testando a fila da 114. Com dois imoveis pedidos, saiu assim:
--     ordem 3   card do Arezzo        13:30:54
--     ordem 4..18  15 fotos do Arezzo 13:30:54
--     ordem 19  card do Conquista     13:31:32   <- esperou, certo
--     ordem 20..33 14 fotos do Conq.  13:30:54   <- NAO esperou
--
-- O espacamento da 113 so mexia em TEXTO. As fotos do segundo imovel saiam
-- junto com as do primeiro, e chegariam antes do card que as explica.
--
-- Agora vale para tudo o que esta na caixa: cada mensagem -- texto ou foto --
-- espera as fotos que estao na frente dela. A ordem em que foi escrita e a
-- ordem em que chega.
--
-- E quando card e foto ficam marcados para o mesmo instante, o card chega
-- primeiro de qualquer jeito: texto vai na hora, foto tem que subir. E o que
-- desordenava antes agora ajuda.
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
  UPDATE nai_saida s
     SET enviar_apos = greatest(s.enviar_apos, now() + (v_seg * x.fotos_na_frente) * interval '1 second')
    FROM (SELECT a.id,
                 (SELECT count(*) FROM nai_saida b
                   WHERE b.turno_id = a.turno_id AND b.tipo = 'imagem' AND b.ordem < a.ordem) AS fotos_na_frente
            FROM nai_saida a
           WHERE a.turno_id = p_turno AND a.estado = 'pendente') x
   WHERE s.id = x.id AND x.fotos_na_frente > 0;
  GET DIAGNOSTICS n = ROW_COUNT;

  IF n > 0 THEN
    PERFORM nai_anotar(p_turno, 21, 'espera_as_fotos', 'mudou',
                       n || ' mensagens com hora marcada para depois das fotos da frente');
  END IF;
  RETURN n;
END;
$function$;

COMMIT;
