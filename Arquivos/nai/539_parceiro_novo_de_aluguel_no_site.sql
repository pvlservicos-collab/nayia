-- 539 (Pedro, 30/10/2026): "pode disponibilizar os de parceiro novo aqui https://imobeasy.online/alugar.html".
-- Os parceiros NOVOS (não o antigo do site antigo, 413) Disponíveis e com aluguel que estavam fora do site entram
-- (publicado_no_site). O 9083 já estava. Muda a regra de 27/09 ("parceiro fora do site") só para estes.
BEGIN;
UPDATE imoveis SET publicado_no_site = true
 WHERE e_parceiro AND coalesce(extras->>'parceiro_antigo', '') <> 'sim'
   AND status = 'Disponível' AND coalesce(disponivel, false) AND NOT coalesce(bloqueado, false)
   AND coalesce(valor_aluguel, 0) > 0 AND NOT coalesce(publicado_no_site, false)
RETURNING codigo, bairro, valor_aluguel;
COMMIT;
