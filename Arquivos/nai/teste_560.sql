-- teste da 560 (dentro do ensaio)
DO $t$
BEGIN
  ASSERT (SELECT bool_and(e_parceiro AND imovel_parceiro_antigo(codigo)) FROM imoveis WHERE codigo IN (5180, 1442)), 'os dois';
  ASSERT (SELECT NOT publicado_no_site FROM imoveis WHERE codigo = 5180), 'saiu do site como os antigos';
  -- o gatilho com o "indicado por" num imóvel que não é parceiro (e volta no ROLLBACK)
  UPDATE imoveis SET extras = extras || '{"indicado por":"Imob corretor parceiro"}'::jsonb
   WHERE codigo = (SELECT codigo FROM imoveis WHERE NOT e_parceiro AND NOT coalesce(administrado,false) AND status = 'Disponível' ORDER BY codigo LIMIT 1);
  ASSERT EXISTS (SELECT 1 FROM imoveis WHERE extras->>'indicado por' = 'Imob corretor parceiro' AND e_parceiro AND codigo NOT IN (5180)), 'o gatilho marca';
  RAISE NOTICE 'teste_560: ok';
END
$t$;
