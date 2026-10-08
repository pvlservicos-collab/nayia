-- 321 -- A resposta do proprietário na captação passa a atualizar o cadastro do imóvel (situação, valor, contrato)
--
-- Pedro, 08/10/2026: "os cadastros dos [proprietários] que responderam as captações já estão atualizando os imóveis
-- deles e a data de contratos deles nos sites? organiza logo para atualizar tudo" e "o que está disponível e caso não
-- tenha foto ele puxe".
--
-- Medido antes (08/10, 18h): NADA levava a resposta ao cadastro (a 160, de 28/09, foi uma aplicação à mão). De 121
-- respostas com imóvel cadastrado, 106 já batiam e 15 não; as 39 datas de contrato ditas estavam todas com vencimento
-- antigo (2023 a 2026) no site; 3 "disponível" estavam como Alugado e sem foto.
--
-- A ORDEM continua a de 28/09 (160): "captação > site antigo > novo ... a não ser que o Tel tenha mudado em data
-- posterior". O que entra SOZINHO:
--   vendido     -> Vendido
--   alugado     -> Alugado, e o fim do contrato vai para contratos_locacao.vencimento quando o que ele disse vira data
--   disponível  -> Disponível, com o valor do aluguel que ele deu. Vai para o site só se tiver foto; sem foto fica
--                  "Disponível fora do site" até a foto chegar (a que ele mandou na conversa o serviço puxa).
-- Tudo o que entra fica TRAVADO ("captação: o dono disse ... em DD/MM"): a leitura do site antigo não desfaz.
--
-- O que NÃO entra sozinho e fica anotado em `captacao_aplicado.conferir`, para gente decidir:
--   * a situação foi mudada à mão DEPOIS da resposta do dono;
--   * ele disse "alugado" e o imóvel está anunciado para VENDA (alugado não tira anúncio de venda);
--   * imóvel de parceiro, bloqueado, Rascunho, Em revisão ou Excluído;
--   * valor dito com mais de um número, e fim de contrato que não vira data ("renova anualmente", "ano que vem");
--   * o dono quer vender (preço e condição são conversa de gente).
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS public.captacao_aplicado (
  id            bigserial PRIMARY KEY,
  lead_id       bigint NOT NULL,
  codigo        integer,
  situacao      text,                              -- o que o dono disse quando isto foi aplicado
  valor_dito    text,
  contrato_dito text,
  mudou         jsonb NOT NULL DEFAULT '{}'::jsonb, -- {"status": {"de": "Alugado", "para": "Vendido"}, ...}
  conferir      text[] NOT NULL DEFAULT '{}',       -- o que NÃO entrou sozinho e por quê
  aplicado_em   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS captacao_aplicado_lead ON public.captacao_aplicado (lead_id, id DESC);
COMMENT ON TABLE public.captacao_aplicado IS
  'O que a resposta do proprietário na captação mudou no cadastro do imóvel (321), e o que ficou para gente conferir. '
  'A última linha de cada lead diz até onde a resposta dele já foi aplicada.';
GRANT SELECT ON public.captacao_aplicado TO nay_leitura, nay_site_leitura;

-- "julho de 27", "dezembro/2027", "até dezembro", "final de 2027", "junho do ano que vem" -> o último dia do mês.
-- O que tem conta para fazer ("setembro de 3 anos") ou não tem mês ("ano que vem", "renova anualmente") devolve NULL.
CREATE OR REPLACE FUNCTION public.captacao_data_do_contrato(p_texto text, p_dito_em date)
 RETURNS date
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  t       text := lower(unaccent(coalesce(p_texto, '')));
  meses   text[] := ARRAY['janeiro','fevereiro','marco','abril','maio','junho','julho','agosto','setembro','outubro','novembro','dezembro'];
  re_mes  text := '\m(janeiro|fevereiro|marco|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro)\M';
  m       text[];
  n_meses int;
  v_mes   int;
  v_ano   int;
  v_hoje  int := extract(year FROM p_dito_em)::int;
BEGIN
  IF btrim(t) = '' OR p_dito_em IS NULL THEN RETURN NULL; END IF;
  SELECT count(*) INTO n_meses FROM regexp_matches(t, re_mes, 'g');
  IF n_meses = 0 THEN
    m := regexp_match(t, '\m(final|fim)\s+de\s+(20\d\d)\M');
    IF m IS NOT NULL AND m[2]::int BETWEEN v_hoje AND v_hoje + 6 THEN RETURN make_date(m[2]::int, 12, 31); END IF;
    RETURN NULL;
  END IF;
  IF n_meses <> 1 THEN RETURN NULL; END IF;                    -- "de maio a março do ano que vem"
  IF t ~ '\d{2,4}\s+e\s+\d{2,4}' THEN RETURN NULL; END IF;      -- "dezembro de 27 e 28"
  v_mes := array_position(meses, (regexp_match(t, re_mes))[1]);
  m := regexp_match(t, re_mes || '\s*(?:de|/|-)?\s*(20\d\d|\d\d)\M');
  IF m IS NOT NULL THEN
    v_ano := m[2]::int;
    IF v_ano < 100 THEN v_ano := 2000 + v_ano; END IF;
  ELSIF t ~ '(ano que vem|proximo ano|daqui a (1|um) ano)' THEN
    v_ano := v_hoje + 1;
  ELSIF t ~ '\d' OR t ~ '\mano' THEN
    RETURN NULL;                                                -- "setembro de 3 anos": conta para gente fazer
  ELSE
    v_ano := v_hoje;                                            -- só o mês: o próximo que vier
    IF v_mes < extract(month FROM p_dito_em)::int THEN v_ano := v_ano + 1; END IF;
  END IF;
  IF v_ano NOT BETWEEN v_hoje AND v_hoje + 6 THEN RETURN NULL; END IF;
  RETURN (make_date(v_ano, v_mes, 1) + interval '1 month' - interval '1 day')::date;
END
$function$;

-- Aplica a resposta de UM lead ao imóvel dele. Devolve o que mudou e o que ficou para conferir; grava em captacao_aplicado.
CREATE OR REPLACE FUNCTION public.captacao_aplicar_ao_cadastro(p_lead bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public'
 SET lock_timeout TO '3s'
AS $function$
DECLARE
  l        captacao_leads;
  i        imoveis;
  v_cod    int;
  v_dito   timestamptz;
  v_dia    text;
  v_para   text;
  v_trava  text;
  v_fotos  int;
  v_valor  numeric;
  v_data   date;
  v_venc   date;
  v_linhas int;
  v_mudou  jsonb := '{}'::jsonb;
  v_conf   text[] := '{}';
BEGIN
  SELECT * INTO l FROM captacao_leads WHERE id = p_lead;
  IF l.id IS NULL OR l.situacao IS NULL THEN RETURN NULL; END IF;
  IF coalesce(l.codigo, '') ~ '^\d{1,9}$' THEN
    v_cod := l.codigo::int;
    SELECT * INTO i FROM imoveis WHERE codigo = v_cod FOR UPDATE;
  END IF;

  IF i.codigo IS NULL THEN
    v_conf := array_append(v_conf, 'o imóvel do lead não está no cadastro: nada para atualizar');
  ELSIF coalesce(i.e_parceiro, false) THEN
    v_conf := array_append(v_conf, 'imóvel de parceiro: não mexi');
  ELSE
    SELECT coalesce(max(m.criada_em), l.atualizado_em) INTO v_dito
      FROM captacao_mensagens m WHERE m.lead_id = l.id AND m.direcao = 'recebida';
    v_dia   := to_char(v_dito AT TIME ZONE 'America/Manaus', 'DD/MM');
    v_para  := CASE l.situacao WHEN 'vendido' THEN 'Vendido' WHEN 'alugado' THEN 'Alugado' WHEN 'disponivel' THEN 'Disponível' END;
    v_trava := 'captação: o dono disse ' || lower(v_para) || ' em ' || v_dia;
    SELECT count(*) INTO v_fotos FROM imovel_fotos WHERE codigo = v_cod;

    -- 1. A SITUAÇÃO
    IF i.status IS DISTINCT FROM v_para THEN
      IF i.status IN ('Rascunho', 'Em revisão', 'Revisão', 'Excluído') THEN
        v_conf := array_append(v_conf, format('o dono disse %s, mas o cadastro está como %s: não mexi', l.situacao, i.status));
      ELSIF i.travado AND i.travado_em > v_dito AND coalesce(i.travado_motivo, '') NOT LIKE 'captação%' THEN
        v_conf := array_append(v_conf, format('o dono disse %s em %s, mas a situação (%s) foi mudada à mão depois, em %s: não mexi',
                                   l.situacao, v_dia, coalesce(i.status, 'sem situação'),
                                   to_char(i.travado_em AT TIME ZONE 'America/Manaus', 'DD/MM')));
      ELSIF l.situacao = 'alugado' AND i.status = 'Disponível' AND coalesce(i.valor_venda, 0) > 0 THEN
        v_conf := array_append(v_conf, 'o dono disse alugado, mas o imóvel está anunciado para VENDA: decidir se o anúncio de venda continua');
      ELSIF l.situacao = 'disponivel' AND coalesce(i.bloqueado, false) THEN
        v_conf := array_append(v_conf, format('o dono disse disponível, mas o imóvel está bloqueado (%s): não mexi',
                                   coalesce(i.motivo_bloqueio, 'sem motivo anotado')));
      ELSIF l.situacao = 'disponivel' THEN
        UPDATE imoveis SET status = 'Disponível', disponivel = true, publicado_no_site = (v_fotos > 0),
               travado = true, travado_motivo = v_trava, travado_em = now()
         WHERE codigo = v_cod;
        v_mudou := v_mudou || jsonb_build_object('status', jsonb_build_object('de', i.status, 'para', 'Disponível'));
        IF v_fotos = 0 THEN
          v_conf := array_append(v_conf, 'ficou Disponível mas FORA do site: o imóvel não tem foto (entra no site quando a foto chegar)');
        END IF;
      ELSE
        UPDATE imoveis SET status = v_para, travado = true, travado_motivo = v_trava, travado_em = now()
         WHERE codigo = v_cod;
        v_mudou := v_mudou || jsonb_build_object('status', jsonb_build_object('de', i.status, 'para', v_para));
      END IF;
    END IF;

    -- 2. O VALOR DO ALUGUEL (só de quem disse disponível, e só quando ele deu UM número)
    IF l.situacao = 'disponivel' AND nullif(btrim(l.valor_locacao_pedido), '') IS NOT NULL
       AND (SELECT status FROM imoveis WHERE codigo = v_cod) = 'Disponível' THEN
      IF (SELECT count(*) FROM regexp_matches(l.valor_locacao_pedido, '\d[\d.,]*', 'g')) = 1 THEN
        v_valor := captacao_numero(l.valor_locacao_pedido);
        IF v_valor BETWEEN 300 AND 200000 AND v_valor IS DISTINCT FROM i.valor_aluguel THEN
          UPDATE imoveis SET valor_aluguel = v_valor WHERE codigo = v_cod;
          v_mudou := v_mudou || jsonb_build_object('valor_aluguel', jsonb_build_object('de', i.valor_aluguel, 'para', v_valor));
        END IF;
      ELSE
        v_conf := array_append(v_conf, format('valor dito com mais de um número: "%s"', left(l.valor_locacao_pedido, 120)));
      END IF;
    END IF;

    -- 3. O FIM DO CONTRATO (de quem disse alugado)
    IF l.situacao = 'alugado' AND nullif(btrim(l.contrato_ate), '') IS NOT NULL THEN
      v_data := captacao_data_do_contrato(l.contrato_ate, (v_dito AT TIME ZONE 'America/Manaus')::date);
      IF v_data IS NULL THEN
        v_conf := array_append(v_conf, format('fim do contrato dito de um jeito que não vira data: "%s"', left(l.contrato_ate, 120)));
      ELSE
        SELECT max(c.vencimento), count(*) INTO v_venc, v_linhas FROM contratos_locacao c WHERE c.codigo = l.codigo;
        IF v_linhas = 0 THEN
          INSERT INTO contratos_locacao (codigo, vencimento) VALUES (l.codigo, v_data);
          v_mudou := v_mudou || jsonb_build_object('vencimento', jsonb_build_object('de', NULL, 'para', v_data));
        ELSIF v_venc IS NULL OR to_char(v_venc, 'YYYY-MM') <> to_char(v_data, 'YYYY-MM') THEN
          -- o mesmo mês e ano já está lá com o dia certo: o que o site sabe é mais preciso, fica
          UPDATE contratos_locacao SET vencimento = v_data WHERE codigo = l.codigo;
          v_mudou := v_mudou || jsonb_build_object('vencimento', jsonb_build_object('de', v_venc, 'para', v_data));
        END IF;
      END IF;
    END IF;

    -- 4. QUER VENDER: preço e condição são conversa de gente
    IF coalesce(l.quer_vender, false) AND captacao_numero(l.valor_venda_pedido) IS DISTINCT FROM i.valor_venda THEN
      v_conf := array_append(v_conf, format('o dono quer vender (disse "%s"; no cadastro a venda está %s): decidir com ele',
                                 left(coalesce(l.valor_venda_pedido, 'sem valor'), 80), coalesce(i.valor_venda::text, 'sem valor')));
    END IF;
  END IF;

  INSERT INTO captacao_aplicado (lead_id, codigo, situacao, valor_dito, contrato_dito, mudou, conferir)
  VALUES (l.id, v_cod, l.situacao, l.valor_locacao_pedido, l.contrato_ate, v_mudou, v_conf);
  RETURN jsonb_build_object('lead', l.id, 'codigo', v_cod, 'mudou', v_mudou, 'conferir', to_jsonb(v_conf));
END
$function$;

-- O que o serviço chama de 5 em 5 minutos: aplica o que os donos disseram e ainda não foi aplicado (ou mudou desde
-- a última vez), depois que a conversa ficou em silêncio. E põe no site o "disponível" que estava sem foto e ganhou.
CREATE OR REPLACE FUNCTION public.captacao_aplicar_pendentes(p_silencio interval DEFAULT '15 minutes', p_limite integer DEFAULT 40)
 RETURNS TABLE(lead_id bigint, codigo integer, mudou jsonb, conferir text[])
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
DECLARE
  r record;
  v jsonb;
BEGIN
  FOR r IN
    SELECT l.id
      FROM captacao_leads l
      LEFT JOIN LATERAL (SELECT a.situacao, a.valor_dito, a.contrato_dito FROM captacao_aplicado a
                          WHERE a.lead_id = l.id ORDER BY a.id DESC LIMIT 1) u ON true
     WHERE l.situacao IS NOT NULL
       AND l.telefone_chave IS DISTINCT FROM nay_fone_chave((SELECT valor FROM captacao_config WHERE chave = 'telefone_teste'))
       AND NOT EXISTS (SELECT 1 FROM captacao_mensagens m WHERE m.lead_id = l.id AND m.direcao = 'recebida'
                          AND m.criada_em > now() - p_silencio)
       AND (u.situacao IS NULL
            OR (u.situacao, coalesce(u.valor_dito, ''), coalesce(u.contrato_dito, ''))
               IS DISTINCT FROM (l.situacao, coalesce(l.valor_locacao_pedido, ''), coalesce(l.contrato_ate, '')))
     ORDER BY l.id
     LIMIT greatest(1, coalesce(p_limite, 40))
  LOOP
    BEGIN
      v := captacao_aplicar_ao_cadastro(r.id);
      IF v IS NOT NULL THEN
        lead_id := r.id; codigo := (v->>'codigo')::int; mudou := v->'mudou';
        conferir := ARRAY(SELECT jsonb_array_elements_text(v->'conferir'));
        RETURN NEXT;
      END IF;
    EXCEPTION WHEN OTHERS THEN   -- um imóvel travado por outra gravação não segura os demais: volta na próxima rodada
      lead_id := r.id; codigo := NULL; mudou := '{}'::jsonb; conferir := ARRAY['erro, tento de novo: ' || SQLERRM];
      RETURN NEXT;
    END;
  END LOOP;

  -- a foto chegou: o que a captação deixou "Disponível fora do site" por falta de foto entra no site
  FOR r IN
    UPDATE imoveis i SET publicado_no_site = true
     WHERE i.status = 'Disponível' AND i.disponivel AND NOT i.publicado_no_site AND NOT coalesce(i.bloqueado, false)
       AND NOT coalesce(i.e_parceiro, false) AND i.travado AND i.travado_motivo LIKE 'captação: o dono disse disponível%'
       AND EXISTS (SELECT 1 FROM imovel_fotos f WHERE f.codigo = i.codigo)
    RETURNING i.codigo
  LOOP
    INSERT INTO captacao_aplicado (lead_id, codigo, situacao, mudou)
    SELECT coalesce((SELECT l.id FROM captacao_leads l WHERE l.codigo = r.codigo::text ORDER BY l.id LIMIT 1), 0), r.codigo, 'disponivel',
           jsonb_build_object('publicado_no_site', jsonb_build_object('de', false, 'para', true, 'por', 'a foto chegou'));
    lead_id := NULL; codigo := r.codigo; conferir := '{}';
    mudou := jsonb_build_object('publicado_no_site', jsonb_build_object('de', false, 'para', true, 'por', 'a foto chegou'));
    RETURN NEXT;
  END LOOP;
END
$function$;

-- As fotos que o dono mandou NA CONVERSA e que ainda não estão no imóvel dele (só de quem disse disponível e cujo
-- imóvel não tem foto própria). O serviço baixa cada uma e entrega à API do site, que guarda em fotos-captacao/crm/<código>/.
CREATE OR REPLACE FUNCTION public.captacao_fotos_a_puxar()
 RETURNS TABLE(codigo integer, foto_id text, url text, ordem integer)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT i.codigo,
         'capt' || c.id || '_' || regexp_replace(regexp_replace(f.url, '^.*/', ''), '\.[A-Za-z0-9]+$', '') AS foto_id,
         f.url, f.ord::int
    FROM captacao_leads l
    JOIN imoveis i ON i.codigo::text = l.codigo
    JOIN captacao_cadastro c ON c.lead_id = l.id AND c.tipo = 'atualizar' AND (c.codigo IS NULL OR c.codigo = i.codigo)
   CROSS JOIN LATERAL jsonb_array_elements_text(CASE WHEN jsonb_typeof(c.fotos) = 'array' THEN c.fotos ELSE '[]'::jsonb END)
         WITH ORDINALITY f(url, ord)
   WHERE l.situacao = 'disponivel'
     AND NOT coalesce(i.e_parceiro, false) AND i.status IS DISTINCT FROM 'Excluído'
     AND f.url ~ '^https://imobeasy\.online/fotos-captacao/whatsapp/[0-9]+/[A-Za-z0-9_-]+\.(jpe?g|png|webp)$'
     -- o imóvel não tem foto própria (as que vieram por aqui não contam)
     AND NOT EXISTS (SELECT 1 FROM imovel_fotos x WHERE x.codigo = i.codigo
                        AND x.url NOT LIKE '%/crm/' || i.codigo || '/capt%')
     -- e esta ainda não foi trazida
     AND NOT EXISTS (SELECT 1 FROM imovel_fotos x WHERE x.codigo = i.codigo
                        AND x.url LIKE '%/crm/' || i.codigo || '/capt' || c.id || '\_'
                                       || regexp_replace(regexp_replace(f.url, '^.*/', ''), '\.[A-Za-z0-9]+$', '') || '.%')
   ORDER BY i.codigo, c.id, f.ord;
$function$;

COMMIT;
