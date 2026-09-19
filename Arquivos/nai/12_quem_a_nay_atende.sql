-- =====================================================================
-- NAI -- 12: QUEM a Nay atende quando sair do teste (Tel, 13/09/2026)
--
-- Pedido, nas palavras dele: "prepare para ligar a nay para os contatos novos
-- que falarem de imoveis, ou seja as conversas que ja estao conversando com o
-- tel a uma semana a nay nao vai responder nenhuma, desligada para todas as
-- conversas existentes, menos se elas pedirem explicitamente foto de um imovel
-- no sentido 'Tem fotos do imovel .....?' ai a nay liga pra essa conversa, fora
-- isso a nay vai fica ligada para as novas pessoas que chamarem no grupo, mas
-- nao ativa isso ainda deixa eu testar".
--
-- E, na segunda rodada de perguntas: antigo e QUALQUER historico, de qualquer
-- epoca; o pedido de foto liga a Nay para AQUELA conversa dali em diante; e
-- entre os novos, "se parecer que nao e um atendimento normal de corretor e sim
-- uma duvida pessoal... ela nao responde".
--
-- NADA DISSO ESTA LIGADO. A chave `regra_publico` nasce 'nao' e, enquanto
-- estiver assim, `nai_deve_atender` devolve atende=true para todo mundo -- quem
-- decide continua sendo o modo de teste. Para ligar, um comando so:
--   SELECT nai_ligar_regra_publico();
-- Para desligar:
--   SELECT nai_desligar_regra_publico();
-- O carimbo do dia em que ligou fica em `regra_publico_desde` e e ELE que
-- separa "quem ja falava com o Tel" de "gente nova" -- por isso desligar e
-- ligar de novo NAO reclassifica ninguem (o carimbo so e gravado uma vez).
-- =====================================================================

INSERT INTO nai_config (chave, valor, descricao) VALUES
  ('regra_publico', 'nao',
   'sim = a Nay so atende quem e novo (e fala de imovel) e quem pediu foto explicitamente. nao = regra desligada.'),
  ('regra_publico_desde', '',
   'Carimbo de quando a regra foi ligada pela primeira vez. Quem tem mensagem ANTES disso e "conversa que ja existia".')
ON CONFLICT (chave) DO NOTHING;

ALTER TABLE nai_contato ADD COLUMN IF NOT EXISTS liberado_em timestamptz;
ALTER TABLE nai_contato ADD COLUMN IF NOT EXISTS liberado_motivo text;
COMMENT ON COLUMN nai_contato.liberado_em IS
  'Conversa antiga que pediu foto de um imovel: a partir daqui a Nay atende ela normalmente (Tel, 13/09).';

-- ------------------------------------------------------------------ ligar
CREATE OR REPLACE FUNCTION nai_ligar_regra_publico()
RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_desde text;
BEGIN
  v_desde := nullif(btrim(nai_cfg('regra_publico_desde', '')), '');
  IF v_desde IS NULL THEN
    v_desde := to_char(now(), 'YYYY-MM-DD HH24:MI:SSOF');
    UPDATE nai_config SET valor = v_desde WHERE chave = 'regra_publico_desde';
  END IF;
  UPDATE nai_config SET valor = 'sim' WHERE chave = 'regra_publico';
  RETURN 'Regra ligada. Quem tem mensagem anterior a ' || v_desde ||
         ' e conversa antiga (Nay calada, menos pedindo foto de imovel).';
END;
$$;

CREATE OR REPLACE FUNCTION nai_desligar_regra_publico()
RETURNS text LANGUAGE sql AS $$
  UPDATE nai_config SET valor = 'nao' WHERE chave = 'regra_publico';
  SELECT 'Regra desligada. O carimbo de quando ligou fica guardado.'::text;
$$;

