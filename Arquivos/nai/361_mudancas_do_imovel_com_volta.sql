-- 361 -- O que o proprietário diz na captação muda o cadastro SOZINHO, fica no histórico do imóvel e tem volta
--
-- Pedro, 13/10/2026: "quero automatizar o processo de atualização de imóveis com a Nay, quero que quando o
-- proprietário afirme que o valor é o mesmo ou algo assim ou que está vendido, ela mude lá no nosso banco de dados
-- mas de forma resetável ... vai surgir um campo lá na aba editar imóvel Última atualização e vai mostrar nesse campo
-- um mockup da mensagem que o proprietário mandou, e o que foi mudado, como um histórico do imóvel, ex De disponível
-- para alugado ... na aba imóveis mais uma tab no final, Mudanças recentes ... elas já são aprovadas e
-- disponibilizadas à Nay automaticamente sem eu autorizar, mas nessa tela eu posso clicar em voltar atrás em cada
-- mudança e organizar: já revisada, ou a revisar ... aproveitando já pega todas as atualizações que estão
-- pendentes, vê se o Tel já não mexeu manualmente, se não, mude e põe nessa tela para mim, sem apagar nada".
--
-- O QUE JÁ EXISTIA (321, 08/10): `captacao_aplicar_ao_cadastro` muda situação, valor do aluguel e fim do contrato e
-- guarda o de/para em `captacao_aplicado`. Faltava: (1) mostrar isso em algum lugar, com a conversa; (2) a volta;
-- (3) o que ficava parado em `conferir` esperando gente.
--
-- O QUE MUDA:
--  * `privado.imovel_mudanca`: uma linha por vez que a resposta do dono tocou (ou confirmou) o cadastro, com o trecho
--    da conversa, o de/para de cada campo, o retrato de antes e as observações. Nada é apagado: voltar atrás é uma
--    marca na linha (`desfeito_em`) e dá para refazer.
--  * passa a entrar sozinho:
--      - o VALOR DE VENDA que o dono disse, quando ele respondeu a pergunta dos 6% (incluso = o número dele;
--        líquido = o número dele + 6%, como o cadastro já guarda: 270 mil -> 286.200);
--      - "alugado" em imóvel anunciado para VENDA (antes ficava parado): vira Alugado, com a observação;
--      - fim do contrato dito como "até 15/10/2027", "10/2027" ou "2028 agosto".
--  * continua SEM entrar (vira card "não apliquei" na tela, com o motivo): mudado à mão depois da resposta,
--    parceiro, bloqueado, Rascunho/Excluído, valor com vários números, data que não vira data, valor de venda sem a
--    resposta dos 6% ou muito longe do cadastro.
--  * a resposta que não muda nada ("o valor é o mesmo") fica no histórico do imóvel como confirmação.
BEGIN;
SET LOCAL lock_timeout = '3s';

-- ---------------------------------------------------------------------------------------------------------------
-- 1. A TABELA (schema privado: tem a conversa do dono; a API aberta do site não enxerga)
-- ---------------------------------------------------------------------------------------------------------------
CREATE TABLE privado.imovel_mudanca (
  id              bigserial PRIMARY KEY,
  codigo          integer NOT NULL,
  tipo            text NOT NULL CHECK (tipo IN ('mudanca', 'confirmacao', 'nao_aplicado')),
  origem          text NOT NULL DEFAULT 'captacao',
  lead_id         bigint,
  aplicado_id     bigint,
  dono            text,
  dito_em         timestamptz,
  mensagens       jsonb NOT NULL DEFAULT '[]'::jsonb,
  campos          jsonb NOT NULL DEFAULT '{}'::jsonb,
  antes           jsonb NOT NULL DEFAULT '{}'::jsonb,
  notas           text[] NOT NULL DEFAULT '{}',
  criado_em       timestamptz NOT NULL DEFAULT now(),
  revisado_em     timestamptz,
  revisado_por    text,
  desfeito_em     timestamptz,
  desfeito_por    text,
  desfeito_campos text[]
);
CREATE INDEX imovel_mudanca_codigo ON privado.imovel_mudanca (codigo, id DESC);
CREATE INDEX imovel_mudanca_a_revisar ON privado.imovel_mudanca (id DESC) WHERE revisado_em IS NULL;
COMMENT ON TABLE privado.imovel_mudanca IS
  '361: o que a resposta do proprietário mudou (ou confirmou) no cadastro do imóvel, com a conversa e o de/para. Voltar atrás é marca na linha (desfeito_em), nada se apaga. Tela: Imóveis › Mudanças recentes e "Última atualização" no editar.';
