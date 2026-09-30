-- 216 (revisão de 30/09/2026): uma regex inválida em nai_giria / nai_lugar_conjunto
-- / nai_lugar_avenida derrubava TODOS os turnos (nai_giria_explica roda em todo
-- turno, e a busca lê os lugares no começo). O banco recusa a linha já na gravação.
-- Fora do ensaio de propósito: ALTER TABLE segura a tabela até o fim da transação
-- (ver a memória "ensaio sem DDL no banco vivo"); aqui é rápido e com lock_timeout.
BEGIN;
SET LOCAL lock_timeout = '3s';
ALTER TABLE nai_lugar_conjunto ADD CONSTRAINT nai_lugar_conjunto_regex_valida CHECK (('' ~ expressao) IS NOT NULL);
ALTER TABLE nai_lugar_avenida  ADD CONSTRAINT nai_lugar_avenida_regex_valida  CHECK (('' ~ expressao) IS NOT NULL);
ALTER TABLE nai_giria          ADD CONSTRAINT nai_giria_regex_valida          CHECK (('' ~ expressao) IS NOT NULL);
COMMIT;
