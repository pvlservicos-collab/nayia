-- testes da 407 (rodam dentro do ensaio, antes do ROLLBACK)
\echo '--- telefone: normalizar'
SELECT p, scrap_telefone_normalizar(p) AS n, scrap_telefone_formatar(scrap_telefone_normalizar(p)) AS f
  FROM unnest(ARRAY['92 9998I-9200', '(92) 99170 4631', '99114.9501', '5592999819200', '92 993214318', '69037000', '1545312951',
                    '3233-4455', '92 3233 4455', '(11) 98888-7777', '(15) 4531-2951', '99999-9999', 'abc', '0 92 99981 9200']) p;

\echo '--- telefone: do texto (esperado: 92999819200, 92991175725 | 92982690039 | 92991149501, 92981262220 | nada)'
SELECT scrap_telefones_do_texto('Venda R$ 550.000,00<br>Aluguel R$ 5.000,00<br>92 9998I-9200 WHATSAPP<br>92 99II7-5725 WHATSAPP<br>CRECI 5174PF /AM') AS a,
       scrap_telefones_do_texto('Código do anúncio: 1K74OR  SAMPAIO 98269-0039  * Área útil: 190m² CEP 69037-000 ref 1545312951') AS b,
       scrap_telefones_do_texto('contato 99114.9501 ou 98126.2220 valor R$ 15.018,00 em 2026') AS c,
       scrap_telefones_do_texto('Apartamento 3 quartos, 110m², R$ 1.550.000 condomínio R$ 683 IPTU R$ 6.000') AS d;

\echo '--- importar 3 anúncios (2 telefones iguais em anúncios diferentes, 1 sem telefone)'
SET ROLE nay_site_escrita;
SELECT site_scrap_importar(jsonb_build_object(
  'lista', jsonb_build_object('nome', 'TESTE 407 apto aluguel', 'url_busca', 'https://www.olx.com.br/x'),
  'anuncios', jsonb_build_array(
    jsonb_build_object('olx_id', 1, 'titulo', 'Apto A', 'preco', 5000, 'bairro', 'Ponta Negra', 'anunciante', 'Sampaio', 'anunciante_id', 'u1',
                       'telefone_mascarado', '9299981*...', 'descricao', 'alugo 92 9998I-9200 whatsapp', 'url', 'https://am.olx.com.br/a-1', 'data', '2026-10-18T10:00:00Z', 'fotos', jsonb_build_array('https://img/1.jpg')),
    jsonb_build_object('olx_id', 2, 'titulo', 'Apto B', 'preco', 7000, 'bairro', 'Adrianópolis', 'anunciante', 'Sampaio', 'anunciante_id', 'u1',
                       'telefone_mascarado', '9299981*...', 'descricao', '92 99981-9200 ou 92 99117-5725', 'url', 'https://am.olx.com.br/a-2', 'data', '2026-10-17T10:00:00Z'),
    jsonb_build_object('olx_id', 3, 'titulo', 'Apto C sem fone', 'preco', 4500, 'bairro', 'Flores', 'anunciante', 'Fulano', 'descricao', 'lindo apto', 'url', 'https://am.olx.com.br/a-3')
  )), 'teste') AS r \gset
SELECT :'r'::jsonb AS importou;
SELECT (:'r'::jsonb->>'lista_id')::bigint AS lid \gset

\echo '--- contatos da lista (esperado 2: 92999819200 com 2 anúncios e confirmado, 92991175725 com 1)'
SELECT c->>'nome' nome, c->>'telefone_fmt' tel, c->>'n_anuncios' n, c->>'confirmado' conf, c->'bairros' bairros, c->>'preco_min' pmin, c->>'preco_max' pmax
  FROM jsonb_array_elements(site_scrap_contatos(:lid)->'contatos') c;
SELECT site_scrap_contatos(:lid, '5725')->>'total' AS busca_por_digitos, site_scrap_contatos(:lid, 'samp')->>'total' AS busca_por_nome,
       site_scrap_contatos(NULL)->>'total' AS todos_sem_lista;

\echo '--- listas (contagens)'
SELECT l->>'nome' nome, l->>'contatos' contatos, l->>'anuncios' anuncios, l->>'anuncios_sem_telefone' sem_tel, l->'por_status' por_status
  FROM jsonb_array_elements(site_scrap_listas()->'listas') l WHERE l->>'nome' LIKE 'TESTE 407%';

