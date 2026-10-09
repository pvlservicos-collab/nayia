-- 328 -- Renomear um condomínio leva junto os imóveis que estão ligados a ele só pelo NOME
--
-- Pedro, 09/10/2026: "vê se está tudo certo o cadastro de condomínios lá no site".
--
-- Achado: site_condominio_salvar (322) ao renomear só atualizava o imóvel ligado pelo id (condo_id). Hoje 3.765 imóveis
-- estão ligados ao condomínio só pelo nome (condo_id vazio, condominio_nome igual ao nome do cadastro). Renomear o
-- condomínio deixava esses imóveis com o nome velho -- e eles deixavam de aparecer no condomínio (as telas ligam pelo
-- id OU pelo nome).
--
-- Agora, ao renomear, o imóvel ligado só pelo nome VELHO passa a ficar ligado pelo id e mostra o nome novo.
-- Só o trecho do renomear muda; o resto da função fica como está no banco.
BEGIN;
SET LOCAL lock_timeout = '3s';

DO $mig$
DECLARE
  v_def   text := pg_get_functiondef('public.site_condominio_salvar(integer, jsonb)'::regprocedure);
  v_velho text := $v$      UPDATE imoveis SET condominio_nome = v_nome WHERE condo_id = c.id AND condominio_nome IS DISTINCT FROM v_nome;
      GET DIAGNOSTICS v_n = ROW_COUNT;$v$;
  v_novo  text := $n$      UPDATE imoveis SET condominio_nome = v_nome WHERE condo_id = c.id AND condominio_nome IS DISTINCT FROM v_nome;
      GET DIAGNOSTICS v_n = ROW_COUNT;
      -- 328: o imóvel ligado só pelo nome VELHO (sem condo_id) vai junto, e passa a ficar ligado pelo id
      UPDATE imoveis SET condo_id = c.id, condominio_nome = v_nome
       WHERE condo_id IS NULL AND lower(unaccent(btrim(condominio_nome))) = lower(unaccent(btrim(c.nome)));
      GET DIAGNOSTICS v_ligados = ROW_COUNT;
      v_n := v_n + v_ligados;$n$;
BEGIN
  IF (length(v_def) - length(replace(v_def, v_velho, ''))) / length(v_velho) <> 1 THEN
    RAISE EXCEPTION '328: o trecho de site_condominio_salvar mudou no banco; leia a função viva antes';
  END IF;
  IF position('328:' IN v_def) > 0 THEN RAISE EXCEPTION '328: já aplicada'; END IF;
  v_def := replace(v_def, v_velho, v_novo);
  -- a variável nova
  v_def := regexp_replace(v_def, '(\nDECLARE\n)', E'\\1  v_ligados int := 0;\n');
  EXECUTE v_def;
END
$mig$;

COMMIT;