COMMENT ON COLUMN privado.imovel_mudanca.campos IS '{campo: {de, para}} -- status, valor_aluguel, valor_venda, vencimento, publicado_no_site';
COMMENT ON COLUMN privado.imovel_mudanca.antes IS 'o retrato do imóvel antes da mudança (situação, no site, trava, valores, vencimento): é o que o voltar atrás devolve';

-- ---------------------------------------------------------------------------------------------------------------
-- 2. O TRECHO DA CONVERSA que vai no card (o que ele disse e o que a Nay perguntou)
-- ---------------------------------------------------------------------------------------------------------------
CREATE FUNCTION public.captacao_mensagens_da_mudanca(p_lead bigint, p_depois_de timestamptz, p_ate timestamptz)
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
             'd', CASE WHEN x.direcao = 'recebida' THEN 'dono' ELSE 'nos' END,
             'o', x.origem, 't', left(x.texto, 700), 'q', x.criada_em) ORDER BY x.criada_em, x.id), '[]'::jsonb)
    FROM (SELECT m.id, m.direcao, m.origem, m.texto, m.criada_em
            FROM captacao_mensagens m
           WHERE m.lead_id = p_lead
             AND m.criada_em <= coalesce(p_ate, now()) + interval '1 minute'
             AND m.criada_em > coalesce(p_depois_de, '-infinity'::timestamptz)
             AND coalesce(btrim(m.texto), '') <> ''
           ORDER BY m.criada_em DESC, m.id DESC
           LIMIT 14) x;
$function$;

-- ---------------------------------------------------------------------------------------------------------------
-- 3. GRAVAR UMA LINHA DO HISTÓRICO
-- ---------------------------------------------------------------------------------------------------------------
CREATE FUNCTION public.imovel_mudanca_registrar(p_codigo integer, p_lead bigint, p_aplicado bigint, p_dito timestamptz,
                                                p_campos jsonb, p_antes jsonb, p_notas text[],
                                                p_criado timestamptz DEFAULT now())
 RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_campos jsonb := coalesce(p_campos, '{}'::jsonb);
  v_notas  text[] := coalesce(p_notas, '{}');
  v_tipo   text := CASE WHEN v_campos <> '{}'::jsonb THEN 'mudanca' WHEN v_notas <> '{}' THEN 'nao_aplicado' ELSE 'confirmacao' END;
  u        privado.imovel_mudanca;
  v_dono   text;
  v_msgs   jsonb := '[]'::jsonb;
  v_id     bigint;
BEGIN
  IF p_codigo IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO u FROM privado.imovel_mudanca m
   WHERE m.codigo = p_codigo AND m.lead_id IS NOT DISTINCT FROM p_lead ORDER BY m.id DESC LIMIT 1;
  -- o mesmo "não apliquei" (ou a observação que já foi junto com a mudança) não vira outra linha; e a confirmação
  -- só entra quando este dono ainda não tem linha recente neste imóvel (senão toda passada "confirmaria" de novo)
  IF u.id IS NOT NULL AND v_tipo <> 'mudanca' AND v_notas <@ u.notas
     AND (v_tipo = 'nao_aplicado' OR u.criado_em > now() - interval '30 days') THEN
    RETURN u.id;
  END IF;
  SELECT nullif(btrim(coalesce(l.tratamento || ' ', '') || coalesce(l.nome, '')), '') INTO v_dono
    FROM captacao_leads l WHERE l.id = p_lead;
  -- a conversa: só o que veio depois da linha anterior deste dono; se nesse trecho ele não disse nada (a mesma
  -- resposta rendendo outra mudança), vai a conversa inteira, senão o card sai sem o que ele falou
  IF p_lead IS NOT NULL THEN
    v_msgs := captacao_mensagens_da_mudanca(p_lead, u.dito_em, p_dito);
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_msgs) e WHERE e->>'d' = 'dono') THEN
      v_msgs := captacao_mensagens_da_mudanca(p_lead, NULL, p_dito);
    END IF;
  END IF;
  INSERT INTO privado.imovel_mudanca (codigo, tipo, lead_id, aplicado_id, dono, dito_em, mensagens, campos, antes, notas, criado_em)
  VALUES (p_codigo, v_tipo, p_lead, p_aplicado, v_dono, p_dito, v_msgs,
          v_campos, coalesce(p_antes, '{}'::jsonb), v_notas, coalesce(p_criado, now()))
  RETURNING id INTO v_id;
  RETURN v_id;
END
$function$;

