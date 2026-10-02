-- Imoveis da resposta que estao SEM foto na tabela: esses serao lidos no site agora.
SELECT nai_fotos_faltando(ARRAY(SELECT jsonb_array_elements_text($1::jsonb)::int)) AS faltando;
