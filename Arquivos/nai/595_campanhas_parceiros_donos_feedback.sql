-- 595: AS CAMPANHAS QUE O PEDRO LIBERA À MÃO (parceiros, donos parados, feedback dos disponíveis) e o AVISO DE BAIXA
--
-- Pedro, 03-04/11/2026: "preparar essas 3 listas e as mensagens que combinam para elas, dos modelos, e a Nay para
-- atender os diferentes tipos; vou liberar manualmente amanhã:
--   - mandar mensagem para os corretores parceiros para verificar se o imóvel está disponível, ou pedir outras opções;
--   - falar com proprietários sobre imóveis oferecidos há muito tempo com métricas ruins;
--   - depois de falar com os donos em que o imóvel está parado, avisar quem recebeu o imóvel quando o dono baixar o preço;
--   - preparar o funil de feedback de imóveis disponíveis, para perguntar se está alugado ou não, pedir para baixar o
--     valor e mandar as métricas."
--
-- O QUE TEM AQUI
--   privado.campanha_contato   uma linha por contato e lista: a 1ª mensagem, a seguinte (com as métricas), a linha por
--                              onde vai, o estado (preparada -> liberada -> enviando -> enviada -> respondida) e a
--                              resposta classificada (classe, novo valor). Nunca o mesmo contato duas vezes no mesmo dia.
--   privado.campanha_evento    o diário de cada contato (o que saiu, o que chegou, a classe, a nota, o aviso).
--   campanha_preparar(dia)     monta as 3 listas como 'preparada' (o fim deste arquivo chama para hoje):
--     donos_parados         o critério de 03/11: imóvel NOSSO, Disponível, no site, cadastrado há 30 dias ou mais; nos
--                           últimos 30 dias nenhuma visita, ninguém pediu pelo código, mandado a no máximo 1 cliente e no
--                           máximo 1 pedido de grupo nota 90+ (cnm_envio_lista(30) + privado.grupo_pedido_par);
--     feedback_disponiveis  os donos dos outros imóveis NOSSOS Disponíveis (quem já está nos parados fica lá);
--     parceiros_disponivel  os corretores dos imóveis de PARCEIRO Disponíveis (o dono do cadastro,
--                           nai_proprietario_do_imovel), um contato por corretor, com os códigos dele.
--     Fica de fora: sem telefone, dois donos, "tratar com outra pessoa", número da casa/equipe/teste
--     (site_painel_internos, whatsapp_nunca), quem pediu para não receber (captacao_leads.opt_out), imóvel com visita
--     marcada, imóvel administrado, CORRETOR como dono de imóvel nosso (garantias do disparo, 352), e quem recebeu
--     mensagem de campanha nos últimos 30 dias.
--   campanha_linha(tel)        'parceria' se já escreveu para a Parceria (nay_leads_linha_do_dono, 492); 'oficial' se a
--                              única conversa dele conosco é a do número oficial (só modelo aprovado, fora da janela de
--                              24 h: situacao_condominio_1 / situacao_imovel_cadastrado_5); o resto, 'captacao' (8595).
--   campanha_quem_atende(id)   quem MAIS responderia esse contato naquela linha (a Nay da Parceria a corretor, a Nay
--                              Leads, a Nay Corretores, a Nay de captação, uma visita, a equipe). Com alguém, a campanha
--                              só anota e avisa: não responde por cima.
--   campanha_reservar(teste)   o próximo 'liberada' que pode sair agora (as garantias, de novo, na hora de mandar).
--   crm_campanha_listar / crm_campanha_liberar / crm_campanha_cancelar   para o CRM (ou à mão). SÓ o liberar põe na fila.
--   crm_campanha_baixa_confirmar   a equipe confirma a baixa de valor (o gatilho do aviso; ver abaixo).
--   campanha_baixa_destinatarios   quem a Nay Leads avisa da baixa.
--
-- O AVISO DE BAIXA: o GATILHO é a confirmação explícita da equipe (crm_campanha_baixa_confirmar), e o aviso só sai
-- quando o CADASTRO já mostra o valor novo (ou menor) e o imóvel segue Disponível. Nada de gatilho em imoveis: o valor
-- muda também pela captação, pela sincronização e por engano de digitação (2.500 -> 250), e um gatilho ali mandaria
-- aviso a dezenas de clientes por um erro. A Nay (nay-olx, olx/campanhas_baixa.py) avisa, UMA vez por pessoa por imóvel
-- (privado.campanha_baixa_aviso), quem recebeu o card desse imóvel da Nay Leads nos últimos `campanha_baixa_dias` e não
-- está com a equipe. Chave `campanha_baixa_avisar` nasce 'nao'.
--
-- NADA aqui muda situação ou valor de imóvel. A Nay anota a resposta, põe nota no CRM e avisa a equipe para conferir.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS privado.campanha_contato (
  id                 bigserial PRIMARY KEY,
  lista              text NOT NULL CHECK (lista IN ('parceiros_disponivel', 'donos_parados', 'feedback_disponiveis')),
  dia                date NOT NULL,                -- o dia em que a lista foi preparada (Manaus)
  nome               text,
  vocativo           text,                         -- como ela chama ("Ana"); NULL = sem nome
  telefone           text NOT NULL,                -- só dígitos, com o 55
  chave              text NOT NULL,                -- nai_chave(telefone)
  tel8               text NOT NULL,
  linha              text NOT NULL CHECK (linha IN ('parceria', 'captacao', 'oficial')),
  modelo             text,                         -- no oficial: o modelo aprovado da Meta
  modelo_valores     text[],
  codigos            integer[] NOT NULL,
  imoveis            jsonb NOT NULL DEFAULT '[]',  -- o retrato de cada imóvel na preparação (nome, valores, métricas)
  prioridade         integer NOT NULL DEFAULT 0,
  falou_conosco_60d  boolean NOT NULL DEFAULT false,
  mensagem           text NOT NULL,                -- a 1ª (no oficial, o texto do modelo como ele recebe)
  mensagem_seguinte  text,                         -- depois do "disponível": as métricas e o pedido de ajuste
  estado             text NOT NULL DEFAULT 'preparada'
                     CHECK (estado IN ('preparada', 'liberada', 'enviando', 'enviada', 'respondida', 'cancelada', 'erro')),
  liberada_em        timestamptz,
  liberada_por       text,
  adiada_em          timestamptz,                  -- liberada, mas esperou (conversa em andamento): tenta de novo depois
  adiada_motivo      text,
  outro_atende       text,                         -- campanha_quem_atende na hora de mandar
  enviada_em         timestamptz,
  message_id         text,
  lida_ate           timestamptz,                  -- até onde as respostas dele já foram lidas
  resposta_em        timestamptz,
  resposta_texto     text,
  classe             text CHECK (classe IN ('disponivel', 'alugado', 'vendido', 'baixa', 'outras_opcoes', 'nao_e_comigo',
                                            'outra_coisa')),
  novo_valor         numeric,
  classe_codigos     integer[],
  resumo             text,
  seguinte_em        timestamptz,
  nossas             integer NOT NULL DEFAULT 0,   -- quantas mensagens a Nay mandou a ele nesta campanha
  respondeu_quem     text,                         -- 'nay' ou quem respondeu no lugar dela
  equipe_avisada_em  timestamptz,
  erro               text,
  criado_em          timestamptz NOT NULL DEFAULT now(),
  atualizado_em      timestamptz NOT NULL DEFAULT now()
);
-- "sem repetir contato entre as listas no mesmo dia"
CREATE UNIQUE INDEX IF NOT EXISTS campanha_contato_um_por_dia ON privado.campanha_contato (chave, dia) WHERE estado <> 'cancelada';
CREATE INDEX IF NOT EXISTS campanha_contato_fila ON privado.campanha_contato (estado, prioridade DESC, id);
CREATE INDEX IF NOT EXISTS campanha_contato_chave ON privado.campanha_contato (chave, enviada_em DESC);
COMMENT ON TABLE privado.campanha_contato IS
  '595: campanhas que o Pedro libera à mão (parceiros_disponivel, donos_parados, feedback_disponiveis); nay-olx olx/campanhas.py manda as liberadas';

