-- 269 (02/10/2026): A PORTA ENTREGA O CORRETOR AO NÚCLEO NOVO (nay-core).
--
-- Pedro, 02/10: "pode implementar a nova nay rodando e põe ela para responder
-- clientes já". O núcleo novo só sabe atender corretor que procura ou pergunta
-- de imóvel. Visita, proprietário, acompanhante, comandos do Tel, mídia,
-- fechamento e cadastro de imóvel CONTINUAM AQUI, no sistema velho.
--
-- COMO AS DUAS NÃO RESPONDEM JUNTAS: a porta continua sendo uma só, esta
-- (nai_abrir_turno). Ela decide tudo o que já decidia -- pausa, Tel com a
-- conversa, Rayssa, acompanhante, resposta automática, lista de corretores --
-- e só no fim, quando o turno IA para o agente do corretor, pergunta a
-- nai_core_atende(): se sim, grava o turno em nai_core_turno, fecha e devolve
-- ok=false (o roteador do fluxo não manda nada com ok falso, como na 186 e na
-- 197). O núcleo novo lê nai_core_turno e responde. Cada mensagem tem um dono só.
--
-- O INTERRUPTOR é nai_config:
--   core_atende = 'nao'  -> tudo como antes (é como esta migração entra)
--   core_atende = 'sim'  -> o núcleo novo atende
--   core_atende_so = '559...,lid:...' -> com 'sim', só estas chaves (canário); vazio = todos
-- Voltar atrás é um UPDATE: vale na mensagem seguinte, sem deploy nem import.
--
-- FICA NO VELHO mesmo com 'sim': mensagem que fala de visita, corretor com
-- visita em andamento (ou realizada há menos de 3 dias), ficha de cadastro de
-- imóvel aberta, turno com imagem/documento/vídeo, e os contatos de teste (a
-- bateria nai_rodar_casos não pode mudar de dono).
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION pg_temp.trocar(p_fn regprocedure, p_de text, p_para text, p_vezes int DEFAULT 1)
 RETURNS void LANGUAGE plpgsql AS $$
DECLARE d text := pg_get_functiondef(p_fn); n int := (length(d) - length(replace(d, p_de, ''))) / length(p_de);
BEGIN
  IF n <> p_vezes THEN RAISE EXCEPTION 'trocar em %: esperava % vez(es), achei % -- %', p_fn, p_vezes, n, left(p_de, 50); END IF;
  EXECUTE replace(d, p_de, p_para);
END $$;

-- 1. o interruptor (entra desligado) e a lista de entrega
INSERT INTO nai_config (chave, valor, descricao) VALUES
  ('core_atende', 'nao', 'sim = o núcleo novo (nay-core) atende o corretor que procura ou pergunta de imóvel; nao = a Nay de sempre (269)'),
  ('core_atende_so', '', 'com core_atende=sim: só estas chaves (separadas por vírgula) vão para o núcleo novo; vazio = todos (269)')
ON CONFLICT (chave) DO NOTHING;

