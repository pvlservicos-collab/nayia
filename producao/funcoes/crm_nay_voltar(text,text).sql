CREATE OR REPLACE FUNCTION public.crm_nay_voltar(p_telefone text, p_quem text)
 RETURNS TABLE(ok boolean, mensagem text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '3s'
AS $function$
DECLARE
  v_ids     bigint[];
  v_contato bigint;
  v_chave   text := nai_chave(p_telefone);
  v_quem    text := left(coalesce(nullif(btrim(p_quem), ''), 'CRM'), 80);
  v_extra   text := '';
BEGIN
  SELECT p.ids, p.contato_id INTO v_ids, v_contato FROM crm_pessoas(ARRAY[p_telefone]) p LIMIT 1;
  IF v_ids IS NULL OR cardinality(v_ids) = 0 THEN
    RETURN QUERY SELECT true, 'A Nay já atende esta conversa.'; RETURN;
  END IF;
  v_contato := coalesce(v_contato, v_ids[1]);

  -- 294: o clique também LIBERA a conversa para a porta. Sem isto, o que o CRM reentregava de um "contato
  -- novo" era barrado ("assunto que não é de corretor") e ninguém respondia (três casos em 05/10).
  UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL, liberado_em = coalesce(liberado_em, now())
   WHERE id = ANY (v_ids);

  -- 228: dono de imóvel é da Rayssa (197)
  IF EXISTS (SELECT 1 FROM unnest(v_ids) i WHERE nai_e_proprietario_contato(i)) THEN
    RETURN QUERY SELECT true, 'Marca tirada, mas é proprietário: quem responde é a Rayssa (a Nay não fala com dono de imóvel).';
    RETURN;
  END IF;

  -- 228: Visitas/Proprietários/Fechamento seguravam a Nay calada: volta para Todos
  IF nai_com_a_rayssa(v_contato, 'corretor') IS NOT NULL
     OR EXISTS (SELECT 1 FROM nai_etapa_manual m WHERE m.contato_id = ANY (v_ids) AND m.etapa <> 'todos'
                   AND (m.valido_ate IS NULL OR m.valido_ate > now())) THEN
    INSERT INTO nai_etapa_manual (contato_id, etapa, definido_por, definido_em, valido_ate)
    VALUES (v_contato, 'todos', left(v_quem || ' (Nay voltar a atender)', 120), now(), NULL)
    ON CONFLICT (contato_id) DO UPDATE SET etapa = 'todos', definido_por = EXCLUDED.definido_por,
                                           definido_em = now(), valido_ate = NULL;
    DELETE FROM nai_etapa_manual WHERE contato_id = ANY (v_ids) AND contato_id <> v_contato;
    v_extra := v_extra || ' A conversa voltou para Todos.';
  END IF;

  -- 228: fora da lista de corretores: o clique aprova (o mesmo que CORRETOR <telefone>)
  IF v_chave IS NOT NULL AND v_chave !~ '^lid:'
     AND nai_lista_governa(v_chave, v_contato) AND NOT nai_pode_falar(v_chave, p_telefone) THEN
    PERFORM nai_decidir_corretor(p_telefone, true);
    v_extra := v_extra || ' O número foi aprovado como corretor.';
  END IF;

  RETURN QUERY SELECT true, 'A Nay voltou a atender esta conversa.' || v_extra;
END $function$;
