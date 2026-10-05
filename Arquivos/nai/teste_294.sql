INSERT INTO nai_contato (chave, telefone) VALUES (nai_chave('5592991230294'), '5592991230294');
SELECT ok, left(mensagem, 50) FROM crm_etapa_manual('5592991230294', 'fechamento', 'Teste');
SELECT count(*) AS abertos_antes FROM nai_fechamento f JOIN nai_contato c ON c.id = f.contato_id WHERE c.telefone = '5592991230294' AND f.concluido_em IS NULL;
SELECT ok, left(mensagem, 50) FROM crm_etapa_manual('5592991230294', 'proprietarios', 'Teste');
SELECT count(*) FILTER (WHERE f.concluido_em IS NULL) AS abertos_depois, max(f.concluido_por) AS por FROM nai_fechamento f JOIN nai_contato c ON c.id = f.contato_id WHERE c.telefone = '5592991230294';
UPDATE nai_contato SET liberado_em = NULL, humano_assumiu_em = now() WHERE telefone = '5592991230294';
SELECT ok, left(mensagem, 60) FROM crm_nay_voltar('5592991230294', 'Teste');
SELECT liberado_em IS NOT NULL AS liberado, humano_assumiu_em IS NULL AS solto FROM nai_contato WHERE telefone = '5592991230294';
