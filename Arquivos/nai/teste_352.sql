-- Testes da 352 (rodam dentro do ensaio, antes do ROLLBACK).
CREATE TEMP TABLE _t (caso text, esperado text, veio text);
-- quem escreveu pela captação ontem é "falou conosco"; quem nunca escreveu, não
SELECT nay_fone_chave(m.telefone) AS c FROM captacao_mensagens m WHERE m.direcao = 'recebida' ORDER BY m.criada_em DESC LIMIT 1 \gset
INSERT INTO _t SELECT 'quem escreveu pela captação falou conosco', 'true', nay_falou_conosco(:'c', 60)::text;
INSERT INTO _t SELECT 'número inventado não falou', 'false', nay_falou_conosco(nay_fone_chave('5592000000352'), 60)::text;
-- a cópia do CRM entra na conta
INSERT INTO privado.falou_conosco_crm_tmp VALUES ('5592000000352', now());
SELECT nay_falou_conosco_crm_trocar() AS n \gset
INSERT INTO _t SELECT 'a troca da cópia do CRM', '1', :'n'::text;
SELECT nay_falou_conosco_atualizar() AS a \gset
INSERT INTO _t SELECT 'depois da cópia do CRM (e da junção), o número passa a ter falado', 'true', nay_falou_conosco(nay_fone_chave('5592000000352'), 60)::text;
INSERT INTO _t SELECT 'a junção tem gente de várias origens', 'true', (SELECT (count(DISTINCT origens) > 2 AND count(*) > 500)::text FROM privado.falou_conosco);
-- corretor dos grupos não é proprietário
SELECT nay_fone_chave(nay_fone_com_ddi(telefone)) AS k FROM corretores WHERE coalesce(telefone, '') <> '' LIMIT 1 \gset
INSERT INTO _t SELECT 'corretor dos grupos é corretor', 'true', nay_e_corretor_chave(:'k')::text;
INSERT INTO _t SELECT 'nenhum corretor nas listas de donos', '0',
  (SELECT count(*)::text FROM site_publicos_disparo() WHERE grupo = 'donos' AND total < 0);
INSERT INTO _t SELECT 'a fila da captação não traz quem falou nem corretor', '0',
  (SELECT count(*)::text FROM captacao_py_fila_do_disparo() f(id) JOIN captacao_leads l ON l.id = f.id
    WHERE nay_falou_conosco(l.telefone_chave, 60) OR nay_e_corretor_chave(l.telefone_chave));
INSERT INTO _t SELECT 'o papel do disparo executa as duas', 'true',
  (has_function_privilege('nay_disparo', 'public.nay_falou_conosco(text,integer)', 'EXECUTE') AND has_function_privilege('nay_disparo', 'public.nay_e_corretor_chave(text)', 'EXECUTE'))::text;
SELECT CASE WHEN esperado = veio THEN 'ok' ELSE 'FALHOU' END AS r, caso,
       CASE WHEN esperado = veio THEN '' ELSE 'esperado ' || esperado || ', veio ' || coalesce(veio, '(nulo)') END AS detalhe FROM _t;
SELECT n, grupo, nome, total, disparados, falaram FROM site_publicos_disparo();
DO $$
DECLARE n int; m int;
BEGIN
  SELECT count(*) FILTER (WHERE esperado IS DISTINCT FROM veio), count(*) INTO n, m FROM _t;
  IF n > 0 THEN RAISE EXCEPTION '352: % de % teste(s) falharam', n, m; END IF;
  RAISE NOTICE '352: % testes, todos certos', m;
END $$;