\echo '--- reimportar o mesmo (idempotente: anúncios atualizados, contatos iguais) e o status preservado'
SELECT (site_scrap_contatos(:lid, '99981-9200')->'contatos'->0->>'id')::bigint AS cid \gset
SELECT site_scrap_contatos_acao(ARRAY[:cid]::bigint[], 'status', 'interessado') AS acao_status;
SELECT site_scrap_contatos_acao(ARRAY[:cid]::bigint[], 'etiqueta_por', 'VIP') AS acao_etiqueta;
SELECT site_scrap_importar(jsonb_build_object('lista', jsonb_build_object('nome', 'TESTE 407 apto aluguel'),
  'anuncios', jsonb_build_array(jsonb_build_object('olx_id', 1, 'titulo', 'Apto A renomeado', 'preco', 5200, 'bairro', 'Ponta Negra', 'anunciante', 'Sampaio',
                                                   'descricao', '92 99981-9200', 'url', 'https://am.olx.com.br/a-1'))), 'teste') AS reimport;
SELECT c->>'telefone_fmt' tel, c->>'status' status, c->'etiquetas' etiquetas, c->>'n_anuncios' n, c->>'exemplo_titulo' exemplo
  FROM jsonb_array_elements(site_scrap_contatos(:lid)->'contatos') c;

\echo '--- contato à mão, inválido, repetido; editar; CSV'
SELECT site_scrap_contato_salvar(jsonb_build_object('lista_id', :lid, 'nome', 'Maria', 'telefone', '(92) 98111-2222', 'etiquetas', jsonb_build_array('Dona')), 'teste') AS manual;
SELECT site_scrap_contato_salvar(jsonb_build_object('lista_id', :lid, 'nome', 'Lixo', 'telefone', '123'), 'teste') AS invalido;
SELECT site_scrap_contato_salvar(jsonb_build_object('lista_id', :lid, 'nome', 'Maria 2', 'telefone', '92981112222'), 'teste') AS repetido;
SELECT site_scrap_contato_salvar(jsonb_build_object('id', :cid, 'nome', 'Sampaio Imóveis', 'observacao', 'ligar amanhã'), 'teste') AS editado;
SELECT site_scrap_importar_contatos(:lid, '[{"nome":"João","telefone":"92 99333-4444"},{"nome":"João de novo","telefone":"92993334444"},{"nome":"Sem fone","telefone":"x"},{"nome":"Maria repetida","telefone":"92981112222"}]'::jsonb, 'teste') AS csv;

\echo '--- segunda lista: copiar e mover; "Todos" junta por telefone'
SELECT site_scrap_lista_salvar(jsonb_build_object('nome', 'TESTE 407 venda'), 'teste') AS l2 \gset
SELECT (:'l2'::jsonb->>'id')::bigint AS lid2 \gset
SELECT site_scrap_contatos_acao(ARRAY[:cid]::bigint[], 'copiar', :'lid2') AS copiou;
SELECT site_scrap_contatos(NULL)->>'total' AS todos_total, site_scrap_contatos(:lid)->>'total' AS lista1, site_scrap_contatos(:lid2)->>'total' AS lista2;
SELECT c->>'telefone_fmt' tel, c->'tambem_em' tambem_em FROM jsonb_array_elements(site_scrap_contatos(:lid)->'contatos') c WHERE c->>'telefone' = '92999819200';
SELECT site_scrap_anuncios('(92) 99981-9200') -> 0 ->> 'titulo' AS anuncio_do_contato, jsonb_array_length(site_scrap_anuncios('92999819200')) AS n_anuncios;
SELECT site_scrap_contatos_acao((SELECT array_agg((c->>'id')::bigint) FROM jsonb_array_elements(site_scrap_contatos(:lid2)->'contatos') c), 'apagar') AS apagou;
SELECT site_scrap_lista_apagar(:lid2) AS lista2_apagada, site_scrap_lista_apagar(:lid) AS lista1_apagada;
RESET ROLE;
SELECT count(*) AS sobrou FROM scrap_contato WHERE lista_id IN (:lid, :lid2);
