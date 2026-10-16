CREATE OR REPLACE FUNCTION public.pergunta_fila_resposta_valida(p_contato bigint, p_texto text, p_citado text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
DECLARE v_tel bigint; s text; a text;
BEGIN
  IF p_contato IS NULL OR NOT pergunta_fila_ligada() THEN RETURN false; END IF;
  IF NOT EXISTS (SELECT 1 FROM pergunta_fila WHERE estado = 'perguntada') THEN RETURN false; END IF;
  SELECT id INTO v_tel FROM nai_contato WHERE chave = nai_chave(nai_cfg('tel_telefone')) LIMIT 1;
  IF v_tel IS NULL OR NOT (p_contato = v_tel OR p_contato = ANY (coalesce(nai_contato_irmaos(v_tel), '{}'))) THEN
    RETURN false;
  END IF;
  s := btrim(regexp_replace(coalesce(p_texto, ''), '^\s*@?nay[\s,:;.!-]*', '', 'i'));
  IF s = '' THEN RETURN false; END IF;
  -- marcou uma mensagem: só vale se for a pergunta (ou a cobrança) da fila
  IF nullif(btrim(coalesce(p_citado, '')), '') IS NOT NULL THEN
    RETURN EXISTS (SELECT 1 FROM nai_saida o WHERE o.message_id = btrim(p_citado)
                      AND o.motivo IN ('pergunta_fila', 'pergunta_fila_cobranca'));
  END IF;
  -- os outros comandos dele passam antes: a fila não engole comando
  IF nai_e_comando_tel(s) OR nai_e_comando_extra(s) OR nai_e_comando_envio(s) OR nai_e_comando_checklist(s)
     OR nai_e_pedido_lembrete(s) OR nay_saida_resposta_valida(p_contato, s, NULL)
     OR nai_resposta_aprovacao_valida(p_contato, s) THEN
    RETURN false;
  END IF;
  a := lower(unaccent(s));
  -- os do caminho antigo (RESPOSTA n, DESCARTA n, PENDENCIAS) e os do publicador (posta, vendeu, envia ... para)
  IF a ~ '^(resposta|responde|responder)( a)?( pendencias?)?\s+\d{1,6}\s'
     OR a ~ '^(descarta|descartar|descarte|esquece|esquecer|apaga|apagar|cancela|cancelar|ignora|ignorar)\s+(\d{1,6}|tudo)\M'
     OR a ~ '^(pendencias?|pendentes)\s*$'
     OR a ~ '^(posta|postar|publica|publicar|dispara|disparar|solta|tira|tirar|remove|remover|retira|retirar|vendeu|vendido|vendida|alugou|alugado|alugada|vagas?|lista)\M'
     OR a ~ '^(envi|m[a]?nd|repass|encaminh|mostr|post|public|dispar|solt)[a-z]*\M.*\m(para|pra|pro)\M'
     OR a ~ '^\d{3,5}\s*[-:,]?\s*(ja)?\s*(vendeu|vendido|vendida|alugou|alugado|alugada)\M' THEN
    RETURN false;
  END IF;
  -- cumprimento e "ok" não são resposta; anúncio colado (o publicador) também não
  IF a ~ '^(bom dia|boa tarde|boa noite|oi+|ola|opa|ok|okay|blz|beleza|obrigad[oa]|valeu|show|certo)[\s!.,]*$' THEN
    RETURN false;
  END IF;
  IF length(s) > 400 AND s ~* 'R\$\s*\d' THEN RETURN false; END IF;
  RETURN true;
END
$function$;