CREATE TABLE IF NOT EXISTS privado.campanha_evento (
  id         bigserial PRIMARY KEY,
  contato    bigint NOT NULL REFERENCES privado.campanha_contato (id),
  tipo       text NOT NULL CHECK (tipo IN ('liberada', 'cancelada', 'adiada', 'enviada', 'recebida', 'classificada', 'nota',
                                           'aviso', 'erro')),
  texto      text,
  message_id text,
  saida_id   bigint,                               -- core_saida (Parceria)
  dados      jsonb,
  em         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS campanha_evento_contato ON privado.campanha_evento (contato, id);

CREATE TABLE IF NOT EXISTS privado.campanha_baixa (
  id            bigserial PRIMARY KEY,
  codigo        integer NOT NULL,
  finalidade    text NOT NULL CHECK (finalidade IN ('locacao', 'venda')),
  valor_antes   numeric NOT NULL,
  valor_novo    numeric NOT NULL CHECK (valor_novo > 0 AND valor_novo < valor_antes),
  contato       bigint REFERENCES privado.campanha_contato (id),
  quem          text NOT NULL,
  estado        text NOT NULL DEFAULT 'confirmada' CHECK (estado IN ('confirmada', 'avisando', 'avisada', 'expirada', 'cancelada')),
  motivo        text,
  confirmada_em timestamptz NOT NULL DEFAULT now(),
  atualizado_em timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS campanha_baixa_aberta ON privado.campanha_baixa (codigo, finalidade)
  WHERE estado IN ('confirmada', 'avisando');

CREATE TABLE IF NOT EXISTS privado.campanha_baixa_aviso (
  id         bigserial PRIMARY KEY,
  baixa      bigint NOT NULL REFERENCES privado.campanha_baixa (id),
  codigo     integer NOT NULL,
  lead       bigint NOT NULL,
  tel8       text NOT NULL,
  estado     text NOT NULL DEFAULT 'enviando' CHECK (estado IN ('enviando', 'enviado', 'erro')),
  texto      text,
  message_id text,
  erro       text,
  criado_em  timestamptz NOT NULL DEFAULT now(),
  enviado_em timestamptz
);
-- "uma vez por pessoa por imóvel": para sempre, não só por baixa
CREATE UNIQUE INDEX IF NOT EXISTS campanha_baixa_aviso_uma_vez ON privado.campanha_baixa_aviso (codigo, tel8);

-- as chaves (privado.olx_config; o serviço relê a cada volta)
INSERT INTO privado.olx_config (chave, valor, descricao) VALUES
  ('campanha_envio', 'sim', '595: nao | teste | sim. As campanhas só mandam o que o Pedro LIBEROU (crm_campanha_liberar); teste = só os números de whatsapp_teste. nao para na hora'),
  ('campanha_responde', 'sim', '595: sim = a Nay responde a resposta do contato (curta; no disponível, as métricas); nao = só classifica, anota e avisa'),
  ('campanha_horario', '8-12,13:30-18', '595: o horário comercial do envio (Manaus, segunda a sexta), faixas separadas por vírgula'),
  ('campanha_horario_resposta', '7-21', '595: a Nay só responde dentro deste horário (Manaus, todo dia); fora dele, responde quando abrir'),
  ('campanha_intervalo_s', '120-300', '595: segundos entre um envio e o próximo (sorteado na faixa)'),
  ('campanha_teto_dia', '60', '595: no máximo tantos envios de campanha por dia (todas as listas)'),
  ('campanha_espera_conversa_h', '12', '595: quem conversou conosco (qualquer número, qualquer lado) nas últimas N horas espera'),
  ('campanha_silencio_s', '90', '595: segundos de silêncio depois da última mensagem dele antes de ler e responder'),
  ('campanha_com_nay_captacao', 'nao', '595: sim = manda também a quem a Nay de captação (nay-captacao) atende: ela responde os botões e aplica situação/valor no cadastro sozinha (321). nao = esses esperam'),
  ('campanha_aviso_onde', 'crm', '595: crm | grupo | nenhum (regra 508: só visita vai ao grupo). Onde a equipe é avisada para conferir (a nota interna na conversa sai sempre)'),
  ('campanha_baixa_avisar', 'nao', '595: nao | teste | sim. A Nay Leads avisa a baixa de valor confirmada (crm_campanha_baixa_confirmar) a quem recebeu o imóvel'),
  ('campanha_baixa_dias', '30', '595: quem recebeu o card do imóvel nos últimos N dias é avisado da baixa'),
  ('campanha_baixa_intervalo_s', '60-150', '595: segundos entre um aviso de baixa e o próximo')
ON CONFLICT (chave) DO NOTHING;

-- ───────────────────────────── textos ─────────────────────────────
CREATE OR REPLACE FUNCTION public.campanha_dinheiro(p numeric)
 RETURNS text LANGUAGE sql IMMUTABLE AS $function$
  SELECT CASE WHEN p IS NULL OR p <= 0 THEN NULL ELSE 'R$ ' || replace(to_char(round(p), 'FM999,999,999,990'), ',', '.') END
$function$;

CREATE OR REPLACE FUNCTION public.campanha_lista_texto(p text[])
 RETURNS text LANGUAGE sql IMMUTABLE AS $function$
  SELECT CASE WHEN coalesce(cardinality(p), 0) = 0 THEN ''
              WHEN cardinality(p) = 1 THEN p[1]
              ELSE array_to_string(p[1:cardinality(p) - 1], ', ') || ' e ' || p[cardinality(p)] END
$function$;

CREATE OR REPLACE FUNCTION public.campanha_mes(p date)
 RETURNS text LANGUAGE sql STABLE AS $function$
  SELECT (ARRAY['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro',
                'novembro', 'dezembro'])[extract(month FROM p)::int]
         || CASE WHEN extract(year FROM p) <> extract(year FROM now() AT TIME ZONE 'America/Manaus')
                 THEN ' de ' || extract(year FROM p)::int ELSE '' END
$function$;

-- "Ana Claudia Rego" -> "Ana"; "Construtora Europa - Rodrigo Vanzin" -> "Rodrigo"; sigla ou empresa -> NULL (463)
CREATE OR REPLACE FUNCTION public.campanha_vocativo(p_nome text)
 RETURNS text LANGUAGE sql STABLE SET search_path TO 'public' AS $function$
  SELECT CASE WHEN v IS NULL OR lower(unaccent(v)) ~ '^(construtora|incorporadora|imobiliaria|empreendimentos?|ltda|me|imob|sr|sra|dr|dra)$'
              THEN NULL ELSE v END
    FROM (SELECT nay_vocativo_dono(btrim(regexp_replace(
                   CASE WHEN p_nome ~* '^\s*(construtora|incorporadora|imobili[aá]ria|empreendimentos?)\M' AND position(' - ' IN p_nome) > 0
                        THEN split_part(p_nome, ' - ', 2) ELSE p_nome END,
                   '^\s*(sr|sra|dr|dra)\.?\s+', '', 'i'))) AS v) x
$function$;

-- o nome do condomínio quando é nome de verdade ("Vision Residence"); "Casa", "Condomínio", "-" -> NULL
CREATE OR REPLACE FUNCTION public.campanha_condominio(p_codigo integer)
 RETURNS text LANGUAGE sql STABLE SET search_path TO 'public' AS $function$
  SELECT CASE WHEN length(c) >= 3 AND EXISTS (
                     SELECT 1 FROM regexp_split_to_table(lower(unaccent(c)), '[^a-z0-9]+') w
                      WHERE w <> '' AND w NOT IN ('casa', 'casas', 'apartamento', 'apto', 'ap', 'sala', 'loja', 'terreno', 'lote',
                                                  'kitnet', 'flat', 'cobertura', 'condominio', 'residencial', 'edificio',
                                                  'predio', 'galpao', 'ponto', 'imovel', 'sem', 'nao', 'na', 'n', 'a', 'de',
                                                  'do', 'da', 'em', 'comercial', 'outro', 'outros'))
              THEN CASE WHEN c = lower(c) THEN initcap(c) ELSE c END END
    FROM (SELECT btrim(regexp_replace(coalesce(condominio_nome, ''), '\s+', ' ', 'g')) AS c FROM imoveis WHERE codigo = p_codigo) x
$function$;

-- "na Ponta Negra", "no Tarumã" (vazio sem bairro)
CREATE OR REPLACE FUNCTION public.campanha_no_bairro(p_codigo integer)
 RETURNS text LANGUAGE sql STABLE SET search_path TO 'public' AS $function$
  SELECT CASE WHEN b = '' THEN ''
              WHEN lower(unaccent(split_part(b, ' ', 1))) IN ('ponta', 'cidade', 'compensa', 'cachoeirinha', 'gloria', 'raiz',
                         'redencao', 'paz', 'praca', 'chapada', 'alvorada', 'nova', 'colonia', 'vila', 'betania', 'zona', 'santa',
                         'uniao', 'nossa', 'lagoa')
              THEN 'na ' || b ELSE 'no ' || b END
    FROM (SELECT btrim(coalesce(bairro, '')) AS b FROM imoveis WHERE codigo = p_codigo) x
$function$;

-- "o seu apartamento no Vision Residence" / "a casa na Ponta Negra" (o condomínio quando é nome de verdade; senão o bairro)
CREATE OR REPLACE FUNCTION public.campanha_imovel_nome(p_codigo integer, p_seu boolean DEFAULT false)
 RETURNS text LANGUAGE sql STABLE SET search_path TO 'public' AS $function$
  SELECT CASE WHEN split_part(tipo, ' ', 1) IN ('casa', 'cobertura', 'sala', 'loja', 'kitnet', 'quitinete', 'chácara', 'chacara',
                                                'área', 'area', 'fazenda', 'granja')
              THEN CASE WHEN p_seu THEN 'a sua ' ELSE 'a ' END ELSE CASE WHEN p_seu THEN 'o seu ' ELSE 'o ' END END
         || tipo || coalesce(' no ' || campanha_condominio(p_codigo), CASE WHEN campanha_no_bairro(p_codigo) <> '' THEN ' ' || campanha_no_bairro(p_codigo) ELSE '' END)
    FROM (SELECT lower(coalesce(nullif(btrim(tipo), ''), 'imóvel')) AS tipo FROM imoveis WHERE codigo = p_codigo) i
$function$;

-- o valor do imóvel em uma frase ("R$ 2.300 por mês", "R$ 499.999")
CREATE OR REPLACE FUNCTION public.campanha_valor_texto(p_codigo integer)
 RETURNS text LANGUAGE sql STABLE SET search_path TO 'public' AS $function$
  SELECT CASE WHEN coalesce(valor_venda, 0) > 0 AND coalesce(valor_aluguel, 0) > 0
                THEN campanha_dinheiro(valor_venda) || ' na venda e ' || campanha_dinheiro(valor_aluguel) || ' por mês no aluguel'
              WHEN coalesce(valor_aluguel, 0) > 0 THEN campanha_dinheiro(valor_aluguel) || ' por mês'
              ELSE campanha_dinheiro(valor_venda) END
    FROM imoveis WHERE codigo = p_codigo
$function$;

-- AS MÉTRICAS de um imóvel (as de 03/11: site, Chaves na Mão, grupos, clientes; mais as visitas)
CREATE OR REPLACE FUNCTION public.campanha_metricas(p_codigo integer)
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'privado' AS $function$
  WITH posts AS (
    SELECT grupo_nome, enviado_em FROM envios WHERE destino = 'grupo' AND codigo = p_codigo::text
    UNION ALL
    SELECT grupo_nome, enviado_em FROM envios_lista_grupo WHERE codigo = p_codigo
  ), pg AS (SELECT count(*) AS posts, count(DISTINCT grupo_nome) AS grupos FROM posts),
  memb AS (SELECT max(g.membros) AS maior FROM nai_grupo_corretor g WHERE g.nome IN (SELECT grupo_nome FROM posts)),
  cli AS (
    SELECT count(DISTINCT p) AS n FROM (
      SELECT right(regexp_replace(e.chave, '\D', '', 'g'), 8) AS p FROM imovel_enviado_no_dia e WHERE e.codigo = p_codigo
      UNION SELECT right(l.telefone, 8) FROM olx_cliente_enviada o JOIN olx_lead_whatsapp l ON l.id = o.lead
             WHERE o.codigo = p_codigo AND o.tipo = 'card'
      UNION SELECT right(regexp_replace(c.chave, '\D', '', 'g'), 8) FROM core_envio_imovel c WHERE c.codigo = p_codigo) x
  ), vis AS (
    SELECT count(*) FILTER (WHERE q > now() - interval '30 days') AS v30, count(*) AS vt FROM (
      SELECT coalesce(v.quando, v.quando_sugerido) AS q FROM nai_visita v
       WHERE v.codigo = p_codigo AND v.estado NOT IN ('cancelada', 'expirada')
      UNION ALL
      SELECT o.quando FROM olx_visita o WHERE o.codigo = p_codigo AND o.estado NOT IN ('cancelada', 'expirada')) x
  )
  SELECT jsonb_build_object(
           'codigo', p_codigo,
           'no_site', coalesce(i.publicado_no_site, false),
           'desde', i.criado_em::date,
           'chaves_na_mao', p_codigo = ANY (coalesce((SELECT s.ids FROM cnm_envio_selecao s WHERE s.id = 1), '{}')),
           'posts', pg.posts, 'grupos', pg.grupos, 'corretores', coalesce(memb.maior, 0),
           'clientes', cli.n, 'visitas_30d', vis.v30, 'visitas', vis.vt)
    FROM imoveis i, pg, memb, cli, vis
   WHERE i.codigo = p_codigo
$function$;

-- "O 5738 está no nosso site desde agosto, no portal Chaves na Mão, já foi divulgado 1 vez em 1 grupo de corretores e
-- foi apresentado a 4 clientes."
CREATE OR REPLACE FUNCTION public.campanha_metricas_texto(p_m jsonb)
 RETURNS text LANGUAGE sql STABLE AS $function$
  SELECT 'O ' || (p_m->>'codigo') || ' ' || campanha_lista_texto(array_remove(ARRAY[
           CASE WHEN p_m->>'desde' IS NOT NULL
                THEN CASE WHEN (p_m->>'no_site')::boolean THEN 'está no nosso site desde ' ELSE 'está cadastrado conosco desde ' END
                     || campanha_mes((p_m->>'desde')::date) END,
           CASE WHEN (p_m->>'chaves_na_mao')::boolean THEN 'no portal Chaves na Mão' END,
           CASE WHEN (p_m->>'posts')::int > 0
                THEN 'já foi divulgado ' || (p_m->>'posts') || CASE WHEN (p_m->>'posts')::int = 1 THEN ' vez' ELSE ' vezes' END
                     || ' em ' || (p_m->>'grupos') || CASE WHEN (p_m->>'grupos')::int = 1 THEN ' grupo' ELSE ' grupos' END
                     || ' de corretores'
                     || CASE WHEN (p_m->>'corretores')::int >= 20
                             THEN ', para mais de ' || ((p_m->>'corretores')::int / 10 * 10) || ' corretores' ELSE '' END END,
           CASE WHEN (p_m->>'clientes')::int > 0
                THEN 'foi apresentado a ' || (p_m->>'clientes') || CASE WHEN (p_m->>'clientes')::int = 1 THEN ' cliente' ELSE ' clientes' END END
         ], NULL)) || '.'
$function$;

-- as métricas de VÁRIOS imóveis do mesmo dono sem repetir a frase: "Os três estão no nosso site desde agosto e no portal
-- Chaves na Mão; o 5027 já foi apresentado a 1 cliente." Meses diferentes: uma frase por imóvel (até 3).
CREATE OR REPLACE FUNCTION public.campanha_metricas_grupo(p_codigos integer[])
 RETURNS text LANGUAGE plpgsql STABLE SET search_path TO 'public' AS $function$
DECLARE
  v_n    int := cardinality(p_codigos);
  v_ms   jsonb[];
  v_meses int;
  v_site boolean;
  v_cnm  boolean;
  v_extra text[];
  v_txt  text;
  m jsonb;
  p text[];
BEGIN
  IF v_n = 1 THEN
    RETURN campanha_metricas_texto(campanha_metricas(p_codigos[1]));
  END IF;
  SELECT array_agg(campanha_metricas(c) ORDER BY o) INTO v_ms FROM unnest(p_codigos) WITH ORDINALITY u(c, o);
  SELECT count(DISTINCT campanha_mes((x->>'desde')::date)), bool_and((x->>'no_site')::boolean), bool_and((x->>'chaves_na_mao')::boolean)
    INTO v_meses, v_site, v_cnm FROM unnest(v_ms) x;
  IF v_meses <> 1 THEN
    SELECT string_agg(campanha_metricas_texto(x), ' ' ORDER BY o) INTO v_txt FROM unnest(v_ms[1:3]) WITH ORDINALITY u(x, o);
    RETURN v_txt || CASE WHEN v_n = 4 THEN ' O outro segue anunciado do mesmo jeito.'
                         WHEN v_n > 4 THEN ' Os outros ' || (v_n - 3) || ' seguem anunciados do mesmo jeito.' ELSE '' END;
  END IF;
  v_txt := 'Os ' || coalesce((ARRAY['', 'dois', 'três', 'quatro', 'cinco', 'seis', 'sete', 'oito', 'nove', 'dez'])[v_n], v_n::text)
           || CASE WHEN v_site THEN ' estão no nosso site desde ' ELSE ' estão cadastrados conosco desde ' END
           || campanha_mes((v_ms[1]->>'desde')::date) || CASE WHEN v_cnm THEN ' e no portal Chaves na Mão' ELSE '' END;
  FOREACH m IN ARRAY v_ms LOOP
    p := array_remove(ARRAY[
           CASE WHEN NOT v_cnm AND (m->>'chaves_na_mao')::boolean THEN 'está no portal Chaves na Mão' END,
           CASE WHEN (m->>'posts')::int > 0
                THEN 'já foi divulgado ' || (m->>'posts') || CASE WHEN (m->>'posts')::int = 1 THEN ' vez' ELSE ' vezes' END
                     || ' em grupos de corretores' END,
           CASE WHEN (m->>'clientes')::int > 0
                THEN 'foi apresentado a ' || (m->>'clientes') || CASE WHEN (m->>'clientes')::int = 1 THEN ' cliente' ELSE ' clientes' END END], NULL);
    IF cardinality(p) > 0 THEN
      v_extra := v_extra || ('o ' || (m->>'codigo') || ' ' || campanha_lista_texto(p));
    END IF;
  END LOOP;
  RETURN v_txt || CASE WHEN cardinality(v_extra) > 0 THEN '; ' || array_to_string(v_extra, '; ') ELSE '' END || '.';
END;
$function$;

-- a 1ª mensagem (texto livre: Parceria e 8595)
CREATE OR REPLACE FUNCTION public.campanha_msg_primeira(p_lista text, p_voc text, p_codigos integer[])
 RETURNS text LANGUAGE plpgsql STABLE SET search_path TO 'public' AS $function$
DECLARE
  v_oi   text := 'Olá' || coalesce(', ' || p_voc, '') || '! Tudo bem? Aqui é a Nay, da Imob Easy. ';
  v_n    int := cardinality(p_codigos);
  v_um   text;
  v_cods text := campanha_lista_texto(p_codigos::text[]);
  v_fin  text;
  v_nomes text[];
BEGIN
  IF v_n = 1 THEN
    v_um := campanha_imovel_nome(p_codigos[1], p_lista <> 'parceiros_disponivel');
  END IF;
  IF p_lista = 'donos_parados' THEN
    RETURN v_oi || CASE WHEN v_n = 1 THEN upper(left(v_um, 1)) || substr(v_um, 2) || ' (cód. ' || p_codigos[1] || ') ainda está disponível?'
                        ELSE 'Os seus imóveis cadastrados conosco (' || v_cods || ') ainda estão disponíveis?' END;
  ELSIF p_lista = 'feedback_disponiveis' THEN
    SELECT CASE WHEN bool_or(coalesce(valor_aluguel, 0) > 0) AND bool_or(coalesce(valor_venda, 0) > 0) THEN 'alugado ou vendido'
                WHEN bool_or(coalesce(valor_aluguel, 0) > 0) THEN 'alugado' ELSE 'vendido' END
      INTO v_fin FROM imoveis WHERE codigo = ANY (p_codigos);
    RETURN v_oi || 'Estou atualizando o nosso cadastro: '
           || CASE WHEN v_n = 1 THEN v_um || ' (cód. ' || p_codigos[1] || ') continua disponível ou já foi ' || v_fin || '?'
                   ELSE 'os seus imóveis (' || v_cods || ') continuam disponíveis, ou algum já foi ' || v_fin || '?' END;
  END IF;
  -- parceiros_disponivel: até 3 pelo nome, o resto pelo código
  IF v_n = 1 THEN
    RETURN v_oi || upper(left(v_um, 1)) || substr(v_um, 2) || ' (cód. ' || p_codigos[1]
           || ') que você tem em parceria conosco ainda está disponível? Se já saiu, tem outra opção parecida para me mandar?';
  END IF;
  SELECT array_agg(campanha_imovel_nome(c, false) || ' (cód. ' || c || ')' ORDER BY o) INTO v_nomes
    FROM unnest(p_codigos[1:3]) WITH ORDINALITY AS u(c, o);
  RETURN v_oi || 'Estou conferindo os imóveis que você tem em parceria conosco: ' || campanha_lista_texto(v_nomes)
         || CASE WHEN v_n > 3 THEN ', e mais ' || (v_n - 3) || ' (cód. '
                                   || campanha_lista_texto((p_codigos[4:least(v_n, 18)])::text[])
                                   || CASE WHEN v_n > 18 THEN '…' ELSE '' END || ')' ELSE '' END
         || '. Ainda estão disponíveis? Se algum já saiu, tem outras opções parecidas para me mandar?';
END;
$function$;

-- a seguinte, depois do "disponível": as métricas e o pedido de ajuste (só as listas dos donos)
CREATE OR REPLACE FUNCTION public.campanha_msg_seguinte(p_lista text, p_codigos integer[])
 RETURNS text LANGUAGE plpgsql STABLE SET search_path TO 'public' AS $function$
DECLARE
  v_n    int := cardinality(p_codigos);
  v_txt  text;
  v_v30  int;
  v_verbo text;
BEGIN
  IF p_lista NOT IN ('donos_parados', 'feedback_disponiveis') THEN
    RETURN NULL;
  END IF;
  v_txt := campanha_metricas_grupo(p_codigos);
  SELECT sum((campanha_metricas(c)->>'visitas_30d')::int) INTO v_v30 FROM unnest(p_codigos) c;
  SELECT CASE WHEN bool_or(coalesce(valor_aluguel, 0) > 0) AND bool_or(coalesce(valor_venda, 0) > 0) THEN 'alugar ou vender'
              WHEN bool_or(coalesce(valor_aluguel, 0) > 0) THEN 'alugar' ELSE 'vender' END
    INTO v_verbo FROM imoveis WHERE codigo = ANY (p_codigos);
  IF p_lista = 'donos_parados' THEN
    RETURN 'Que bom! ' || v_txt || ' Nos últimos 30 dias ninguém pediu visita. Para ' || v_verbo
           || ' mais rápido, toparia ajustar o valor?'
           || CASE WHEN v_n = 1 THEN ' Hoje ele está em ' || campanha_valor_texto(p_codigos[1]) || '.' ELSE '' END
           || ' Se topar, me diz o novo valor que eu passo para a equipe atualizar o anúncio.';
  END IF;
  RETURN 'Ótimo, obrigada por confirmar! Para você acompanhar: ' || lower(left(v_txt, 1)) || substr(v_txt, 2)
         || CASE WHEN coalesce(v_v30, 0) > 0
                 THEN ' Nos últimos 30 dias ' || CASE WHEN v_n = 1 THEN 'ele teve ' ELSE 'eles tiveram ' END || v_v30
                      || CASE WHEN v_v30 = 1 THEN ' visita.' ELSE ' visitas.' END
                 ELSE ' Nos últimos 30 dias ninguém pediu visita.' END
         || ' Se quiser ' || v_verbo || ' mais rápido, um ajuste no valor costuma ajudar bastante. Se topar, me diz o novo valor'
         || ' que eu passo para a equipe.';
END;
$function$;

-- o modelo aprovado do número oficial para a 1ª mensagem (Utilidade, botões Disponível / Alugado / Vendido)
CREATE OR REPLACE FUNCTION public.campanha_modelo(p_codigos integer[], p_voc text)
 RETURNS TABLE(modelo text, valores text[], texto text) LANGUAGE sql STABLE SET search_path TO 'public' AS $function$
  -- situacao_condominio_1: "Olá, {{1}}! ... a situação do seu imóvel no {{2}}, cadastrado conosco. ..."
  -- situacao_imovel_cadastrado_5: "Olá, {{1}}. O seu imóvel {{2}} está cadastrado na Imob Easy e ..."
  WITH c AS (SELECT p_codigos[1] AS codigo, campanha_condominio(p_codigos[1]) AS condo, campanha_no_bairro(p_codigos[1]) AS bairro,
                    coalesce(p_voc, 'tudo bem') AS voc),
  v AS (SELECT *, CASE WHEN condo IS NOT NULL THEN condo || ' (cód. ' || codigo || ')'
                       ELSE '(cód. ' || codigo || ')' || CASE WHEN bairro <> '' THEN ', ' || bairro || ',' ELSE '' END END AS dois
          FROM c)
  SELECT CASE WHEN condo IS NOT NULL THEN 'situacao_condominio_1' ELSE 'situacao_imovel_cadastrado_5' END,
         ARRAY[voc, dois],
         CASE WHEN condo IS NOT NULL
              THEN 'Olá, ' || voc || '! Este é o novo número da Imob Easy. Precisamos atualizar a situação do seu imóvel no ' || dois
                   || ', cadastrado conosco. Por favor, selecione a opção que corresponde à situação atual: [Disponível | Alugado | Vendido]'
              ELSE 'Olá, ' || voc || '. O seu imóvel ' || dois || ' está cadastrado na Imob Easy e precisamos atualizar a situação dele. '
                   || 'Este é o nosso novo número de atendimento. Selecione a situação atual: [Disponível | Alugado | Vendido]' END
    FROM v
$function$;

-- ───────────────────────────── linha e quem atende ─────────────────────────────
CREATE OR REPLACE FUNCTION public.campanha_linha(p_tel text)
 RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'privado' AS $function$
  SELECT CASE
    WHEN nay_leads_linha_do_dono(p_tel) = 'parceria' THEN 'parceria'
    WHEN EXISTS (SELECT 1 FROM captacao_mensagens m WHERE nay_fone_chave(m.telefone) = nay_fone_chave(p_tel)
                    AND m.direcao = 'enviada' AND m.message_id LIKE 'wamid.%')
     AND NOT EXISTS (SELECT 1 FROM captacao_mensagens m WHERE nay_fone_chave(m.telefone) = nay_fone_chave(p_tel)
                        AND m.direcao = 'enviada' AND m.message_id IS NOT NULL AND m.message_id NOT LIKE 'wamid.%')
     AND NOT EXISTS (SELECT 1 FROM olx_lead_whatsapp o WHERE right(o.telefone, 8) = right(regexp_replace(p_tel, '\D', '', 'g'), 8))
    THEN 'oficial'
    ELSE 'captacao' END
$function$;

-- Quem MAIS responderia esse contato naquela linha. NULL = ninguém: a campanha pode responder.
CREATE OR REPLACE FUNCTION public.campanha_quem_atende(p_id bigint)
 RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public', 'privado' AS $function$
DECLARE
  r privado.campanha_contato;
  v_contato bigint;
BEGIN
  SELECT * INTO r FROM privado.campanha_contato WHERE id = p_id;
  IF NOT FOUND THEN RETURN 'sem_contato'; END IF;
  -- a Nay Leads está falando com ele por um cliente (dúvida, visita): é dela
  IF EXISTS (SELECT 1 FROM nay_leads_com_dono d WHERE d.chave = r.chave AND d.ate > now()
                AND coalesce(d.motivo, '') NOT LIKE 'campanha%') THEN
    RETURN 'nay_leads_com_o_dono';
  END IF;
  IF EXISTS (SELECT 1 FROM olx_visita_consulta c WHERE c.estado = 'esperando' AND right(c.telefone, 8) = r.tel8) THEN
    RETURN 'visita_da_nay_leads';
  END IF;
  IF r.linha = 'parceria' THEN
    SELECT id INTO v_contato FROM nai_contato WHERE chave = r.chave;
    IF v_contato IS NULL THEN RETURN NULL; END IF;
    IF nai_tel_com_a_conversa(v_contato) THEN RETURN 'equipe'; END IF;
    IF captacao_olx_da_parceria(r.telefone, v_contato) IS NOT NULL THEN RETURN 'nay_captacao_olx'; END IF;
    IF cadastro_whats_da_parceria(r.telefone, v_contato) IS NOT NULL THEN RETURN 'nay_cadastro'; END IF;
    IF EXISTS (SELECT 1 FROM nai_visita x WHERE x.proprietario_id = v_contato AND nai_visita_aberta(x.estado)) THEN
      RETURN 'visita_da_parceria';
    END IF;
    -- a Nay da Parceria (nay-core) atende CORRETOR; dono de imóvel (nay_proprietario_bloqueio, 463) ela não atende
    IF NOT EXISTS (SELECT 1 FROM nay_proprietario_bloqueio b WHERE b.chave = r.chave) THEN
      RETURN 'nay_parceria';
    END IF;
    RETURN NULL;
  END IF;
  IF EXISTS (SELECT 1 FROM olx_lead_whatsapp o WHERE right(o.telefone, 8) = r.tel8) THEN RETURN 'nay_leads'; END IF;
  IF captacao_e_do_python(r.telefone) THEN RETURN 'nay_captacao'; END IF;
  IF r.linha = 'captacao' AND busca_corretor_e(r.telefone) THEN RETURN 'nay_corretores'; END IF;
  RETURN NULL;
END;
$function$;

-- ───────────────────────────── as listas ─────────────────────────────
CREATE OR REPLACE FUNCTION public.campanha_preparar(p_dia date DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'privado' AS $function$
DECLARE
  v_dia      date := coalesce(p_dia, (now() AT TIME ZONE 'America/Manaus')::date);
  v_internos text[] := site_painel_internos()
                       || coalesce((SELECT array_agg(right(regexp_replace(x, '\D', '', 'g'), 8))
                                      FROM regexp_split_to_table(coalesce((SELECT valor FROM olx_config WHERE chave = 'whatsapp_nunca'), ''), '[,;\s]+') x
                                     WHERE length(regexp_replace(x, '\D', '', 'g')) >= 8), '{}');
  v_res      jsonb;
  v_cancel   int;
BEGIN
  -- a lista é refeita: as preparadas de outro dia que ninguém liberou saem
  UPDATE campanha_contato SET estado = 'cancelada', erro = 'lista refeita em ' || to_char(v_dia, 'DD/MM'), atualizado_em = now()
   WHERE estado = 'preparada' AND dia < v_dia;
  GET DIAGNOSTICS v_cancel = ROW_COUNT;

  DROP TABLE IF EXISTS pg_temp._camp_imovel;
  CREATE TEMP TABLE _camp_imovel ON COMMIT DROP AS
  WITH lst AS (SELECT * FROM cnm_envio_lista(30)),
  gp AS (
    SELECT pp.codigo, count(DISTINCT q.remetente) FILTER (WHERE pp.nota >= 90) AS ped90
      FROM grupo_pedido_par pp JOIN grupo_pedido q ON q.id = pp.pedido_id
     WHERE q.fonte = 'grupo' AND q.enviada_em > now() - interval '30 days'
     GROUP BY pp.codigo
  ), base AS (
    SELECT i.codigo, i.e_parceiro, i.administrado, i.criado_em, i.publicado_no_site,
           (coalesce(l.candidato, false) AND coalesce(l.visitas, 0) = 0 AND coalesce(l.buscados, 0) = 0
            AND coalesce(l.enviados, 0) <= 1 AND coalesce(gp.ped90, 0) <= 1
            AND i.criado_em::date <= v_dia - 30) AS parado,
           EXISTS (SELECT 1 FROM nai_visita v WHERE v.codigo = i.codigo AND nai_visita_aberta(v.estado)
                      AND coalesce(v.quando, v.quando_sugerido, now()) > now() - interval '1 day')
           OR EXISTS (SELECT 1 FROM olx_visita o WHERE o.codigo = i.codigo
                         AND o.estado NOT IN ('cancelada', 'expirada', 'realizada') AND coalesce(o.quando, now()) > now() - interval '1 day')
             AS visita_marcada
      FROM imoveis i LEFT JOIN lst l ON l.codigo = i.codigo LEFT JOIN gp ON gp.codigo = i.codigo
     WHERE i.status = 'Disponível' AND i.disponivel AND NOT i.bloqueado
  )
  SELECT b.*, d.nome AS dono_nome, nay_fone_com_ddi(regexp_replace(coalesce(d.telefone, ''), '\D', '', 'g')) AS dono_tel,
         d.motivo AS dono_motivo, nai_chave(d.telefone) AS chave, NULL::text AS fora
    FROM base b LEFT JOIN LATERAL nai_proprietario_do_imovel(b.codigo) d ON true;

  UPDATE _camp_imovel c SET fora = CASE
      WHEN c.dono_motivo IS NOT NULL THEN c.dono_motivo
      WHEN c.chave IS NULL OR length(c.dono_tel) < 12 THEN 'sem_telefone'
      WHEN right(c.chave, 8) = ANY (v_internos) THEN 'numero_da_casa'
      WHEN EXISTS (SELECT 1 FROM captacao_leads l WHERE l.telefone_chave = c.chave AND l.opt_out) THEN 'pediu_para_nao_receber'
      WHEN c.visita_marcada THEN 'visita_marcada'
      WHEN NOT c.e_parceiro AND c.administrado THEN 'administrado'
      WHEN EXISTS (SELECT 1 FROM campanha_contato x WHERE x.chave = c.chave
                      AND (x.enviada_em > now() - interval '30 days' OR x.estado IN ('liberada', 'enviando'))) THEN 'campanha_nos_ultimos_30_dias'
      END;
  -- corretor nunca entra em lista de proprietário (352): uma conta por telefone
  UPDATE _camp_imovel c SET fora = 'corretor_como_dono'
   WHERE c.fora IS NULL AND NOT c.e_parceiro
     AND c.chave IN (SELECT DISTINCT x.chave FROM _camp_imovel x WHERE x.fora IS NULL AND NOT x.e_parceiro
                        AND nay_e_corretor_chave(x.chave));

  -- (b) donos dos parados, (c) feedback dos outros nossos, (a) corretores dos parceiros. Nessa ordem: o mesmo telefone
  -- num dia fica só na primeira (o índice campanha_contato_um_por_dia).
  INSERT INTO campanha_contato (lista, dia, nome, vocativo, telefone, chave, tel8, linha, modelo, modelo_valores, codigos,
                                imoveis, prioridade, falou_conosco_60d, mensagem, mensagem_seguinte)
  SELECT x.lista, v_dia, x.nome, x.voc, x.tel, x.chave, right(x.chave, 8), x.linha, mo.modelo, mo.valores, x.codigos,
         (SELECT jsonb_agg(jsonb_build_object('codigo', c, 'nome', campanha_imovel_nome(c, false),
                                              'valor_venda', i.valor_venda, 'valor_aluguel', i.valor_aluguel,
                                              'metricas', CASE WHEN x.lista <> 'parceiros_disponivel' THEN campanha_metricas(c) END)
                           ORDER BY o)
            FROM unnest(x.codigos) WITH ORDINALITY u(c, o) JOIN imoveis i ON i.codigo = u.c),
         x.prioridade, nay_falou_conosco(x.chave, 60),
         CASE WHEN x.linha = 'oficial' THEN mo.texto ELSE campanha_msg_primeira(x.lista, x.voc, x.codigos) END,
         campanha_msg_seguinte(x.lista, x.codigos)
    FROM (
      SELECT g.*, campanha_vocativo(g.nome) AS voc, campanha_linha(g.tel) AS linha
        FROM (
          SELECT 1 AS ordem, 'donos_parados' AS lista, c.chave, max(c.dono_tel) AS tel, max(c.dono_nome) AS nome,
                 array_agg(c.codigo ORDER BY c.codigo) AS codigos, 100 + count(*)::int AS prioridade
            FROM _camp_imovel c WHERE c.fora IS NULL AND NOT c.e_parceiro AND c.parado GROUP BY c.chave
          UNION ALL
          SELECT 2, 'feedback_disponiveis', c.chave, max(c.dono_tel), max(c.dono_nome),
                 array_agg(c.codigo ORDER BY c.codigo), 50 + count(*)::int
            FROM _camp_imovel c WHERE c.fora IS NULL AND NOT c.e_parceiro
             AND NOT EXISTS (SELECT 1 FROM _camp_imovel p WHERE p.chave = c.chave AND p.fora IS NULL AND NOT p.e_parceiro AND p.parado)
           GROUP BY c.chave
          UNION ALL
          SELECT 3, 'parceiros_disponivel', c.chave, max(c.dono_tel), max(c.dono_nome),
                 array_agg(c.codigo ORDER BY c.publicado_no_site DESC, c.criado_em DESC, c.codigo DESC),
                 20 * count(*) FILTER (WHERE c.publicado_no_site)::int
                 + CASE WHEN max(c.criado_em) > now() - interval '30 days' THEN 10 ELSE 0 END + least(count(*)::int, 10)
            FROM _camp_imovel c WHERE c.fora IS NULL AND c.e_parceiro GROUP BY c.chave
        ) g
       ORDER BY g.ordem, g.prioridade DESC
    ) x
    LEFT JOIN LATERAL campanha_modelo(x.codigos, x.voc) mo ON x.linha = 'oficial'
   ORDER BY x.ordem, x.prioridade DESC
  ON CONFLICT (chave, dia) WHERE estado <> 'cancelada' DO NOTHING;

  SELECT jsonb_build_object(
           'dia', v_dia,
           'canceladas_de_antes', v_cancel,
           'listas', (SELECT jsonb_object_agg(lista, n) FROM (SELECT lista, count(*) AS n FROM campanha_contato
                                                               WHERE dia = v_dia AND estado = 'preparada' GROUP BY lista) t),
           'linhas', (SELECT jsonb_object_agg(k, n) FROM (SELECT lista || ':' || linha AS k, count(*) AS n FROM campanha_contato
                                                           WHERE dia = v_dia AND estado = 'preparada' GROUP BY 1) t),
           'imoveis_fora', (SELECT jsonb_object_agg(fora, n) FROM (SELECT fora, count(*) AS n FROM _camp_imovel
                                                                     WHERE fora IS NOT NULL GROUP BY fora) t))
    INTO v_res;
  RETURN v_res;
END;
$function$;

-- ───────────────────────────── a fila do envio ─────────────────────────────
-- O próximo 'liberada' que pode sair agora. As garantias, de novo, na hora: número da casa sai; imóvel que deixou de
-- estar Disponível sai; outra campanha para ele nos últimos 7 dias sai; quem conversou conosco nas últimas
-- `campanha_espera_conversa_h` horas (qualquer número, qualquer lado: privado.falou_conosco) ESPERA.
CREATE OR REPLACE FUNCTION public.campanha_reservar(p_so_teste boolean DEFAULT false)
 RETURNS SETOF privado.campanha_contato LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'privado' AS $function$
DECLARE
  r privado.campanha_contato;
  v_teste text[] := coalesce((SELECT array_agg(right(regexp_replace(x, '\D', '', 'g'), 8))
                                FROM regexp_split_to_table(coalesce((SELECT valor FROM olx_config WHERE chave = 'whatsapp_teste'), ''), '[,;\s]+') x
                               WHERE length(regexp_replace(x, '\D', '', 'g')) >= 8), '{}');
  v_h int := coalesce(nullif(regexp_replace(coalesce((SELECT valor FROM olx_config WHERE chave = 'campanha_espera_conversa_h'), ''), '\D', '', 'g'), '')::int, 12);
  v_motivo text;
  v_quem text;
BEGIN
  FOR r IN SELECT * FROM campanha_contato c
            WHERE c.estado = 'liberada' AND (NOT p_so_teste OR c.tel8 = ANY (v_teste))
              AND (c.adiada_em IS NULL OR c.adiada_em < now() - interval '30 minutes')
            ORDER BY c.prioridade DESC, c.id
            FOR UPDATE SKIP LOCKED LOOP
    v_motivo := CASE
      WHEN r.tel8 = ANY (site_painel_internos()) AND NOT r.tel8 = ANY (v_teste) THEN 'número da casa, da equipe ou de teste'
      WHEN NOT EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = ANY (r.codigos) AND i.status = 'Disponível' AND i.disponivel)
        THEN 'os imóveis não estão mais Disponíveis'
      WHEN EXISTS (SELECT 1 FROM campanha_contato o WHERE o.chave = r.chave AND o.id <> r.id AND o.enviada_em > now() - interval '7 days')
        THEN 'outra campanha falou com ele nos últimos 7 dias'
      WHEN EXISTS (SELECT 1 FROM captacao_leads l WHERE l.telefone_chave = r.chave AND l.opt_out) THEN 'pediu para não receber' END;
    IF v_motivo IS NOT NULL THEN
      UPDATE campanha_contato SET estado = 'cancelada', erro = v_motivo, atualizado_em = now() WHERE id = r.id;
      INSERT INTO campanha_evento (contato, tipo, texto) VALUES (r.id, 'cancelada', v_motivo);
      CONTINUE;
    END IF;
    IF EXISTS (SELECT 1 FROM falou_conosco f WHERE f.chave = r.chave AND f.ultima_em > now() - make_interval(hours => v_h))
       AND NOT r.tel8 = ANY (v_teste) THEN
      UPDATE campanha_contato SET adiada_em = now(), adiada_motivo = 'conversou conosco nas últimas ' || v_h || ' h', atualizado_em = now()
       WHERE id = r.id;
      CONTINUE;
    END IF;
    -- NÃO FALAR POR CIMA DE OUTRA NAY. Corretor com a Nay da Parceria (nay_parceria) ou com a Nay Corretores
    -- (nay_corretores): sai, e a resposta dele é DELAS (a campanha só anota e avisa). A Nay de captação (nay_captacao)
    -- responde os botões do modelo e aplica no cadastro sozinha (321): só sai com campanha_com_nay_captacao = sim.
    -- Conversa em andamento com outra Nay, uma visita ou a equipe: espera.
    v_quem := campanha_quem_atende(r.id);
    IF v_quem IS NOT NULL AND v_quem NOT IN ('nay_parceria', 'nay_corretores')
       AND NOT (v_quem = 'nay_captacao' AND coalesce((SELECT valor FROM olx_config WHERE chave = 'campanha_com_nay_captacao'), 'nao') = 'sim') THEN
      UPDATE campanha_contato SET adiada_em = now(), atualizado_em = now(),
             adiada_motivo = CASE v_quem WHEN 'nay_captacao' THEN 'a Nay de captação responderia (e aplicaria no cadastro sozinha): campanha_com_nay_captacao = nao'
                                         ELSE 'outro atendimento em andamento: ' || v_quem END
       WHERE id = r.id;
      CONTINUE;
    END IF;
    UPDATE campanha_contato SET estado = 'enviando', adiada_motivo = NULL, outro_atende = v_quem, atualizado_em = now()
     WHERE id = r.id RETURNING * INTO r;
    RETURN NEXT r;
    RETURN;
  END LOOP;
END;
$function$;

-- ───────────────────────────── para o CRM (ou à mão) ─────────────────────────────
CREATE OR REPLACE FUNCTION public.crm_campanha_listar(p_lista text DEFAULT NULL, p_estado text DEFAULT NULL, p_limite integer DEFAULT 500)
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'privado' AS $function$
  SELECT jsonb_build_object(
    'resumo', (SELECT coalesce(jsonb_agg(jsonb_build_object('lista', lista, 'estado', estado, 'n', n) ORDER BY lista, estado), '[]')
                 FROM (SELECT lista, estado, count(*) AS n FROM campanha_contato
                        WHERE dia >= (now() AT TIME ZONE 'America/Manaus')::date - 14 GROUP BY 1, 2) t),
    'itens', (SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.lista, t.prioridade DESC, t.id), '[]') FROM (
                SELECT c.id, c.lista, c.dia, c.nome, c.vocativo, c.telefone, c.linha, c.modelo, c.codigos, c.imoveis,
                       c.prioridade, c.falou_conosco_60d, c.mensagem, c.mensagem_seguinte, c.estado, c.liberada_em,
                       c.liberada_por, c.adiada_motivo, c.outro_atende, c.enviada_em, c.resposta_em, c.resposta_texto,
                       c.classe, c.novo_valor, c.classe_codigos, c.resumo, c.seguinte_em, c.respondeu_quem, c.erro
                  FROM campanha_contato c
                 WHERE (p_lista IS NULL OR c.lista = p_lista) AND (p_estado IS NULL OR c.estado = p_estado)
                   AND c.dia >= (now() AT TIME ZONE 'America/Manaus')::date - 14
                 ORDER BY c.lista, c.prioridade DESC, c.id LIMIT greatest(coalesce(p_limite, 500), 1)) t))
