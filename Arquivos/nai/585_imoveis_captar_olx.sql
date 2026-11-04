-- 585: IMÓVEIS CAPTAR OLX (Pedro, 03/11/2026): "Analisa nossa banca de imóveis da olx, quero que retire uma lista e ponha
-- lá no menu do crm IMOVEIS CAPTAR OLX que vai ser só imóveis com alta probabilidade de serem de proprietários e não de
-- corretores, tire dessa lista os proprietários que já conhecemos, os corretores que já conhecemos, todos que já falamos
-- e quem tem creci, ou imobiliária lá, ou quem tem muitos imóveis, e separa lá uma lista de contatos com um botão chamar
-- no WhatsApp e outro chamar na OLX".
--
-- A base: os anúncios de PARTICULAR da lista "OLX · Recentes de Manaus" (scrap_lista 30, raspada em 30/10), abertos um a
-- um pelo Chrome do Agente OLX para ler a descrição (de onde sai o telefone) e a conta do anunciante. Quem carrega é
-- Arquivos/olx-captar-03-11/montar.py, que já tira o que dá para ver no anúncio (conta profissional, CRECI ou imobiliária
-- no texto, código de imobiliária, 3+ anúncios da mesma conta ou do mesmo telefone) e grava em olx_captar com a nota e os
-- sinais de dono.
-- O que muda com o tempo é conferido NA HORA, a cada leitura (crm_olx_captar): telefone de corretor ou proprietário
-- cadastrado, de quem já falou com a gente por qualquer número (todo o histórico da Parceria, do Leads/Oficial, da Nay e o
-- falou_conosco), das listas da Base e de corretores/imobiliárias da OLX no Scrap; o anúncio já cadastrado, já consultado
-- pelo bot, no chat da OLX ou numa busca de parceiro. As conversas do CRM a rota confere (crmdb).
-- O clique em "Chamar" fica anotado (quem e quando), para a mesma pessoa não ser chamada duas vezes.
BEGIN;

CREATE TABLE IF NOT EXISTS public.olx_captar (
  olx_id            bigint PRIMARY KEY,
  url               text NOT NULL,
  titulo            text,
  preco             numeric,
  preco_texto       text,
  tipo_negocio      text,
  categoria         text,
  bairro            text,
  quartos           integer,
  area_m2           numeric,
  foto              text,
  n_fotos           integer,
  anunciante        text,
  anunciante_id     text,
  telefone          text,                          -- o primeiro da descrição, 55+DDD+número (scrap_telefone_normalizar)
  telefones         text[] NOT NULL DEFAULT '{}',
  telefone_mascarado text,
  whatsapp          boolean,
  descricao         text,
  publicado_em      timestamptz,
  nota              integer NOT NULL DEFAULT 0,    -- 0-100: a chance de ser o dono
  sinais            text[] NOT NULL DEFAULT '{}',  -- por que parece dono
  fora              text,                          -- por que saiu na carga (corretor, muitos anúncios...); NULL = entra
  carregado_em      timestamptz NOT NULL DEFAULT now(),
  chamado_em        timestamptz,
  chamado_por       text,
  chamado_como      text CHECK (chamado_como IN ('whatsapp', 'olx'))
);
CREATE INDEX IF NOT EXISTS olx_captar_fora_idx ON public.olx_captar (fora) WHERE fora IS NULL;
REVOKE ALL ON public.olx_captar FROM PUBLIC;
GRANT SELECT ON public.olx_captar TO nay_leitura;

