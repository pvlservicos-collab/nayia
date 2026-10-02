SELECT DISTINCT condominio_nome FROM imoveis WHERE condominio_nome IS NOT NULL AND condominio_nome <> '' AND condominio_nome NOT ILIKE '%identificado%' AND disponivel = true;
