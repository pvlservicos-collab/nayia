-- O ESTADO DA CONVERSA, em jsonb, pronto para o classificador.
-- Substitui o envelope de texto que hoje polui a nai_memoria.
SELECT nai_estado_v2((SELECT contato_id FROM nai_turno WHERE id = $1::bigint), 3) AS estado;
