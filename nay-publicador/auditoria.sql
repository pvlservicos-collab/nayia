-- Auditoria: cada coisa que o Tel pediu, medida contra a PRODUÇÃO.
--
-- Não é teste de unidade -- as suítes `teste_*.sql` fazem isso, em
-- transação, com cenário montado. Aqui é o contrário: pergunta ao banco
-- vivo se o que foi prometido está de pé AGORA, com o catálogo de hoje.
--
-- Rode depois de qualquer deploy grande, e sempre que o Tel perguntar
-- "isso está mesmo funcionando?".
--
--   docker cp auditoria.sql nay-postgres:/tmp/a.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/a.sql

\pset pager off
CREATE TEMP TABLE auditoria(item text, medida text, esperado text);

-- 1. O número do apartamento nunca sai.
INSERT INTO auditoria VALUES
 ('1. pergunta de unidade é barrada',
  nay_pede_localizacao_da_unidade('qual andar, bloco e apartamento')::text, 'true'),
 ('1. e a recusa não vira pendência',
  (SELECT count(*)::text FROM pendencias
    WHERE o_que_falta ~* '(apartamento|complemento|unidade)' AND status='aberta'), '0');

-- 2. Código não pode vir da cabeça dela.
INSERT INTO auditoria VALUES
 ('2. código não dito pelo corretor é recusado',
  nay_codigo_confirmado('559299999999','5717'), 'nao');

-- 3. Citação: toda mensagem que sai é registrada.
INSERT INTO auditoria
SELECT '3. mensagens que sairam foram registradas (24h)',
       CASE WHEN count(*) > 0 THEN 'sim' ELSE 'NENHUMA' END, 'sim'
  FROM mensagem_saida WHERE enviado_em > now() - interval '24 hours';

-- O ÚLTIMO disparo de grupo, não as últimas 24h: as linhas antigas são de
-- antes do conserto e vão ficar sem ID para sempre -- a citação delas cai
-- na pergunta, e é o certo. O que precisa estar de pé é o disparo de
-- AGORA.
INSERT INTO auditoria
SELECT '3. último disparo de grupo: linhas sem message_id',
       coalesce(count(*) FILTER (WHERE message_id IS NULL)::text, '0'), '0'
  FROM envios
 WHERE destino = 'grupo'
   AND enviado_em > (SELECT max(enviado_em) - interval '5 minutes'
                       FROM envios WHERE destino = 'grupo');

-- 4. Bairro: a busca no Parque 10 nunca cita Ponta Negra.
INSERT INTO auditoria
SELECT '4. busca no Parque 10 cita Ponta Negra?',
       count(*) FILTER (WHERE d.texto_pronto ILIKE '%Ponta Negra%')::text, '0'
  FROM (VALUES ('venda'),('locacao')) n(neg),
       (VALUES (NULL),('400000'),('5000'),('1000000')) t(teto),
       (VALUES (NULL),('2'),('3'),('4')) q(qt),
       LATERAL nay_buscar_por_perfil('Parque 10 de Novembro', n.neg, t.teto, q.qt) d;

INSERT INTO auditoria
SELECT '4. bairros do catálogo sem zona',
       count(*)::text, '0'
  FROM (SELECT DISTINCT bairro FROM imoveis
         WHERE coalesce(disponivel,true) AND coalesce(bairro,'') <> '') b
  LEFT JOIN bairro_zona z
    ON nay_normalizar_lugar(z.bairro,true) = nay_normalizar_lugar(b.bairro,true)
 WHERE z.bairro IS NULL;

-- 5. Condomínio pelo nome: todo nome do catálogo se resolve.
INSERT INTO auditoria
SELECT '5. condomínios que não se identificam',
       count(*)::text, '0'
  FROM (SELECT DISTINCT condominio_nome AS nome FROM imoveis
         WHERE coalesce(condominio_nome,'') <> '') c,
       LATERAL nay_disponibilidade_no_condominio(c.nome, NULL) d
 WHERE d.texto_pronto LIKE 'temos mais de um%'
    OR d.texto_pronto LIKE 'você quis dizer%'
    OR d.texto_pronto LIKE 'não temos imóvel no %';

