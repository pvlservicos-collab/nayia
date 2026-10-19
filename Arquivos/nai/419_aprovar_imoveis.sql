-- 419: IMÓVEIS › APROVAR IMÓVEIS (Pedro, 19/10/2026)
--
-- Pedro: "liste todos os imóveis que os proprietários mandaram pelo WhatsApp ou confirmaram a autorização pela OLX e
-- hoje ainda não estão disponíveis para a gente; crie uma aba lá em Imóveis, Aprovar imóveis, põe lá a origem, todos os
-- dados que temos, igual no cadastro rápido, mas esse quero só esses da lista, com uma opção de editar cada campo".
--
-- A lista (site_aprovar_imoveis), cada item com a origem, o dono, o motivo e os MESMOS campos do cadastro:
--   ficha   o dono ditou um imóvel NOVO na conversa do WhatsApp (captacao_cadastro, coletando/pronto, sem imóvel);
--           os campos são os que a IA já preparou (captacao_ficha_campos, 327). A cópia "repetido" do palpite não entra.
--   bot     o bot da OLX mandou com a autorização do dono escrita (privado.olx_bot_imovel pendente, 260).
--   imovel  já é cadastro e não está Disponível:
--             - nasceu de uma ficha da conversa (captacao_cadastro aplicada nele, tipo novo) ou do bot da OLX / do
--               favorito da OLX (origem 'olx') e ainda está em Rascunho;
--             - o dono mandou ATUALIZAÇÃO pela conversa e ninguém aplicou;
--             - o dono disse "disponível" na captação (captacao_leads.situacao) e o imóvel continua fora.
--           Excluído e parceiro (e_parceiro: "Parceria nunca sai") ficam fora.
-- Editar = o PUT de sempre (/admin/api/imoveis/<código>). A ficha e o envio do bot viram pré-cadastro (Rascunho) no
-- primeiro editar ou no aprovar, pelas rotas que já existem (POST /admin/api/imoveis + juntar; aprovar do bot).
-- "Tirar da lista" grava em privado.imovel_aprovar_fora: não apaga nem muda nada da origem, e volta pelo DELETE.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS privado.imovel_aprovar_fora (
  chave     text PRIMARY KEY,               -- 'ficha:<id>' | 'bot:<id>' | 'imovel:<código>'
  motivo    text,
  quem      text,
  criado_em timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE privado.imovel_aprovar_fora IS '419: o que foi tirado da aba Imóveis › Aprovar imóveis (a origem não muda; voltar = DELETE da linha).';

CREATE OR REPLACE FUNCTION public.site_aprovar_imoveis()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'privado' SET jit TO 'off' AS $function$
  WITH fora AS (SELECT chave FROM privado.imovel_aprovar_fora),
  fotos AS (SELECT codigo, count(*)::int AS n, (array_agg(url ORDER BY e_capa DESC, ordem NULLS LAST, id))[1:4] AS primeiras
              FROM imovel_fotos GROUP BY codigo),
  linha_do_lead AS (
    SELECT l.id, l.nome, l.telefone, l.situacao, l.respondeu_em,
           CASE l.canal WHEN 'oficial' THEN 'WhatsApp oficial (92) 8456-0874' WHEN 'zapi' THEN 'WhatsApp da captação (8595)'
                        WHEN 'parceria' THEN 'WhatsApp da Parceria' ELSE 'WhatsApp' END AS linha
      FROM captacao_leads l),
  -- 1. a ficha de imóvel novo que o dono ditou na conversa
  fichas AS (
    SELECT 'ficha:' || c.id AS chave, 'ficha' AS fonte, c.id AS item, NULL::int AS codigo,
           'Proprietário pelo WhatsApp' AS origem,
           coalesce(ll.linha, 'WhatsApp') || ' · ficha ' || c.id || CASE c.estado WHEN 'pronto' THEN ' (completa)' ELSE ' (ainda colhendo dados)' END AS origem_detalhe,
           greatest(c.atualizado_em, a.analisado_em) AS quando,
           ll.nome AS dono_nome, ll.telefone AS dono_tel, 'Sem cadastro' AS status,
           'o dono mandou este imóvel pelo WhatsApp e ele ainda não está cadastrado' AS motivo,
           pa.categoria AS palpite, pa.porque AS palpite_porque, a.observacao,
           coalesce(jsonb_array_length(CASE WHEN jsonb_typeof(c.fotos) = 'array' THEN c.fotos END), 0) AS n_fotos,
           coalesce((SELECT jsonb_agg(t.u) FROM (SELECT u FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(c.fotos) = 'array' THEN c.fotos ELSE '[]' END) u
                                                  WHERE u ~ '^https?://' LIMIT 4) t), '[]') AS primeiras,
           NULL::text AS link,
           jsonb_build_object(
             'tipo', coalesce(a.campos->>'tipo', c.dados->>'tipo'), 'bairro', coalesce(a.campos->>'bairro', c.dados->>'bairro'),
             'condominio', coalesce(a.campos->>'condominio', c.dados->>'condominio'),
             'logradouro', a.campos->>'logradouro', 'numero', a.campos->>'numero', 'complemento', a.campos->>'complemento',
             'quartos', a.campos->'quartos', 'suites', a.campos->'suites', 'banheiros', a.campos->'banheiros', 'vagas', a.campos->'vagas',
             'area_util', a.campos->'area_util', 'area_total', a.campos->'area_total', 'andar', a.campos->>'andar',
             'mobilia', a.campos->>'mobilia', 'valor_aluguel', a.campos->'valor_aluguel', 'valor_venda', a.campos->'valor_venda',
             'taxa_condominio', a.campos->'taxa_condominio', 'iptu', a.campos->'iptu',
             'descricao', coalesce(a.campos->>'descricao', c.dados->>'detalhes'), 'caracteristicas', a.campos->'caracteristicas',
             'negocio', coalesce(a.campos->>'negocio', c.dados->>'negocio')) AS campos,
           c.dados AS o_que_ele_disse
      FROM captacao_cadastro c
      LEFT JOIN captacao_ficha_campos a ON a.ficha_id = c.id
      LEFT JOIN linha_do_lead ll ON ll.id = c.lead_id
      LEFT JOIN cadastro_rapido_palpite pa ON pa.fonte = 'ficha' AND pa.item = c.id
     WHERE c.estado IN ('coletando', 'pronto') AND c.codigo IS NULL AND c.tipo = 'novo'
       AND coalesce(pa.categoria, '') <> 'repetido'
       AND 'ficha:' || c.id NOT IN (SELECT chave FROM fora)),
  -- 2. o bot da OLX, com a autorização do dono
  bot AS (
    SELECT 'bot:' || b.id, 'bot', b.id, NULL::int,
           'OLX com autorização do proprietário',
           'bot da OLX (' || b.corretor_nome || ') · autorização: ' || b.autorizacao_como,
           b.atualizado_em, b.proprietario_nome, b.proprietario_telefone, 'Sem cadastro',
           'o dono autorizou pela OLX e o imóvel ainda não está cadastrado',
           NULL::text, NULL::text, nullif(btrim(b.dados->>'observacoes'), ''),
           coalesce(array_length(b.fotos, 1), 0), coalesce(to_jsonb(b.fotos[1:4]), '[]'), b.link,
           jsonb_build_object(
             'tipo', b.dados->>'tipo', 'bairro', b.dados->>'bairro', 'condominio', b.dados->>'condominio_nome',
             'logradouro', b.dados->>'endereco', 'numero', b.dados->>'numero', 'complemento', b.dados->>'complemento',
             'quartos', b.dados->'quartos', 'suites', b.dados->'suites', 'banheiros', b.dados->'banheiros', 'vagas', b.dados->'vagas',
             'area_util', b.dados->'area_m2', 'area_total', b.dados->'area_total_m2', 'andar', b.dados->>'andar',
             'mobilia', b.dados->>'mobilia', 'valor_aluguel', coalesce(b.dados->'preco_aluguel', CASE WHEN b.dados->>'finalidade' ~* 'alug|loca' THEN b.dados->'preco' END),
             'valor_venda', coalesce(b.dados->'preco_venda', CASE WHEN b.dados->>'finalidade' ~* 'vend' THEN b.dados->'preco' END),
             'taxa_condominio', b.dados->'valor_condominio', 'iptu', b.dados->'iptu',
             'descricao', coalesce(b.dados->>'descricao', b.dados->>'titulo'), 'caracteristicas', b.dados->'caracteristicas',
             'negocio', b.dados->>'finalidade'),
           b.dados
      FROM privado.olx_bot_imovel b
     WHERE b.estado = 'pendente' AND 'bot:' || b.id NOT IN (SELECT chave FROM fora)),
  -- 3. já é cadastro e não está Disponível
  motivo_do_imovel AS (
    SELECT i.codigo,
           (SELECT 'Proprietário pelo WhatsApp' FROM captacao_cadastro c WHERE c.codigo = i.codigo AND c.tipo = 'novo' AND c.estado = 'aplicado' LIMIT 1) AS de_ficha,
           (SELECT c.id FROM captacao_cadastro c WHERE c.codigo = i.codigo AND c.tipo = 'atualizar' AND c.estado IN ('coletando', 'pronto') ORDER BY c.id DESC LIMIT 1) AS atualizacao,
           (SELECT l.id FROM captacao_leads l WHERE btrim(l.codigo) = i.codigo::text AND l.situacao = 'disponivel' ORDER BY l.respondeu_em DESC NULLS LAST LIMIT 1) AS disse_disponivel
      FROM imoveis i
     WHERE i.status IS DISTINCT FROM 'Disponível' AND i.status IS DISTINCT FROM 'Excluído' AND NOT i.e_parceiro),
  ims AS (
    SELECT 'imovel:' || i.codigo, 'imovel', i.codigo::bigint, i.codigo,
           CASE WHEN m.de_ficha IS NOT NULL OR m.atualizacao IS NOT NULL OR m.disse_disponivel IS NOT NULL THEN 'Proprietário pelo WhatsApp'
                ELSE 'OLX com autorização do proprietário' END,
           concat_ws(' · ',
             CASE WHEN i.origem = 'olx' AND i.extras->>'cadastrado_pelo' = 'grokbot' THEN 'bot da OLX, aprovado como Rascunho'
                  WHEN i.origem = 'olx' THEN 'importado do anúncio da OLX' END,
             CASE WHEN m.de_ficha IS NOT NULL THEN 'pré-cadastro da ficha do dono' END,
             CASE WHEN m.atualizacao IS NOT NULL THEN 'ficha de atualização ' || m.atualizacao END,
             CASE WHEN m.disse_disponivel IS NOT NULL THEN (SELECT ll.linha FROM linha_do_lead ll WHERE ll.id = m.disse_disponivel) END),
           coalesce((SELECT ll.respondeu_em FROM linha_do_lead ll WHERE ll.id = m.disse_disponivel), i.criado_em),
           coalesce(pr.nome, (SELECT ll.nome FROM linha_do_lead ll WHERE ll.id = m.disse_disponivel)),
           coalesce(pr.telefone, (SELECT ll.telefone FROM linha_do_lead ll WHERE ll.id = m.disse_disponivel)),
           i.status,
           concat_ws('; ',
             CASE WHEN i.status = 'Rascunho' THEN 'pré-cadastro: falta aprovar' END,
             CASE WHEN m.atualizacao IS NOT NULL THEN 'o dono mandou atualização pela conversa e ninguém aplicou' END,
             CASE WHEN m.disse_disponivel IS NOT NULL THEN 'o dono disse que está disponível e o imóvel está ' || coalesce(i.status, 'sem situação') END),
           pa.categoria, pa.porque, NULL::text,
           coalesce(f.n, 0), coalesce(to_jsonb(f.primeiras), '[]'), i.extras->>'olx_url',
           jsonb_build_object(
             'tipo', i.tipo, 'bairro', i.bairro, 'condominio', i.condominio_nome, 'logradouro', i.logradouro, 'numero', i.numero,
             'complemento', i.complemento, 'quartos', i.quartos, 'suites', i.suites, 'banheiros', i.banheiros, 'vagas', i.vagas,
             'area_util', i.area_util, 'area_total', i.area_total, 'andar', i.andar, 'mobilia', i.mobilia,
             'valor_aluguel', i.valor_aluguel, 'valor_venda', i.valor_venda, 'taxa_condominio', i.taxa_condominio, 'iptu', i.iptu,
             'descricao', i.descricao, 'caracteristicas', to_jsonb(i.caracteristicas),
             'negocio', CASE WHEN i.valor_venda > 0 AND coalesce(i.valor_aluguel, 0) = 0 THEN 'venda'
                             WHEN i.valor_aluguel > 0 AND coalesce(i.valor_venda, 0) = 0 THEN 'locação' END),
           (SELECT c.dados FROM captacao_cadastro c WHERE c.id = m.atualizacao)
      FROM motivo_do_imovel m
      JOIN imoveis i ON i.codigo = m.codigo
      LEFT JOIN proprietarios pr ON pr.id = i.proprietario_id
      LEFT JOIN fotos f ON f.codigo = i.codigo
      LEFT JOIN cadastro_rapido_palpite pa ON pa.fonte = 'imovel' AND pa.item = i.codigo
     WHERE ((i.status = 'Rascunho' AND (m.de_ficha IS NOT NULL OR i.origem = 'olx'))
            OR m.atualizacao IS NOT NULL OR m.disse_disponivel IS NOT NULL)
       AND 'imovel:' || i.codigo NOT IN (SELECT chave FROM fora)),
  tudo AS (SELECT * FROM fichas UNION ALL SELECT * FROM bot UNION ALL SELECT * FROM ims)
  SELECT jsonb_build_object(
    'itens', coalesce(jsonb_agg(jsonb_build_object(
               'chave', t.chave, 'fonte', t.fonte, 'item', t.item, 'codigo', t.codigo, 'origem', t.origem,
               'origem_detalhe', t.origem_detalhe, 'quando', t.quando, 'dono', jsonb_build_object('nome', t.dono_nome, 'telefone', t.dono_tel),
               'status', t.status, 'motivo', t.motivo, 'palpite', t.palpite, 'palpite_porque', t.palpite_porque,
               'observacao', t.observacao, 'fotos', t.n_fotos, 'primeiras', t.primeiras, 'link', t.link,
               'campos', t.campos, 'o_que_ele_disse', t.o_que_ele_disse) ORDER BY t.quando DESC NULLS LAST), '[]'),
    'fora', (SELECT count(*) FROM fora))
    FROM tudo t
