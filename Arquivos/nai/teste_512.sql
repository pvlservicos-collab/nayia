-- 512: ensaio (tudo desfeito)
SELECT to_regclass('privado.duvida') AS tabela,
       (SELECT valor FROM privado.olx_config WHERE chave = 'duvidas_rotina') AS chave;
-- sem contato na Parceria: não enfileira nada
SELECT nay_duvida_mandar_pela_parceria('92900000000', 'teste') IS NULL AS sem_contato_nao_manda;
-- com contato: o texto e a foto entram na core_saida como da Nay (motivo nay_duvida)
WITH c AS (SELECT telefone FROM nai_contato WHERE telefone ~ '^\d{12,13}$' ORDER BY id DESC LIMIT 1)
SELECT nay_duvida_mandar_pela_parceria((SELECT telefone FROM c), 'Sobre o #9051: teste') IS NOT NULL AS texto_entra,
       nay_duvida_mandar_pela_parceria((SELECT telefone FROM c), '', 'https://exemplo/foto.jpg', 9051) IS NOT NULL AS foto_entra;
SELECT tipo, motivo, estado, left(texto, 40) texto, codigo FROM core_saida WHERE motivo = 'nay_duvida' ORDER BY id DESC LIMIT 2;
