CREATE OR REPLACE FUNCTION public.nai_trilha(p_turno bigint)
 RETURNS TABLE(setor text, setor_ordem integer, passo integer, etapa text, resultado text, ms integer, detalhe text, entrada jsonb, saida jsonb, quando timestamp with time zone)
 LANGUAGE sql
 STABLE
AS $function$
  WITH tudo AS (
    -- as etapas novas
    SELECT e.setor,
           e.seq                  AS passo,
           e.etapa,
           e.resultado,
           e.ms,
           e.detalhe,
           e.entrada,
           e.saida,
           e.criado_em            AS quando,
           e.id                   AS desempate
      FROM nai_evento e
     WHERE e.turno_id = p_turno

    UNION ALL

    -- AS ETAPAS QUE RODARAM ANTES DO TURNO EXISTIR.
    -- O webhook e a porta acontecem antes de `nai_abrir_turno`, então não têm
    -- turno para apontar -- e sem este trecho o setor "Entrada" apareceria
    -- SEMPRE VAZIO no painel, que é justamente a primeira coisa que alguém
    -- abre quando a Nay não respondeu. O fio é o `exec_id` do n8n.
    SELECT e.setor,
           e.seq                  AS passo,
           e.etapa,
           e.resultado,
           e.ms,
           e.detalhe,
           e.entrada,
           e.saida,
           e.criado_em            AS quando,
           e.id                   AS desempate
      FROM nai_evento e
     WHERE e.turno_id IS NULL
       AND e.exec_id IS NOT NULL
       AND e.exec_id = (SELECT t.exec_id FROM nai_turno t WHERE t.id = p_turno)

    UNION ALL

    -- a esteira que ja existia (arquivo 15)
    SELECT 'conferencia'          AS setor,
           c.ordem                AS passo,
           c.etapa,
           CASE c.resultado WHEN 'passou' THEN 'ok' ELSE c.resultado END AS resultado,
           NULL::int              AS ms,
           c.detalhe,
           NULL::jsonb            AS entrada,
           NULL::jsonb            AS saida,
           c.criado_em            AS quando,
           c.id                   AS desempate
      FROM nai_conferencia c
     WHERE c.turno_id = p_turno

    UNION ALL

    -- o que saiu (ou nao saiu)
    SELECT 'saida'                AS setor,
           s.ordem                AS passo,
           s.tipo || coalesce(' · ' || s.motivo, '') AS etapa,
           CASE s.estado
             WHEN 'bloqueado' THEN 'parou'
             WHEN 'erro'      THEN 'erro'
             ELSE 'ok' END       AS resultado,
           NULL::int              AS ms,
           CASE WHEN s.estado = 'bloqueado'
                THEN 'BARRADA: ' || coalesce(s.bloqueio, 'sem motivo gravado')
                ELSE s.estado || coalesce(' · imovel ' || s.codigo, '') END AS detalhe,
           NULL::jsonb            AS entrada,
           jsonb_build_object('texto', s.texto, 'imagem', s.imagem_url,
                              'estado', s.estado, 'destino', s.papel_destino) AS saida,
           coalesce(s.enviado_em, s.criado_em) AS quando,
           s.id                   AS desempate
      FROM nai_saida s
     WHERE s.turno_id = p_turno
  )
  SELECT t.setor,
         nai_setor_ordem(t.setor) AS setor_ordem,
         t.passo,
         t.etapa,
         t.resultado,
         t.ms,
         t.detalhe,
         nai_mascarar(t.entrada),
         nai_mascarar(t.saida),
         t.quando
    FROM tudo t
   ORDER BY nai_setor_ordem(t.setor), t.passo, t.desempate;
$function$
;