$function$;

-- tirar da lista (e pôr de volta): não mexe na origem
CREATE OR REPLACE FUNCTION public.site_aprovar_tirar(p_chave text, p_tirar boolean DEFAULT true, p_motivo text DEFAULT NULL, p_quem text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'privado' AS $function$
BEGIN
  IF p_chave !~ '^(ficha|bot|imovel):[0-9]+$' THEN
    RETURN jsonb_build_object('erro', 'chave inválida');
  END IF;
  IF p_tirar THEN
    INSERT INTO privado.imovel_aprovar_fora (chave, motivo, quem) VALUES (p_chave, left(p_motivo, 300), left(p_quem, 60))
    ON CONFLICT (chave) DO UPDATE SET motivo = excluded.motivo, quem = excluded.quem, criado_em = now();
  ELSE
    DELETE FROM privado.imovel_aprovar_fora WHERE chave = p_chave;
  END IF;
  RETURN jsonb_build_object('ok', true);
END
$function$;

REVOKE ALL ON FUNCTION public.site_aprovar_imoveis() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.site_aprovar_tirar(text, boolean, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.site_aprovar_imoveis() TO nay_site_escrita;
GRANT EXECUTE ON FUNCTION public.site_aprovar_tirar(text, boolean, text, text) TO nay_site_escrita;
COMMIT;