$function$;

-- SÓ isto põe contato na fila de envio. Por ids (da mesma lista) ou os N de maior prioridade da lista; sem ids e sem
-- quantidade, a lista inteira. Só a preparação mais recente da lista.
CREATE OR REPLACE FUNCTION public.crm_campanha_liberar(p_lista text, p_ids bigint[] DEFAULT NULL, p_quantos integer DEFAULT NULL,
                                                        p_quem text DEFAULT NULL)
 RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'privado' AS $function$
DECLARE v_n int;
BEGIN
  IF btrim(coalesce(p_quem, '')) = '' THEN
    RAISE EXCEPTION 'diga quem liberou (p_quem)';
  END IF;
  WITH alvo AS (
    SELECT c.id FROM campanha_contato c
     WHERE c.lista = p_lista AND c.estado = 'preparada'
       AND c.dia = (SELECT max(dia) FROM campanha_contato WHERE lista = p_lista)
       AND (p_ids IS NULL OR c.id = ANY (p_ids))
     ORDER BY c.prioridade DESC, c.id
     LIMIT CASE WHEN p_quantos IS NULL OR p_ids IS NOT NULL THEN NULL ELSE greatest(p_quantos, 0) END
  ), lib AS (
    UPDATE campanha_contato c SET estado = 'liberada', liberada_em = now(), liberada_por = btrim(p_quem), atualizado_em = now()
      FROM alvo WHERE c.id = alvo.id RETURNING c.id
  ), ev AS (
    INSERT INTO campanha_evento (contato, tipo, texto) SELECT id, 'liberada', 'por ' || btrim(p_quem) FROM lib RETURNING 1
  )
  SELECT count(*) INTO v_n FROM ev;
  RETURN v_n;
