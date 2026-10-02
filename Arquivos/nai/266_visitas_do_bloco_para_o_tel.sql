-- 266 (02/10/2026): AS VISITAS DO BLOCO, PARA O TEL LIGAR.
-- Pedro: "veja aqui para a Michelly Velloso prop Vision: ela mandou msg ontem, a
-- proprietária não respondeu, e também teve um pedido de visita que está chegando
-- próximo. É bom avisar o Tel quando tiver um pedido que seja nesse bloco de
-- tempo, ou seja manhã, tarde e noite; no começo do bloco, às 8:30, a Nay deve
-- avisar o Tel de todas as visitas marcadas, ou solicitadas que o proprietário
-- não respondeu, para ele ligar."
--
-- O CASO: visita #1063, imóvel 5713, hoje (02/10) às 09h30. A Nay escreveu para a
-- proprietária em 01/10 às 19h38 e ela não respondeu. A visita está `com_rayssa`
-- (desde a 197/199 quem cuida é a equipe), e nesse estado NADA no nai_agenda_tick
-- olha para "o dono não respondeu": o reenvio e o aviso ao Tel só existem para
-- `aguardando = 'proprietario'`. Então a visita chegava em cima da hora sem
-- ninguém saber que o dono estava mudo.
--
-- A REGRA NOVA: quando o bloco do dia começa, o Tel recebe UMA mensagem com as
-- visitas daquele bloco, separadas em "o proprietário não respondeu: vale ligar"
-- (com o telefone do dono) e "confirmadas". Bloco = manhã, tarde, noite; os
-- horários ficam em nai_config (`resumo_tel_manha` 08:30 como ele pediu,
-- `resumo_tel_tarde` 12:00, `resumo_tel_noite` 18:00), separados dos
-- `inicio_*` que marcam o lembrete do CORRETOR -- mexer num não mexe no outro.
--
-- E O PEDIDO QUE ENTRA NO MEIO DO BLOCO ("avisar o Tel quando tiver um pedido que
-- seja nesse bloco de tempo"): a mesma regra pega. Todo minuto o tick procura
-- visita do bloco corrente que ainda não foi avisada; achou, manda. A que entra
-- às 10h para as 11h sai na hora, sozinha, com o título "entrou visita".
--
-- CADA VISITA É AVISADA UMA VEZ POR BLOCO (tabela nai_aviso_bloco). Mudou de
-- horário para outro bloco, é avisada no bloco novo.
--
-- O QUE ENTRA: visita aberta, de hoje, ainda por acontecer, em que o dono já foi
-- procurado (ou já confirmou). A que ainda está sendo combinada com o corretor
-- (coletando/confirmando) fica de fora: não há o que o Tel fazer nela.
--
-- TABELA NOVA em vez de coluna em nai_visita: ALTER TABLE numa tabela que a Nay
-- usa o tempo todo já travou ela 2 minutos num ensaio (28/09).
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS public.nai_aviso_bloco (
  visita_id  bigint NOT NULL,
  dia        date   NOT NULL,
  bloco      text   NOT NULL CHECK (bloco IN ('manha', 'tarde', 'noite')),
  situacao   text   NOT NULL,
  avisado_em timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (visita_id, dia, bloco)
);
COMMENT ON TABLE public.nai_aviso_bloco IS
  '266: cada visita que o Tel já recebeu no resumo do bloco (manhã/tarde/noite). Uma vez por bloco.';

INSERT INTO nai_config (chave, valor, descricao) VALUES
  ('resumo_tel_ligado', 'sim',   '266: no começo de cada bloco, o Tel recebe as visitas do bloco (sim/nao)'),
  ('resumo_tel_manha',  '08:30', '266: hora do aviso das visitas da manhã ao Tel (visitas até o começo da tarde)'),
  ('resumo_tel_tarde',  '12:00', '266: hora do aviso das visitas da tarde ao Tel'),
  ('resumo_tel_noite',  '18:00', '266: hora do aviso das visitas da noite ao Tel')
ON CONFLICT (chave) DO NOTHING;

CREATE OR REPLACE FUNCTION public.nai_visitas_do_bloco_avisar()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_agora  timestamp := now() AT TIME ZONE 'America/Manaus';   -- a hora de Manaus, sem fuso
  v_manha  time := nai_cfg('resumo_tel_manha', '08:30')::time;
  v_tarde  time := nai_cfg('resumo_tel_tarde', '12:00')::time;
  v_noite  time := nai_cfg('resumo_tel_noite', '18:00')::time;
  v_bloco  text;
  v_ini    timestamp;
  v_fim    timestamp;
  v_ligar  text := '';
  v_ok     text := '';
  v_ids    bigint[] := '{}';
  v_sit    text[] := '{}';
  v_primeiro boolean;
  r        record;
  dono     record;
  v_fone   text;
  v_linha  text;
BEGIN
  IF nai_cfg('resumo_tel_ligado', 'sim') <> 'sim' THEN RETURN 0; END IF;

  -- o bloco de AGORA. Antes do aviso da manhã não há bloco: ninguém é acordado.
  IF    v_agora::time >= v_noite THEN v_bloco := 'noite'; v_ini := v_agora::date + v_noite; v_fim := v_agora::date + interval '1 day';
  ELSIF v_agora::time >= v_tarde THEN v_bloco := 'tarde'; v_ini := v_agora::date + v_tarde; v_fim := v_agora::date + v_noite;
  ELSIF v_agora::time >= v_manha THEN v_bloco := 'manha'; v_ini := v_agora::date;           v_fim := v_agora::date + v_tarde;
  ELSE RETURN 0;
  END IF;

  -- já saiu alguma visita deste bloco hoje? (decide o título: resumo ou "entrou visita")
  v_primeiro := NOT EXISTS (SELECT 1 FROM nai_aviso_bloco a WHERE a.dia = v_agora::date AND a.bloco = v_bloco);

  FOR r IN
    SELECT v.*, (v.quando AT TIME ZONE 'America/Manaus') AS local,
           -- o dono já disse sim?
           (v.prop_ok_em IS NOT NULL OR v.estado = 'confirmada'
            OR (v.ult_resp_prop_em IS NOT NULL AND v.ult_resp_prop_em >= coalesce(v.ult_msg_prop_em, v.ult_resp_prop_em))) AS dono_ok,
           coalesce(c.nome_completo, c.nome_whatsapp, 'corretor') AS corretor
      FROM nai_visita v
      LEFT JOIN nai_contato c ON c.id = v.corretor_id
     WHERE nai_visita_aberta(v.estado)
       AND v.estado NOT IN ('coletando', 'confirmando', 'realizada')
       AND v.quando IS NOT NULL
       AND v.quando > now()
       AND (v.quando AT TIME ZONE 'America/Manaus') >= v_ini
       AND (v.quando AT TIME ZONE 'America/Manaus') <  v_fim
       -- o dono foi procurado, ou já confirmou: é o que o Tel pediu para ver
       AND (v.ult_msg_prop_em IS NOT NULL OR v.prop_ok_em IS NOT NULL OR v.estado = 'confirmada')
       AND NOT EXISTS (SELECT 1 FROM nai_aviso_bloco a
                        WHERE a.visita_id = v.id AND a.dia = v_agora::date AND a.bloco = v_bloco)
     ORDER BY v.quando
  LOOP
    SELECT * INTO dono FROM nai_proprietario_do_imovel(r.codigo);
    v_fone := coalesce(nullif(r.prop_telefone_manual, ''), dono.telefone);
    v_linha := '• ' || to_char(r.local, 'HH24"h"MI') || ' · ' || nai_ref_imovel(r.codigo) || ' (visita #' || r.id || ')' || E'\n'
            || '   Proprietário: ' || coalesce(nullif(btrim(coalesce(r.proprietario_nome, dono.nome, '')), ''), 'sem nome no cadastro')
            || CASE WHEN coalesce(v_fone, '') <> '' THEN ' ' || nai_fone_fmt(v_fone) ELSE ' (sem telefone no cadastro)' END || E'\n'
            || '   Corretor: ' || r.corretor;
    IF r.dono_ok THEN
      v_ok := v_ok || v_linha || E'\n';
    ELSE
      v_ligar := v_ligar || v_linha
              || CASE WHEN r.ult_msg_prop_em IS NOT NULL
                      THEN E'\n   Escrevi ' || nai_quando_humano(r.ult_msg_prop_em, now()) || ', e não tive resposta.' ELSE '' END
              || E'\n';
    END IF;
    v_ids := array_append(v_ids, r.id);
    v_sit := array_append(v_sit, CASE WHEN r.dono_ok THEN 'confirmada' ELSE 'dono_sem_resposta' END);
  END LOOP;

  IF array_length(v_ids, 1) IS NULL THEN RETURN 0; END IF;

  PERFORM nai_avisar_tel(NULL, NULL,
    CASE WHEN v_primeiro THEN 'Tel, as visitas ' ELSE 'Tel, entrou visita para ' END
      || CASE v_bloco WHEN 'manha' THEN CASE WHEN v_primeiro THEN 'desta manhã' ELSE 'esta manhã' END
                      WHEN 'tarde' THEN CASE WHEN v_primeiro THEN 'desta tarde' ELSE 'esta tarde' END
                      ELSE CASE WHEN v_primeiro THEN 'desta noite' ELSE 'esta noite' END END || ':'
      || CASE WHEN v_ligar <> '' THEN E'\n\n☎️ *O proprietário ainda não respondeu — vale ligar:*\n' || rtrim(v_ligar, E'\n') ELSE '' END
      || CASE WHEN v_ok    <> '' THEN E'\n\n✅ *Confirmadas com o proprietário:*\n' || rtrim(v_ok, E'\n') ELSE '' END,
    'visitas_do_bloco');

  INSERT INTO nai_aviso_bloco (visita_id, dia, bloco, situacao)
  SELECT u.id, v_agora::date, v_bloco, u.sit FROM unnest(v_ids, v_sit) AS u(id, sit)
  ON CONFLICT DO NOTHING;
  RETURN array_length(v_ids, 1);
END;
$function$;
COMMENT ON FUNCTION nai_visitas_do_bloco_avisar() IS
  '266: no começo de cada bloco (e a cada visita que entrar nele), manda ao Tel as visitas do bloco -- as que o dono não respondeu, com o telefone, e as confirmadas';

-- entra no tick da agenda (todo minuto), com a proteção das outras: erro aqui
-- nunca para a agenda das visitas
CREATE OR REPLACE FUNCTION pg_temp.trocar(p_fn regprocedure, p_de text, p_para text, p_vezes int DEFAULT 1)
 RETURNS void LANGUAGE plpgsql AS $$
DECLARE d text := pg_get_functiondef(p_fn); n int := (length(d) - length(replace(d, p_de, ''))) / length(p_de);
BEGIN
  IF n <> p_vezes THEN RAISE EXCEPTION 'trocar em %: esperava % vez(es), achei % -- %', p_fn, p_vezes, n, left(p_de, 50); END IF;
  EXECUTE replace(d, p_de, p_para);
END $$;

SELECT pg_temp.trocar('nai_agenda_tick()'::regprocedure,
$de$  -- 141: o follow-up do dia seguinte. Um erro aqui nunca para a agenda das visitas.$de$,
$para$  -- 266: as visitas do bloco (manhã/tarde/noite) para o Tel ligar. Erro aqui nunca para a agenda.
  BEGIN
    n := n + nai_visitas_do_bloco_avisar();
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'nai_visitas_do_bloco_avisar: %', SQLERRM;
  END;

  -- 141: o follow-up do dia seguinte. Um erro aqui nunca para a agenda das visitas.$para$);
COMMIT;
