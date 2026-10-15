-- testes da 374 (no ensaio, que termina em ROLLBACK: nada sai)
\echo '== o lead do Pedro: canal e quem o reconhece pela Parceria =='
SELECT l.id, l.canal, captacao_olx_da_parceria('559691712835') AS pelo_numero_da_parceria,
       captacao_olx_da_parceria('lid:000', 36) AS pelo_contato
  FROM captacao_leads l WHERE l.id = 835;
\echo '== a mensagem dele na Parceria vai para a Nay da OLX, e a NAI não atende =='
SELECT nai_abrir_turno('559691712835', 'Pedro', 'oi, pode falar', NULL, '{}'::bigint[]) AS abrir_turno;
SELECT lead_id, direcao, status, texto, criada_em < now() - interval '17 seconds' AS ja_pode_pegar
  FROM captacao_mensagens WHERE lead_id = 835 ORDER BY id DESC LIMIT 1;
\echo '== um corretor qualquer continua com a NAI (não é OLX) =='
SELECT captacao_olx_da_parceria('5592999990000') IS NULL AS nao_e_olx;
\echo '== a saída pela Parceria: a mesma SQL do envio.parceria, e a trava de repetida não barra o roteiro =='
WITH t AS (
  INSERT INTO nai_turno (contato_id, papel, texto)
  VALUES (nai_contato_do_cadastro(nai_cfg('tel_telefone'), 'Tel'), 'tel', 'teste 374') RETURNING id)
SELECT nai_enfileirar_texto(t.id, NULL, nai_contato_do_cadastro('5596991712835', 'Pedro'), 'entrega', 'Certo.', 'olx_proprietario', 1) AS saida FROM t;
SELECT position('olx_proprietario' IN pg_get_functiondef('public.nai_liberar_saida(bigint,boolean)'::regprocedure)) > 0 AS repetida_liberada;
