-- testes da 364 (rodam dentro da transação do ensaio, antes do ROLLBACK). Nada aqui fala com a OLX.
\echo '== quantos imóveis dariam anúncio =='
SELECT negocio, count(*) AS candidatos, count(*) FILTER (WHERE (m->>'ok')::boolean) AS prontos,
       count(*) FILTER (WHERE NOT (m->>'ok')::boolean) AS faltando_dado
  FROM olx_anuncios_candidatos() GROUP BY 1 ORDER BY 1;

\echo '== o que falta, por motivo =='
SELECT regexp_replace(t, '\s*\(.*$', '') AS motivo, count(*) FROM olx_anuncios_candidatos() c, jsonb_array_elements_text(c.m->'falta') t
 GROUP BY 1 ORDER BY 2 DESC;

\echo '== os anúncios prontos respeitam os limites da OLX? (tudo tem de dar zero) =='
SELECT count(*) FILTER (WHERE length(m->'anuncio'->>'subject') NOT BETWEEN 2 AND 90) AS titulo_fora,
       count(*) FILTER (WHERE length(m->'anuncio'->>'body') NOT BETWEEN 2 AND 6000) AS descricao_fora,
       count(*) FILTER (WHERE m->'anuncio'->>'id' !~ '^[A-Za-z0-9_{}-]{1,19}$') AS id_fora,
       count(*) FILTER (WHERE jsonb_array_length(m->'anuncio'->'images') NOT BETWEEN 1 AND 20) AS fotos_fora,
       count(*) FILTER (WHERE m->'anuncio'->>'zipcode' !~ '^\d{8}$') AS cep_fora,
       count(*) FILTER (WHERE (m->'anuncio'->>'price')::bigint <= 0) AS preco_fora,
       count(*) FILTER (WHERE m->'anuncio'->>'body' ~* '(https?://|www\.|@[a-z0-9-]+\.[a-z]{2,}|\(?\d{2}\)?[\s.-]*9?\d{4}[\s.-]?\d{4})') AS descricao_com_contato,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM jsonb_each(m->'anuncio'->'params') p WHERE p.value IN ('""'::jsonb, '"0"'::jsonb, '[]'::jsonb) AND p.key NOT IN ('rooms', 'garage_spaces'))) AS parametro_vazio,
       max(length(m->'anuncio'->>'subject')) AS maior_titulo, max(length(m->'anuncio'->>'body')) AS maior_descricao
  FROM olx_anuncios_candidatos() WHERE (m->>'ok')::boolean;

\echo '== categorias e tipos =='
SELECT m->'anuncio'->>'category' AS categoria, m->'anuncio'->>'type' AS tipo, count(*),
       min(m->'anuncio'->>'subject') AS um_titulo
  FROM olx_anuncios_candidatos() WHERE (m->>'ok')::boolean GROUP BY 1, 2 ORDER BY 1, 2;

\echo '== um anúncio de cada categoria, inteiro =='
SELECT DISTINCT ON (m->'anuncio'->>'category') jsonb_pretty(m->'anuncio' || jsonb_build_object('images', jsonb_build_array(m->'anuncio'->'images'->0, '... ' || jsonb_array_length(m->'anuncio'->'images') || ' fotos'))) AS anuncio
  FROM olx_anuncios_candidatos() WHERE (m->>'ok')::boolean ORDER BY m->'anuncio'->>'category', codigo DESC;

\echo '== o plano com o teto de fábrica (5): só publica 5 =='
SELECT acao, codigo, negocio, ad_id, left(anuncio->>'subject', 70) AS titulo, anuncio->'price' AS preco FROM olx_anuncios_plano();

\echo '== a vida de um anúncio: enviado -> publicado -> o valor muda -> o imóvel é alugado =='
SELECT codigo, negocio, ad_id, anuncio, hash FROM olx_anuncios_plano() LIMIT 1 \gset p_
SELECT olx_anuncio_enviado(:'p_ad_id', :p_codigo, :'p_negocio', 'proprietarios', 'insert', :'p_anuncio'::jsonb, :'p_hash', 'token-de-teste');
SELECT ad_id, estado, import_token FROM olx_anuncios_a_conferir();
SELECT olx_anuncio_resultado(:'p_ad_id', 'publicado', '1999999999', 'https://www.olx.com.br/vi/1999999999.htm', NULL);
SELECT ad_id, estado, list_id, url, publicado_em IS NOT NULL AS tem_data FROM privado.olx_anuncio;
SELECT count(*) AS no_plano_depois_de_publicado FROM olx_anuncios_plano() WHERE ad_id = :'p_ad_id';
UPDATE imoveis SET valor_venda = valor_venda + 1000, valor_aluguel = valor_aluguel + 100 WHERE codigo = :p_codigo;
SELECT acao, ad_id, motivo, anuncio->'price' AS preco_novo FROM olx_anuncios_plano() WHERE ad_id = :'p_ad_id';
UPDATE imoveis SET status = 'Alugado' WHERE codigo = :p_codigo;
SELECT acao, ad_id, motivo, anuncio FROM olx_anuncios_plano() WHERE ad_id = :'p_ad_id';
SELECT olx_anuncio_enviado(:'p_ad_id', :p_codigo, :'p_negocio', 'proprietarios', 'delete', NULL, NULL, 'token-da-remocao');
SELECT olx_anuncio_resultado(:'p_ad_id', 'removido', NULL, NULL, NULL);
SELECT ad_id, estado, list_id, removido_em IS NOT NULL AS tem_data FROM privado.olx_anuncio;
SELECT count(*) AS linhas_no_diario FROM privado.olx_anuncio_log;

