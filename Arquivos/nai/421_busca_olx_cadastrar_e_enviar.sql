-- 421: BUSCA NA OLX > CADASTRAR > ENVIAR (Pedro, 19/10/2026: "Nay não tem imóvel > buscar na OLX > cadastrar > enviar ...
-- se não [falamos com ele] mandar lá no nosso grupo pra gente falar, e aí assim que o imóvel for cadastrado e dado como
-- disponível ela manda ao lead"; "se o cara disser que tá disponível ela pode oferecer").
-- Quando a ordem vai ao grupo (anunciante desconhecido, sem resposta, resposta que precisa de gente), o nay-olx cria o
-- PRÉ-CADASTRO (Rascunho, origem olx, extras.busca_parceiro = a ordem) e a ordem fica em 'aguardando_cadastro' com o
-- código; quando a equipe deixa Disponível, a Nay manda ao cliente ('enviado'). Descartado ou 7 dias: 'sem_cadastro'.
-- O pré-cadastro aparece em Imóveis > Aprovar imóveis (mesmo marcado como parceiro, quando o anúncio é de corretor).
BEGIN;
SET LOCAL lock_timeout = '3s';

ALTER TABLE privado.olx_busca_parceiro ADD COLUMN IF NOT EXISTS codigo integer;
ALTER TABLE privado.olx_busca_parceiro DROP CONSTRAINT IF EXISTS olx_busca_parceiro_estado_check;
ALTER TABLE privado.olx_busca_parceiro ADD CONSTRAINT olx_busca_parceiro_estado_check
  CHECK (estado IN ('pendente', 'buscando', 'sem_navegador', 'sem_resultado', 'perguntado', 'confirmado', 'negado',
                    'sem_resposta', 'no_grupo', 'erro', 'cancelado', 'aguardando_cadastro', 'enviado', 'sem_cadastro'));
DROP INDEX IF EXISTS privado.olx_busca_parceiro_aberta;
CREATE UNIQUE INDEX olx_busca_parceiro_aberta ON privado.olx_busca_parceiro (lead)
  WHERE estado IN ('pendente', 'buscando', 'sem_navegador', 'perguntado', 'aguardando_cadastro');

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
     WHERE i.status IS DISTINCT FROM 'Disponível' AND i.status IS DISTINCT FROM 'Excluído'
       AND (NOT i.e_parceiro OR i.extras ? 'busca_parceiro')),          -- 421: o achado na OLX para um cliente entra
  ims AS (
    SELECT 'imovel:' || i.codigo, 'imovel', i.codigo::bigint, i.codigo,
           CASE WHEN i.extras ? 'busca_parceiro' THEN 'OLX: achado para um cliente da Nay'
                WHEN m.de_ficha IS NOT NULL OR m.atualizacao IS NOT NULL OR m.disse_disponivel IS NOT NULL THEN 'Proprietário pelo WhatsApp'
                ELSE 'OLX com autorização do proprietário' END,
           concat_ws(' · ',
             CASE WHEN i.extras ? 'busca_parceiro' THEN 'busca na OLX para o cliente ' || coalesce(i.extras->>'cliente', '?')
                         || ' (nota ' || coalesce(i.extras->>'nota', '?') || ')'
                  WHEN i.origem = 'olx' AND i.extras->>'cadastrado_pelo' = 'grokbot' THEN 'bot da OLX, aprovado como Rascunho'
                  WHEN i.origem = 'olx' THEN 'importado do anúncio da OLX' END,
             CASE WHEN m.de_ficha IS NOT NULL THEN 'pré-cadastro da ficha do dono' END,
             CASE WHEN m.atualizacao IS NOT NULL THEN 'ficha de atualização ' || m.atualizacao END,
             CASE WHEN m.disse_disponivel IS NOT NULL THEN (SELECT ll.linha FROM linha_do_lead ll WHERE ll.id = m.disse_disponivel) END),
           coalesce((SELECT ll.respondeu_em FROM linha_do_lead ll WHERE ll.id = m.disse_disponivel), i.criado_em),
           coalesce(pr.nome, (SELECT ll.nome FROM linha_do_lead ll WHERE ll.id = m.disse_disponivel), i.extras->>'anunciante'),
           coalesce(pr.telefone, (SELECT ll.telefone FROM linha_do_lead ll WHERE ll.id = m.disse_disponivel), i.extras->>'anunciante_telefone'),
           i.status,
           concat_ws('; ',
             CASE WHEN i.extras ? 'busca_parceiro' THEN 'a Nay achou na OLX para um cliente: falar com o anunciante; quando ficar Disponível ela manda ao cliente sozinha'
                  WHEN i.status = 'Rascunho' THEN 'pré-cadastro: falta aprovar' END,
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
    'fora', (SELECT count(*) FROM fora),
    'tirados', (SELECT coalesce(jsonb_agg(jsonb_build_object('chave', f.chave, 'motivo', f.motivo, 'quem', f.quem, 'quando', f.criado_em)
                                          ORDER BY f.criado_em DESC), '[]') FROM privado.imovel_aprovar_fora f))
    FROM tudo t
$function$;

COMMIT;