CREATE TABLE IF NOT EXISTS nai_core_turno (
  turno_id  bigint PRIMARY KEY,   -- nai_turno.id (sem chave estrangeira: ela travaria nai_turno ao criar)
  criado_em timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE nai_core_turno IS 'Turnos de corretor que a porta (nai_abrir_turno) entregou ao núcleo novo (269). O nay-core lê daqui.';
GRANT SELECT ON nai_core_turno TO nay_core;

-- 2. quem atende este turno de corretor: o núcleo novo?
CREATE OR REPLACE FUNCTION public.nai_core_atende(p_contato bigint, p_texto text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE
    WHEN lower(coalesce(public.nai_cfg('core_atende', 'nao'), 'nao')) <> 'sim' THEN false
    -- visita é do sistema velho: a mensagem fala de visita...
    WHEN public.nay_sem_acento(lower(coalesce(p_texto, '')))
         ~ '\m(visita|visitas|visitar|visitacao|agendar|agendamento|agenda|reagendar|remarcar|desmarcar)\M' THEN false
    -- ...ou ele tem visita em andamento (ou acabou de acontecer: o resultado dela vem em seguida)
    WHEN EXISTS (SELECT 1 FROM public.nai_visita v
                  WHERE v.corretor_id = ANY (coalesce(public.nai_contato_irmaos(p_contato), ARRAY[p_contato]))
                    AND v.estado NOT IN ('encerrada', 'cancelada', 'expirada')
                    AND (v.estado <> 'realizada' OR v.atualizado_em > now() - interval '3 days')) THEN false
    -- ficha de cadastro de imóvel aberta com a secretária
    WHEN EXISTS (SELECT 1 FROM public.nai_imovel_novo n
                  WHERE n.contato_id = ANY (coalesce(public.nai_contato_irmaos(p_contato), ARRAY[p_contato]))
                    AND n.situacao = 'colhendo' AND n.criado_em > now() - interval '24 hours') THEN false
    -- canário: com a lista preenchida, só quem está nela
    WHEN btrim(coalesce(public.nai_cfg('core_atende_so', ''), '')) <> '' THEN
      (SELECT c.chave FROM public.nai_contato c WHERE c.id = p_contato)
        = ANY (string_to_array(replace(public.nai_cfg('core_atende_so', ''), ' ', ''), ','))
    -- os contatos de teste (espelho da bateria) continuam no velho
    WHEN (SELECT c.chave FROM public.nai_contato c WHERE c.id = p_contato) = ANY (public.nai_chaves_teste()) THEN false
    ELSE true
  END;
$function$;

-- 3. a porta: o turno que ia para o agente do corretor vai para o núcleo novo.
--    As condições são as do roteador do fluxo (não pausado, atende, aprovado) e sem mídia visual.
SELECT pg_temp.trocar('nai_abrir_turno(text,text,text,text,bigint[])'::regprocedure,
$de$  -- 223: a resposta dele à pergunta do perfil ("só serve com elevador?") vai para o perfil
$de$,
$para$  -- 269: O NÚCLEO NOVO (nay-core) ATENDE ESTE TURNO. Só o turno que ia para o agente
  -- do corretor (as mesmas condições do "Rotear pelo cabeçalho"), sem imagem nem
  -- documento, e que nai_core_atende() não segura aqui (visita, cadastro, teste).
  -- ok falso = o fluxo não manda nada; quem responde é o núcleo, lendo nai_core_turno.
  IF v_papel = 'corretor' AND NOT v_pausado
     AND (CASE WHEN lower(coalesce(nai_cfg('regra_publico', 'nao'), 'nao')) = 'sim' THEN v_porta.atende END) IS DISTINCT FROM false
     AND ((CASE WHEN lower(coalesce(nai_cfg('regra_publico', 'nao'), 'nao')) = 'sim' THEN v_porta.atende END) IS TRUE
          OR v_aprov IS TRUE)
     AND jsonb_array_length(nai_midias_do_turno(v_turno)) = 0
     AND nai_core_atende(v_contato, v_texto) THEN
    INSERT INTO nai_core_turno (turno_id) VALUES (v_turno) ON CONFLICT DO NOTHING;
    UPDATE nai_turno SET fechado_em = now() WHERE id = v_turno;
    RETURN jsonb_build_object('ok', false, 'motivo', 'core_atende', 'turno_id', v_turno,
                              'contato_id', v_contato, 'papel', v_papel);
  END IF;

  -- 223: a resposta dele à pergunta do perfil ("só serve com elevador?") vai para o perfil
$para$);

-- 4. o eco do que o núcleo novo envia NÃO é "o Tel escreveu pelo celular".
--    O id é gravado item a item; a comparação por texto e por foto cobre o eco que
--    chega antes de o id ser gravado.
SELECT pg_temp.trocar('nai_tel_assumiu(text,text,text)'::regprocedure,
$de$  -- 194 (30/09): o ECO DA FOTO. Sem texto e com foto nossa saindo para a
$de$,
$para$  -- 269: o ECO DO NÚCLEO NOVO (core_saida).
  IF NOT v_eco THEN
    v_eco := EXISTS (SELECT 1 FROM core_saida s
                      WHERE nullif(p_message_id, '') IS NOT NULL AND s.message_id = p_message_id)
          OR EXISTS (SELECT 1 FROM core_saida s
                      WHERE s.chave_destino = v_chave AND s.estado IN ('enviando', 'enviado')
                        AND s.criado_em > now() - interval '15 minutes'
                        AND (   (s.tipo = 'imagem' AND nullif(btrim(coalesce(p_texto, '')), '') IS NULL)
                             OR (s.tipo = 'texto' AND nullif(btrim(coalesce(p_texto, '')), '') IS NOT NULL
                                 AND btrim(s.texto) = btrim(p_texto))));
  END IF;

  -- 194 (30/09): o ECO DA FOTO. Sem texto e com foto nossa saindo para a
$para$);

-- 5. "o imóvel na frente" enxerga o que o núcleo novo mostrou: é com isso que o
--    pedido de visita (que fica aqui) sabe de qual imóvel o corretor fala.
SELECT pg_temp.trocar('nai_imoveis_na_frente(bigint)'::regprocedure,
$de$       AND e.enviado_em > now() - interval '2 hours' AND e.codigo ~ '^[0-9]{3,5}$'
  )$de$,
$para$       AND e.enviado_em > now() - interval '2 hours' AND e.codigo ~ '^[0-9]{3,5}$'
    UNION ALL   -- 269: card e resposta do núcleo novo
    SELECT s.criado_em, s.codigo
      FROM core_saida s, k
     WHERE s.chave_destino IN (SELECT c.chave FROM nai_contato c WHERE c.id = ANY (k.ids))
       AND s.codigo IS NOT NULL AND s.tipo <> 'imagem' AND s.papel_destino = 'turno'
       AND s.estado IN ('enviado', 'enviando', 'pendente') AND s.criado_em > now() - interval '2 hours'
    UNION ALL   -- 269: lista do núcleo novo ("Código: N")
    SELECT s.criado_em, m[1]::int
      FROM core_saida s, k, regexp_matches(s.texto, 'C[óo]digo:\s*(\d{3,5})', 'gi') m
     WHERE s.chave_destino IN (SELECT c.chave FROM nai_contato c WHERE c.id = ANY (k.ids))
       AND s.codigo IS NULL AND s.tipo = 'texto' AND s.papel_destino = 'turno'
       AND s.estado IN ('enviado', 'enviando', 'pendente') AND s.criado_em > now() - interval '2 hours'
  )$para$);

-- 6. a escalação do núcleo novo vira pausa AQUI: é este sistema que cala, que
--    vence o prazo (escalacao_expira_horas) e que ouve o DEVOLVER. O papel
--    nay_core não escreve em nai_contato; esta função escreve por ele, só isto.
CREATE OR REPLACE FUNCTION public.nai_core_escalou(p_chave text, p_motivo text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, pg_temp
AS $function$
DECLARE v_id bigint; n int;
BEGIN
  SELECT id INTO v_id FROM nai_contato WHERE chave = p_chave;
  IF v_id IS NULL THEN RETURN 0; END IF;
  UPDATE nai_contato
     SET humano_assumiu_em = now(),
         humano_motivo = 'duvida fora da base (nay-core): ' || left(coalesce(p_motivo, ''), 80)
   WHERE id = ANY (coalesce(nai_contato_irmaos(v_id), ARRAY[v_id]));
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$function$;
REVOKE ALL ON FUNCTION public.nai_core_escalou(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nai_core_escalou(text, text) TO nay_core;

COMMIT;
