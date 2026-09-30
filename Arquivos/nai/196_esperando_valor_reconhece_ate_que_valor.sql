-- =====================================================================
-- NAI -- 196: "ATÉ QUE VALOR" TAMBÉM É PERGUNTA DE VALOR (30/09/2026)
--
-- Entrevista de 29/09, pergunta 12. O roteador ("Rotear pelo cabeçalho") manda
-- número solto de 3 a 5 dígitos para o card do imóvel, a menos que
-- `nai_esperando_valor` diga que a última coisa que a Nay perguntou foi valor.
-- A regex dela só conhecia "faixa de preço", "qual o valor", "até quanto" e
-- "teto de valor" -- e a busca por perfil (146/190) pergunta "Até que valor o
-- seu cliente quer?". Como 1000, 1500, 2000, 2500, 3000, 3500, 4000, 4500 e
-- 5000 são códigos de imóvel, a resposta "3500" viraria o card e as fotos do
-- imóvel 3500. A pergunta nova já saiu duas vezes (28/09 10:45 e 29/09 18:45);
-- ninguém respondeu com número solto ainda.
--
-- O QUE MUDA: a regex passa a aceitar "até que valor" (com e sem acento), que
-- cobre as três frases da busca: a pergunta do filtro, o "me diz até que valor
-- o cliente vai, que eu procuro em toda a cidade" e o fim da lista ("me diz até
-- que valor o cliente vai que eu filtro aqui"). O resto da função não muda:
-- a pergunta continua valendo por 2 horas e só se for a última mensagem de
-- texto dela.
--
-- Backup da versão anterior: /root/backups-funcoes/nai_esperando_valor-20260929-2013.sql
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.nai_esperando_valor(p_contato bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM nai_saida s
     WHERE s.contato_id = p_contato AND s.tipo = 'texto'
       AND s.criado_em > now() - interval '2 hours'
       AND s.texto ~* '(faixa de pre|qual (o )?valor|ate quanto|teto de valor|at[eéÉ] que valor)'
       AND s.id = (SELECT max(s2.id) FROM nai_saida s2
                    WHERE s2.contato_id = p_contato AND s2.tipo = 'texto'));
$function$;

COMMIT;