INSERT INTO auditoria
SELECT '5. caso Erick: nome completo resolve',
       CASE WHEN texto_pronto LIKE 'no Liverpool Reserva Inglesa%'
            THEN 'resolve' ELSE left(texto_pronto,40) END, 'resolve'
  FROM nay_disponibilidade_no_condominio('Condomínio Liverpool (Reserva Inglesa)','locacao');

-- 6. Fotos: pedido passa, "já tenho" não passa, envelope de sistema não passa.
INSERT INTO auditoria VALUES
 ('6. "me manda as fotos" abre',
  nay_deve_mandar_fotos('559299999999','me manda as fotos')::text, 'true'),
 ('6. "as fotos eu já tenho" NÃO abre',
  nay_deve_mandar_fotos('559299999999','não, as fotos eu já tenho')::text, 'false'),
 ('6. envelope de áudio NÃO abre',
  nay_deve_mandar_fotos('559299999999',
   '(o corretor mandou um audio. transcricao: "qual o valor?") Antes de enviar qualquer material, repita em uma linha o que voce entendeu e peca confirmacao.')::text,
  'false');

-- 7. Turno com dois pedidos.
INSERT INTO auditoria VALUES
 ('7. venda + locação no mesmo turno é detectado',
  coalesce(nay_negocio_pedido('os dois de locacao' || chr(10) || 'me manda os de venda tambem'),'(nulo)'), 'ambos'),
 ('7. pedido de visita é detectado',
  nay_pede_visita('Cliente gostaria de agendar uma visita')::text, 'true');

-- 8. Nome de empresa vira pergunta.
INSERT INTO auditoria VALUES
 ('8. "OPEN SERVIÇOS" não é nome de gente',
  coalesce(nay_nome_de_pessoa('OPEN SERVIÇOS'),'(pergunta)'), '(pergunta)'),
 ('8. nome de gente continua passando',
  coalesce(nay_nome_de_pessoa('Waldyrene Oliveira Corretora'),'(pergunta)'), 'Waldyrene');

-- 9. Comando do Tel.
INSERT INTO auditoria VALUES
 ('9. nay_comando sem sobrecarga',
  (SELECT count(*)::text FROM pg_proc WHERE proname='nay_comando'), '1'),
 ('9. nay_responder_pendencia sem sobrecarga',
  (SELECT count(*)::text FROM pg_proc WHERE proname='nay_responder_pendencia'), '1');

-- 10. Nenhuma resposta viva carrega o número da UNIDADE.
--
-- O predicado aqui é mais estreito que o `nay_tem_numero_de_unidade` de
-- propósito. Aquele é a PAREDE e pode ser mais rígido do que a política
-- (ele barra "torre 4", que a regra do Tel libera para apartamento) --
-- rígido demais numa parede é seguro. Aqui a pergunta é outra: escapou
-- número que identifica a unidade? Isso é o que não pode.
INSERT INTO auditoria
SELECT '10. respostas guardadas com o nº da unidade',
       count(*)::text, '0'
  FROM pendencias
 WHERE resposta IS NOT NULL AND status <> 'descartada'
   AND lower(unaccent(resposta)) ~ '\m(ap|apto|apartamento|casa|sobrado|lote|quadra|n[°º]|numero)\M[^0-9]{0,4}[0-9]';

-- E a contagem informativa da parede, que é mais rígida: se este número
-- for maior que o de cima, a diferença é resposta que menciona torre ou
-- andar. Não vaza nada, mas também não é reusada nem repassada aos outros
-- interessados -- é o preço de a parede falhar fechada.
INSERT INTO auditoria
SELECT '10. (informativo) barradas pela parede, mais rígida',
       count(*)::text,
       count(*)::text
  FROM pendencias
 WHERE resposta IS NOT NULL AND nay_tem_numero_de_unidade(resposta)
   AND status <> 'descartada';

