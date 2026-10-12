-- Em que tabelas do banco aparecem os telefones dos leads que a 353 pôs no disparo (só leitura).
--   ./scripts/nay q "$(cat scripts/fila_do_disparo_onde_aparece.sql)"
DO $$
DECLARE r record; n bigint;
BEGIN
  FOR r IN
    SELECT c.table_schema AS s, c.table_name AS t, c.column_name AS col
      FROM information_schema.columns c JOIN information_schema.tables b USING (table_schema, table_name)
     WHERE b.table_type = 'BASE TABLE' AND c.table_schema IN ('public', 'privado')
       AND c.data_type IN ('text', 'character varying')
       AND c.column_name ~* 'fone|phone|chave|numero|jid|whats|celular|remetente|destino|chat'
       AND c.table_name !~ '^(captacao_leads|proprietarios|proprietarios_export|proprietarios_admin|imoveis_admin)'
  LOOP
    BEGIN
      EXECUTE format($q$SELECT count(DISTINCT right(regexp_replace(coalesce(%3$I, ''), '\D', '', 'g'), 8)) FROM %1$I.%2$I
                         WHERE length(regexp_replace(coalesce(%3$I, ''), '\D', '', 'g')) >= 10
                           AND right(regexp_replace(coalesce(%3$I, ''), '\D', '', 'g'), 8) IN
                               (SELECT right(l.telefone, 8) FROM captacao_leads l WHERE l.quem_importou LIKE 'Pedro (lista _: %%12/10)')$q$,
                     r.s, r.t, r.col) INTO n;
      IF n > 0 THEN RAISE NOTICE '%.% (%): % telefones da fila', r.s, r.t, r.col, n; END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;
END $$;
