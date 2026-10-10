-- 336 -- Captação ativa por grupos: os pedidos que os corretores fazem nos grupos, comparados com o nosso catálogo
--
-- Pedro, 09/10/2026: "quero adicionar uma aba na aba Grupos do menu com essa função" (a especificação do módulo
-- "Captação Ativa por Grupos") e depois "põe a nova aba ao lado de Métricas".
--
-- Quem LÊ, EXTRAI e PONTUA é o serviço em Python `nay-grupos` (nayia/nay-grupos, systemd na VPS1). Aqui ficam só
-- as tabelas dele e as funções que a tela chama (admin do site › Grupos › Captação ativa, pela senha do painel).
--
--   privado.grupo_pedido_teste       mensagem colada na tela, para treinar a leitura sem depender do grupo
--   privado.grupo_mensagem_lida      o que o serviço já leu (pedido ou não): cada mensagem passa uma vez só
--   privado.grupo_pedido             CADA solicitação (uma mensagem pode ter várias), com a ficha extraída
--   privado.grupo_pedido_par         os imóveis nossos que passaram nos filtros, com a nota e o detalhe dela
--   privado.grupo_pedido_julgamento  "Leitura correta / errada" (para medir a taxa de acerto)
--   privado.grupo_apelido            apelidos de bairro e condomínio, editáveis na tela
--   privado.grupo_captacao_estado    o que o serviço publica: modo, cortes, batimento
--
-- MODO TREINO: nada aqui manda mensagem. A função que muda o estado do pedido RECUSA "aprovado" -- o envio fica
-- bloqueado no código (aqui e no serviço), não só no botão. O modo ativo é outra migração, depois do sim dele.
--
-- Tudo em `privado` (tem telefone e nome de corretor) e só por função SECURITY DEFINER dada ao papel do site.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS privado.grupo_pedido_teste (
  id        bigserial   PRIMARY KEY,
  texto     text        NOT NULL,
  nome      text,
  criado_em timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS privado.grupo_mensagem_lida (
  fonte   text        NOT NULL CHECK (fonte IN ('grupo', 'teste')),
  ref     text        NOT NULL,                 -- message_id do grupo, ou o id do teste
  lida_em timestamptz NOT NULL DEFAULT now(),
  pedidos integer     NOT NULL DEFAULT 0,
  motivo  text,                                 -- por que não virou pedido (oferta, conversa, card nosso...)
  erro    text,                                 -- a IA não respondeu: tenta de novo depois (até 5 vezes)
  tentativas integer  NOT NULL DEFAULT 1,
  modelo  text,
  PRIMARY KEY (fonte, ref)
);

CREATE TABLE IF NOT EXISTS privado.grupo_pedido (
  id               bigserial   PRIMARY KEY,
  fonte            text        NOT NULL CHECK (fonte IN ('grupo', 'teste')),
  ref              text        NOT NULL,
  parte            integer     NOT NULL,        -- qual pedido dentro da mensagem (1, 2, ...)
  grupo_id         text,
  grupo_nome       text,
  remetente        text,                        -- telefone de quem escreveu no grupo
  remetente_nome   text,
  enviada_em       timestamptz NOT NULL,
  texto            text        NOT NULL,        -- a mensagem original inteira
  ficha            jsonb       NOT NULL,        -- o que a IA leu (campos da especificação)
  duvidosos        text[]      NOT NULL DEFAULT '{}',
  local            jsonb,                       -- os nomes que o serviço reconheceu (bairros e condomínios oficiais)
  estado           text        NOT NULL DEFAULT 'novo' CHECK (estado IN ('novo', 'rejeitado', 'aprovado', 'enviado')),
  melhor_codigo    integer,
  nota             numeric(5,1),
  faixa            text CHECK (faixa IN ('verde', 'amarelo', 'registro', 'sem_match')),
  sem_match_motivo text,
  funil            jsonb,                       -- quantos imóveis sobraram depois de cada filtro
  extraido_em      timestamptz NOT NULL DEFAULT now(),
  pontuado_em      timestamptz,
  UNIQUE (fonte, ref, parte)
);
CREATE INDEX IF NOT EXISTS grupo_pedido_quando ON privado.grupo_pedido (enviada_em DESC);

CREATE TABLE IF NOT EXISTS privado.grupo_pedido_par (
  pedido_id     bigint       NOT NULL REFERENCES privado.grupo_pedido (id) ON DELETE CASCADE,
  codigo        integer      NOT NULL,
  posicao       integer      NOT NULL,          -- 1 = o melhor; os outros são as alternativas
  nota          numeric(5,1) NOT NULL,
  detalhe       jsonb        NOT NULL,          -- quanto cada critério rendeu
  acima_do_teto boolean      NOT NULL DEFAULT false,
  imovel        jsonb        NOT NULL,          -- como o imóvel estava na hora da conta
  PRIMARY KEY (pedido_id, codigo)
);

CREATE TABLE IF NOT EXISTS privado.grupo_pedido_julgamento (
  id          bigserial   PRIMARY KEY,
  pedido_id   bigint      NOT NULL REFERENCES privado.grupo_pedido (id) ON DELETE CASCADE,
  leitura     text        NOT NULL CHECK (leitura IN ('correta', 'errada')),
  o_que_errou text,
  criado_em   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS grupo_pedido_julgamento_pedido ON privado.grupo_pedido_julgamento (pedido_id, id DESC);

CREATE TABLE IF NOT EXISTS privado.grupo_apelido (
  apelido   text        PRIMARY KEY,            -- sem acento, minúsculo, só letra e número
  tipo      text        NOT NULL CHECK (tipo IN ('bairro', 'condominio')),
  oficial   text        NOT NULL,               -- o nome como está no cadastro
  obs       text,
  criado_em timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS privado.grupo_captacao_estado (
  id        integer     PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  config    jsonb       NOT NULL DEFAULT '{}',
  batimento timestamptz,
  repontuar boolean     NOT NULL DEFAULT false,
  aviso     text
);
INSERT INTO privado.grupo_captacao_estado (id) VALUES (1) ON CONFLICT DO NOTHING;

-- os apelidos do exemplo dele ("Parque Vile", "Vile"); o resto ele acrescenta na tela
INSERT INTO privado.grupo_apelido (apelido, tipo, oficial, obs) VALUES
  ('parque vile',  'condominio', 'Parque Ville Municipal', 'exemplo do Pedro (09/10)'),
  ('parque ville', 'condominio', 'Parque Ville Municipal', 'exemplo do Pedro (09/10)'),
  ('vile',         'condominio', 'Parque Ville Municipal', 'exemplo do Pedro (09/10)')
ON CONFLICT DO NOTHING;

-- o nome como chave: sem acento, minúsculo, só letra e número (a MESMA conta do serviço, texto.normal)
CREATE OR REPLACE FUNCTION public.site_captacao_chave(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  SELECT btrim(regexp_replace(lower(unaccent(coalesce(p, ''))), '[^a-z0-9]+', ' ', 'g'));
$function$;

-- A TELA: os pedidos da janela (mais recente primeiro), com o melhor imóvel, as alternativas e o julgamento
CREATE OR REPLACE FUNCTION public.site_captacao_grupos(p_filtro text DEFAULT 'todos', p_horas integer DEFAULT NULL, p_limite integer DEFAULT 80)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  e       privado.grupo_captacao_estado;
  v_horas int;
  v_desde timestamptz;
  v_fil   text := lower(coalesce(nullif(btrim(p_filtro), ''), 'todos'));
  v_ped   jsonb;
  v_cont  jsonb;
  v_fonte jsonb;
BEGIN
  SELECT * INTO e FROM privado.grupo_captacao_estado WHERE id = 1;
  v_horas := least(greatest(coalesce(p_horas, nullif(e.config->>'janela_h', '')::int, 48), 1), 24 * 60);
  v_desde := now() - make_interval(hours => v_horas);

  SELECT jsonb_build_object(
           'todos',     count(*),
           'verde',     count(*) FILTER (WHERE q.faixa = 'verde'),
           'amarelo',   count(*) FILTER (WHERE q.faixa = 'amarelo'),
           'registro',  count(*) FILTER (WHERE q.faixa = 'registro'),
           'sem_match', count(*) FILTER (WHERE q.faixa = 'sem_match'),
           'a_pontuar', count(*) FILTER (WHERE q.pontuado_em IS NULL),
           'teste',     count(*) FILTER (WHERE q.fonte = 'teste'))
    INTO v_cont FROM privado.grupo_pedido q WHERE q.enviada_em >= v_desde;

  -- o que chega dos grupos (para a tela dizer quando a fonte está muda)
  SELECT jsonb_build_object(
           'mensagens',  count(*),
           'com_texto',  count(*) FILTER (WHERE nullif(btrim(c.texto), '') IS NOT NULL),
           'grupos',     count(DISTINCT c.grupo_id),
           'ultima_com_texto', max(c.enviada_em) FILTER (WHERE nullif(btrim(c.texto), '') IS NOT NULL),
           'lidas',      (SELECT count(*) FROM privado.grupo_mensagem_lida l WHERE l.fonte = 'grupo' AND l.lida_em >= v_desde))
    INTO v_fonte FROM privado.grupo_conversa c WHERE c.enviada_em >= v_desde AND NOT c.de_mim;

  SELECT coalesce(jsonb_agg(x.j ORDER BY x.enviada_em DESC, x.id DESC), '[]'::jsonb) INTO v_ped
    FROM (
      SELECT q.id, q.enviada_em,
             jsonb_build_object(
               'id', q.id, 'fonte', q.fonte, 'parte', q.parte,
               'grupo', q.grupo_nome, 'nome', q.remetente_nome, 'telefone', q.remetente,
               'enviada_em', q.enviada_em, 'texto', q.texto,
               'ficha', q.ficha, 'duvidosos', to_jsonb(q.duvidosos), 'local', q.local,
               'estado', q.estado, 'nota', q.nota, 'faixa', q.faixa, 'sem_match_motivo', q.sem_match_motivo,
               'funil', q.funil, 'pontuado', q.pontuado_em IS NOT NULL,
               'pares', coalesce((SELECT jsonb_agg(jsonb_build_object(
                                           'codigo', p.codigo, 'posicao', p.posicao, 'nota', p.nota,
                                           'detalhe', p.detalhe, 'acima_do_teto', p.acima_do_teto, 'imovel', p.imovel)
                                         ORDER BY p.posicao)
                                    FROM privado.grupo_pedido_par p WHERE p.pedido_id = q.id), '[]'::jsonb),
               'julgamento', (SELECT jsonb_build_object('leitura', j.leitura, 'o_que_errou', j.o_que_errou, 'quando', j.criado_em)
                                FROM privado.grupo_pedido_julgamento j WHERE j.pedido_id = q.id ORDER BY j.id DESC LIMIT 1)) AS j
        FROM privado.grupo_pedido q
       WHERE q.enviada_em >= v_desde
         AND CASE v_fil WHEN 'verde'     THEN q.faixa = 'verde'
                        WHEN 'amarelo'   THEN q.faixa = 'amarelo'
                        WHEN 'sem_match' THEN q.faixa = 'sem_match'
                        WHEN 'teste'     THEN q.fonte = 'teste'
                        ELSE true END
       ORDER BY q.enviada_em DESC, q.id DESC
       LIMIT least(greatest(coalesce(p_limite, 80), 1), 300)) x;

  RETURN jsonb_build_object(
    'modo',      coalesce(e.config->>'modo', 'treino'),
    'config',    e.config,
    'aviso',     e.aviso,
    'batimento', e.batimento,
    'servico_vivo', coalesce(e.batimento > now() - interval '3 minutes', false),
    'horas',     v_horas,
    'fonte',     v_fonte,
    'contagem',  v_cont,
    'acerto',    (SELECT jsonb_build_object(
                           'julgados', count(*),
                           'corretas', count(*) FILTER (WHERE u.leitura = 'correta'),
                           'erradas',  count(*) FILTER (WHERE u.leitura = 'errada'))
                    FROM (SELECT DISTINCT ON (j.pedido_id) j.leitura
                            FROM privado.grupo_pedido_julgamento j ORDER BY j.pedido_id, j.id DESC) u),
    'pedidos',   v_ped);
END
$function$;

-- "Leitura correta" / "Leitura errada" (com o que errou)
CREATE OR REPLACE FUNCTION public.site_captacao_grupos_julgar(p_id bigint, p_leitura text, p_erro text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
BEGIN
  IF lower(coalesce(p_leitura, '')) NOT IN ('correta', 'errada') THEN
    RETURN jsonb_build_object('erro', 'Diga se a leitura está correta ou errada.');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM privado.grupo_pedido WHERE id = p_id) THEN
    RETURN jsonb_build_object('erro', 'Não achei essa solicitação.');
  END IF;
  IF lower(p_leitura) = 'errada' AND nullif(btrim(coalesce(p_erro, '')), '') IS NULL THEN
    RETURN jsonb_build_object('erro', 'Diga o que a leitura errou.');
  END IF;
  INSERT INTO privado.grupo_pedido_julgamento (pedido_id, leitura, o_que_errou)
  VALUES (p_id, lower(p_leitura), nullif(left(btrim(coalesce(p_erro, '')), 1000), ''));
  RETURN jsonb_build_object('ok', true);
END
$function$;

-- Rejeitar (e desfazer). "aprovado" é RECUSADO aqui: o envio não existe nesta versão (modo treino).
CREATE OR REPLACE FUNCTION public.site_captacao_grupos_estado(p_id bigint, p_estado text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE v_estado text := lower(coalesce(p_estado, ''));
BEGIN
  IF v_estado IN ('aprovado', 'enviado') THEN
    RETURN jsonb_build_object('erro', 'Modo treino: aprovar e enviar está desligado. Nenhuma mensagem sai daqui.');
  END IF;
  IF v_estado NOT IN ('novo', 'rejeitado') THEN
    RETURN jsonb_build_object('erro', 'Estado desconhecido.');
  END IF;
  UPDATE privado.grupo_pedido SET estado = v_estado WHERE id = p_id AND estado IN ('novo', 'rejeitado');
  IF NOT FOUND THEN RETURN jsonb_build_object('erro', 'Não achei essa solicitação.'); END IF;
  RETURN jsonb_build_object('ok', true, 'estado', v_estado);
END
$function$;

-- Colar uma mensagem para a IA ler (treino). O serviço pega em alguns segundos.
CREATE OR REPLACE FUNCTION public.site_captacao_grupos_testar(p_texto text, p_nome text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE v_id bigint; v_texto text := btrim(coalesce(p_texto, ''));
BEGIN
  IF length(v_texto) < 8 THEN RETURN jsonb_build_object('erro', 'Cole a mensagem do corretor.'); END IF;
  IF (SELECT count(*) FROM privado.grupo_pedido_teste WHERE criado_em > now() - interval '1 hour') >= 120 THEN
    RETURN jsonb_build_object('erro', 'Muitos testes nesta hora: espere um pouco.');
  END IF;
  INSERT INTO privado.grupo_pedido_teste (texto, nome)
  VALUES (left(v_texto, 4000), nullif(left(btrim(coalesce(p_nome, '')), 80), '')) RETURNING id INTO v_id;
  RETURN jsonb_build_object('ok', true, 'id', v_id);
END
$function$;

-- Já foi lida? (a tela espera o teste virar pedido, ou saber que não era pedido)
CREATE OR REPLACE FUNCTION public.site_captacao_grupos_teste_lido(p_id bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT coalesce((SELECT jsonb_build_object('lido', true, 'pedidos', l.pedidos, 'motivo', l.motivo, 'erro', l.erro,
                                             'pontuado', NOT EXISTS (SELECT 1 FROM privado.grupo_pedido q
                                                                      WHERE q.fonte = 'teste' AND q.ref = p_id::text AND q.pontuado_em IS NULL))
                     FROM privado.grupo_mensagem_lida l WHERE l.fonte = 'teste' AND l.ref = p_id::text),
                  jsonb_build_object('lido', false));
$function$;

-- Os apelidos (bairro e condomínio)
CREATE OR REPLACE FUNCTION public.site_captacao_grupos_apelidos()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT jsonb_build_object(
    'apelidos', coalesce((SELECT jsonb_agg(jsonb_build_object('apelido', a.apelido, 'tipo', a.tipo, 'oficial', a.oficial, 'obs', a.obs)
                                           ORDER BY a.tipo, a.apelido) FROM privado.grupo_apelido a), '[]'::jsonb),
    'bairros', coalesce((SELECT jsonb_agg(b ORDER BY b) FROM (SELECT DISTINCT btrim(i.bairro) AS b FROM imoveis i
                          WHERE nullif(btrim(i.bairro), '') IS NOT NULL) x), '[]'::jsonb),
    'condominios', coalesce((SELECT jsonb_agg(n ORDER BY n) FROM (SELECT DISTINCT btrim(c.nome) AS n FROM condominios c
                              WHERE nullif(btrim(c.nome), '') IS NOT NULL) y), '[]'::jsonb));
$function$;

CREATE OR REPLACE FUNCTION public.site_captacao_grupos_apelido_salvar(p_apelido text, p_tipo text, p_oficial text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  v_chave   text := site_captacao_chave(p_apelido);
  v_tipo    text := lower(coalesce(p_tipo, ''));
  v_oficial text;
BEGIN
  IF length(v_chave) < 2 THEN RETURN jsonb_build_object('erro', 'Escreva o apelido.'); END IF;
  IF v_tipo NOT IN ('bairro', 'condominio') THEN RETURN jsonb_build_object('erro', 'O apelido é de bairro ou de condomínio?'); END IF;
  -- o nome oficial tem de existir no cadastro (senão o apelido leva a lugar nenhum)
  IF v_tipo = 'bairro' THEN
    SELECT btrim(i.bairro) INTO v_oficial FROM imoveis i
     WHERE site_captacao_chave(i.bairro) = site_captacao_chave(p_oficial) GROUP BY 1 ORDER BY count(*) DESC LIMIT 1;
  ELSE
    SELECT btrim(c.nome) INTO v_oficial FROM condominios c
     WHERE site_captacao_chave(c.nome) = site_captacao_chave(p_oficial) LIMIT 1;
  END IF;
  IF v_oficial IS NULL THEN
    RETURN jsonb_build_object('erro', 'Não achei "' || coalesce(btrim(p_oficial), '') || '" no cadastro de '
                                      || CASE v_tipo WHEN 'bairro' THEN 'bairros' ELSE 'condomínios' END || '.');
  END IF;
  INSERT INTO privado.grupo_apelido (apelido, tipo, oficial) VALUES (v_chave, v_tipo, v_oficial)
  ON CONFLICT (apelido) DO UPDATE SET tipo = excluded.tipo, oficial = excluded.oficial, obs = NULL, criado_em = now();
  UPDATE privado.grupo_captacao_estado SET repontuar = true WHERE id = 1;   -- o serviço refaz a conta da janela
  RETURN jsonb_build_object('ok', true, 'apelido', v_chave, 'oficial', v_oficial);
END
$function$;

CREATE OR REPLACE FUNCTION public.site_captacao_grupos_apelido_excluir(p_apelido text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
BEGIN
  DELETE FROM privado.grupo_apelido WHERE apelido = site_captacao_chave(p_apelido);
  IF NOT FOUND THEN RETURN jsonb_build_object('erro', 'Não achei esse apelido.'); END IF;
  UPDATE privado.grupo_captacao_estado SET repontuar = true WHERE id = 1;
  RETURN jsonb_build_object('ok', true);
END
$function$;

-- DEMANDA DO MERCADO: o que mais pedem nos grupos, e quanto disso ficou sem imóvel nosso. Só pedido de grupo
-- (teste colado na tela não entra). Um pedido com dois bairros conta nos dois.
CREATE OR REPLACE FUNCTION public.site_captacao_grupos_demanda(p_dias integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  WITH base AS (
    SELECT q.id, q.faixa,
           coalesce(q.local->>'operacao', q.ficha->>'operacao') AS operacao,
           nullif(q.ficha->>'quartos', '')::int AS quartos,
           nullif(q.ficha->>'preco_max', '')::numeric AS teto,
           coalesce((SELECT array_agg(DISTINCT z) FROM (
                       SELECT jsonb_array_elements_text(coalesce(q.local->'bairros', '[]'::jsonb)) AS z
                       UNION SELECT jsonb_array_elements_text(coalesce(q.local->'condominios', '[]'::jsonb))) s), ARRAY['(sem lugar)']) AS lugares
      FROM privado.grupo_pedido q
     WHERE q.fonte = 'grupo' AND q.enviada_em >= now() - make_interval(days => least(greatest(coalesce(p_dias, 30), 1), 365))
  ), linhas AS (
    SELECT b.id, b.faixa, coalesce(b.operacao, '(não disse)') AS operacao, lugar, b.quartos,
           CASE WHEN b.teto IS NULL THEN '(sem valor)'
                WHEN coalesce(b.operacao, CASE WHEN b.teto < 30000 THEN 'aluguel' ELSE 'venda' END) = 'aluguel' THEN
                  CASE WHEN b.teto <= 1500 THEN 'até 1.500' WHEN b.teto <= 2500 THEN '1.500 a 2.500' WHEN b.teto <= 4000 THEN '2.500 a 4.000'
                       WHEN b.teto <= 6000 THEN '4.000 a 6.000' ELSE 'acima de 6.000' END
                ELSE CASE WHEN b.teto <= 300000 THEN 'até 300 mil' WHEN b.teto <= 500000 THEN '300 a 500 mil' WHEN b.teto <= 800000 THEN '500 a 800 mil'
                          WHEN b.teto <= 1500000 THEN '800 mil a 1,5 mi' ELSE 'acima de 1,5 mi' END END AS faixa_de_preco
      FROM base b, unnest(b.lugares) AS lugar
  )
  SELECT jsonb_build_object(
    'dias', least(greatest(coalesce(p_dias, 30), 1), 365),
    'pedidos', (SELECT count(*) FROM base),
    'sem_imovel', (SELECT count(*) FROM base WHERE faixa = 'sem_match'),
    'linhas', coalesce((SELECT jsonb_agg(jsonb_build_object('operacao', g.operacao, 'lugar', g.lugar, 'quartos', g.quartos,
                                                             'preco', g.faixa_de_preco, 'pedidos', g.n, 'sem_imovel', g.sem)
                                         ORDER BY g.sem DESC, g.n DESC, g.lugar)
                          FROM (SELECT l.operacao, l.lugar, l.quartos, l.faixa_de_preco, count(DISTINCT l.id) AS n,
                                       count(DISTINCT l.id) FILTER (WHERE l.faixa = 'sem_match') AS sem
                                  FROM linhas l GROUP BY 1, 2, 3, 4 ORDER BY 6 DESC, 5 DESC LIMIT 60) g), '[]'::jsonb));
$function$;

REVOKE ALL ON FUNCTION public.site_captacao_grupos(text, integer, integer),
                       public.site_captacao_grupos_julgar(bigint, text, text),
                       public.site_captacao_grupos_estado(bigint, text),
                       public.site_captacao_grupos_testar(text, text),
                       public.site_captacao_grupos_teste_lido(bigint),
                       public.site_captacao_grupos_apelidos(),
                       public.site_captacao_grupos_apelido_salvar(text, text, text),
                       public.site_captacao_grupos_apelido_excluir(text),
                       public.site_captacao_grupos_demanda(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.site_captacao_grupos(text, integer, integer),
                          public.site_captacao_grupos_julgar(bigint, text, text),
                          public.site_captacao_grupos_estado(bigint, text),
                          public.site_captacao_grupos_testar(text, text),
                          public.site_captacao_grupos_teste_lido(bigint),
                          public.site_captacao_grupos_apelidos(),
                          public.site_captacao_grupos_apelido_salvar(text, text, text),
                          public.site_captacao_grupos_apelido_excluir(text),
                          public.site_captacao_grupos_demanda(integer) TO nay_site_escrita;

COMMIT;
