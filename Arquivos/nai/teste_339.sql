-- Testes da 339 (rodam dentro do ensaio, antes do ROLLBACK). Os telefones são inventados e NADA sai: as linhas
-- da caixa de saída nascem e morrem dentro desta transação (o enviador não enxerga o que não foi gravado).
CREATE TEMP TABLE _t (caso text, esperado text, veio text);

UPDATE privado.grupo_captacao_estado
   SET config = config || '{"envio_manual": true, "intervalo_min_entre_envios": 30, "enviar_dados_e_fotos": true, "janela_h": 48}'::jsonb
                       || jsonb_build_object('mensagem_de_abertura', 'Oi, vi sua solicitação no grupo, tenho um imóvel que pode se encaixar no que o seu cliente quer, vou te enviar aqui ok? Qualquer dúvida me avisa')
 WHERE id = 1;

-- dois imóveis nossos que podem ir (no mercado, com card e foto) e um de parceiro
SELECT k[1] AS a, k[2] AS b FROM (SELECT array_agg(codigo ORDER BY codigo DESC) AS k FROM (
  SELECT i.codigo FROM imoveis i
   WHERE NOT coalesce(i.e_parceiro, false) AND i.status = 'Disponível' AND nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
     AND (SELECT texto_pronto FROM nai_card_do_imovel(i.codigo)) IS NOT NULL
     AND EXISTS (SELECT 1 FROM imovel_fotos f WHERE f.codigo = i.codigo)
   ORDER BY i.codigo DESC LIMIT 2) x) y \gset
SELECT codigo AS parceiro FROM imoveis WHERE coalesce(e_parceiro, false) AND coalesce(disponivel, true) ORDER BY codigo DESC LIMIT 1 \gset

INSERT INTO privado.grupo_pedido (fonte, ref, parte, grupo_nome, remetente, remetente_nome, enviada_em, texto, ficha)
VALUES ('grupo', 'T339-A', 1, 'GRUPO TESTE 339', '559290000339', 'Corretora Teste', now(), 'Procuro apartamento', '{"operacao": "aluguel"}')
RETURNING id AS p1 \gset
INSERT INTO privado.grupo_pedido_par (pedido_id, codigo, posicao, nota, detalhe, imovel)
VALUES (:p1, :a, 1, 90, '[]', '{}'), (:p1, :b, 2, 80, '[]', '{}'), (:p1, :parceiro, 3, 70, '[]', '{}');

-- ============ 1. o envio: abertura, card e fotos, na ordem
SELECT site_captacao_grupos_enviar(:p1, :a, NULL, 'teste') AS r1 \gset
INSERT INTO _t SELECT 'o envio entra na fila', 'true', :'r1'::jsonb->>'ok';
SELECT coalesce(:'r1'::jsonb->>'turno', '0') AS t1 \gset
INSERT INTO _t SELECT 'a primeira linha é a mensagem padrão dele, para o corretor, como entrega pendente', 'sim',
  coalesce((SELECT CASE WHEN s.tipo = 'texto' AND s.papel_destino = 'entrega' AND s.estado = 'pendente' AND s.motivo = 'captacao_ativa_abertura'
                         AND s.texto = 'Oi, vi sua solicitação no grupo, tenho um imóvel que pode se encaixar no que o seu cliente quer, vou te enviar aqui ok? Qualquer dúvida me avisa'
                         AND s.chave_destino = nai_chave('559290000339') THEN 'sim'
                        ELSE s.estado || ' | ' || coalesce(s.bloqueio, '') || ' | ' || left(s.texto, 60) END
              FROM nai_saida s WHERE s.turno_id = :t1 ORDER BY s.id LIMIT 1), '(nenhuma linha)');
INSERT INTO _t SELECT 'depois vêm o card e as fotos do imóvel, tudo como entrega para a mesma pessoa', 'sim',
  (SELECT CASE WHEN (array_agg(s.tipo ORDER BY s.id))[2] = 'texto' AND (array_agg(s.texto ORDER BY s.id))[2] ~ ('C[óo]digo:\s*' || :a)
                AND count(*) FILTER (WHERE s.tipo = 'imagem' AND s.codigo = :a) >= 1
                AND count(*) FILTER (WHERE s.papel_destino <> 'entrega' OR s.chave_destino <> nai_chave('559290000339')) = 0
                AND count(*) FILTER (WHERE s.estado <> 'pendente') = 0 THEN 'sim'
               ELSE 'linhas ' || count(*) || ', fora do lugar ' || count(*) FILTER (WHERE s.estado <> 'pendente') END
     FROM nai_saida s WHERE s.turno_id = :t1);
