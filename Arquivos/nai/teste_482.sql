-- 482: dentro da transação do ensaio (termina em ROLLBACK): o aviso nasce bloqueado, a pergunta pendente
SELECT nai_avisar_tel(NULL, NULL, 'teste 482 aviso externo', 'aviso_externo') AS a,
       nai_avisar_tel(NULL, NULL, 'teste 482 cobranca', 'pergunta_fila_cobranca') AS b,
       nai_avisar_tel(NULL, NULL, 'teste 482 pergunta', 'pergunta_fila') AS c,
       nai_avisar_tel(NULL, NULL, 'teste 482 saiu do ar', 'aviso_saida_pergunta') AS d \gset
SELECT id = :a AS aviso, motivo, estado, bloqueio FROM nai_saida WHERE id IN (:a, :b, :c, :d) ORDER BY id;
SELECT valor FROM nai_config WHERE chave IN ('tel_so_perguntas', 'pergunta_fila_cobrar_min') ORDER BY chave;
