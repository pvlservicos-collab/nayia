CREATE OR REPLACE FUNCTION public.nay_cobrar_escaladas()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
-- A conversa que o núcleo escalou (nai_core_escalou: humano_motivo 'duvida fora da base (nay-core): ...') e que ninguém
-- assumiu: a 1ª cobrança aos 30 min; depois, só quando ele escreve de novo, no máximo de 20 em 20 min. Quem responde
-- pelo celular ou pelo CRM troca a marca ("o Tel escreveu pelo celular") e a cobrança para.
DECLARE
  r       record;
  v_ult   timestamptz;
  v_novas text;
  v_orig  text;
  n       int := 0;
BEGIN
  FOR r IN
    SELECT c.chave, c.humano_assumiu_em AS desde, c.humano_motivo,
           coalesce(nullif(btrim(c.nome_completo), ''), nullif(btrim(c.nome_whatsapp), ''), 'Corretor') AS nome
      FROM nai_contato c
     WHERE c.humano_motivo LIKE 'duvida fora da base (nay-core)%'
       AND c.chave ~ '^\d{10,15}$'
       AND c.humano_assumiu_em < now() - interval '30 minutes'
       AND c.humano_assumiu_em > now() - make_interval(hours => greatest(nai_cfg_int('escalacao_expira_horas', 24), 1))
  LOOP
    SELECT max(a.criado_em) INTO v_ult FROM aviso_equipe a
     WHERE a.fonte = 'nay-core-cobranca' AND right(a.telefone, 8) = right(r.chave, 8) AND a.criado_em > r.desde;
    SELECT string_agg(to_char(m.criada_em AT TIME ZONE 'America/Manaus', 'HH24:MI') || ' "' || left(btrim(m.texto), 300) || '"',
                      E'\n' ORDER BY m.criada_em)
      INTO v_novas
      FROM mensagens m
     WHERE m.direcao = 'recebida' AND right(regexp_replace(m.telefone, '\D', '', 'g'), 8) = right(r.chave, 8)
       AND m.criada_em > coalesce(v_ult, r.desde) AND btrim(coalesce(m.texto, '')) <> ''
       AND lower(unaccent(btrim(m.texto))) !~ '^\W*(ok|okay|blz|beleza|obrigad[oa]|valeu|vlw|certo|sim|show|top|perfeito|combinado|ta bom|tudo bem)\W*$';
    IF v_ult IS NOT NULL AND (v_novas IS NULL OR v_ult > now() - interval '20 minutes') THEN
      CONTINUE;
    END IF;
    SELECT a.texto INTO v_orig FROM aviso_equipe a
     WHERE a.fonte = 'nay-core' AND a.tipo = 'escalada' AND right(a.telefone, 8) = right(r.chave, 8)
       AND a.criado_em BETWEEN r.desde - interval '5 minutes' AND r.desde + interval '5 minutes'
     ORDER BY a.id DESC LIMIT 1;
    PERFORM nay_aviso_equipe('nay-core-cobranca', 'escalada',
      r.nome || ' ainda espera a equipe (Parceria)',
      'Ninguém respondeu ' || r.nome || ' desde ' || to_char(r.desde AT TIME ZONE 'America/Manaus', 'HH24:MI')
      || ' (' || replace(r.humano_motivo, 'duvida fora da base (nay-core): ', '') || '). A Nay está calada nessa conversa até '
      || to_char((r.desde + make_interval(hours => greatest(nai_cfg_int('escalacao_expira_horas', 24), 1))) AT TIME ZONE 'America/Manaus', 'HH24:MI')
      || '.' || coalesce(E'\nEle escreveu depois:\n' || v_novas, '') || coalesce(E'\n\nO aviso: ' || v_orig, ''),
      r.chave);
    n := n + 1;
  END LOOP;
  RETURN n;
END
$function$;
