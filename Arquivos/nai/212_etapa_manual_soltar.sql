-- 212 (30/09/2026): O × DA ETIQUETA "COM O TEL" / "COM A RAYSSA" NO CRM.
-- O card ganhou um × na etiqueta de quem está atendendo (pedido do Pedro). Ele
-- chamava crm_etapa_manual 'todos', que também CONCLUI o fechamento aberto e troca
-- a etapa escolhida à mão: tirar a etiqueta de quem estava no meio de um fechamento
-- fecharia o fechamento junto. 'soltar' só tira a marca de humano (das duas linhas
-- da pessoa); a etapa e o fechamento ficam como estão. A Nay volta a responder se a
-- conversa estiver em Todos; em Visitas, Proprietários ou Fechamento continua calada.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION pg_temp.trocar(p_fn regprocedure, p_de text, p_para text, p_vezes int DEFAULT 1)
 RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  d text := pg_get_functiondef(p_fn);
  n int := (length(d) - length(replace(d, p_de, ''))) / length(p_de);
BEGIN
  IF n <> p_vezes THEN
    RAISE EXCEPTION 'trocar em %: esperava % vez(es), achei % -- %', p_fn, p_vezes, n, left(p_de, 60);
  END IF;
  EXECUTE replace(d, p_de, p_para);
END $$;

SELECT pg_temp.trocar('crm_etapa_manual(text,text,text)',
$a$  IF p_etapa NOT IN ('todos', 'visitas', 'proprietarios', 'fechamento', 'tel', 'rayssa') THEN$a$,
$b$  IF p_etapa NOT IN ('todos', 'visitas', 'proprietarios', 'fechamento', 'tel', 'rayssa', 'soltar') THEN$b$);

SELECT pg_temp.trocar('crm_etapa_manual(text,text,text)',
$a$    RETURN QUERY SELECT true, 'Com a Rayssa: a Nay não responde até a conversa voltar para Todos.'::text;
    RETURN;
  END IF;
$a$, $b$    RETURN QUERY SELECT true, 'Com a Rayssa: a Nay não responde até a conversa voltar para Todos.'::text;
    RETURN;
  END IF;
  -- 212: o × da etiqueta -- só tira a marca de humano, sem mexer em etapa nem fechamento
  IF p_etapa = 'soltar' THEN
    UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL WHERE id = ANY (v_ids);
    RETURN QUERY SELECT true, CASE WHEN nai_com_a_rayssa(v_contato, NULL) IS NULL
      THEN 'Etiqueta tirada: a Nay volta a responder.'
      ELSE 'Etiqueta tirada. A conversa continua em Visitas, Proprietários ou Fechamento: a Nay segue calada.' END;
    RETURN;
  END IF;
$b$);
COMMIT;
