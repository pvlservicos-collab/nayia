CREATE OR REPLACE FUNCTION public.nai_core_visita_confirmada(p_chave text, p_codigo integer, p_quando timestamp with time zone, p_turno bigint DEFAULT NULL::bigint)
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
