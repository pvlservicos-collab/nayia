-- 208 (30/09/2026): "MANDAR PARA A RAYSSA" PELO CARD DO CRM.
-- O menu do card (Todos, Visitas, Proprietários, Fechamento | Tel, Rayssa) mandava
-- 'tel' quando o destino era a Rayssa, porque a 201 não aceitava 'rayssa': a Nay
-- calava, mas a marca dizia que era o Tel. Agora 'rayssa' é destino próprio, pelo
-- mesmo caminho do 'tel': a marca de humano começa com "Rayssa: " (a regra do
-- filtro Tel x Rayssa do CRM, a mesma das 27 marcas da 204), e a Nay fica calada
-- até a conversa voltar para Todos.
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
$a$  IF p_etapa NOT IN ('todos', 'visitas', 'proprietarios', 'fechamento', 'tel') THEN$a$,
$b$  IF p_etapa NOT IN ('todos', 'visitas', 'proprietarios', 'fechamento', 'tel', 'rayssa') THEN$b$);

SELECT pg_temp.trocar('crm_etapa_manual(text,text,text)',
$a$    RETURN QUERY SELECT true, 'Com o Tel: a Nay não responde até o Tel devolver.'::text;
    RETURN;
  END IF;
$a$, $b$    RETURN QUERY SELECT true, 'Com o Tel: a Nay não responde até o Tel devolver.'::text;
    RETURN;
  END IF;
  -- 208: a Rayssa, pelo mesmo caminho; "Rayssa: " na frente é o que o CRM lê
  IF p_etapa = 'rayssa' THEN
    UPDATE nai_contato SET humano_assumiu_em = now(),
                           humano_motivo = left('Rayssa: CRM: ' || v_quem || ' mandou para a Rayssa', 200)
     WHERE id = v_contato;
    RETURN QUERY SELECT true, 'Com a Rayssa: a Nay não responde até a conversa voltar para Todos.'::text;
    RETURN;
  END IF;
$b$);
COMMIT;
