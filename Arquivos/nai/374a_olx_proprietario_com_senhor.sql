-- 374a: a Nay proprietários da OLX trata o dono por Sr./Sra. -- a parede "sem Sr. e Sra." é da Nay dos corretores
--
-- Na 374 a primeira mensagem pela Parceria saiu "Olá, Pedro! ... com você." no lugar de "Olá, Sr. Pedro! ... com o
-- Sr.": o gatilho nai_saida_validar tira o tratamento de TODA saída da caixa (Tel, 28/09: "retire o SR e SRA das
-- mensagens e só cita o nome do corretor"). Isso vale para corretor; o roteiro do Pedro para o dono da OLX pede o
-- tratamento. A exceção é só para o motivo 'olx_proprietario'.
BEGIN;
DO $$
DECLARE v text; a text := 'IF NEW.tipo = ''texto'' AND NEW.texto ~ ''\mSra?\M'' THEN';
BEGIN
  v := pg_get_functiondef('public.nai_saida_validar()'::regprocedure);
  IF position(a IN v) = 0 THEN RAISE EXCEPTION 'nai_saida_validar mudou: não achei a parede do Sr.'; END IF;
  v := replace(v, a, 'IF NEW.tipo = ''texto'' AND NEW.texto ~ ''\mSra?\M'' AND coalesce(NEW.motivo, '''') <> ''olx_proprietario'' THEN');
  EXECUTE v;
END $$;
COMMIT;
