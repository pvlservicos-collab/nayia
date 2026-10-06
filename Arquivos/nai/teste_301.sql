-- dentro do ensaio (ROLLBACK no fim): um "Me envia" para um número que não existe
SELECT site_me_envia('92900000001', ARRAY[9020], 'ensaio-301') ->> 'mensagem' AS pedido;
-- no ensaio o relógio (now) fica parado no começo da transação; a fila marca enviar_apos um pouco à frente
UPDATE nai_saida s SET enviar_apos = now() - interval '1 second' FROM nai_contato k
 WHERE k.id = s.contato_id AND right(regexp_replace(k.telefone, '\D', '', 'g'), 8) = '00000001' AND s.estado = 'pendente';
-- o n8n não vê mais a entrega (a de um argumento devolve só o que é da Nay)
SELECT count(*) FILTER (WHERE papel = 'entrega') AS entrega_no_n8n FROM nai_liberar_saida(NULL::bigint);
-- o enviador manual vê, e a linha vai para 'enviando'
SELECT papel, rota, count(*) AS linhas, right(min(telefone), 4) AS fone_fim FROM nai_liberar_saida(NULL::bigint, true) GROUP BY 1, 2;
SELECT s.estado, count(*) FROM nai_saida s JOIN nai_contato k ON k.id = s.contato_id
 WHERE right(regexp_replace(k.telefone, '\D', '', 'g'), 8) = '00000001' GROUP BY 1;
