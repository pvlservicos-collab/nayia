-- 504: depois da limpeza, nada que saia para fora pode ter sigilo; e a trava separa o que chegar de novo
SELECT 'observacao com registro interno (tem que ser 0)' AS teste, count(*) FROM imoveis WHERE nay_e_registro_interno(observacao)
UNION ALL SELECT 'memória da Nay com sigilo (0)', count(*) FROM imovel_conhecimento WHERE nay_e_sigilo(assunto || ' ' || texto)
UNION ALL SELECT 'memória com nome do dono entre parênteses (0)', count(*) FROM imovel_conhecimento WHERE texto ~* '(propriet|procurador)[a-zà-ú]*\s*\('
UNION ALL SELECT 'card guardado com registro interno (0)', count(*) FROM imovel_ficha WHERE nay_e_registro_interno(card)
UNION ALL SELECT 'ficha do anúncio com sigilo (0)', count(*) FROM imovel_ficha WHERE nay_e_sigilo(descricao) OR nay_e_sigilo(observacoes)
UNION ALL SELECT 'descrição com sigilo (0)', count(*) FROM imoveis WHERE nay_e_sigilo(descricao)
UNION ALL SELECT 'uso interno acima de 4000 letras (0)', count(*) FROM privado.imovel_ficha WHERE length(observacoes) > 4000
UNION ALL SELECT 'observações que sobraram', count(*) FROM imoveis WHERE coalesce(btrim(observacao), '') <> ''
UNION ALL SELECT 'fatos que sobraram na memória', count(*) FROM imovel_conhecimento;

SELECT codigo, observacao FROM imoveis WHERE codigo IN (3883, 3647, 2944, 205) ORDER BY codigo;
SELECT codigo, right(card, 160) AS fim_do_card FROM imovel_ficha WHERE codigo IN (3883, 5694);
SELECT codigo, right(observacoes, 400) AS uso_interno FROM privado.imovel_ficha WHERE codigo IN (3883, 5694, 9044);
SELECT codigo, right(regexp_replace(descricao, '\s+', ' ', 'g'), 120) AS fim_da_descricao FROM imoveis WHERE codigo IN (4376, 9049, 9050, 9066, 9074);
SELECT 'API pública sem obs' AS teste, NOT (site_imovel_publico(205) ? 'obs') AS ok;

-- a trava: observação nova com negociação
UPDATE imoveis SET observacao = 'Aceita pet. O proprietário (Zé, 12/10) quer R$ 500 mil líquidos.' WHERE codigo = 205;
SELECT 'trava da observação' AS teste, observacao = 'Aceita pet.' AS ok, observacao FROM imoveis WHERE codigo = 205;
SELECT 'foi para o uso interno' AS teste, observacoes ~ 'líquidos' AS ok FROM privado.imovel_ficha WHERE codigo = 205;
-- a trava: a memória da Nay não recebe comissão
SELECT nay_gravar_conhecimento('205', 'teste 504', 'Paga 6% de comissão.', 'teste');
SELECT 'memória recusou' AS teste, NOT EXISTS (SELECT 1 FROM imovel_conhecimento WHERE codigo = '205' AND assunto = 'teste 504') AS ok;
-- e o que é público entra, sem o nome do dono
SELECT nay_gravar_conhecimento('205', 'teste 504b', 'A proprietária (Maria, 12/10) disse que aceita pet.', 'teste');
SELECT 'memória aceitou sem nome' AS teste, texto FROM imovel_conhecimento WHERE codigo = '205' AND assunto = 'teste 504b';
