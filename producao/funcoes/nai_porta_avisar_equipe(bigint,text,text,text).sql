CREATE OR REPLACE FUNCTION public.nai_porta_avisar_equipe(p_contato bigint, p_papel text, p_motivo text, p_texto text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  v_tel  text;
  v_nome text;
  v_vis  text;
BEGIN
  IF p_papel <> 'corretor' OR p_motivo NOT IN ('visita_com_a_rayssa', 'visita_manual_com_a_rayssa', 'fechamento_com_a_rayssa')
     OR length(btrim(coalesce(p_texto, ''))) < 2
     OR lower(unaccent(btrim(p_texto))) ~ '^\W*(ok|okay|blz|beleza|obrigad[oa]|valeu|vlw|certo|sim|show|top|perfeito|combinado|ta bom|tudo bem|bom dia|boa tarde|boa noite)\W*$' THEN
    RETURN;
  END IF;
  SELECT regexp_replace(telefone, '\D', '', 'g'), coalesce(nullif(btrim(nome_completo), ''), nullif(btrim(nome_whatsapp), ''), 'Corretor')
    INTO v_tel, v_nome FROM nai_contato WHERE id = p_contato;
  IF EXISTS (SELECT 1 FROM aviso_equipe a WHERE a.fonte = 'porta' AND right(a.telefone, 8) = right(v_tel, 8)
               AND a.titulo LIKE '%escreveu durante%' AND a.criado_em > now() - interval '20 minutes') THEN
    RETURN;
  END IF;
  SELECT 'a visita #' || v.id || ' (' || nai_ref_imovel(v.codigo) || ', ' || nai_hora_exata(v.quando) || ')' INTO v_vis
    FROM nai_visita v WHERE v.corretor_id = ANY (coalesce(nai_contato_irmaos(p_contato), ARRAY[p_contato]))
     AND nai_visita_aberta(v.estado) ORDER BY v.atualizado_em DESC LIMIT 1;
  PERFORM nay_aviso_equipe('porta', 'escalada',
    v_nome || ' escreveu durante ' || CASE WHEN p_motivo LIKE 'fechamento%' THEN 'o fechamento' ELSE 'a visita' END || ' (Parceria)',
    v_nome || ' escreveu: "' || left(btrim(p_texto), 600) || '"' || E'\n'
    || 'A conversa está com a Rayssa' || coalesce(' por ' || v_vis, '') || ' e a Nay não responde. Responda pelo CRM.',
    v_tel);
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'nai_porta_avisar_equipe: %', SQLERRM;    -- a porta nunca cai por causa do aviso
END
$function$;