-- ------------------------------------------------------------------ os testes de texto
-- PEDIDO DE FOTO, explicito, do jeito que ele escreveu: "Tem fotos do imovel X?".
-- Pede foto e NAO nega ("ja recebi as fotos" nao e pedido).
CREATE OR REPLACE FUNCTION nai_pede_foto(p_texto text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT x ~ '(foto|fotos|imagem|imagens|fachada|video|fotografia)'
     AND x ~ '(\mtem\M|\mtens\M|teria|manda|mandar|envia|enviar|passa|passar|poderia|pode|queria|quero|gostaria|consegue|me ve|me mostra|mostra|tira)'
     AND x !~ '(ja (recebi|vi|tenho|peguei)|nao precis|dispensa)'
  FROM (SELECT lower(unaccent(coalesce(p_texto, ''))) AS x) t;
$$;

-- ASSUNTO DE CORRETOR (para quem chega novo): imovel, aluguel, visita, codigo,
-- condominio, bairro, foto. "Duvida pessoal" -- boleto, contrato do apartamento
-- dele, assunto de familia, emprego -- nao e atendimento e a Nay nao responde.
CREATE OR REPLACE FUNCTION nai_assunto_de_corretor(p_texto text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT x ~ ('(imovel|imoveis|apartamento|\mapto\M|\map\M|casa|kitnet|flat|sala comercial|terreno|'
              || 'aluguel|alugar|locacao|venda|vender|comprar|financ|'
              || 'visita|visitar|agendar|disponivel|disponibilidade|'
              || 'quarto|suite|banheiro|vaga|garagem|mobiliad|condominio|bairro|metragem|'
              || 'foto|fotos|imagem|imagens|fachada|card|anuncio|'
              || 'corretor|creci|cliente|proposta|valor|preco)')
     AND x !~ '(boleto|segunda via|contrato de trabalho|curriculo|vaga de emprego|processo seletivo)'
  FROM (SELECT lower(unaccent(coalesce(p_texto, ''))) AS x) t;
$$;

-- ------------------------------------------------------------------ a porta
-- Devolve SE a Nay responde essa mensagem e por que. Com a regra desligada,
-- atende todo mundo (e o modo de teste que manda, como hoje).
-- p_codigo_citado: o imovel que o sistema JA sabe -- codigo escrito por ele,
-- card colado ou mensagem do grupo marcada. NULL = nao sabe qual imovel e.
CREATE OR REPLACE FUNCTION nai_deve_atender(p_telefone text, p_texto text, p_codigo_citado int DEFAULT NULL)
RETURNS TABLE(atende boolean, motivo text) LANGUAGE plpgsql AS $$
DECLARE
  v_chave  text := nai_chave(p_telefone);
  v_desde  timestamptz;
  v_antigo boolean;
  v_lib    timestamptz;
  v_cod    boolean;
BEGIN
  IF lower(coalesce(nai_cfg('regra_publico', 'nao'), 'nao')) <> 'sim' THEN
    RETURN QUERY SELECT true, 'regra desligada'::text; RETURN;
  END IF;
  v_desde := nullif(btrim(nai_cfg('regra_publico_desde', '')), '')::timestamptz;
  IF v_desde IS NULL THEN
    RETURN QUERY SELECT true, 'sem carimbo: regra nao vale'::text; RETURN;
  END IF;

  SELECT c.liberado_em INTO v_lib FROM nai_contato c WHERE c.chave = v_chave;
  IF v_lib IS NOT NULL THEN
    RETURN QUERY SELECT true, 'conversa liberada por pedido de foto'::text; RETURN;
  END IF;

  -- "Antigo" e QUALQUER historico anterior ao carimbo (Tel: "qualquer historico,
  -- de qualquer epoca"), na Nay ou no numero do Tel.
  SELECT EXISTS (SELECT 1 FROM mensagens m
                  WHERE nai_chave(m.telefone) = v_chave AND m.criada_em < v_desde)
      OR EXISTS (SELECT 1 FROM nai_turno t JOIN nai_contato c ON c.id = t.contato_id
                  WHERE c.chave = v_chave AND t.criado_em < v_desde)
    INTO v_antigo;

  IF NOT v_antigo THEN
    -- Gente nova: atende quando fala de imovel. Duvida pessoal, nao.
    IF nai_assunto_de_corretor(p_texto) THEN
      RETURN QUERY SELECT true, 'contato novo falando de imovel'::text; RETURN;
    END IF;
    RETURN QUERY SELECT false, 'contato novo, assunto que nao e de corretor'::text; RETURN;
  END IF;

  -- Conversa que ja existia: so o pedido explicito de foto DE UM IMOVEL liga a
  -- Nay -- e liga de vez naquela conversa. Sem saber qual imovel, ela fica
  -- calada: o portao falha FECHADO, e o Tel segue sozinho no chat.
  v_cod := p_codigo_citado IS NOT NULL
        OR EXISTS (SELECT 1 FROM unnest(coalesce(nay_codigos_citados(coalesce(p_texto, '')), '{}'::text[])) x
                    WHERE x ~ '^[0-9]{3,5}$');
  IF nai_pede_foto(p_texto) AND v_cod THEN
    UPDATE nai_contato SET liberado_em = now(),
                           liberado_motivo = left('pediu foto: ' || coalesce(p_texto, ''), 200)
     WHERE chave = v_chave;
    RETURN QUERY SELECT true, 'conversa antiga pediu foto de um imovel'::text; RETURN;
  END IF;
  IF nai_pede_foto(p_texto) THEN
    RETURN QUERY SELECT false, 'pediu foto mas nao da para saber o imovel'::text; RETURN;
  END IF;
  RETURN QUERY SELECT false, 'conversa que ja existia: quem responde e o Tel'::text;
END;
$$;