END;
$function$;

CREATE OR REPLACE FUNCTION public.crm_campanha_cancelar(p_ids bigint[], p_motivo text DEFAULT NULL, p_quem text DEFAULT NULL)
 RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'privado' AS $function$
DECLARE v_n int;
BEGIN
  WITH c AS (
    UPDATE campanha_contato SET estado = 'cancelada', atualizado_em = now(),
           erro = left(coalesce(nullif(btrim(p_motivo), ''), 'cancelada') || coalesce(' (' || nullif(btrim(p_quem), '') || ')', ''), 300)
     WHERE id = ANY (p_ids) AND estado IN ('preparada', 'liberada') RETURNING id, erro
  ), ev AS (INSERT INTO campanha_evento (contato, tipo, texto) SELECT id, 'cancelada', erro FROM c RETURNING 1)
  SELECT count(*) INTO v_n FROM ev;
  RETURN v_n;
END;
$function$;

-- O GATILHO DO AVISO DE BAIXA: a equipe confirma o valor menor. Não muda o imóvel (quem muda é a equipe, no editar
-- imóvel); o aviso só sai quando o cadastro já mostra esse valor (ou menor).
CREATE OR REPLACE FUNCTION public.crm_campanha_baixa_confirmar(p_codigo integer, p_valor_novo numeric, p_quem text,
                                                                p_finalidade text DEFAULT NULL, p_valor_antes numeric DEFAULT NULL,
                                                                p_contato bigint DEFAULT NULL)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'privado' AS $function$