-- ---------------------------------------------------------------------------------------------------------------
-- 4. O VALOR DE VENDA nas palavras dele -> número; e a resposta dos 6%
-- ---------------------------------------------------------------------------------------------------------------
CREATE FUNCTION public.captacao_valor_venda_num(p_texto text)
 RETURNS numeric LANGUAGE sql IMMUTABLE
AS $function$
  -- "277k" -> 277000; "R$ 350 mil" -> 350000; "1.400.000" -> 1400000; "165.000,00" -> 165000; "2,5" -> 2500000.
  -- Mais de um número no texto ("160 ou 170") não vira valor.
  SELECT CASE
           WHEN (SELECT count(*) FROM regexp_matches(coalesce(p_texto, ''), '\d[\d.,]*', 'g')) <> 1 THEN NULL
           WHEN n.bruto IS NULL THEN NULL
           WHEN p_texto ~* 'milh' THEN replace(replace(n.bruto, '.', ''), ',', '.')::numeric * 1000000
           WHEN p_texto ~* '\mmil\M' OR p_texto ~* '\d\s*k\M' THEN replace(replace(n.bruto, '.', ''), ',', '.')::numeric * 1000
           WHEN n.bruto ~ '^\d{1,2}(,\d+)?$' THEN replace(n.bruto, ',', '.')::numeric * 1000000
           WHEN n.bruto ~ '^\d{3}$' THEN n.bruto::numeric * 1000
           ELSE replace(split_part(n.bruto, ',', 1), '.', '')::numeric
         END
    FROM (SELECT (regexp_match(coalesce(p_texto, ''), '(\d[\d\.]*(?:,\d+)?)'))[1] AS bruto) n;
$function$;

CREATE FUNCTION public.captacao_honorarios_tipo(p_lead bigint)
 RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  -- o que ele respondeu à pergunta dos 6% (324): 'inclusos', 'liquido' ou NULL (não respondeu / não deu para saber)
  -- resposta que parece as duas coisas ("Sim $370 tira os 6 por cento") não decide: fica para gente
  SELECT CASE
           WHEN x.r ~ '(liquid|\+\s*6|em cima|por fora|descontad|tira os 6|so quero)'
                AND x.r ~ '(inclus|ja esta|\msim\M|^isso|com a corretagem)' THEN NULL
           WHEN x.r ~ '(liquid|\+\s*6|em cima|por fora|descontad|tira os 6|so quero)' THEN 'liquido'
           WHEN x.r ~ '(inclus|ja esta|\msim\M|^isso|com a corretagem)' THEN 'inclusos'
         END
    FROM (SELECT lower(unaccent(h.resposta)) AS r FROM privado.captacao_honorarios h
           WHERE h.lead_id = p_lead ORDER BY h.id DESC LIMIT 1) x;
$function$;

-- ---------------------------------------------------------------------------------------------------------------
-- 5. O FIM DO CONTRATO: também "até 15/10/2027", "10/2027" e "2028 agosto"
-- ---------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.captacao_data_do_contrato(p_texto text, p_dito_em date)
 RETURNS date
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  t       text := lower(unaccent(coalesce(p_texto, '')));
  meses   text[] := ARRAY['janeiro','fevereiro','marco','abril','maio','junho','julho','agosto','setembro','outubro','novembro','dezembro'];
  re_mes  text := '\m(janeiro|fevereiro|marco|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro)\M';
  -- 361: a data escrita só vale como FIM quando o texto é só ela ou vem depois de "até / vence / termina / encerra":
  -- "renovado em 15/09/2026, prazo não informado" é o começo, não o fim
  re_fim  text := '(?:^\s*|\m(?:ate|vence\w*|vencimento|termina\w*|encerra\w*|acaba\w*|fim|final)\M\D{0,14})';
  m       text[];
  n_meses int;
  v_mes   int;
  v_ano   int;
  v_data  date;
  v_hoje  int := extract(year FROM p_dito_em)::int;
BEGIN
  IF btrim(t) = '' OR p_dito_em IS NULL THEN RETURN NULL; END IF;

  m := regexp_match(t, re_fim || '(\d{1,2})[/.-](\d{1,2})[/.-](20\d\d)\M');
  IF m IS NOT NULL THEN
    BEGIN
      v_data := make_date(m[3]::int, m[2]::int, m[1]::int);
    EXCEPTION WHEN OTHERS THEN v_data := NULL;
    END;
    IF v_data IS NOT NULL AND extract(year FROM v_data)::int BETWEEN v_hoje AND v_hoje + 6 THEN RETURN v_data; END IF;
    RETURN NULL;
  END IF;
  m := regexp_match(t, re_fim || '(\d{1,2})[/.-](20\d\d)\M');
  IF m IS NOT NULL THEN
    IF m[1]::int BETWEEN 1 AND 12 AND m[2]::int BETWEEN v_hoje AND v_hoje + 6 THEN
      RETURN (make_date(m[2]::int, m[1]::int, 1) + interval '1 month' - interval '1 day')::date;
    END IF;
    RETURN NULL;
  END IF;

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
  ELSIF t ~ ('^\s*(20\d\d)\s*(?:de|/|-)?\s*' || re_mes || '\s*$') THEN
    v_ano := (regexp_match(t, '(20\d\d)'))[1]::int;             -- 361: "2028 agosto"
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

