-- Onde um telefone aparece no banco (só leitura). Troque os 8 dígitos finais em v_fim.
--   ./scripts/nay q "$(cat scripts/onde_esta_o_telefone.sql)"
DO $$
DECLARE r record; n bigint; v_fim text := '94481676';
BEGIN
  FOR r IN
    SELECT c.table_schema AS s, c.table_name AS t, c.column_name AS col
      FROM information_schema.columns c JOIN information_schema.tables b USING (table_schema, table_name)
     WHERE b.table_type = 'BASE TABLE' AND c.table_schema IN ('public', 'privado')
       AND c.data_type IN ('text', 'character varying')
       AND c.column_name ~* 'fone|phone|chave|numero|jid|whats|celular|contato|remetente|destino|chat'
  LOOP
    BEGIN
      EXECUTE format('SELECT count(*) FROM %I.%I WHERE right(regexp_replace(coalesce(%I, ''''), ''\D'', '''', ''g''), 8) = %L', r.s, r.t, r.col, v_fim) INTO n;
      IF n > 0 THEN RAISE NOTICE '%.% (%): % linhas', r.s, r.t, r.col, n; END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;
END $$;
