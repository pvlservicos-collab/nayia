-- Monta a resposta na caixa de saida: card, fotos DAQUELE card, resto do texto.
-- Guardas: negou foto que existe -> corrige; prometeu foto que nao existe -> Tel.
SELECT nai_enfileirar_resposta_ferramentas($1::bigint, $2, $3::jsonb, $4, $5::jsonb, $6::jsonb) AS r;
