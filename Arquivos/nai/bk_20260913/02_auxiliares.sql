-- =====================================================================
-- NAI atendimento locacao -- 02: funcoes auxiliares (chave, datas
-- humanizadas, CPF, proprietario do imovel)
-- =====================================================================

-- Telefone brasileiro so com digitos e com DDI. O cadastro de
-- proprietarios guarda "(92) 99420-9841"; a Z-API manda "5592994209841".
CREATE OR REPLACE FUNCTION nai_fone_br(p text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN d = '' THEN NULL
    WHEN length(d) IN (10, 11) AND d !~ '^55' THEN '55' || d
    WHEN length(d) IN (11, 12) AND d ~ '^0' THEN '55' || ltrim(d, '0')
    ELSE d
  END
  FROM (SELECT regexp_replace(coalesce(p, ''), '\D', '', 'g') AS d) t;
$$;

-- A CHAVE da pessoa. Mesmo criterio de `nay_fone_chave` (DDI+DDD+8 ultimos
-- digitos), para o 9 a mais ou a menos nunca virar outra pessoa. O @lid
-- vira uma chave propria, 'lid:<digitos>': ele NAO e resolvido para
-- telefone aqui. Resolver pelo nome (como a Nay antiga faz) juntaria duas
-- pessoas de mesmo nome na mesma conversa -- exatamente o que nao pode.
CREATE OR REPLACE FUNCTION nai_chave(p text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN p IS NULL OR btrim(p) = '' THEN NULL
    WHEN p ILIKE '%@lid' THEN
      CASE WHEN regexp_replace(p, '\D', '', 'g') ~ '^[0-9]{6,20}$'
           THEN 'lid:' || regexp_replace(p, '\D', '', 'g') END
    WHEN nai_fone_br(p) IS NULL THEN NULL
    WHEN nai_fone_br(p) !~ '^[0-9]{8,15}$' THEN NULL
    ELSE nay_fone_chave(nai_fone_br(p))
  END;
$$;

-- O identificador para ENVIAR: digitos com DDI, ou o @lid como veio.
CREATE OR REPLACE FUNCTION nai_fone_envio(p text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN p ILIKE '%@lid' THEN regexp_replace(p, '\D', '', 'g') || '@lid'
    ELSE nai_fone_br(p)
  END;
$$;

CREATE OR REPLACE FUNCTION nai_chaves_teste()
RETURNS text[] LANGUAGE sql STABLE AS $$
  SELECT coalesce(array_agg(nai_chave(btrim(x))) FILTER (WHERE nai_chave(btrim(x)) IS NOT NULL), '{}')
    FROM unnest(string_to_array(nai_cfg('numeros_teste', ''), ',')) x;
$$;

-- "(92) 99201-9498" para mostrar a gente.
CREATE OR REPLACE FUNCTION nai_fone_fmt(p text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN d ~ '^55[0-9]{2}9[0-9]{8}$' THEN '(' || substr(d,3,2) || ') ' || substr(d,5,5) || '-' || substr(d,10,4)
    WHEN d ~ '^55[0-9]{2}[0-9]{8}$'  THEN '(' || substr(d,3,2) || ') ' || substr(d,5,4) || '-' || substr(d,9,4)
    ELSE p
  END
  FROM (SELECT nai_fone_br(p) AS d) t;
$$;

-- ------------------------------------------------------------------ CPF
CREATE OR REPLACE FUNCTION nai_cpf_valido(p text)
RETURNS text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  d text := regexp_replace(coalesce(p, ''), '\D', '', 'g');
  s int; r int; i int;
BEGIN
  IF d !~ '^[0-9]{11}$' OR d ~ '^(.)\1{10}$' THEN RETURN NULL; END IF;
  s := 0;
  FOR i IN 1..9 LOOP s := s + substr(d, i, 1)::int * (11 - i); END LOOP;
  r := (s * 10) % 11; IF r = 10 THEN r := 0; END IF;
  IF r <> substr(d, 10, 1)::int THEN RETURN NULL; END IF;
  s := 0;
  FOR i IN 1..10 LOOP s := s + substr(d, i, 1)::int * (12 - i); END LOOP;
  r := (s * 10) % 11; IF r = 10 THEN r := 0; END IF;
  IF r <> substr(d, 11, 1)::int THEN RETURN NULL; END IF;
  RETURN d;   -- valido: devolve so os digitos
END;
$$;

CREATE OR REPLACE FUNCTION nai_cpf_fmt(p text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN p ~ '^[0-9]{11}$'
    THEN substr(p,1,3) || '.' || substr(p,4,3) || '.' || substr(p,7,3) || '-' || substr(p,10,2)
    ELSE p END;
$$;

-- Nome completo: pelo menos duas palavras com letra.
CREATE OR REPLACE FUNCTION nai_nome_completo(p text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN n IS NULL THEN NULL
    WHEN n ~ '[0-9@]' THEN NULL
    WHEN array_length(regexp_split_to_array(n, '\s+'), 1) >= 2
         AND length(n) BETWEEN 5 AND 120 THEN n
    ELSE NULL
  END
  FROM (SELECT NULLIF(regexp_replace(btrim(coalesce(p, '')), '\s+', ' ', 'g'), '') AS n) t;
$$;

-- ------------------------------------------------------- datas e horas
-- Le o horario que o modelo passou ('AAAA-MM-DD HH:MM', hora de Manaus).
-- NULL quando nao da para ler -- e NULL leva a perguntar, nunca a chutar.
CREATE OR REPLACE FUNCTION nai_ler_quando(p text)
RETURNS timestamptz LANGUAGE plpgsql STABLE AS $$
DECLARE m text[];
BEGIN
  m := regexp_match(coalesce(p, ''), '(\d{4})-(\d{1,2})-(\d{1,2})[ T]+(\d{1,2}):(\d{2})');
  IF m IS NULL THEN RETURN NULL; END IF;
  RETURN make_timestamptz(m[1]::int, m[2]::int, m[3]::int, m[4]::int, m[5]::int, 0, 'America/Manaus');
EXCEPTION WHEN others THEN
  RETURN NULL;
END;
$$;

-- "hoje a tarde, as 15h", "amanha de manha, as 9h30", "quinta-feira a
-- noite, as 19h". O Tel pediu no card do proprietario: sem data numerica.
CREATE OR REPLACE FUNCTION nai_quando_humano(p_ts timestamptz, p_agora timestamptz DEFAULT now())
RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE
  l    timestamp := p_ts AT TIME ZONE 'America/Manaus';
  hoje date := (p_agora AT TIME ZONE 'America/Manaus')::date;
  d    int;
  h    int;
  mi   int;
  dia  text;
  per  text;
  hora text;
  sem  text[] := ARRAY['domingo','segunda-feira','terça-feira','quarta-feira','quinta-feira','sexta-feira','sábado'];
BEGIN
  IF p_ts IS NULL THEN RETURN NULL; END IF;
  d  := l::date - hoje;
  h  := extract(hour FROM l)::int;
  mi := extract(minute FROM l)::int;
  dia := CASE
    WHEN d = 0 THEN 'hoje'
    WHEN d = 1 THEN 'amanhã'
    WHEN d = -1 THEN 'ontem'
    WHEN d BETWEEN 2 AND 6 THEN sem[extract(dow FROM l)::int + 1]
    ELSE sem[extract(dow FROM l)::int + 1] || ', dia ' || extract(day FROM l)::int
  END;
  IF h = 12 AND mi = 0 THEN
    RETURN dia || ', ao meio-dia';
  END IF;
  per  := CASE WHEN h < 12 THEN 'de manhã' WHEN h < 18 THEN 'à tarde' ELSE 'à noite' END;
  hora := 'às ' || h || 'h' || CASE WHEN mi > 0 THEN lpad(mi::text, 2, '0') ELSE '' END;
  IF d >= 7 THEN
    RETURN dia || ', ' || per || ', ' || hora;
  END IF;
  RETURN dia || ' ' || per || ', ' || hora;
END;
$$;

-- "sex 12/09 às 15:00" -- para o Fernando e o Tel, que precisam da hora exata.
CREATE OR REPLACE FUNCTION nai_hora_exata(p_ts timestamptz)
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT (ARRAY['dom','seg','ter','qua','qui','sex','sáb'])[extract(dow FROM l)::int + 1]
         || ' ' || to_char(l, 'DD/MM') || ' às ' || to_char(l, 'HH24:MI')
    FROM (SELECT p_ts AT TIME ZONE 'America/Manaus' AS l) t;
$$;

CREATE OR REPLACE FUNCTION nai_saudacao(p_ts timestamptz DEFAULT now())
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT CASE
    WHEN h >= 6 AND h < 12 THEN 'Bom dia'
    WHEN h >= 12 AND h < 18 THEN 'Boa tarde'
    ELSE 'Boa noite' END
  FROM (SELECT extract(hour FROM p_ts AT TIME ZONE 'America/Manaus')::int AS h) t;
$$;

CREATE OR REPLACE FUNCTION nai_dentro_da_janela(p_ts timestamptz DEFAULT now())
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT (p_ts AT TIME ZONE 'America/Manaus')::time
         BETWEEN nai_cfg('janela_inicio', '06:00')::time AND nai_cfg('janela_fim', '22:00')::time;
$$;

-- ----------------------------------------------------- nomes de imovel
CREATE OR REPLACE FUNCTION nai_condominio_ok(p text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN coalesce(btrim(p), '') = '' OR p ~* 'identificado' THEN NULL ELSE btrim(p) END;
$$;

-- Para o CORRETOR: "Condomínio Acquarelle, código 5611".
CREATE OR REPLACE FUNCTION nai_ref_imovel(p_codigo int)
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT coalesce(nai_condominio_ok(i.condominio_nome),
                  coalesce(i.tipo, 'imóvel') || CASE WHEN coalesce(i.bairro,'') <> '' THEN ' no ' || i.bairro ELSE '' END)
         || ', código ' || i.codigo
    FROM imoveis i WHERE i.codigo = p_codigo;
$$;

-- Para o PROPRIETARIO, que nao conhece codigo: "no seu imóvel do
-- Condomínio Acquarelle" / "no seu imóvel no Aleixo".
CREATE OR REPLACE FUNCTION nai_ref_imovel_prop(p_codigo int)
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT CASE
    WHEN nai_condominio_ok(i.condominio_nome) IS NOT NULL THEN 'no seu imóvel do ' || nai_condominio_ok(i.condominio_nome)
    WHEN coalesce(i.bairro, '') <> '' THEN 'no seu imóvel no ' || i.bairro
    ELSE 'no seu imóvel' END
    FROM imoveis i WHERE i.codigo = p_codigo;
$$;

-- Para o FERNANDO, que e da equipe e precisa chegar la: endereco inteiro,
-- torre e unidade. NUNCA vai para corretor.
CREATE OR REPLACE FUNCTION nai_endereco_interno(p_codigo int)
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT concat_ws(', ',
           nai_condominio_ok(i.condominio_nome),
           NULLIF(concat_ws(' ', NULLIF(i.logradouro,''), NULLIF(i.numero,'')), ''),
           NULLIF(i.complemento, ''),
           CASE WHEN coalesce(p.torre,'') <> '' THEN 'torre ' || p.torre END,
           CASE WHEN coalesce(p.unidade,'') <> '' THEN 'unidade ' || p.unidade END,
           NULLIF(i.bairro, ''))
         || ' (código ' || i.codigo || ')'
    FROM imoveis i LEFT JOIN imovel_privado p ON p.codigo = i.codigo
   WHERE i.codigo = p_codigo;
$$;

-- -------------------------------------------------- quem e o proprietario
-- Devolve o proprietario do imovel e SE da para falar direto com ele.
-- motivo NULL = pode falar. Qualquer outra coisa = passa ao Tel.
CREATE OR REPLACE FUNCTION nai_proprietario_do_imovel(p_codigo int)
RETURNS TABLE(cadastro_id int, nome text, telefone text, motivo text)
LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_id   int;
  v_nome text;
  v_tel  text;
  v_n    int;
  m      text[];
BEGIN
  SELECT pr.id, pr.nome, pr.telefone INTO v_id, v_nome, v_tel
    FROM imovel_privado p JOIN proprietarios pr ON pr.id = p.proprietario_id
   WHERE p.codigo = p_codigo;

  IF v_id IS NULL THEN
    -- Segunda fonte: o que foi coletado do admin. So vale se o imovel tiver
    -- UM proprietario so -- dois donos e perguntar ao errado nao tem volta.
    SELECT count(DISTINCT a.proprietario_id), min(pa.id) INTO v_n, v_id
      FROM proprietarios_admin_imoveis a JOIN proprietarios_admin pa ON pa.id = a.proprietario_id
     WHERE a.codigo = p_codigo::text;
    IF coalesce(v_n, 0) > 1 THEN
      RETURN QUERY SELECT NULL::int, NULL::text, NULL::text, 'dois_donos'::text; RETURN;
    END IF;
    IF v_id IS NOT NULL THEN
      SELECT pa.nome, pa.telefone INTO v_nome, v_tel FROM proprietarios_admin pa WHERE pa.id = v_id;
    END IF;
  END IF;

  IF v_id IS NULL THEN
    RETURN QUERY SELECT NULL::int, NULL::text, NULL::text, 'sem_cadastro'::text; RETURN;
  END IF;

  -- "Neide (Tratar com a Imob Easy)": o cadastro manda falar com outra pessoa.
  IF coalesce(v_nome, '') ~* '(tratar|falar|contato)\s+com' THEN
    RETURN QUERY SELECT v_id, v_nome, NULL::text, 'tratar_com_outra_pessoa'::text; RETURN;
  END IF;

  -- O primeiro telefone que aparecer no campo ("(92) 9999-8888 / ...").
  m := regexp_match(coalesce(v_tel, ''), '\(?\d{2}\)?[\s.-]*9?\s*\d{4}[\s.-]?\d{4}');
  IF m IS NULL OR nai_chave(m[1]) IS NULL THEN
    RETURN QUERY SELECT v_id, v_nome, NULL::text, 'sem_telefone'::text; RETURN;
  END IF;

  RETURN QUERY SELECT v_id, NULLIF(btrim(regexp_replace(v_nome, '\(.*?\)', '', 'g')), ''), nai_fone_br(m[1]), NULL::text;
END;
$$;

-- "Sr. Hugo", "Sra. Vania", ou so "Hugo" quando o genero nao e claro.
CREATE OR REPLACE FUNCTION nai_vocativo(p_nome text)
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT CASE
    WHEN coalesce(btrim(p_nome), '') = '' THEN NULL
    WHEN nay_tratamento_por_nome(p_nome) IS NOT NULL
      THEN nay_tratamento_por_nome(p_nome) || ' ' || coalesce(nay_primeiro_nome(p_nome), p_nome)
    ELSE coalesce(nay_primeiro_nome(p_nome), p_nome)
  END;
$$;

-- O Fernando (papel acompanhante, ativo). Cria o contato dele se preciso.
CREATE OR REPLACE FUNCTION nai_motoboy()
RETURNS TABLE(contato_id bigint, nome text, telefone text)
LANGUAGE plpgsql AS $$
DECLARE e record; v_id bigint;
BEGIN
  SELECT * INTO e FROM equipe WHERE papel = 'acompanhante' AND ativo ORDER BY criado_em LIMIT 1;
  IF e IS NULL OR nai_chave(e.telefone) IS NULL THEN RETURN; END IF;
  v_id := nai_contato_de(e.telefone, e.nome);
  RETURN QUERY SELECT v_id, e.nome::text, e.telefone::text;
END;
$$;

CREATE OR REPLACE FUNCTION nai_e_motoboy(p_chave text)
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM equipe WHERE papel = 'acompanhante' AND ativo AND nai_chave(telefone) = p_chave);
$$;

-- --------------------------------------------------------- contato (upsert)
-- A UNICA forma de criar/achar uma pessoa. O telefone guardado passa a ser
-- o ultimo formato que CHEGOU dela (e o que a Z-API sabe entregar).
CREATE OR REPLACE FUNCTION nai_contato_de(p_tel text, p_nome text DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v_chave text := nai_chave(p_tel); v_id bigint;
BEGIN
  IF v_chave IS NULL THEN RETURN NULL; END IF;
  INSERT INTO nai_contato (chave, telefone, nome_whatsapp)
       VALUES (v_chave, nai_fone_envio(p_tel), NULLIF(btrim(coalesce(p_nome, '')), ''))
  ON CONFLICT (chave) DO UPDATE
     SET telefone = EXCLUDED.telefone,
         nome_whatsapp = coalesce(EXCLUDED.nome_whatsapp, nai_contato.nome_whatsapp),
         atualizado_em = now()
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- So acha, sem mexer no telefone guardado (usado para proprietario, cujo
-- numero vem do cadastro e nao de uma mensagem que ele mandou).
CREATE OR REPLACE FUNCTION nai_contato_do_cadastro(p_tel text, p_nome text)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v_chave text := nai_chave(p_tel); v_id bigint;
BEGIN
  IF v_chave IS NULL THEN RETURN NULL; END IF;
  SELECT id INTO v_id FROM nai_contato WHERE chave = v_chave;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;
  INSERT INTO nai_contato (chave, telefone, nome_whatsapp)
       VALUES (v_chave, nai_fone_envio(p_tel), NULLIF(btrim(coalesce(p_nome, '')), ''))
  ON CONFLICT (chave) DO NOTHING
  RETURNING id INTO v_id;
  IF v_id IS NULL THEN SELECT id INTO v_id FROM nai_contato WHERE chave = v_chave; END IF;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION nai_evento(p_visita bigint, p_tipo text, p_detalhe text DEFAULT NULL)
RETURNS void LANGUAGE sql AS $$
  INSERT INTO nai_visita_evento (visita_id, tipo, detalhe) VALUES (p_visita, p_tipo, p_detalhe);
$$;

-- O corretor, com o que se sabe dele (cadastro antigo + o que a NAI guardou).
CREATE OR REPLACE FUNCTION nai_dados_corretor(p_contato bigint)
RETURNS TABLE(primeiro_nome text, nome_completo text, cpf text, creci text, completo boolean)
LANGUAGE sql STABLE AS $$
  WITH k AS (SELECT * FROM nai_contato WHERE id = p_contato),
       c AS (SELECT c.* FROM corretores c, k WHERE k.chave !~ '^lid:' AND nai_chave(c.telefone) = k.chave
              ORDER BY c.aprovado DESC LIMIT 1)
  SELECT coalesce(nay_nome_de_pessoa((SELECT nome FROM c)), nay_nome_de_pessoa(k.nome_completo),
                  nay_nome_de_pessoa(k.nome_whatsapp)),
         coalesce(k.nome_completo, nai_nome_completo((SELECT CASE WHEN nome_origem = 'manual' THEN nome END FROM c))),
         k.cpf,
         coalesce(NULLIF(btrim((SELECT creci FROM c)), ''), k.creci),
         (coalesce(k.nome_completo, nai_nome_completo((SELECT CASE WHEN nome_origem = 'manual' THEN nome END FROM c))) IS NOT NULL
          AND k.cpf IS NOT NULL
          AND coalesce(NULLIF(btrim((SELECT creci FROM c)), ''), k.creci) IS NOT NULL)
    FROM k;
$$;

-- "a, b e c" -- lista em portugues para as frases que pedem dados.
CREATE OR REPLACE FUNCTION nai_lista_pt(p text[])
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN coalesce(array_length(p, 1), 0) = 0 THEN ''
    WHEN array_length(p, 1) = 1 THEN p[1]
    ELSE array_to_string(p[1:array_length(p, 1) - 1], ', ') || ' e ' || p[array_length(p, 1)] END;
$$;

-- Carimba no turno a ferramenta que rodou (ver a coluna nai_turno.ferramentas).
CREATE OR REPLACE FUNCTION nai_usou_ferramenta(p_turno bigint, p_nome text)
RETURNS void LANGUAGE sql AS $$
  UPDATE nai_turno SET ferramentas = array_append(ferramentas, p_nome)
   WHERE id = p_turno AND NOT (p_nome = ANY(ferramentas));
$$;
