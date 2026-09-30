CREATE OR REPLACE FUNCTION public.nai_estado_gravar_v2(p_contato bigint, p_foco integer DEFAULT NULL::integer, p_foco_origem text DEFAULT NULL::text, p_mostrados integer[] DEFAULT '{}'::integer[], p_rejeitados integer[] DEFAULT '{}'::integer[], p_fala_dela text DEFAULT NULL::text, p_papel text DEFAULT NULL::text, p_visita bigint DEFAULT NULL::bigint)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- CODIGO QUE NAO EXISTE NAO VIRA FOCO (140, 28/09/2026). O modelo cita
  -- numero que nao e imovel nosso, e o INSERT abaixo estourava a chave
  -- estrangeira de `codigo_foco` -- derrubando o "Enfileirar resposta"
  -- inteiro: 12 respostas perdidas em 27-28/09, a do Walter (Acquarelle,
  -- 09:28) e a da Magna ("Rio negro", 07:05) entre elas.
  IF p_foco IS NOT NULL AND NOT EXISTS (SELECT 1 FROM imoveis WHERE codigo = p_foco) THEN
    p_foco := NULL;
  END IF;
  IF p_visita IS NOT NULL AND NOT EXISTS (SELECT 1 FROM nai_visita WHERE id = p_visita) THEN
    p_visita := NULL;
  END IF;
  p_mostrados  := ARRAY(SELECT x FROM unnest(coalesce(p_mostrados, '{}')) x WHERE EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = x));
  p_rejeitados := ARRAY(SELECT x FROM unnest(coalesce(p_rejeitados, '{}')) x WHERE EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = x));

  INSERT INTO nai_estado_conversa AS e (contato_id, codigo_foco, foco_desde, foco_origem,
                                        codigos_mostrados, codigos_rejeitados,
                                        ultima_fala_dela, ultima_fala_em, papel, visita_pendente)
  VALUES (p_contato, p_foco, CASE WHEN p_foco IS NOT NULL THEN now() END, p_foco_origem,
          coalesce(p_mostrados,'{}'), coalesce(p_rejeitados,'{}'),
          p_fala_dela, CASE WHEN p_fala_dela IS NOT NULL THEN now() END, p_papel, p_visita)
  ON CONFLICT (contato_id) DO UPDATE SET
    -- o foco so muda quando chega um foco novo; NULL nao apaga o que havia
    codigo_foco = coalesce(EXCLUDED.codigo_foco, e.codigo_foco),
    foco_desde  = CASE WHEN EXCLUDED.codigo_foco IS DISTINCT FROM e.codigo_foco
                         AND EXCLUDED.codigo_foco IS NOT NULL THEN now() ELSE e.foco_desde END,
    foco_origem = coalesce(EXCLUDED.foco_origem, e.foco_origem),
    -- somar sem repetir
    codigos_mostrados = ARRAY(SELECT DISTINCT unnest(e.codigos_mostrados || EXCLUDED.codigos_mostrados)),
    codigos_rejeitados = ARRAY(SELECT DISTINCT unnest(e.codigos_rejeitados || EXCLUDED.codigos_rejeitados)),
    ultima_fala_dela = coalesce(EXCLUDED.ultima_fala_dela, e.ultima_fala_dela),
    ultima_fala_em   = coalesce(EXCLUDED.ultima_fala_em, e.ultima_fala_em),
    papel            = coalesce(EXCLUDED.papel, e.papel),
    visita_pendente  = coalesce(EXCLUDED.visita_pendente, e.visita_pendente),
    atualizado_em    = now();

  -- REJEITAR TIRA DO FOCO. Sem isto, o imovel recusado continua sendo "o
  -- imovel da conversa" e volta na resposta seguinte -- que e exatamente
  -- o erro relatado.
  UPDATE nai_estado_conversa
     SET codigo_foco = NULL, foco_origem = NULL
   WHERE contato_id = p_contato
     AND codigo_foco = ANY (coalesce(p_rejeitados, '{}'));
-- ANOTAR O ESTADO NUNCA DERRUBA A RESPOSTA (140): isto e memoria auxiliar.
-- Falhou, fica o aviso no log do banco e a mensagem segue.
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'nai_estado_gravar_v2 (contato %): %', p_contato, SQLERRM;
END;
$function$
;