INSERT INTO _t SELECT 'a oferta fica registrada, o pedido vira enviado e o resumo diz o que foi', '1/enviado/true',
  (SELECT count(*) FROM privado.grupo_pedido_oferta WHERE pedido_id = :p1 AND codigo = :a AND com_card AND turno_id = :t1) || '/' ||
  (SELECT estado FROM privado.grupo_pedido WHERE id = :p1) || '/' || ((:'r1'::jsonb->>'resumo') ~ '^Na fila de envio: a abertura, o card e [0-9]+ fotos?\.$')::text;
INSERT INTO _t SELECT 'a tela recebe o que já foi enviado nesse pedido', '1/' || :a || '/enviado',
  coalesce((SELECT jsonb_array_length(p->'ofertas') || '/' || (p->'ofertas'->0->>'codigo') || '/' || (p->>'estado')
              FROM jsonb_array_elements(site_captacao_grupos('todos', 48, 300)->'pedidos') p WHERE (p->>'id')::bigint = :p1), '(não veio)');

-- ============ 2. as travas
SELECT site_captacao_grupos_enviar(:p1, :a) ->> 'erro' AS e_repetido \gset
INSERT INTO _t SELECT 'o mesmo imóvel não vai duas vezes para o mesmo pedido', 'Esse imóvel já foi enviado para este pedido.', :'e_repetido';
SELECT site_captacao_grupos_enviar(:p1, :b) ->> 'erro' AS e_intervalo \gset
INSERT INTO _t SELECT 'outra mensagem ao mesmo corretor antes do intervalo é recusada', 'true', (:'e_intervalo' LIKE 'Esse corretor já recebeu uma mensagem daqui às %O intervalo é de 30 min%')::text;
UPDATE privado.grupo_pedido_oferta SET enviado_em = now() - interval '31 minutes' WHERE pedido_id = :p1;
SELECT site_captacao_grupos_enviar(:p1, :b) ->> 'ok' AS ok_alternativa \gset
INSERT INTO _t SELECT 'passado o intervalo, a alternativa vai', 'true', :'ok_alternativa';
UPDATE privado.grupo_pedido_oferta SET enviado_em = now() - interval '31 minutes' WHERE pedido_id = :p1;
SELECT site_captacao_grupos_enviar(:p1, :parceiro) ->> 'erro' AS e_parceiro \gset
INSERT INTO _t SELECT 'imóvel de parceiro não sai, e nem a abertura fica na caixa', 'true/2/0',
  (:'e_parceiro' ~* 'parceiro')::text || '/' ||
  (SELECT count(*) FROM nai_saida s WHERE s.motivo = 'captacao_ativa_abertura' AND s.chave_destino = nai_chave('559290000339')) || '/' ||
  (SELECT count(*) FROM nai_turno t WHERE t.texto LIKE 'captação ativa pelo painel%: ' || :parceiro || ' para %');

-- quem não pode receber
INSERT INTO privado.grupo_pedido (fonte, ref, parte, grupo_nome, remetente, enviada_em, texto, ficha, estado)
VALUES ('teste', 'T339-T', 1, 'Teste colado na tela', NULL, now(), 'x', '{}', 'novo'),
       ('grupo', 'T339-S', 1, 'GRUPO TESTE 339', NULL, now(), 'x', '{}', 'novo'),
       ('grupo', 'T339-R', 1, 'GRUPO TESTE 339', '559290000342', now(), 'x', '{}', 'rejeitado'),
       ('grupo', 'T339-V', 1, 'GRUPO TESTE 339', '559290000343', now() - interval '60 hours', 'x', '{}', 'novo'),
       ('grupo', 'T339-F', 1, 'GRUPO TESTE 339', '559290000344', now(), 'x', '{}', 'novo');
