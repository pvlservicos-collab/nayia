CREATE OR REPLACE FUNCTION public.captacao_vigiar_rodar()
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_pct   int := COALESCE((SELECT NULLIF(btrim(valor), '')::int FROM captacao_config WHERE chave = 'disjuntor_resposta_min'), 20);
  v_max   int := COALESCE((SELECT NULLIF(btrim(valor), '')::int FROM captacao_config WHERE chave = 'disjuntor_sem_entrega'), 5);
  v_n     int;
  v_resp  int;
  v_sem   int;
  v_vistos int;
  v_motivo text;
BEGIN
  IF COALESCE((SELECT valor FROM captacao_config WHERE chave = 'captacao_pausada'), 'sim') <> 'nao' THEN
    RETURN NULL;
  END IF;

  -- a) RESPOSTA: o sinal de 16/09
  SELECT count(*),
         count(*) FILTER (WHERE EXISTS (SELECT 1 FROM captacao_mensagens r
                                         WHERE r.lead_id = d.lead_id AND r.direcao = 'recebida'
                                           AND r.criada_em > d.criada_em))
    INTO v_n, v_resp
    FROM (SELECT m.lead_id, m.criada_em FROM captacao_mensagens m
           WHERE m.direcao = 'enviada' AND m.origem = 'disparo' AND m.status = 'Enviado'
             AND m.criada_em BETWEEN now() - interval '48 hours' AND now() - interval '3 hours'
           ORDER BY m.criada_em DESC LIMIT 10) d;
  IF v_n >= 10 AND v_resp * 100 < v_pct * v_n THEN
    v_motivo := format('só %s dos últimos %s disparos tiveram resposta (mínimo %s%%) -- sinal de número restrito, como em 16/09',
                       v_resp, v_n, v_pct);
  END IF;

  -- b) ENTREGA: só vale com o aviso de entrega da Z-API chegando (webhook de status)
  IF v_motivo IS NULL AND EXISTS (SELECT 1 FROM captacao_mensagens WHERE entregue_em > now() - interval '7 days') THEN
    SELECT count(*) FILTER (WHERE u.entregue_em IS NULL), count(*)
      INTO v_sem, v_vistos
      FROM (SELECT m.entregue_em FROM captacao_mensagens m
             WHERE m.direcao = 'enviada' AND m.origem = 'disparo' AND m.status = 'Enviado'
               AND m.message_id IS NOT NULL
               AND m.criada_em BETWEEN now() - interval '48 hours' AND now() - interval '30 minutes'
             ORDER BY m.criada_em DESC LIMIT v_max) u;
    IF v_vistos >= v_max AND v_sem = v_vistos THEN
      v_motivo := format('os últimos %s disparos não foram entregues (30 min depois) -- sinal de número restrito', v_sem);
    END IF;
  END IF;

  IF v_motivo IS NULL THEN
    RETURN NULL;
  END IF;
  PERFORM captacao_desarmar(v_motivo);
  RETURN v_motivo;
END $function$;