-- a lista para o CRM: só quem entra, sem quem já conhecemos; e quantos saíram por cada motivo
CREATE OR REPLACE FUNCTION public.crm_olx_captar()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  WITH base AS MATERIALIZED (SELECT * FROM olx_captar WHERE fora IS NULL),
  chaves AS MATERIALIZED (SELECT DISTINCT unnest(telefones) t FROM base),
  ch AS MATERIALIZED (SELECT t, nay_fone_chave(nay_fone_com_ddi(t)) AS chave FROM chaves),
  conhecido AS MATERIALIZED (
    SELECT DISTINCT ON (chave) chave, motivo FROM (
      SELECT nay_fone_chave(nay_fone_com_ddi(x.telefone)) chave, 'corretor que já conhecemos' motivo, 1 o
        FROM corretores x WHERE coalesce(x.telefone, '') <> ''
      UNION ALL SELECT nay_fone_chave(nay_fone_com_ddi(x.telefone)), 'proprietário que já conhecemos', 2
        FROM proprietarios x WHERE coalesce(x.telefone, '') <> ''
      UNION ALL SELECT f.chave, 'já falamos (' || array_to_string(f.origens, ', ') || ')', 3 FROM privado.falou_conosco f
      UNION ALL SELECT nay_fone_chave(nay_fone_com_ddi(regexp_replace(t, '\D', '', 'g'))), 'já falamos pela Parceria', 4
        FROM (SELECT DISTINCT telefone t FROM mensagens WHERE coalesce(telefone, '') !~ '@') m
      UNION ALL SELECT nay_fone_chave(nay_fone_com_ddi(regexp_replace(t, '\D', '', 'g'))), 'já falamos pelo Leads/Oficial', 5
        FROM (SELECT DISTINCT telefone t FROM captacao_mensagens) m
      UNION ALL SELECT nay_fone_chave(nay_fone_com_ddi(n.chave)), 'já falou com a Nay', 6 FROM nai_contato n WHERE n.chave !~ '(@|lid)'
      UNION ALL SELECT scrap_chave(s.telefone), 'está no Scrap: ' || l.nome, 7
        FROM scrap_contato s JOIN scrap_lista l ON l.id = s.lista_id
       WHERE l.pasta IN ('Base', 'Blacklist') OR (l.pasta = 'OLX' AND l.nome ~* '(corretor|imobili)')
      UNION ALL SELECT nay_fone_chave(nay_fone_com_ddi(regexp_replace(a.telefone, '\D', '', 'g'))), 'o bot da OLX já falou com ele', 8
        FROM privado.anuncio_consulta a WHERE coalesce(a.telefone, '') <> ''
    ) z WHERE chave IN (SELECT chave FROM ch WHERE chave IS NOT NULL)
    ORDER BY chave, o),
  anuncio_falado AS MATERIALIZED (
    SELECT DISTINCT o FROM (
      SELECT (extras->>'olx_id')::text o FROM imoveis WHERE extras ? 'olx_id'
      UNION ALL SELECT id_anuncio FROM privado.anuncio_consulta WHERE id_anuncio IS NOT NULL
      UNION ALL SELECT substring(link from '(\d{8,})(?:\D*$)') FROM privado.anuncio_consulta
      UNION ALL SELECT list_id FROM privado.olx_chat WHERE list_id IS NOT NULL
      UNION ALL SELECT substring(escolhido->>'url' from '(\d{8,})(?:\D*$)') FROM privado.olx_busca_parceiro WHERE escolhido IS NOT NULL
    ) y WHERE o IS NOT NULL),
  julgado AS MATERIALIZED (
    SELECT b.*,
           (SELECT k.motivo FROM ch JOIN conhecido k ON k.chave = ch.chave WHERE ch.t = ANY (b.telefones) LIMIT 1) AS motivo,
           (b.olx_id::text IN (SELECT o FROM anuncio_falado)) AS anuncio_ja
      FROM base b)
  SELECT jsonb_build_object(
    'itens', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'olx_id', j.olx_id, 'url', j.url, 'titulo', j.titulo, 'preco', j.preco, 'preco_texto', j.preco_texto,
        'tipo_negocio', j.tipo_negocio, 'categoria', j.categoria, 'bairro', j.bairro, 'quartos', j.quartos, 'area_m2', j.area_m2,
        'foto', j.foto, 'n_fotos', j.n_fotos, 'anunciante', j.anunciante, 'telefone', j.telefone, 'telefones', j.telefones,
        'whatsapp', j.whatsapp, 'descricao', left(j.descricao, 600), 'publicado_em', j.publicado_em, 'nota', j.nota,
        'sinais', j.sinais, 'chamado_em', j.chamado_em, 'chamado_por', j.chamado_por, 'chamado_como', j.chamado_como)
        ORDER BY (j.chamado_em IS NOT NULL), (j.telefone IS NULL), j.nota DESC, j.publicado_em DESC NULLS LAST)
      FROM julgado j WHERE j.motivo IS NULL AND NOT j.anuncio_ja), '[]'::jsonb),
    'fora', (SELECT coalesce(jsonb_object_agg(m, n), '{}'::jsonb) FROM (
        SELECT m, count(*) n FROM (
          SELECT fora m FROM olx_captar WHERE fora IS NOT NULL
          UNION ALL SELECT CASE WHEN anuncio_ja THEN 'anúncio que já cadastramos ou consultamos'
                                ELSE regexp_replace(motivo, ' \(.*$', '') END
            FROM julgado WHERE motivo IS NOT NULL OR anuncio_ja) q GROUP BY m) r),
    'carregado_em', (SELECT max(carregado_em) FROM olx_captar),
    'analisados', (SELECT count(*) FROM olx_captar))
$function$;

-- anota o clique em "Chamar no WhatsApp" / "Chamar na OLX" (o primeiro fica; não apaga quem chamou antes)
CREATE OR REPLACE FUNCTION public.crm_olx_captar_chamado(p_olx_id bigint, p_como text, p_quem text)
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  UPDATE olx_captar SET chamado_em = now(), chamado_por = left(coalesce(p_quem, ''), 120), chamado_como = p_como
   WHERE olx_id = p_olx_id AND chamado_em IS NULL AND p_como IN ('whatsapp', 'olx')
  RETURNING true
$function$;

REVOKE ALL ON FUNCTION public.crm_olx_captar() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.crm_olx_captar_chamado(bigint, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crm_olx_captar() TO nay_disparo, nay;
GRANT EXECUTE ON FUNCTION public.crm_olx_captar_chamado(bigint, text, text) TO nay_disparo, nay;

COMMIT;
