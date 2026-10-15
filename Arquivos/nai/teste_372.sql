SELECT chave, valor FROM privado.olx_config WHERE chave IN ('avisar_grupo', 'grupo_silencio_s', 'grupo_ultimo_id') ORDER BY 1;
SELECT olx_cfg_gravar('grupo_ultimo_id', '13', 'ensaio') AS gravou;
SELECT valor = '13' AS ok_gravou FROM privado.olx_config WHERE chave = 'grupo_ultimo_id';
