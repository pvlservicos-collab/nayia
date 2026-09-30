-- 228 (30/09/2026): O BOTÃO VERDE "NAY VOLTAR A ATENDER" FAZ A NAY RESPONDER.
-- Pedro: "quando eu clicar no botão verdinho 'Nay voltar a atender' é para a Nay
-- olhar o contexto da conversa e a última mensagem e já gerar uma resposta para a
-- pessoa; o Tel colocou umas pessoas nessa opção mas a Nay não disparou nada".
--
-- Medido (30/09): o CRM reentregou 8 vezes à NAI. 4 responderam; 1 saiu barrada
-- como repetida; 1 a Nay escalou; 2 (a mesma pessoa, 14h58 e 15h32) morreram na
-- porta "fora da lista: esperando o Tel dizer se é corretor" -- o botão só tirava a
-- marca do Tel, não aprovava a pessoa. E conversa em Visitas/Proprietários/
-- Fechamento continuava com a Rayssa (197), com a Nay calada.
--
-- Agora o clique é a decisão de quem está no CRM:
--   * tira a marca de humano das duas linhas da pessoa (como antes);
--   * se a conversa estava em Visitas/Proprietários/Fechamento, volta para Todos
--     (sem concluir o fechamento: a etapa nova só vale do clique em diante);
--   * se o número está fora da lista de corretores, aprova (o mesmo que o Tel faz
--     com CORRETOR <telefone>);
--   * dono de imóvel continua com a Rayssa (197): o botão não o vira corretor.
BEGIN;
SET LOCAL lock_timeout = '3s';

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

  UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL WHERE id = ANY (v_ids);

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
COMMIT;
