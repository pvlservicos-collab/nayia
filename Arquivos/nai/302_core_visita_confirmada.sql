-- 302 (07/10/2026): a visita que o corretor confirma com a NAY NOVA segue o MESMO caminho da velha.
--
-- O QUE ACONTECIA. Desde 06/10 (treino, rodadas 1 e 3) o nay-core conduz a conversa da visita: pergunta o dia e a
-- hora, manda a mensagem padrão ("Só para confirmar a solicitação de visita...") e, no "sim" do corretor, responde
-- "Certo! Anotei a sua visita". Mas parava aí: não criava a visita, não falava com o proprietário, não passava para a
-- Rayssa, o corretor não ia para a etapa Visitas do CRM e a Nay continuava respondendo. Só o Tel recebia um aviso.
-- O sistema velho faz tudo isso em `nai_visita_corretor_confirmou` (179, 197), mas só quando a conversa da visita foi
-- com ele: a porta (`nai_core_atende`, 269) segura no velho a mensagem que fala "visita", "agendar"...; a que não usa
-- essas palavras ("ele quer ver amanhã às 10", "às 19:00 pode?") chega ao núcleo. Em 5 dias, 11 turnos assim.
--
-- O QUE MUDA. Uma ponte, chamada pelo worker do nay-core no "sim" do corretor: ela cria a visita (ou pega a que já
-- está esperando a confirmação dele) e chama `nai_visita_corretor_confirmou`, a MESMA função de produção. Daí em
-- diante é tudo o que já existe e já foi medido: a 1ª solicitação ao proprietário, a confirmação completa à Rayssa,
-- o aviso ao Tel, a visita em 'com_rayssa' -> o corretor aparece na etapa Visitas do CRM
-- (`crm_parceria_com_a_rayssa`) e a porta cala a Nay, a velha e a nova (`nai_com_a_rayssa`), até o horário da visita
-- + visita_rayssa_ate_min (120) ou até ela ser encerrada.
--
-- Não muda nenhuma função que existe. Desfazer: DROP FUNCTION nai_core_visita_confirmada(text, integer, timestamptz, bigint).
BEGIN;

CREATE OR REPLACE FUNCTION public.nai_core_visita_confirmada(p_chave text, p_codigo integer, p_quando timestamptz,
                                                             p_turno bigint DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  k       nai_contato;
  v_ids   bigint[];
  v_ja    nai_visita;
  v_id    bigint;
  v_dono  record;
  v_moto  record;
  v_turno bigint;
BEGIN
  SELECT * INTO k FROM nai_contato WHERE chave = p_chave;
  IF k.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'sem_contato');
  END IF;
  IF p_codigo IS NULL OR p_quando IS NULL OR NOT EXISTS (SELECT 1 FROM imoveis WHERE codigo = p_codigo) THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'falta_o_imovel_ou_o_horario');
  END IF;
  -- as mensagens saem ligadas ao turno do sistema velho, quando ele existe (o nay-core manda o id que a porta entregou)
  SELECT id INTO v_turno FROM nai_turno WHERE id = p_turno;

  -- já existe visita aberta deste imóvel com ele (pelo telefone ou pelo @lid)?
  v_ids := coalesce(nai_contato_irmaos(k.id), ARRAY[k.id]);
  SELECT * INTO v_ja FROM nai_visita x
   WHERE x.corretor_id = ANY (v_ids) AND x.codigo = p_codigo AND nai_visita_aberta(x.estado) AND x.excluida_em IS NULL
   ORDER BY x.id DESC LIMIT 1;
  IF v_ja.id IS NOT NULL AND v_ja.estado <> 'confirmando' THEN
    -- já passou da confirmação (está com a Rayssa, com o proprietário...): não cria outra nem avisa de novo
    RETURN jsonb_build_object('ok', true, 'visita_id', v_ja.id, 'estado', v_ja.estado, 'ja_existia', true);
  END IF;

  IF v_ja.id IS NULL THEN
    -- a mesma linha que nai_pedir_visita cria, já no ponto de esperar o "sim" dele
    SELECT * INTO v_dono FROM nai_proprietario_do_imovel(p_codigo);
    SELECT * INTO v_moto FROM nai_motoboy();
    INSERT INTO nai_visita (codigo, corretor_id, quando, estado, aguardando, urgente, qualificado,
                            proprietario_cadastro, proprietario_nome, motoboy_id)
         VALUES (p_codigo, k.id, p_quando, 'confirmando', 'corretor', false, NULL,
                 v_dono.cadastro_id, v_dono.nome, v_moto.contato_id)
      RETURNING id INTO v_id;
    PERFORM nai_evento(v_id, 'pedida', 'pelo nay-core, horario ' || nai_hora_exata(p_quando));
  ELSE
    v_id := v_ja.id;
    UPDATE nai_visita SET quando = p_quando, atualizado_em = now() WHERE id = v_id;
  END IF;

  -- o "sim" do corretor: o caminho de produção (proprietário, Rayssa, Tel, 'com_rayssa')
  PERFORM nai_visita_corretor_confirmou(v_id, v_turno);
  RETURN jsonb_build_object('ok', true, 'visita_id', v_id, 'ja_existia', false,
                            'estado', (SELECT estado FROM nai_visita WHERE id = v_id));
END $function$;

COMMENT ON FUNCTION public.nai_core_visita_confirmada(text, integer, timestamptz, bigint) IS
  '302: o corretor confirmou a visita com o nay-core. Cria a visita e segue por nai_visita_corretor_confirmou (proprietário, Rayssa, Tel, etapa Visitas, Nay calada).';

REVOKE ALL ON FUNCTION public.nai_core_visita_confirmada(text, integer, timestamptz, bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nai_core_visita_confirmada(text, integer, timestamptz, bigint) TO nay_core;

COMMIT;
