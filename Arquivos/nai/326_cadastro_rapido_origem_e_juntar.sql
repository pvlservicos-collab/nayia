-- 326 -- Cadastro rápido: de onde veio cada cadastro, e "na verdade é atualização deste outro imóvel"
--
-- Pedro, 09/10/2026, sobre a aba CADASTRO RÁPIDO: "se na verdade esse imóvel é outro quero poder marcar lá, em um
-- campo, pesquisar outro e dizer: na verdade isso é uma atualização desse imóvel, aí abre o campo o que mudou e eu
-- edito por lá" e "quero saber a origem, um card só da origem, de onde veio, se por WhatsApp de qual número e quando,
-- para eu checar 1 a 1".
--
-- 1. site_origem_do_cadastro(codigo, ficha) -> jsonb com o card da origem:
--      OLX (link e título do anúncio), secretária (WhatsApp da Nay 92 9445-3618, quem e quando), captação (conversa
--      no WhatsApp oficial 92 8456-0874 ou no da captação 92 8595-6408, o dono, o telefone dele e quando), card da
--      captação no CRM, planilha do site antigo (captado por / em / indicado por), cadastro no site.
--    Telefone do dono é dado pessoal: a função só é chamada pela rota /admin/api/imoveis/origem, que pede a senha
--    do /admin (ou o login do CRM, pelo proxy).
-- 2. site_juntar_cadastro(de_codigo, de_ficha, em, fotos, quem) -> o cadastro vira atualização do imóvel `em`:
--      · as fotos dele vão para o `em` (depois das que já tinha, sem repetir o mesmo link), se pedido;
--      · o dono passa para o `em` se o `em` não tinha;
--      · o imóvel duplicado vira 'Excluído' (sai do site, da Nay e da lista; linha de imoveis NUNCA se apaga) com
--        extras.atualizacao_de = em; a ficha da conversa fica 'aplicado' no `em`.
--    Os CAMPOS que mudaram não passam por aqui: a tela manda pelo PUT de sempre, só o que a pessoa marcou.
--    A mesma função liga a ficha ao imóvel que acabou de ser cadastrado a partir dela (fotos + dono + aplicada).
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION public.site_origem_do_cadastro(p_codigo integer, p_ficha bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  i      imoveis;
  c      captacao_cadastro;
  l      captacao_leads;
  n      nai_imovel_novo;
  k      nai_contato;
  v_fotos int;
  v_ficha bigint := p_ficha;
  v_lead  bigint;
BEGIN
  IF p_codigo IS NOT NULL THEN
    SELECT * INTO i FROM imoveis WHERE codigo = p_codigo;
    IF i.codigo IS NULL THEN RETURN NULL; END IF;
    SELECT count(*) INTO v_fotos FROM imovel_fotos WHERE codigo = p_codigo AND coalesce(url, '') <> '';

    IF i.origem = 'olx' OR i.extras ? 'olx_url' THEN
      RETURN jsonb_build_object('fonte', 'olx', 'rotulo', 'Anúncio da OLX', 'link', i.extras->>'olx_url',
        'titulo', i.extras->>'olx_titulo', 'quando', i.criado_em, 'fotos', v_fotos,
        'detalhe', 'trazido pelo favorito "Enviar para Imob Easy"');
    END IF;

    SELECT * INTO n FROM nai_imovel_novo WHERE codigo = p_codigo ORDER BY id DESC LIMIT 1;
    IF n.id IS NOT NULL THEN
      SELECT * INTO k FROM nai_contato WHERE id = n.contato_id;
      RETURN jsonb_build_object('fonte', 'secretaria', 'rotulo', 'Conversa com a secretária da Nay',
        'linha', 'WhatsApp da Nay 92 9445-3618', 'nome', coalesce(k.nome_completo, k.nome_whatsapp),
        'telefone', k.telefone, 'quando', n.criado_em, 'fotos', v_fotos);
    END IF;

    IF coalesce(i.extras->>'captacao_lead', '') ~ '^\d+$' THEN v_lead := (i.extras->>'captacao_lead')::bigint; END IF;
    IF v_ficha IS NULL THEN
      v_ficha := CASE WHEN coalesce(i.extras->>'captacao_ficha', '') ~ '^\d+$' THEN (i.extras->>'captacao_ficha')::bigint END;
      v_ficha := coalesce(v_ficha, (SELECT max(x.id) FROM captacao_cadastro x WHERE x.codigo = p_codigo));
    END IF;
  END IF;

  IF v_ficha IS NOT NULL THEN
    SELECT * INTO c FROM captacao_cadastro WHERE id = v_ficha;
    v_lead := coalesce(v_lead, c.lead_id);
  END IF;
  IF v_lead IS NULL AND i.origem IN ('crm', 'captacao') THEN
    SELECT x.id INTO v_lead FROM captacao_leads x
     WHERE x.proprietario_id = coalesce(i.proprietario_id, (SELECT p.proprietario_id FROM imovel_privado p WHERE p.codigo = i.codigo))
     ORDER BY x.respondeu_em DESC NULLS LAST LIMIT 1;
  END IF;

  IF v_lead IS NOT NULL THEN
    SELECT * INTO l FROM captacao_leads WHERE id = v_lead;
    RETURN jsonb_build_object(
      'fonte', CASE WHEN i.origem = 'crm' THEN 'crm' ELSE 'conversa' END,
      'rotulo', CASE WHEN i.origem = 'crm' THEN 'Cadastrado pelo card da captação no CRM' ELSE 'Conversa da captação' END,
      'linha', CASE l.canal WHEN 'oficial' THEN 'WhatsApp oficial 92 8456-0874' ELSE 'WhatsApp da captação 92 8595-6408' END,
      'nome', l.nome, 'telefone', l.telefone,
      'quando', coalesce(c.criado_em, i.criado_em), 'respondeu_em', l.respondeu_em,
      'fotos', coalesce(v_fotos, (SELECT count(*) FROM jsonb_array_elements(c.fotos))::int),
      'detalhe', CASE WHEN c.id IS NOT NULL THEN 'o dono contou na conversa' END);
  END IF;

  IF i.codigo IS NOT NULL THEN
    IF i.origem LIKE 'planilha%' THEN
      RETURN jsonb_build_object('fonte', 'antigo', 'rotulo', 'Planilha do site antigo', 'quando', i.criado_em, 'fotos', v_fotos,
        'detalhe', nullif(concat_ws(' · ', 'captado por ' || nullif(btrim(i.extras->>'captado por'), ''),
                                           'captado em ' || nullif(btrim(i.extras->>'captado em'), ''),
                                           'indicado por ' || nullif(btrim(i.extras->>'indicado por'), '')), ''));
    END IF;
    RETURN jsonb_build_object('fonte', coalesce(i.origem, '?'),
      'rotulo', CASE i.origem WHEN 'site' THEN 'Cadastrado no site (admin)'
                              WHEN 'crm' THEN 'Cadastrado pelo card da captação no CRM'
                              WHEN 'captacao' THEN 'Ficha da captação aplicada'
                              ELSE 'Origem: ' || coalesce(i.origem, 'não registrada') END,
      'quando', i.criado_em, 'fotos', v_fotos,
      'detalhe', nullif(concat_ws(' · ', 'captado por ' || nullif(btrim(coalesce(i.captado_por, i.extras->>'captado por')), ''),
                                         'captado em ' || nullif(btrim(coalesce(i.captado_em, i.extras->>'captado em')), '')), ''));
  END IF;
  RETURN NULL;
END
$function$;

CREATE OR REPLACE FUNCTION public.site_juntar_cadastro(p_de_codigo integer, p_de_ficha bigint, p_em integer,
                                                       p_fotos boolean, p_quem text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '3s'
AS $function$
DECLARE
  v_base   int;
  v_tinha  int;
  v_n      int := 0;
  v_dono   int;
  v_quem   text := left(coalesce(nullif(btrim(p_quem), ''), 'cadastro rápido'), 80);
  c        captacao_cadastro;
BEGIN
  IF p_em IS NULL OR NOT EXISTS (SELECT 1 FROM imoveis WHERE codigo = p_em) THEN
    RAISE EXCEPTION 'o imóvel % não existe', p_em;
  END IF;
  IF (p_de_codigo IS NULL) = (p_de_ficha IS NULL) THEN
    RAISE EXCEPTION 'diga de onde vem: um imóvel OU uma ficha';
  END IF;
  IF p_de_codigo = p_em THEN RAISE EXCEPTION 'é o mesmo imóvel'; END IF;

  SELECT coalesce(max(ordem), 0), count(*) INTO v_base, v_tinha FROM imovel_fotos WHERE codigo = p_em;

  IF p_de_codigo IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM imoveis WHERE codigo = p_de_codigo) THEN RAISE EXCEPTION 'o imóvel % não existe', p_de_codigo; END IF;
    IF p_fotos THEN
      INSERT INTO imovel_fotos (codigo, ordem, url, e_capa)
      SELECT p_em, v_base + q.o, q.url, v_tinha = 0 AND q.o = 1
        FROM (SELECT f.url, row_number() OVER (ORDER BY f.ordem, f.id) AS o
                FROM imovel_fotos f
               WHERE f.codigo = p_de_codigo AND coalesce(f.url, '') <> ''
                 AND f.url NOT IN (SELECT x.url FROM imovel_fotos x WHERE x.codigo = p_em AND x.url IS NOT NULL)) q;
      GET DIAGNOSTICS v_n = ROW_COUNT;
    END IF;
    SELECT coalesce(i.proprietario_id, p.proprietario_id) INTO v_dono
      FROM imoveis i LEFT JOIN imovel_privado p ON p.codigo = i.codigo WHERE i.codigo = p_de_codigo;
    UPDATE imoveis
       SET status = 'Excluído', travado = true, travado_em = now(),
           travado_motivo = left('atualização do #' || p_em || ' (' || v_quem || ')', 200),
           extras = coalesce(extras, '{}'::jsonb) || jsonb_build_object('atualizacao_de', p_em::text)
     WHERE codigo = p_de_codigo;
    UPDATE captacao_cadastro
       SET estado = 'aplicado', codigo = p_em, aplicado_em = now(), aplicado_por = left('cadastro rápido: ' || v_quem, 80),
           atualizado_em = now()
     WHERE codigo = p_de_codigo AND estado IN ('coletando', 'pronto');
  ELSE
    SELECT * INTO c FROM captacao_cadastro WHERE id = p_de_ficha FOR UPDATE;
    IF c.id IS NULL THEN RAISE EXCEPTION 'a ficha % não existe', p_de_ficha; END IF;
    IF p_fotos THEN
      INSERT INTO imovel_fotos (codigo, ordem, url, e_capa)
      SELECT p_em, v_base + q.o, q.url, v_tinha = 0 AND q.o = 1
        FROM (SELECT t.u AS url, row_number() OVER (ORDER BY t.o) AS o
                FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(c.fotos) = 'array' THEN c.fotos ELSE '[]'::jsonb END)
                     WITH ORDINALITY AS t(u, o)
               WHERE t.u ~ '^https?://'
                 AND t.u NOT IN (SELECT x.url FROM imovel_fotos x WHERE x.codigo = p_em AND x.url IS NOT NULL)) q;
      GET DIAGNOSTICS v_n = ROW_COUNT;
    END IF;
    SELECT l.proprietario_id INTO v_dono FROM captacao_leads l WHERE l.id = c.lead_id;
    UPDATE captacao_cadastro
       SET estado = 'aplicado', codigo = p_em, aplicado_em = now(), aplicado_por = left('cadastro rápido: ' || v_quem, 80),
           atualizado_em = now()
     WHERE id = c.id;
  END IF;

  IF v_dono IS NOT NULL THEN
    INSERT INTO imovel_privado (codigo, proprietario_id) VALUES (p_em, v_dono)
    ON CONFLICT (codigo) DO UPDATE SET proprietario_id = coalesce(imovel_privado.proprietario_id, EXCLUDED.proprietario_id);
    UPDATE imoveis SET proprietario_id = v_dono WHERE codigo = p_em AND proprietario_id IS NULL;
  END IF;

  RETURN jsonb_build_object('ok', true, 'em', p_em, 'fotos', v_n, 'dono', v_dono IS NOT NULL);
END
$function$;

GRANT EXECUTE ON FUNCTION public.site_origem_do_cadastro(integer, bigint) TO nay_site_escrita;
GRANT EXECUTE ON FUNCTION public.site_juntar_cadastro(integer, bigint, integer, boolean, text) TO nay_site_escrita;

COMMIT;
