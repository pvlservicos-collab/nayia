-- =====================================================================
-- NAI -- 19: o comando AGENDA DE VISITAS (Tel, 15/09/2026)
--
-- Ele: "quero que o tel e eu quando digitar no pv dela Agenda de visitas ela
-- liste todas as visitas por dia, mas faça isso sem mexer em nada no atual
-- que ja esta pronto".
--
-- O que ja existia e CONTINUA igual: o comando VISITAS, que lista as visitas
-- em andamento numa lista corrida, ordenada por hora. Nada dele foi tocado.
--
-- O que nasce aqui: AGENDA DE VISITAS, uma AGENDA -- do dia de hoje em diante,
-- com as visitas separadas por dia, cada dia com seu cabecalho. Serve para
-- olhar a semana; o VISITAS serve para ver o que esta pendurado agora.
--
-- Quem pode pedir: o telefone do Tel e o do Pedro (a chave `comando_telefones`).
-- Fora esses dois, "agenda de visitas" continua sendo conversa normal de
-- corretor, e a NAI responde como sempre respondeu.
-- =====================================================================

-- Os telefones que mandam este comando. Nasce com os dois; e um UPDATE para
-- acrescentar alguem, sem deploy.
INSERT INTO nai_config (chave, valor, descricao)
VALUES ('comando_telefones',
        coalesce(nai_cfg('tel_telefone'), '') || ',' || coalesce(nai_cfg('telefone_teste_destino'), ''),
        'Telefones que podem mandar AGENDA DE VISITAS no pv da NAI (separados por virgula).')
ON CONFLICT (chave) DO NOTHING;

-- Quem pode mandar o comando. Compara por CHAVE (nai_chave), que e o mesmo
-- normalizador do resto do sistema -- entao o numero escrito com ou sem o 9,
-- com ou sem o 55, cai no mesmo lugar.
CREATE OR REPLACE FUNCTION nai_pode_comandar(p_chave text)
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM regexp_split_to_table(coalesce(nai_cfg('comando_telefones'), ''), '\s*,\s*') AS n
     WHERE nullif(btrim(n), '') IS NOT NULL AND nai_chave(n) = p_chave);
$$;

-- O texto e o comando da agenda?
CREATE OR REPLACE FUNCTION nai_e_comando_agenda(p text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  -- "agenda", "agenda de visitas", "Nay, agenda das visitas". Nada de
  -- parametro: a agenda e sempre de hoje em diante.
  SELECT coalesce(p, '') ~* '^\s*(@?nay[\s,:;.!-]*)?agenda(\s+(de|das|de as)\s+visitas?)?\s*[.!]?\s*$';
$$;

-- "Hoje, ter 15/09" / "Amanha, qua 16/09" / "qui 17/09"
CREATE OR REPLACE FUNCTION nai_dia_por_extenso(p_dia date, p_hoje date)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN p_dia = p_hoje THEN 'Hoje, '
              WHEN p_dia = p_hoje + 1 THEN 'Amanhã, '
              ELSE '' END
      || CASE extract(isodow FROM p_dia)
           WHEN 1 THEN 'segunda' WHEN 2 THEN 'terça' WHEN 3 THEN 'quarta'
           WHEN 4 THEN 'quinta'  WHEN 5 THEN 'sexta' WHEN 6 THEN 'sábado'
           ELSE 'domingo' END
      || ' ' || to_char(p_dia, 'DD/MM');
$$;

-- O estado em portugues de gente, que e como ele le a lista.
CREATE OR REPLACE FUNCTION nai_estado_por_extenso(p_estado text, p_aguardando text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_estado
           WHEN 'confirmada'              THEN 'confirmada'
           WHEN 'coletando'               THEN 'montando o pedido'
           WHEN 'aguardando_proprietario' THEN 'esperando o proprietário'
           WHEN 'negociando'              THEN 'negociando o horário'
           WHEN 'aguardando_acesso'       THEN 'esperando saber como entra'
           WHEN 'aguardando_motoboy'      THEN 'esperando o Fernando'
           WHEN 'com_tel'                 THEN 'parada com o Tel'
           ELSE p_estado
         END;
$$;

-- ---------------------------------------------------------------------
-- A AGENDA, dia por dia.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION nai_agenda_por_dia()
RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_hoje date := (now() AT TIME ZONE 'America/Manaus')::date;
  v_txt  text;
BEGIN
  SELECT string_agg(bloco, E'\n\n' ORDER BY dia) INTO v_txt FROM (
    SELECT d.dia,
           '*' || nai_dia_por_extenso(d.dia, v_hoje) || '*' || E'\n' ||
           string_agg(d.linha, E'\n' ORDER BY d.quando, d.id) AS bloco
      FROM (
        SELECT x.id,
               x.quando,
               ((x.quando AT TIME ZONE 'America/Manaus')::date) AS dia,
               to_char(x.quando AT TIME ZONE 'America/Manaus', 'HH24:MI') || ' - ' ||
               nai_ref_imovel(x.codigo) ||
               -- o nome do corretor como o resto do sistema o enxerga: o que ele
               -- mesmo passou, e so entao o do WhatsApp (que pode ser empresa).
               coalesce(' - ' || nullif(btrim(coalesce(k.nome_completo,
                        nay_nome_de_pessoa(k.nome_whatsapp))), ''), '') ||
               ' - ' || nai_estado_por_extenso(x.estado, x.aguardando) AS linha
          FROM nai_visita x
          LEFT JOIN nai_contato k ON k.id = x.corretor_id
         WHERE nai_visita_aberta(x.estado)
           AND x.quando IS NOT NULL
           AND (x.quando AT TIME ZONE 'America/Manaus')::date >= v_hoje
      ) d
     GROUP BY d.dia
  ) z;

  IF v_txt IS NULL THEN
    RETURN 'Agenda de visitas' || E'\n\n' || 'Nenhuma visita marcada de hoje em diante.';
  END IF;
  RETURN 'Agenda de visitas' || E'\n\n' || v_txt;
END;
$$;