-- ---------------------------------------------------------------------------------------------------------------
-- 6. APLICAR A RESPOSTA DO DONO AO CADASTRO (a 321, agora com histórico, valor de venda e sem a parede da venda)
-- ---------------------------------------------------------------------------------------------------------------
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
  v_vv     numeric;
  v_hon    text;
  v_data   date;
  v_venc   date;
  v_linhas int;
  v_a_mao  boolean := false;
  v_mudou  jsonb := '{}'::jsonb;
  v_antes  jsonb := '{}'::jsonb;
  v_conf   text[] := '{}';
  v_apl    bigint;
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
    SELECT max(c.vencimento), count(*) INTO v_venc, v_linhas FROM contratos_locacao c WHERE c.codigo = l.codigo;
    -- alguém mudou o cadastro à mão DEPOIS do que o dono disse: a mão vale mais
    v_a_mao := i.travado AND i.travado_em > v_dito AND coalesce(i.travado_motivo, '') NOT LIKE 'captação%';
    -- 361: o retrato de antes, para o voltar atrás
    v_antes := jsonb_build_object('status', i.status, 'disponivel', i.disponivel, 'publicado_no_site', i.publicado_no_site,
                                  'travado', i.travado, 'travado_motivo', i.travado_motivo, 'travado_em', i.travado_em,
                                  'valor_aluguel', i.valor_aluguel, 'valor_venda', i.valor_venda, 'vencimento', v_venc);

    -- 1. A SITUAÇÃO
    IF i.status IS DISTINCT FROM v_para THEN
      IF i.status IN ('Rascunho', 'Em revisão', 'Revisão', 'Excluído') THEN
        v_conf := array_append(v_conf, format('o dono disse %s, mas o cadastro está como %s: não mexi', l.situacao, i.status));
      ELSIF v_a_mao THEN
        v_conf := array_append(v_conf, format('o dono disse %s em %s, mas a situação (%s) foi mudada à mão depois, em %s: não mexi',
                                   l.situacao, v_dia, coalesce(i.status, 'sem situação'),
                                   to_char(i.travado_em AT TIME ZONE 'America/Manaus', 'DD/MM')));
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
        -- 361: antes isto ficava parado esperando gente; agora entra e a tela tem o voltar atrás
        IF l.situacao = 'alugado' AND i.status = 'Disponível' AND coalesce(i.valor_venda, 0) > 0 THEN
          v_conf := array_append(v_conf, format('estava anunciado para VENDA por R$ %s: se a venda continua, volte atrás',
                                     replace(to_char(i.valor_venda, 'FM999,999,999'), ',', '.')));
        END IF;
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

    -- 4. O VALOR DE VENDA (361). Entra sozinho quando ele respondeu a pergunta dos 6%: incluso = o número dele;
    --    líquido = o número dele + 6% (é como o cadastro guarda: 270 mil -> 286.200).
    IF nullif(btrim(l.valor_venda_pedido), '') IS NOT NULL AND l.situacao <> 'vendido'
       AND coalesce(i.status, '') NOT IN ('Rascunho', 'Em revisão', 'Revisão', 'Excluído', 'Vendido') THEN
      v_vv  := captacao_valor_venda_num(l.valor_venda_pedido);
      v_hon := captacao_honorarios_tipo(l.id);
      IF v_vv IS NULL OR v_vv < 10000 THEN
        v_conf := array_append(v_conf, format('valor de venda dito de um jeito que não vira número: "%s" (no cadastro: %s)',
                                   left(l.valor_venda_pedido, 80), coalesce(i.valor_venda::text, 'sem valor')));
      ELSIF coalesce(i.valor_venda, 0) > 0 AND v_vv NOT BETWEEN i.valor_venda * 0.5 AND i.valor_venda * 2 THEN
        v_conf := array_append(v_conf, format('valor de venda dito ("%s") muito longe do cadastro (%s): não mexi',
                                   left(l.valor_venda_pedido, 80), i.valor_venda::text));
      ELSIF v_a_mao THEN
        IF v_vv IS DISTINCT FROM i.valor_venda THEN
          v_conf := array_append(v_conf, format('o dono disse venda por "%s", mas o cadastro foi mudado à mão depois (venda em %s): não mexi',
                                     left(l.valor_venda_pedido, 80), coalesce(i.valor_venda::text, 'sem valor')));
        END IF;
      ELSIF v_hon IS NULL THEN
        IF v_vv IS DISTINCT FROM i.valor_venda THEN
          v_conf := array_append(v_conf, format('o dono disse venda por "%s" (no cadastro: %s), mas não disse se os 6%% já estão no valor: não mexi',
                                     left(l.valor_venda_pedido, 80), coalesce(i.valor_venda::text, 'sem valor')));
        END IF;
      ELSE
        IF v_hon = 'liquido' THEN v_vv := round(v_vv * 1.06); END IF;
        IF v_vv IS DISTINCT FROM i.valor_venda THEN
          UPDATE imoveis SET valor_venda = v_vv, travado = true, travado_em = now(),
                 travado_motivo = CASE WHEN travado AND travado_motivo LIKE 'captação%' AND travado_em > v_dito THEN travado_motivo
                                       ELSE 'captação: o dono disse o valor de venda em ' || v_dia END
           WHERE codigo = v_cod;
          v_mudou := v_mudou || jsonb_build_object('valor_venda', jsonb_build_object('de', i.valor_venda, 'para', v_vv));
          IF v_hon = 'liquido' THEN
            v_conf := array_append(v_conf, format('ele quer "%s" líquido: somei os 6%% de honorários', left(l.valor_venda_pedido, 80)));
          END IF;
        END IF;
      END IF;
    END IF;
  END IF;

  INSERT INTO captacao_aplicado (lead_id, codigo, situacao, valor_dito, contrato_dito, mudou, conferir)
  VALUES (l.id, v_cod, l.situacao, l.valor_locacao_pedido, l.contrato_ate, v_mudou, v_conf)
  RETURNING id INTO v_apl;
  -- 361: o histórico do imóvel (a tela Mudanças recentes e o "Última atualização" do editar leem daqui)
  IF i.codigo IS NOT NULL AND NOT coalesce(i.e_parceiro, false) THEN
    PERFORM imovel_mudanca_registrar(v_cod, l.id, v_apl, v_dito, v_mudou, v_antes, v_conf);
  END IF;
  RETURN jsonb_build_object('lead', l.id, 'codigo', v_cod, 'mudou', v_mudou, 'conferir', to_jsonb(v_conf));
