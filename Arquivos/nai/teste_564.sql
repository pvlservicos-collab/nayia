-- 564: 'lucas' é aceito e cala a Nay com a marca "Lucas: ..."
DO $$
DECLARE r record; v_chave text; v_motivo text;
BEGIN
  SELECT chave INTO v_chave FROM nai_contato WHERE chave ~ '^55\d{10,11}$' ORDER BY id DESC LIMIT 1;
  SELECT * INTO r FROM crm_etapa_manual(v_chave, 'lucas', 'ensaio 564');
  IF NOT r.ok THEN RAISE EXCEPTION 'lucas recusado: %', r.mensagem; END IF;
  SELECT humano_motivo INTO v_motivo FROM nai_contato WHERE chave = v_chave;
  IF v_motivo NOT LIKE 'Lucas: %' THEN RAISE EXCEPTION 'marca errada: %', v_motivo; END IF;
  SELECT * INTO r FROM crm_etapa_manual(v_chave, 'xyz', 'ensaio 564');
  IF r.ok THEN RAISE EXCEPTION 'etapa desconhecida passou'; END IF;
  RAISE NOTICE '564 ok: %', v_motivo;
END $$;
