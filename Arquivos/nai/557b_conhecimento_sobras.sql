-- 557b (01/11/2026): as duas que sobraram com assunto "pergunta:" depois da 557.
BEGIN;
DELETE FROM imovel_conhecimento WHERE id = 672 AND codigo = '5742';   -- "CLIENTE APROVADO" como resposta do andar: recado de fechamento
UPDATE imovel_conhecimento SET assunto = 'taxa_condominio', atualizado_em = now()
 WHERE id = 409 AND codigo = '9021'
   AND NOT EXISTS (SELECT 1 FROM imovel_conhecimento WHERE codigo = '9021' AND assunto = 'taxa_condominio');
COMMIT;
