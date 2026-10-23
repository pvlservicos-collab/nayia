-- teste da 478: o perfil dos donos salvo, o de um lead sem carimbo, a troca para um perfil que não existe e para um que existe
SELECT * FROM captacao_nay_perfis();
SELECT nome, prompt_papel, roteiro, length(prompt) AS tam FROM captacao_nay_perfil_do_lead((SELECT telefone FROM captacao_leads WHERE id = 778));
SELECT captacao_nay_perfil_trocar('corretores');
SELECT captacao_nay_perfil_salvar('corretores', 'corretor', 'corretores', 'ensaio', 'listas OLX', 'ensaio');
SELECT captacao_nay_perfil_trocar('corretores');
SELECT valor FROM captacao_config WHERE chave = 'nay_perfil_ativo';
SELECT nome, ativo, prompt_versao_salva, leads FROM captacao_nay_perfis();