END
$function$;

-- ---------------------------------------------------------------------------------------------------------------
-- 7. A RODADA DE 5 EM 5 MINUTOS: também quando o valor de venda ou a resposta dos 6% chegou depois
-- ---------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.captacao_aplicar_pendentes(p_silencio interval DEFAULT '00:15:00'::interval, p_limite integer DEFAULT 40)
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
      LEFT JOIN LATERAL (SELECT a.situacao, a.valor_dito, a.contrato_dito, a.aplicado_em FROM captacao_aplicado a
                          WHERE a.lead_id = l.id ORDER BY a.id DESC LIMIT 1) u ON true
     WHERE l.situacao IS NOT NULL
       AND l.telefone_chave IS DISTINCT FROM nay_fone_chave((SELECT valor FROM captacao_config WHERE chave = 'telefone_teste'))
       AND NOT EXISTS (SELECT 1 FROM captacao_mensagens m WHERE m.lead_id = l.id AND m.direcao = 'recebida'
                          AND m.criada_em > now() - p_silencio)
       AND (u.situacao IS NULL
            OR (u.situacao, coalesce(u.valor_dito, ''), coalesce(u.contrato_dito, ''))
               IS DISTINCT FROM (l.situacao, coalesce(l.valor_locacao_pedido, ''), coalesce(l.contrato_ate, ''))
            -- 361: o valor de venda ou a resposta dos 6% chegou depois da última passada
            OR (nullif(btrim(l.valor_venda_pedido), '') IS NOT NULL
                AND (l.atualizado_em > u.aplicado_em OR captacao_honorarios_depois_de(l.id, u.aplicado_em))))
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
    PERFORM imovel_mudanca_registrar(r.codigo, NULL, NULL, NULL,
              jsonb_build_object('publicado_no_site', jsonb_build_object('de', false, 'para', true)),
              jsonb_build_object('publicado_no_site', false), ARRAY['a foto chegou: o imóvel entrou no site']);
    lead_id := NULL; codigo := r.codigo; conferir := '{}';
    mudou := jsonb_build_object('publicado_no_site', jsonb_build_object('de', false, 'para', true, 'por', 'a foto chegou'));
    RETURN NEXT;
  END LOOP;