DECLARE
  i imoveis;
  v_fin text;
  v_antes numeric;
  v_id bigint;
BEGIN
  IF btrim(coalesce(p_quem, '')) = '' THEN RETURN jsonb_build_object('ok', false, 'erro', 'diga quem confirmou'); END IF;
  SELECT * INTO i FROM imoveis WHERE codigo = p_codigo;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'erro', 'imóvel não existe'); END IF;
  v_fin := coalesce(p_finalidade, CASE WHEN coalesce(i.valor_aluguel, 0) > 0 AND coalesce(i.valor_venda, 0) > 0 THEN NULL
                                       WHEN coalesce(i.valor_aluguel, 0) > 0 THEN 'locacao' ELSE 'venda' END);
  IF v_fin IS NULL OR v_fin NOT IN ('locacao', 'venda') THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'o imóvel tem venda e aluguel: diga a finalidade (locacao | venda)');
  END IF;
  -- o valor de antes: o dito, ou o do retrato da campanha (o cadastro pode já estar com o novo), ou o do cadastro
  v_antes := coalesce(p_valor_antes,
    (SELECT (e->>CASE WHEN v_fin = 'locacao' THEN 'valor_aluguel' ELSE 'valor_venda' END)::numeric
       FROM campanha_contato c, jsonb_array_elements(c.imoveis) e
      WHERE (e->>'codigo')::int = p_codigo AND (p_contato IS NULL OR c.id = p_contato)
      ORDER BY c.id DESC LIMIT 1),
    CASE WHEN v_fin = 'locacao' THEN i.valor_aluguel ELSE i.valor_venda END);
  IF v_antes IS NULL OR p_valor_novo IS NULL OR p_valor_novo >= v_antes THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'o valor novo não é menor que o de antes (' || coalesce(campanha_dinheiro(v_antes), '?') || ')');
  END IF;
  IF p_valor_novo < v_antes * 0.5 THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'mais de 50% abaixo de ' || campanha_dinheiro(v_antes) || ': confira (erro de digitação?)');
  END IF;
  IF EXISTS (SELECT 1 FROM campanha_baixa b WHERE b.codigo = p_codigo AND b.finalidade = v_fin AND b.estado IN ('confirmada', 'avisando')) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'já há uma baixa aberta deste imóvel');
  END IF;
  INSERT INTO campanha_baixa (codigo, finalidade, valor_antes, valor_novo, contato, quem)
  VALUES (p_codigo, v_fin, v_antes, p_valor_novo, p_contato, btrim(p_quem)) RETURNING id INTO v_id;
  IF p_contato IS NOT NULL THEN
    INSERT INTO campanha_evento (contato, tipo, texto, dados)
    VALUES (p_contato, 'nota', 'baixa confirmada por ' || btrim(p_quem), jsonb_build_object('baixa', v_id, 'valor', p_valor_novo));
  END IF;
  RETURN jsonb_build_object('ok', true, 'id', v_id, 'finalidade', v_fin, 'de', v_antes, 'para', p_valor_novo,
                            'cadastro_ja_mostra', CASE WHEN v_fin = 'locacao' THEN i.valor_aluguel ELSE i.valor_venda END <= p_valor_novo);
