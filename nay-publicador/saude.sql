-- Raio-X da Nay: uma consulta para cada coisa que já quebrou de verdade.
--
-- Rodar quando o Tel reclamar de qualquer comportamento estranho, ANTES
-- de sair procurando no prompt ou no fluxo. Quase todo bug deste projeto
-- foi de DADO chegando errado, não de lógica decidindo errado -- e a
-- pergunta certa quase sempre foi "o que ela recebeu?" e não "o que ela
-- pensou?".
--
--   docker cp saude.sql nay-postgres:/tmp/saude.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/saude.sql

\echo ''
\echo '=== 1. A Nay está atendendo? ==='
SELECT valor AS pausado, atualizado_em FROM config WHERE chave = 'atendimento_pausado';

\echo ''
\echo '=== 2. Truncamento por vírgula (o bug de 29/08) ==='
-- Zero vírgulas em muitas mensagens = o queryReplacement voltou a ser
-- string separada por vírgula e está comendo o texto de novo.
SELECT count(*) AS msgs_1h,
       count(*) FILTER (WHERE texto LIKE '%,%') AS com_virgula,
       CASE WHEN count(*) > 20 AND count(*) FILTER (WHERE texto LIKE '%,%') = 0
            THEN 'SUSPEITO: nenhuma vírgula em muitas mensagens'
            ELSE 'ok' END AS diagnostico
FROM mensagens
WHERE criada_em > now() - interval '1 hour' AND coalesce(texto,'') <> '';

\echo ''
\echo '=== 3. A citação está sendo capturada? ==='
-- `forma_crua` = a Z-API mandou um formato que a extração não previu, e o
-- JSON foi guardado inteiro. É o sinal para ajustar `Filtrar e normalizar`.
SELECT count(*) AS msgs_24h,
       count(citado) AS com_citacao,
       count(*) FILTER (WHERE citado LIKE '{%') AS forma_crua
FROM mensagens WHERE criada_em > now() - interval '24 hours';

\echo ''
\echo '=== 4. Idade do catálogo ==='
-- Já enganou duas vezes: o doc dizia uma coisa e o banco outra.
SELECT max(sincronizado_em)::date AS ultima_varredura,
       (now()::date - max(sincronizado_em)::date) AS dias_atras,
       count(*) AS imoveis
FROM imoveis;

\echo ''
\echo '=== 5. Pendências abertas (ela prometeu e está devendo) ==='
SELECT id, coalesce(codigo,'-') AS imovel, left(o_que_falta, 50) AS assunto,
       (now() - criada_em)::interval(0) AS esperando
FROM pendencias WHERE status = 'aberta' ORDER BY id;

\echo ''
\echo '=== 6. Quem escreveu e não está cadastrado ==='
SELECT DISTINCT m.telefone, m.nome
FROM mensagens m
WHERE m.criada_em > now() - interval '24 hours'
  AND NOT EXISTS (SELECT 1 FROM corretores c WHERE c.telefone = m.telefone AND c.aprovado AND c.ativo)
  AND NOT EXISTS (SELECT 1 FROM nay_e_da_equipe(m.telefone))
LIMIT 10;

\echo ''
\echo '=== 7. Rascunho de resposta parado (ela pediu confirmação e você não deu) ==='
SELECT r.pendencia_id, left(r.texto, 45) AS vai_dizer,
       (now() - r.criado_em)::interval(0) AS parado_ha
FROM pendencia_rascunho r ORDER BY r.criado_em;

\echo ''
\echo '=== 8. Imóveis administrados e o que se sabe da visita ==='
SELECT i.codigo, i.condominio_nome,
       CASE WHEN coalesce(p.como_funciona_visita,'') = '' THEN 'NAO SABE'
            ELSE left(p.como_funciona_visita, 40) END AS visita,
       p.proprietario_acompanha AS dono_acompanha
FROM imoveis i LEFT JOIN imovel_privado p ON p.codigo = i.codigo::int
WHERE i.administrado ORDER BY i.codigo;