END
$function$;

CREATE FUNCTION public.captacao_honorarios_depois_de(p_lead bigint, p_quando timestamptz)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT EXISTS (SELECT 1 FROM privado.captacao_honorarios h WHERE h.lead_id = p_lead AND h.criado_em > p_quando);
$function$;

-- ---------------------------------------------------------------------------------------------------------------
-- 8. VOLTAR ATRÁS (e refazer). Só mexe no campo que AINDA está como a mudança deixou: o que alguém mudou depois fica.
-- ---------------------------------------------------------------------------------------------------------------
CREATE FUNCTION public.imovel_mudanca_trocar(p_id bigint, p_desfazer boolean, p_quem text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' SET lock_timeout TO '3s'
AS $function$
DECLARE
  m        privado.imovel_mudanca;
  i        imoveis;
  k        text;
  v_esp    jsonb;
  v_alvo   jsonb;
  v_st     text;
  v_disp   boolean;
  v_pub    boolean;
  v_venc   date;
  v_feito  text[] := '{}';
  v_pulado text[] := '{}';
  v_tocou  boolean := false;
  v_quem   text := left(coalesce(nullif(btrim(p_quem), ''), 'painel'), 80);
  v_dia    text := to_char(now() AT TIME ZONE 'America/Manaus', 'DD/MM');
  v_nome   text;
BEGIN
  SELECT * INTO m FROM privado.imovel_mudanca WHERE id = p_id FOR UPDATE;
  IF m.id IS NULL THEN RAISE EXCEPTION 'mudança % não existe', p_id; END IF;
  IF m.tipo <> 'mudanca' THEN RAISE EXCEPTION 'esta linha não mudou nada no cadastro: não há o que voltar'; END IF;
  IF p_desfazer AND m.desfeito_em IS NOT NULL THEN RAISE EXCEPTION 'esta mudança já foi desfeita'; END IF;
  IF NOT p_desfazer AND m.desfeito_em IS NULL THEN RAISE EXCEPTION 'esta mudança está valendo: não há o que refazer'; END IF;
  SELECT * INTO i FROM imoveis WHERE codigo = m.codigo FOR UPDATE;
  IF i.codigo IS NULL THEN RAISE EXCEPTION 'o imóvel % não está mais no cadastro', m.codigo; END IF;

  FOR k IN SELECT jsonb_object_keys(m.campos) LOOP
    IF NOT p_desfazer AND NOT (k = ANY (coalesce(m.desfeito_campos, '{}'))) THEN CONTINUE; END IF;
    v_esp  := CASE WHEN p_desfazer THEN m.campos->k->'para' ELSE m.campos->k->'de' END;
    v_alvo := CASE WHEN p_desfazer THEN m.campos->k->'de' ELSE m.campos->k->'para' END;
    v_nome := CASE k WHEN 'status' THEN 'situação' WHEN 'valor_aluguel' THEN 'valor do aluguel' WHEN 'valor_venda' THEN 'valor de venda'
                     WHEN 'vencimento' THEN 'fim do contrato' WHEN 'publicado_no_site' THEN 'no site' ELSE k END;

    IF k = 'status' THEN
      IF i.status IS DISTINCT FROM (v_esp #>> '{}') THEN
        v_pulado := array_append(v_pulado, format('%s (agora está %s)', v_nome, coalesce(i.status, 'sem situação'))); CONTINUE;
      END IF;
      v_st := v_alvo #>> '{}';
      IF v_st = 'Disponível' THEN
        v_disp := true;
        v_pub  := CASE WHEN p_desfazer AND m.antes ? 'publicado_no_site' AND m.antes->>'publicado_no_site' IS NOT NULL
                       THEN (m.antes->>'publicado_no_site')::boolean
                       ELSE EXISTS (SELECT 1 FROM imovel_fotos f WHERE f.codigo = m.codigo) END;
      ELSIF v_st IS NULL AND p_desfazer THEN
        v_disp := coalesce((m.antes->>'disponivel')::boolean, false);
        v_pub  := coalesce((m.antes->>'publicado_no_site')::boolean, false);
      ELSE
        v_disp := false; v_pub := false;
      END IF;
      UPDATE imoveis SET status = v_st, disponivel = v_disp, publicado_no_site = v_pub WHERE codigo = m.codigo;
      v_tocou := true;
    ELSIF k IN ('valor_aluguel', 'valor_venda') THEN
      IF (CASE k WHEN 'valor_aluguel' THEN i.valor_aluguel ELSE i.valor_venda END) IS DISTINCT FROM (v_esp #>> '{}')::numeric THEN
        v_pulado := array_append(v_pulado, format('%s (agora está %s)', v_nome,
                      coalesce((CASE k WHEN 'valor_aluguel' THEN i.valor_aluguel ELSE i.valor_venda END)::text, 'vazio'))); CONTINUE;
      END IF;
      EXECUTE format('UPDATE imoveis SET %I = $1 WHERE codigo = $2', k) USING (v_alvo #>> '{}')::numeric, m.codigo;
      v_tocou := true;
    ELSIF k = 'publicado_no_site' THEN
      IF i.publicado_no_site IS DISTINCT FROM (v_esp #>> '{}')::boolean THEN
        v_pulado := array_append(v_pulado, v_nome || ' (já foi mudado depois)'); CONTINUE;
      END IF;
      UPDATE imoveis SET publicado_no_site = (v_alvo #>> '{}')::boolean WHERE codigo = m.codigo;
      v_tocou := true;
    ELSIF k = 'vencimento' THEN
      SELECT max(c.vencimento) INTO v_venc FROM contratos_locacao c WHERE c.codigo = m.codigo::text;
      IF v_venc IS DISTINCT FROM (v_esp #>> '{}')::date THEN
        v_pulado := array_append(v_pulado, format('%s (agora está %s)', v_nome, coalesce(to_char(v_venc, 'DD/MM/YYYY'), 'vazio'))); CONTINUE;
      END IF;
      -- nada se apaga: o contrato que a captação criou fica, só sem a data
      UPDATE contratos_locacao SET vencimento = (v_alvo #>> '{}')::date WHERE codigo = m.codigo::text;
    ELSE
      CONTINUE;
    END IF;
    v_feito := array_append(v_feito, k);
  END LOOP;

  IF v_feito = '{}' THEN
    RETURN jsonb_build_object('ok', false, 'feito', '[]'::jsonb, 'pulado', to_jsonb(v_pulado),
                              'erro', 'nada voltou: o cadastro já foi mudado depois desta mudança');
  END IF;
  IF v_tocou THEN
    -- a trava segura a decisão: nem a raspagem do site antigo nem a mesma resposta do dono refazem por cima
    UPDATE imoveis SET travado = true, travado_em = now(),
           travado_motivo = CASE WHEN p_desfazer THEN format('voltei atrás em %s (%s) na mudança que a captação fez', v_dia, v_quem)
                                 ELSE format('captação: mudança refeita em %s (%s)', v_dia, v_quem) END
     WHERE codigo = m.codigo;
  END IF;
  UPDATE privado.imovel_mudanca
     SET desfeito_em = CASE WHEN p_desfazer THEN now() END,
         desfeito_por = CASE WHEN p_desfazer THEN v_quem END,
         desfeito_campos = CASE WHEN p_desfazer THEN v_feito END
   WHERE id = m.id;
  RETURN jsonb_build_object('ok', true, 'feito', to_jsonb(v_feito), 'pulado', to_jsonb(v_pulado));
END
$function$;

-- ---------------------------------------------------------------------------------------------------------------
-- 9. O QUE A TELA LÊ E MARCA
-- ---------------------------------------------------------------------------------------------------------------
CREATE FUNCTION public.site_mudancas(p_estado text, p_codigo integer, p_limite integer DEFAULT 300)
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  -- p_codigo: o histórico de UM imóvel (com as confirmações). Sem ele: a tela Mudanças recentes
  -- (p_estado = 'revisar' | 'revisadas'), sem as confirmações, que não têm o que revisar.
  SELECT jsonb_build_object(
    'contagem', (SELECT jsonb_build_object('revisar', count(*) FILTER (WHERE m.revisado_em IS NULL),
                                           'revisadas', count(*) FILTER (WHERE m.revisado_em IS NOT NULL))
                   FROM privado.imovel_mudanca m WHERE m.tipo <> 'confirmacao'),
    'itens', coalesce((
      SELECT jsonb_agg(x.j ORDER BY x.id DESC)
        FROM (SELECT m.id, jsonb_build_object(
                       'id', m.id, 'codigo', m.codigo, 'tipo', m.tipo, 'origem', m.origem, 'dono', m.dono,
                       'dito_em', m.dito_em, 'criado_em', m.criado_em, 'mensagens', m.mensagens, 'campos', m.campos,
                       'notas', to_jsonb(m.notas), 'revisado_em', m.revisado_em, 'revisado_por', m.revisado_por,
                       'desfeito_em', m.desfeito_em, 'desfeito_por', m.desfeito_por, 'desfeito_campos', to_jsonb(m.desfeito_campos),
                       'imovel', jsonb_build_object('tipo', i.tipo, 'condominio', i.condominio_nome, 'bairro', i.bairro,
                                   'status', i.status, 'valor_aluguel', i.valor_aluguel, 'valor_venda', i.valor_venda,
                                   'publicado_no_site', i.publicado_no_site,
                                   'vencimento', (SELECT max(c.vencimento) FROM contratos_locacao c WHERE c.codigo = m.codigo::text))) AS j
                FROM privado.imovel_mudanca m
                LEFT JOIN imoveis i ON i.codigo = m.codigo
               WHERE (p_codigo IS NULL OR m.codigo = p_codigo)
                 AND (p_codigo IS NOT NULL OR m.tipo <> 'confirmacao')
                 AND (p_codigo IS NOT NULL OR p_estado IS NULL
                      OR (p_estado = 'revisar' AND m.revisado_em IS NULL)
                      OR (p_estado = 'revisadas' AND m.revisado_em IS NOT NULL))
               ORDER BY m.id DESC
               LIMIT greatest(1, least(coalesce(p_limite, 300), 1000))) x), '[]'::jsonb));
$function$;

CREATE FUNCTION public.site_mudanca_revisar(p_ids bigint[], p_revisada boolean, p_quem text)
 RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE n int;
BEGIN
  UPDATE privado.imovel_mudanca
     SET revisado_em = CASE WHEN p_revisada THEN now() END,
         revisado_por = CASE WHEN p_revisada THEN left(coalesce(nullif(btrim(p_quem), ''), 'painel'), 80) END
   WHERE id = ANY (p_ids) AND (revisado_em IS NULL) = p_revisada;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END
$function$;

REVOKE ALL ON FUNCTION public.site_mudancas(text, integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.site_mudanca_revisar(bigint[], boolean, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.imovel_mudanca_trocar(bigint, boolean, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.imovel_mudanca_registrar(integer, bigint, bigint, timestamptz, jsonb, jsonb, text[], timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.captacao_mensagens_da_mudanca(bigint, timestamptz, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.site_mudancas(text, integer, integer) TO nay_site_escrita;
GRANT EXECUTE ON FUNCTION public.site_mudanca_revisar(bigint[], boolean, text) TO nay_site_escrita;
GRANT EXECUTE ON FUNCTION public.imovel_mudanca_trocar(bigint, boolean, text) TO nay_site_escrita;

-- ---------------------------------------------------------------------------------------------------------------
-- 10. O QUE JÁ TINHA SIDO MUDADO DESDE 08/10 entra no histórico (com a conversa de então)
-- ---------------------------------------------------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT a.id, a.lead_id, a.codigo, a.mudou, a.conferir, a.aplicado_em,
           (SELECT max(m.criada_em) FROM captacao_mensagens m
             WHERE m.lead_id = a.lead_id AND m.direcao = 'recebida' AND m.criada_em <= a.aplicado_em) AS dito,
           (SELECT coalesce(jsonb_object_agg(e.key, e.value->'de'), '{}'::jsonb) FROM jsonb_each(a.mudou) e) AS antes
      FROM captacao_aplicado a
      JOIN imoveis i ON i.codigo = a.codigo
     WHERE a.mudou <> '{}'::jsonb
     ORDER BY a.id
  LOOP
    PERFORM imovel_mudanca_registrar(r.codigo, nullif(r.lead_id, 0), r.id, r.dito,
              (SELECT jsonb_object_agg(e.key, e.value - 'por') FROM jsonb_each(r.mudou) e), r.antes, r.conferir, r.aplicado_em);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------------------------------------------
-- 11. AS PENDENTES: toda resposta já dada passa de novo pela regra nova. O que o Tel mudou à mão depois continua
--     como ele deixou (a trava com data posterior); o resto entra e aparece na tela, com volta.
-- ---------------------------------------------------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT l.id FROM captacao_leads l
     WHERE l.situacao IS NOT NULL AND l.codigo ~ '^\d{1,9}$'
       AND EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = l.codigo::int)
       AND l.telefone_chave IS DISTINCT FROM nay_fone_chave((SELECT valor FROM captacao_config WHERE chave = 'telefone_teste'))
     ORDER BY l.id
  LOOP
    PERFORM captacao_aplicar_ao_cadastro(r.id);
  END LOOP;
END $$;

COMMIT;
