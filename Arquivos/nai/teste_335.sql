-- Testes da 335 (rodam dentro do ensaio, antes do ROLLBACK). Só leitura de dados reais.
CREATE TEMP TABLE _t (caso text, esperado text, veio text);

-- um exemplo real de cada fonte (o mais recente)
SELECT e.message_id AS id_card, e.codigo AS cod_card FROM envios e
 WHERE e.message_id IS NOT NULL AND e.destino = 'grupo' AND e.codigo ~ '^[0-9]{3,5}$'
   AND EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo::text = e.codigo)
 ORDER BY e.enviado_em DESC LIMIT 1 \gset
SELECT l.message_id AS id_lista, count(*) AS n_lista FROM envios_lista_grupo l
 WHERE l.message_id = (SELECT x.message_id FROM envios_lista_grupo x ORDER BY x.enviado_em DESC LIMIT 1)
 GROUP BY 1 \gset
SELECT f.message_id AS id_foto, f.codigo AS cod_foto FROM envios_foto f ORDER BY f.enviado_em DESC LIMIT 1 \gset
SELECT s.message_id AS id_nai FROM nai_saida s
 WHERE s.message_id IS NOT NULL AND s.tipo = 'texto'
   AND NOT EXISTS (SELECT 1 FROM envios e WHERE e.message_id = s.message_id)
 ORDER BY s.id DESC LIMIT 1 \gset
SELECT m.message_id AS id_msg FROM mensagens m
 WHERE m.message_id IS NOT NULL AND m.direcao = 'recebida' AND nullif(btrim(m.texto), '') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM envios e WHERE e.message_id = m.message_id)
   AND NOT EXISTS (SELECT 1 FROM nai_saida s WHERE s.message_id = m.message_id)
   AND NOT EXISTS (SELECT 1 FROM core_saida s WHERE s.message_id = m.message_id)
   AND NOT EXISTS (SELECT 1 FROM mensagem_saida s WHERE s.message_id = m.message_id)
   AND NOT EXISTS (SELECT 1 FROM envios_foto s WHERE s.message_id = m.message_id)
   AND NOT EXISTS (SELECT 1 FROM envios_lista_grupo s WHERE s.message_id = m.message_id)
 ORDER BY m.id DESC LIMIT 1 \gset

INSERT INTO _t SELECT 'card do grupo: diz de que grupo e quando, e traz o card com o código', 'sim',
  coalesce((SELECT CASE WHEN c.quem ~ '^Card postado no grupo .+ · [0-9]{2}/[0-9]{2} [0-9]{2}:[0-9]{2}$'
                         AND c.texto ~ ('(C[óo]digo:\s*' || :'cod_card' || '|^Imóvel ' || :'cod_card' || ')') THEN 'sim'
                        ELSE c.quem || ' | ' || left(c.texto, 120) END
              FROM crm_mensagem_citada(ARRAY[:'id_card']) c), '(nada)');

INSERT INTO _t SELECT 'lista do grupo: título e uma linha por imóvel', 'sim/' || (:n_lista + 1),
  coalesce((SELECT CASE WHEN c.quem ~ '^Lista postada no grupo .+ · [0-9]{2}/[0-9]{2} [0-9]{2}:[0-9]{2}$'
                         AND c.texto ~ ('^Lista de (locação|venda|imóveis).* \(' || :n_lista || ' imóveis\)') THEN 'sim'
                        ELSE c.quem || ' | ' || left(c.texto, 120) END
                   || '/' || array_length(string_to_array(c.texto, E'\n'), 1)
              FROM crm_mensagem_citada(ARRAY[:'id_lista']) c), '(nada)');

INSERT INTO _t SELECT 'foto do post: diz que é foto e de qual imóvel', 'sim',
  coalesce((SELECT CASE WHEN c.quem ~ '^Foto (postada no grupo|enviada pela Nay)' AND c.texto LIKE '[foto] Imóvel ' || :'cod_foto' || '%' THEN 'sim'
                        ELSE c.quem || ' | ' || left(c.texto, 120) END
              FROM crm_mensagem_citada(ARRAY[:'id_foto']) c), '(nada)');

INSERT INTO _t SELECT 'mensagem da Nay no privado: o texto que ela mandou', 'Nay/sim',
  coalesce((SELECT c.quem || '/' || CASE WHEN c.texto = left((SELECT btrim(s.texto) FROM nai_saida s WHERE s.message_id = :'id_nai' ORDER BY s.id DESC LIMIT 1), 3000) THEN 'sim' ELSE 'não' END
              FROM crm_mensagem_citada(ARRAY[:'id_nai']) c), '(nada)');

INSERT INTO _t SELECT 'mensagem que ele mesmo mandou: o texto dela', 'sim',
  coalesce((SELECT CASE WHEN c.texto = left((SELECT btrim(m.texto) FROM mensagens m WHERE m.message_id = :'id_msg' ORDER BY m.id DESC LIMIT 1), 3000) THEN 'sim' ELSE left(c.texto, 80) END
              FROM crm_mensagem_citada(ARRAY[:'id_msg']) c), '(nada)');

INSERT INTO _t SELECT 'id que ninguém conhece: nenhuma linha (o CRM continua dizendo que não achou)', '0',
  (SELECT count(*)::text FROM crm_mensagem_citada(ARRAY['TESTE335-NAO-EXISTE']));
INSERT INTO _t SELECT 'lista vazia e nula: nenhuma linha, sem erro', '0/0',
  (SELECT count(*)::text FROM crm_mensagem_citada('{}'::text[])) || '/' || (SELECT count(*)::text FROM crm_mensagem_citada(NULL));
INSERT INTO _t SELECT 'vários de uma vez, com repetido e vazio: uma linha por mensagem conhecida', '3',
  (SELECT count(*)::text FROM crm_mensagem_citada(ARRAY[:'id_card', :'id_lista', :'id_card', '', ' ' || :'id_foto' || ' ', 'TESTE335-NAO-EXISTE']));
INSERT INTO _t SELECT 'só o papel do CRM executa (e o dono)', 'true/false',
  has_function_privilege('nay_disparo', 'public.crm_mensagem_citada(text[])', 'EXECUTE')::text || '/' ||
  has_function_privilege('nay_leitura', 'public.crm_mensagem_citada(text[])', 'EXECUTE')::text;

SELECT CASE WHEN esperado = veio THEN 'ok' ELSE 'FALHOU' END AS r, caso,
       CASE WHEN esperado = veio THEN '' ELSE 'esperado ' || esperado || ', veio ' || coalesce(veio, '(nulo)') END AS detalhe
  FROM _t;

DO $$
DECLARE n int; m int;
BEGIN
  SELECT count(*) FILTER (WHERE esperado IS DISTINCT FROM veio), count(*) INTO n, m FROM _t;
  IF n > 0 THEN RAISE EXCEPTION '335: % de % teste(s) falharam', n, m; END IF;
  RAISE NOTICE '335: % testes, todos certos', m;
END $$;
