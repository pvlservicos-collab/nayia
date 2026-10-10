-- Testes da 342 (rodam dentro do ensaio, antes do ROLLBACK).
CREATE TEMP TABLE _t (caso text, esperado text, veio text);

INSERT INTO _t SELECT 'todo lead que já recebeu mensagem nossa está na lista', '0',
  (SELECT count(*)::text FROM captacao_leads l
    WHERE (l.ultimo_envio_em IS NOT NULL OR EXISTS (SELECT 1 FROM captacao_motor mt WHERE mt.lead_id = l.id)
           OR EXISTS (SELECT 1 FROM captacao_mensagens m WHERE nay_fone_chave(m.telefone) = l.telefone_chave
                                                           AND m.direcao = 'enviada' AND m.status <> 'Falhou'))
      AND NOT EXISTS (SELECT 1 FROM captacao_nao_disparar n WHERE n.telefone_chave = l.telefone_chave));
INSERT INTO _t SELECT 'ninguém que nunca recebeu entrou na lista', '0',
  (SELECT count(*)::text FROM captacao_nao_disparar n JOIN captacao_leads l ON l.telefone_chave = n.telefone_chave
    WHERE l.ultimo_envio_em IS NULL AND NOT EXISTS (SELECT 1 FROM captacao_motor mt WHERE mt.lead_id = l.id)
      AND NOT EXISTS (SELECT 1 FROM captacao_mensagens m WHERE nay_fone_chave(m.telefone) = l.telefone_chave
                                                           AND m.direcao = 'enviada' AND m.status <> 'Falhou'));
INSERT INTO _t SELECT 'a lista tem gente (centenas)', 'true', (SELECT (count(*) BETWEEN 300 AND 400)::text FROM captacao_nao_disparar);
INSERT INTO _t SELECT 'a fila do disparo continua vazia', '0', (SELECT count(*)::text FROM captacao_py_fila_do_disparo());
-- quem está na lista não volta à fila nem se o status for mexido à mão (o que a 291 já barrava; aqui é a segunda parede)
INSERT INTO _t SELECT 'quem está na lista não entra na fila', '0',
  (SELECT count(*)::text FROM captacao_py_fila_do_disparo() f(id) JOIN captacao_leads l ON l.id = f.id
     JOIN captacao_nao_disparar n ON n.telefone_chave = l.telefone_chave);

SELECT CASE WHEN esperado = veio THEN 'ok' ELSE 'FALHOU' END AS r, caso,
       CASE WHEN esperado = veio THEN '' ELSE 'esperado ' || esperado || ', veio ' || coalesce(veio, '(nulo)') END AS detalhe
  FROM _t;
SELECT count(*) AS na_lista_de_nao_disparar FROM captacao_nao_disparar;

DO $$
DECLARE n int; m int;
BEGIN
  SELECT count(*) FILTER (WHERE esperado IS DISTINCT FROM veio), count(*) INTO n, m FROM _t;
  IF n > 0 THEN RAISE EXCEPTION '342: % de % teste(s) falharam', n, m; END IF;
  RAISE NOTICE '342: % testes, todos certos', m;
END $$;