INSERT INTO privado.grupo_pedido_par (pedido_id, codigo, posicao, nota, detalhe, imovel)
SELECT q.id, :a, 1, 90, '[]', '{}' FROM privado.grupo_pedido q WHERE q.ref IN ('T339-T', 'T339-S', 'T339-R', 'T339-V');
INSERT INTO _t SELECT 'teste colado, sem telefone, rejeitado, velho e imóvel que não casou: todos recusados', 'teste/telefone/rejeitada/passou/casaram',
  (SELECT string_agg(CASE WHEN e ~ 'teste colado' THEN 'teste' WHEN e ~ 'telefone' THEN 'telefone' WHEN e ~ 'rejeitada' THEN 'rejeitada'
                          WHEN e ~ 'passou de' THEN 'passou' WHEN e ~ 'casaram' THEN 'casaram' ELSE coalesce(e, 'FOI') END, '/' ORDER BY o)
     FROM (SELECT x.o, site_captacao_grupos_enviar((SELECT id FROM privado.grupo_pedido WHERE ref = x.ref), :a) ->> 'erro' AS e
             FROM (VALUES (1, 'T339-T'), (2, 'T339-S'), (3, 'T339-R'), (4, 'T339-V'), (5, 'T339-F')) x(o, ref)) y);
INSERT INTO _t SELECT 'pedido que não existe', 'Não achei essa solicitação.', site_captacao_grupos_enviar(-1, :a) ->> 'erro';

-- ============ 3. só a abertura, e a abertura escrita na hora
UPDATE privado.grupo_captacao_estado SET config = config || '{"enviar_dados_e_fotos": false}'::jsonb WHERE id = 1;
INSERT INTO privado.grupo_pedido_par (pedido_id, codigo, posicao, nota, detalhe, imovel)
SELECT q.id, :a, 1, 90, '[]', '{}' FROM privado.grupo_pedido q WHERE q.ref = 'T339-F';
SELECT site_captacao_grupos_enviar((SELECT id FROM privado.grupo_pedido WHERE ref = 'T339-F'), :a, '   Olá! Tenho um imóvel para o seu cliente.  ') AS r3 \gset
INSERT INTO _t SELECT 'com "só a abertura" sai uma mensagem só, com o texto que ele escreveu na hora', 'true/1/Olá! Tenho um imóvel para o seu cliente./Na fila de envio: a abertura (só ela).',
  (:'r3'::jsonb->>'ok') || '/' || (SELECT count(*) FROM nai_saida s WHERE s.turno_id = (:'r3'::jsonb->>'turno')::bigint) || '/' ||
  (SELECT s.texto FROM nai_saida s WHERE s.turno_id = (:'r3'::jsonb->>'turno')::bigint) || '/' || (:'r3'::jsonb->>'resumo');

-- ============ 4. o interruptor e quem pode
UPDATE privado.grupo_captacao_estado SET config = config || '{"envio_manual": false}'::jsonb WHERE id = 1;
INSERT INTO _t SELECT 'com envio_manual desligado no arquivo, o banco recusa', 'O envio manual está desligado na configuração (envio_manual).',
  site_captacao_grupos_enviar(:p1, :a) ->> 'erro';
INSERT INTO _t SELECT 'só o papel de escrita do site envia', 'true/false',
  has_function_privilege('nay_site_escrita', 'public.site_captacao_grupos_enviar(bigint, integer, text, text)', 'EXECUTE')::text || '/' ||
  has_function_privilege('nay_site_leitura', 'public.site_captacao_grupos_enviar(bigint, integer, text, text)', 'EXECUTE')::text;
INSERT INTO _t SELECT 'nada deste ensaio saiu de verdade (tudo pendente, nada enviado)', '0',
  (SELECT count(*)::text FROM nai_saida s JOIN nai_turno t ON t.id = s.turno_id
    WHERE t.texto LIKE 'captação ativa pelo painel%' AND s.estado NOT IN ('pendente', 'bloqueado'));
INSERT INTO _t SELECT 'aprovar pelo caminho antigo continua recusado (o envio é só o botão)', 'true',
  (site_captacao_grupos_estado(:p1, 'aprovado') ? 'erro')::text;

SELECT CASE WHEN esperado = veio THEN 'ok' ELSE 'FALHOU' END AS r, caso,
       CASE WHEN esperado = veio THEN '' ELSE 'esperado ' || esperado || ', veio ' || coalesce(veio, '(nulo)') END AS detalhe
  FROM _t;

DO $$
DECLARE n int; m int;
BEGIN
  SELECT count(*) FILTER (WHERE esperado IS DISTINCT FROM veio), count(*) INTO n, m FROM _t;
  IF n > 0 THEN RAISE EXCEPTION '339: % de % teste(s) falharam', n, m; END IF;
  RAISE NOTICE '339: % testes, todos certos', m;
END $$;