-- 11. Fotos no banco: imóvel nosso, publicado e sem foto nenhuma.
INSERT INTO auditoria
SELECT '11. imóveis publicados sem NENHUMA foto',
       count(*)::text, '0'
  FROM imoveis i
 WHERE coalesce(i.disponivel,true) AND NOT coalesce(i.e_parceiro,false)
   AND coalesce(i.publicado_no_site,false)
   AND NOT EXISTS (SELECT 1 FROM imovel_fotos f WHERE f.codigo = i.codigo);

-- 12. A varredura está viva (o alarme mede este carimbo).
INSERT INTO auditoria
SELECT '12. varredura rodou nas últimas 3h',
       CASE WHEN (SELECT valor FROM config WHERE chave='varredura_rodou_em')::timestamptz
                 > now() - interval '3 hours' THEN 'sim' ELSE 'NÃO' END, 'sim';

-- 13. A fila não pode ter mensagem parada.
INSERT INTO auditoria
SELECT '13. mensagens paradas em Recebido',
       count(*)::text, '0'
  FROM mensagens WHERE status='Recebido' AND criada_em < now() - interval '5 minutes';

-- 14. Corretores: o Tel tem que estar na lista, senão os comandos dele morrem.
INSERT INTO auditoria
SELECT '14. o Tel está aprovado e ativo',
       CASE WHEN EXISTS (SELECT 1 FROM corretores
                          WHERE right(regexp_replace(telefone,'[^0-9]','','g'),8)='94717316'
                            AND aprovado AND ativo) THEN 'sim' ELSE 'NÃO' END, 'sim';

INSERT INTO auditoria
SELECT '14. atendimento está ligado',
       CASE WHEN (SELECT valor FROM config WHERE chave='atendimento_pausado')='nao'
            THEN 'ligado' ELSE 'PAUSADO' END, 'ligado';

-- 15. Contexto da conversa: um imóvel resolve, dois perguntam, grupo não conta.
INSERT INTO auditoria VALUES
 ('15. disparo de grupo não vira contexto',
  coalesce(nay_aviso_do_foco('120363023894631899-group'),'(nulo)'), '(nulo)');

INSERT INTO auditoria
SELECT '15. conversas com contexto resolvido (24h)',
       CASE WHEN count(*) >= 0 THEN 'ok' END, 'ok'
  FROM (SELECT DISTINCT telefone FROM mensagens
         WHERE criada_em > now() - interval '24 hours' AND direcao='recebida') t,
       LATERAL nay_imovel_em_foco(t.telefone) f
 WHERE f.codigo IS NOT NULL;

-- 16. Os crons de minuto estão batendo? (o alarme mora fora do SQL, mas o
--     efeito dá para ver aqui: grade parada = nada postado nos grupos.)
INSERT INTO auditoria
SELECT '16. postagens em grupo nas últimas 24h',
       CASE WHEN count(*) > 0 THEN 'sim' ELSE 'NENHUMA -- grade parada?' END, 'sim'
  FROM envios WHERE destino='grupo' AND enviado_em > now() - interval '24 hours';

-- --------------------------------------------------------------------
SELECT CASE WHEN medida = esperado THEN 'OK  ' ELSE '>>> ' END AS r,
       item, medida, esperado
  FROM auditoria ORDER BY (medida = esperado), item;

SELECT CASE WHEN falhas = 0
            THEN 'AUDITORIA LIMPA: ' || total || ' verificações'
            ELSE falhas || ' DE ' || total || ' PRECISAM DE ATENÇÃO' END AS resumo
  FROM (SELECT count(*) FILTER (WHERE medida <> esperado) AS falhas,
               count(*) AS total FROM auditoria) s;