\echo '== parceiro nunca vai =='
SELECT olx_anuncio_montar((SELECT codigo FROM imoveis WHERE e_parceiro AND status = 'Disponível' AND coalesce(valor_venda, 0) > 0 LIMIT 1), 'venda') - 'ad_id' AS parceiro;

\echo '== o chat, para a Nay: fila, reserva, contexto, gente assume =='
INSERT INTO privado.olx_chat (conta, chat_id, list_id, nome, telefone, ultima_em, ultima_texto, ultima_de)
VALUES ('proprietarios', 'chat-de-teste', '1999999999', 'Cliente de Teste', '92999990000', now() - interval '2 minutes', 'Ainda está disponível?', 'comprador')
RETURNING id \gset c_
INSERT INTO privado.olx_chat_mensagem (chat, message_id, de, texto, quando) VALUES (:c_id, 'm1', 'comprador', 'Ainda está disponível?', now() - interval '2 minutes');
SELECT chat, conta, list_id, nome, ultima_texto FROM olx_nay_fila();
SELECT olx_nay_reservar(:c_id, 'teste') AS primeira_reserva, olx_nay_reservar(:c_id, 'outro') AS segunda_reserva;
SELECT count(*) AS na_fila_enquanto_reservada FROM olx_nay_fila();
SELECT jsonb_pretty(olx_nay_contexto(:c_id) #- '{imovel,fotos}' #- '{imovel,desc}') AS contexto;
SELECT olx_nay_soltar(:c_id);
SELECT count(*) AS na_fila_depois_de_soltar FROM olx_nay_fila();
SELECT crm_olx_chat_enviada('proprietarios', :c_id, 'r1', 'Está sim!', 'Nay OLX') AS nay_respondeu;
UPDATE privado.olx_chat SET ultima_de = 'comprador', ultima_em = now() - interval '1 minute' WHERE id = :c_id;
SELECT count(*) AS na_fila_depois_da_resposta_da_nay FROM olx_nay_fila();
SELECT crm_olx_chat_enviada('proprietarios', :c_id, 'r2', 'Aqui é o Pedro', 'Pedro') AS gente_respondeu;
UPDATE privado.olx_chat SET ultima_de = 'comprador', ultima_em = now() - interval '1 minute' WHERE id = :c_id;
SELECT count(*) AS na_fila_depois_de_gente_responder FROM olx_nay_fila();

\echo '== a tela do CRM, pelo papel do CRM =='
SET ROLE nay_disparo;
SELECT p->'contagem' AS contagem, p->'config'->>'publicar' AS publicar, p->'config'->>'permissao' AS permissao,
       jsonb_array_length(p->'proximos') AS proximos, jsonb_array_length(p->'nossos') AS nossos
  FROM crm_olx_anuncios_painel() p;
SELECT crm_olx_config_gravar('publicar', 'sim', 'teste') AS ligar_sem_conta,
       crm_olx_config_gravar('conta_que_publica', 'proprietarios', 'teste') AS escolher_conta,
       crm_olx_config_gravar('teto', 'muitos', 'teste') AS teto_errado,
       crm_olx_config_gravar('permissao', 'ok', 'teste') AS chave_proibida;
SELECT crm_olx_config_gravar('publicar', 'sim', 'teste') AS ligar_com_conta;
RESET ROLE;
SELECT chave, valor, atualizado_por FROM privado.olx_config WHERE chave IN ('publicar', 'conta_que_publica', 'teto', 'permissao') ORDER BY 1;
\echo '== o papel do CRM não lê o que não é dele =='
SET ROLE nay_disparo;
DO $$ BEGIN PERFORM olx_cfg('publicar'); RAISE NOTICE 'ERRO: o CRM chamou olx_cfg'; EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'certo: olx_cfg negada ao CRM'; END $$;
RESET ROLE;

\echo '== apagado pelo site da OLX nao volta sozinho; e nenhum titulo cita o tipo como condominio =='
SELECT codigo, negocio, ad_id, anuncio, hash FROM olx_anuncios_plano() LIMIT 1 \gset q_
SELECT olx_anuncio_enviado(:'q_ad_id', :q_codigo, :'q_negocio', 'proprietarios', 'insert', :'q_anuncio'::jsonb, :'q_hash', 't2');
SELECT olx_anuncio_resultado(:'q_ad_id', 'publicado', '1888888888', NULL, NULL);
SELECT olx_anuncio_na_olx(:'q_ad_id', '1888888888', 'deleted');
SELECT ad_id, estado, olx_status, removido_por_fora FROM privado.olx_anuncio WHERE ad_id = :'q_ad_id';
SELECT count(*) AS volta_ao_plano FROM olx_anuncios_plano(500) WHERE ad_id = :'q_ad_id';
SELECT count(*) AS titulos_com_o_tipo_no_lugar_do_condominio FROM olx_anuncios_candidatos()
 WHERE m->>'titulo' ~* ' no (loja|sala|casa|pr[eé]dio|lote|galp[aã]o|apartamento)(/| em |,|$)';