END;
$function$;

-- quem a Nay Leads avisa da baixa: recebeu o card do imóvel dela nos últimos N dias, não está com a equipe, não é da
-- casa, não é o dono, a finalidade não briga e ainda não foi avisado deste imóvel.
CREATE OR REPLACE FUNCTION public.campanha_baixa_destinatarios(p_baixa bigint)
 RETURNS TABLE(lead bigint, telefone text, tel8 text, nome text, recebeu_em timestamptz)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'privado' AS $function$
  SELECT l.id, l.telefone, right(l.telefone, 8), l.nome, max(o.enviado_em)
    FROM campanha_baixa b
    JOIN olx_cliente_enviada o ON o.codigo = b.codigo AND o.tipo = 'card'
     AND o.enviado_em > b.confirmada_em - make_interval(days => coalesce(nullif(regexp_replace(coalesce(
           (SELECT valor FROM olx_config WHERE chave = 'campanha_baixa_dias'), ''), '\D', '', 'g'), '')::int, 30))
    JOIN olx_lead_whatsapp l ON l.id = o.lead
   WHERE b.id = p_baixa
     AND l.humano_em IS NULL AND l.etapa NOT IN ('fechamento', 'finalizado', 'proprietarios')
     AND NOT (right(l.telefone, 8) = ANY (site_painel_internos()))
     AND position(right(l.telefone, 8) IN regexp_replace(coalesce((SELECT valor FROM olx_config WHERE chave = 'whatsapp_nunca'), ''), '\D', '', 'g')) = 0
     AND NOT EXISTS (SELECT 1 FROM campanha_baixa_aviso a WHERE a.codigo = b.codigo AND a.tel8 = right(l.telefone, 8))
     AND NOT EXISTS (SELECT 1 FROM nai_proprietario_do_imovel(b.codigo) d WHERE right(regexp_replace(coalesce(d.telefone, ''), '\D', '', 'g'), 8) = right(l.telefone, 8))
     AND NOT (b.finalidade = 'locacao' AND coalesce(l.filtros->>'finalidade', '') ~* '^vend')
     AND NOT (b.finalidade = 'venda' AND coalesce(l.filtros->>'finalidade', '') ~* '^(loc|alug)')
   GROUP BY l.id, l.telefone, l.nome
   ORDER BY max(o.enviado_em) DESC
$function$;

REVOKE ALL ON FUNCTION public.campanha_metricas(integer), public.campanha_linha(text), public.campanha_quem_atende(bigint),
                       public.campanha_preparar(date), public.campanha_reservar(boolean),
                       public.crm_campanha_listar(text, text, integer), public.crm_campanha_liberar(text, bigint[], integer, text),
                       public.crm_campanha_cancelar(bigint[], text, text),
                       public.crm_campanha_baixa_confirmar(integer, numeric, text, text, numeric, bigint),
                       public.campanha_baixa_destinatarios(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crm_campanha_listar(text, text, integer), public.crm_campanha_liberar(text, bigint[], integer, text),
                          public.crm_campanha_cancelar(bigint[], text, text),
                          public.crm_campanha_baixa_confirmar(integer, numeric, text, text, numeric, bigint) TO nay_disparo, nay;

-- as listas de hoje
SELECT campanha_preparar() AS preparadas;
COMMIT;
