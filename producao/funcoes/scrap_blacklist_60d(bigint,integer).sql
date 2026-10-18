CREATE OR REPLACE FUNCTION public.scrap_blacklist_60d(p_lista bigint, p_dias integer DEFAULT 60)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_n int; v_tirados int;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM scrap_lista WHERE id = p_lista AND tipo = 'blacklist') THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'a lista não é uma blacklist');
  END IF;
  DELETE FROM scrap_contato WHERE lista_id = p_lista AND origem = 'sistema';
  -- a chave guarda 55 + DDD + 8 dígitos; celular (8 dígitos começando em 6-9) ganha o 9 de volta
  INSERT INTO scrap_contato (lista_id, telefone, nome, origem, observacao, dados)
  SELECT p_lista,
         CASE WHEN substr(f.chave, 5, 1) IN ('6', '7', '8', '9') THEN substr(f.chave, 3, 2) || '9' || substr(f.chave, 5)
              ELSE substr(f.chave, 3) END,
         coalesce((SELECT c.nome FROM corretores c WHERE scrap_chave(c.telefone) = f.chave AND coalesce(c.nome, '') <> '' LIMIT 1),
                  (SELECT p.nome FROM proprietarios p WHERE scrap_chave(p.telefone) = f.chave AND coalesce(p.nome, '') <> '' LIMIT 1),
                  (SELECT coalesce(nullif(k.nome_completo, ''), nullif(k.nome_whatsapp, '')) FROM nai_contato k
                    WHERE scrap_chave(k.telefone) = f.chave AND coalesce(nullif(k.nome_completo, ''), k.nome_whatsapp, '') <> '' LIMIT 1)),
         'sistema',
         'falou conosco em ' || to_char(f.ultima_em, 'DD/MM/YYYY') || ' (' || array_to_string(f.origens, ', ') || ')',
         jsonb_build_object('ultima_em', f.ultima_em, 'origens', to_jsonb(f.origens))
    FROM privado.falou_conosco f
   WHERE f.ultima_em > now() - make_interval(days => p_dias) AND f.chave ~ '^55\d{10}$'
  ON CONFLICT (lista_id, telefone) DO UPDATE SET observacao = EXCLUDED.observacao, dados = EXCLUDED.dados, atualizado_em = now();
  GET DIAGNOSTICS v_n = ROW_COUNT;
  UPDATE scrap_lista SET atualizado_em = now(), descricao = 'Quem falou conosco nos últimos ' || p_dias || ' dias por qualquer número (Parceria, Captação, Nay, CRM e o que nós mandamos). Refeita em ' || to_char(now(), 'DD/MM HH24:MI') || '.'
   WHERE id = p_lista;
  -- quem está na blacklist sai das listas normais vindas de raspagem/CSV (o que foi posto à mão fica)
  WITH t AS (
    DELETE FROM scrap_contato c USING scrap_lista l
     WHERE l.id = c.lista_id AND l.tipo = 'lista' AND c.origem IN ('olx', 'csv') AND scrap_bloqueado(c.telefone)
    RETURNING c.lista_id
  ), n AS (SELECT lista_id, count(*) k FROM t GROUP BY lista_id)
  UPDATE scrap_lista l SET bloqueados = l.bloqueados + n.k FROM n WHERE n.lista_id = l.id;
  SELECT coalesce(sum(bloqueados), 0) INTO v_tirados FROM scrap_lista WHERE tipo = 'lista';
  RETURN jsonb_build_object('ok', true, 'na_blacklist', v_n, 'bloqueados_total', v_tirados);
END
$function$;
