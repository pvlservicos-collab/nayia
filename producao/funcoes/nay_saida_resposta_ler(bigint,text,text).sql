CREATE OR REPLACE FUNCTION public.nay_saida_resposta_ler(p_contato bigint, p_texto text, p_citado text DEFAULT NULL::text)
 RETURNS TABLE(resposta text, ids bigint[], sem_pergunta text[])
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  s        text;
  v_resp   text;
  v_cods   text[];
  v_todos  boolean;
  v_irmaos bigint[];
  v_ids    bigint[];
  v_sem    text[] := '{}';
  v_saida  bigint;
  v_val    interval := make_interval(hours => greatest(nai_cfg_int('aviso_saida_validade_h', 24), 1));
  -- a primeira palavra decide; o resto só pode ser enfeite da mesma resposta, "todos" ou código
  c_sim    CONSTANT text := 'sim|s|ss|pode|avisa|avise|avisar|manda|mande|mandar|dispara|dispare|disparar|confirmo|confirmado';
  c_sim_r  CONSTANT text := 'sim|pode|avisa|avise|avisar|manda|mande|mandar|dispara|dispare|disparar|ai|la|no|na|o|a|os|as|e|do|da|de|grupo|easy|todos|todas|tudo|dois|duas|[0-9]{3,5}';
  c_nao    CONSTANT text := 'nao|n|nn|negativo|deixa|nem';
  c_nao_r  CONSTANT text := 'nao|deixa|precisa|avisa|avise|avisar|manda|mande|mandar|dispara|dispare|disparar|quieto|pra|la|assim|no|na|o|a|os|as|e|do|da|de|grupo|easy|nenhum|nenhuma|todos|todas|tudo|dois|duas|[0-9]{3,5}';
BEGIN
  IF p_contato IS NULL OR lower(coalesce(nai_cfg('aviso_saida_pergunta', 'sim'), 'sim')) <> 'sim' THEN RETURN; END IF;

  s := regexp_replace(lower(unaccent(coalesce(p_texto, ''))), '^\s*@?nay\M[\s,:;.!-]*', '');
  s := btrim(regexp_replace(s, '[^a-z0-9]+', ' ', 'g'));
  IF s = '' OR length(s) > 60 THEN RETURN; END IF;
  IF s ~ ('^(' || c_sim || ')( (' || c_sim_r || '))*$') THEN
    v_resp := 'sim';
  ELSIF s ~ ('^(' || c_nao || ')( (' || c_nao_r || '))*$') THEN
    v_resp := 'nao';
  ELSE
    RETURN;
  END IF;

  v_irmaos := coalesce(nai_contato_irmaos(p_contato), ARRAY[p_contato]);
  v_cods   := ARRAY(SELECT DISTINCT (m.x)[1] FROM regexp_matches(s, '\m([0-9]{3,5})\M', 'g') AS m(x));
  v_todos  := s ~ '\m(todos|todas|tudo|dois|duas|nenhum|nenhuma)\M';

  IF cardinality(v_cods) > 0 THEN
    -- "SIM 3097": pelo código, a pergunta desta saída (vale mudar de ideia depois do NÃO, até 7 dias).
    -- Um número só, que também é visita esperando aprovação: é da visita (141), não daqui.
    IF cardinality(v_cods) = 1 AND EXISTS (SELECT 1 FROM nai_visita x
                                            WHERE x.id = v_cods[1]::bigint AND x.estado = 'aguardando_rayssa') THEN
      RETURN;
    END IF;
    SELECT array_agg(x.id ORDER BY x.id) INTO v_ids
      FROM (SELECT DISTINCT ON (q.codigo) q.id
              FROM aviso_de_saida_pergunta q
              JOIN aviso_de_saida a ON a.codigo = q.codigo AND a.marcado_em = q.marcado_em
             WHERE q.contato_id = ANY (v_irmaos) AND q.codigo = ANY (v_cods)
               AND a.avisado_em IS NULL AND q.perguntado_em > now() - interval '7 days'
             ORDER BY q.codigo, q.id DESC) x;
    IF v_ids IS NULL THEN RETURN; END IF;
    v_sem := ARRAY(SELECT c FROM unnest(v_cods) c
                    WHERE NOT EXISTS (SELECT 1 FROM aviso_de_saida_pergunta q WHERE q.id = ANY (v_ids) AND q.codigo = c)
                    ORDER BY c);
  ELSIF nullif(btrim(coalesce(p_citado, '')), '') IS NOT NULL THEN
    -- marcou uma mensagem: só vale se for a pergunta. Marcou outra coisa, a resposta é para outra coisa.
    SELECT o.id INTO v_saida FROM nai_saida o
     WHERE o.message_id = btrim(p_citado) AND o.motivo = 'aviso_saida_pergunta' LIMIT 1;
    IF v_saida IS NULL THEN RETURN; END IF;
    SELECT array_agg(q.id ORDER BY q.id) INTO v_ids
      FROM aviso_de_saida_pergunta q
      JOIN aviso_de_saida a ON a.codigo = q.codigo AND a.marcado_em = q.marcado_em
     WHERE q.saida_id = v_saida AND q.contato_id = ANY (v_irmaos) AND a.avisado_em IS NULL;
  ELSE
    -- sem código e sem marcar: as perguntas ainda abertas. "todos" pega todas; solto, só a ÚLTIMA mensagem.
    SELECT array_agg(y.id ORDER BY y.id) INTO v_ids
      FROM (SELECT q.id, dense_rank() OVER (ORDER BY q.perguntado_em DESC, coalesce(q.saida_id, 0) DESC) AS ordem
              FROM aviso_de_saida_pergunta q
              JOIN aviso_de_saida a ON a.codigo = q.codigo AND a.marcado_em = q.marcado_em
             WHERE q.contato_id = ANY (v_irmaos) AND q.resposta IS NULL
               AND a.avisado_em IS NULL AND q.perguntado_em > now() - v_val) y
     WHERE v_todos OR y.ordem = 1;
  END IF;

  IF v_ids IS NULL THEN RETURN; END IF;
  RETURN QUERY SELECT v_resp, v_ids, v_sem;
END
$function$;
