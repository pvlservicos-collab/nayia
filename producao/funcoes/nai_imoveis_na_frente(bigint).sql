CREATE OR REPLACE FUNCTION public.nai_imoveis_na_frente(p_contato bigint)
 RETURNS integer[]
 LANGUAGE sql
 STABLE
AS $function$
  -- O ÚLTIMO LOTE de imóveis que a Nay pôs na conversa, nas últimas 2 horas:
  -- card ("Código: 5739"), lista ("*La Villette #5640*"), saída com código (sem
  -- contar as fotos: foto mandada não é oferta nova) e envio registrado. "Lote" é
  -- o que saiu junto: até 3 minutos antes do mais recente.
  WITH k AS (
    SELECT coalesce(nai_contato_irmaos(p_contato), ARRAY[p_contato]) AS ids,
           right(regexp_replace((SELECT telefone FROM nai_contato WHERE id = p_contato), '\D', '', 'g'), 8) AS fim8
  ),
  ev AS (
    SELECT s.criado_em AS em, s.codigo AS c
      FROM nai_saida s, k
     WHERE s.contato_id = ANY (k.ids) AND s.codigo IS NOT NULL AND s.tipo <> 'imagem'
       AND s.papel_destino <> 'tel' AND s.estado IN ('enviado', 'enviando', 'pendente', 'simulado')
       AND s.criado_em > now() - interval '2 hours'
    UNION ALL
    SELECT s.criado_em, m[1]::int
      FROM nai_saida s, k,
           regexp_matches(s.texto, '(?:C[óo]digo:\s*|\*[^*\n]{1,80}#)(\d{3,5})', 'gi') m
     WHERE s.contato_id = ANY (k.ids) AND s.tipo = 'texto' AND s.texto IS NOT NULL
       AND s.papel_destino <> 'tel' AND s.estado IN ('enviado', 'enviando', 'pendente', 'simulado')
       AND s.criado_em > now() - interval '2 hours'
    UNION ALL
    SELECT e.enviado_em, e.codigo::int
      FROM envios e, k
     WHERE k.fim8 <> '' AND right(regexp_replace(coalesce(e.telefone, ''), '\D', '', 'g'), 8) = k.fim8
       AND e.enviado_em > now() - interval '2 hours' AND e.codigo ~ '^[0-9]{3,5}$'
  )
  SELECT coalesce(array_agg(DISTINCT ev.c), '{}')
    FROM ev
   WHERE ev.em >= (SELECT max(em) FROM ev) - interval '3 minutes'
     AND EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = ev.c);
$function$;
