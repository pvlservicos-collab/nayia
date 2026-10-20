-- 436: O CONDOMÍNIO RECENTE TAMBÉM PELO ANO DO CADASTRO (Pedro, 20/10/2026: "sim, adiciona no filtro os outros segundo
-- a ordem de lançamento"). A planilha (433) marca 22 recentes; a ficha do condomínio tem o ano de lançamento ou de
-- construção. Agora é recente quem a planilha marca OU quem foi lançado nos últimos 5 anos (2021 para cá, em 2026).
-- O que a planilha marca fica (Bellagio e River Side são de 2016 na ficha e continuam recentes: ele pediu para somar).
--
--   condominio_proximo.recente_planilha   a marca dele, guardada (o `recente` passa a ser a conta)
--   condominio_proximo.ano                o ano da ficha (lançamento; senão o ano escrito na construção)
--   condominio_proximo.origem             'planilha' | 'cadastro': o lançado nos últimos 5 anos que não está na
--                                         planilha entra como linha nova (sem lista de próximos), para "condomínio
--                                         novo" e para a ordem
--   privado.condominio_proximo_anos()     a conta; roda aqui e a cada ficha de condomínio gravada (gatilho)
-- A ORDEM DE LANÇAMENTO: entre os recentes, o mais novo primeiro (nay-core proximos.py, olx_cliente_buscar).
BEGIN;
SET LOCAL lock_timeout = '3s';

ALTER TABLE public.condominio_proximo ADD COLUMN IF NOT EXISTS recente_planilha boolean NOT NULL DEFAULT false;
ALTER TABLE public.condominio_proximo ADD COLUMN IF NOT EXISTS ano integer;
ALTER TABLE public.condominio_proximo ADD COLUMN IF NOT EXISTS origem text NOT NULL DEFAULT 'planilha';
UPDATE public.condominio_proximo SET recente_planilha = recente WHERE origem = 'planilha';
-- dois ligados por semelhança que são outro condomínio (o bairro do cadastro fica longe do da planilha)
UPDATE public.condominio_proximo SET condo_id = NULL, ligado_como = NULL
 WHERE nome IN ('Vila das Flores', 'Amazon Boulevard Life e Garden') AND ligado_como LIKE 'parecido%';

CREATE OR REPLACE FUNCTION privado.condominio_ano(p_lancamento integer, p_construcao text) RETURNS integer
LANGUAGE sql IMMUTABLE AS $f$
  SELECT coalesce(p_lancamento, (substring(coalesce(p_construcao, '') from '(19[5-9][0-9]|20[0-4][0-9])'))::int)
$f$;

CREATE OR REPLACE FUNCTION privado.condominio_proximo_anos() RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path TO 'public', 'privado' AS $f$
  -- o ano de cada um, pela ficha do condomínio ligado (o que não está ligado não tem ano)
  UPDATE condominio_proximo SET ano = NULL WHERE condo_id IS NULL AND ano IS NOT NULL;
  UPDATE condominio_proximo p SET ano = privado.condominio_ano(f.ano_lancamento, f.ano_construcao)
    FROM condominio_ficha f WHERE f.condominio_id = p.condo_id
     AND p.ano IS DISTINCT FROM privado.condominio_ano(f.ano_lancamento, f.ano_construcao);
  -- o lançado nos últimos 5 anos que a planilha não tem: linha nova, ligada ao cadastro
  INSERT INTO condominio_proximo (nome, bairro, recente, recente_planilha, proximos, condo_id, ligado_como, origem, ano)
  SELECT c.nome, c.bairro, true, false, '{}', c.id, 'cadastro', 'cadastro',
         privado.condominio_ano(f.ano_lancamento, f.ano_construcao)
    FROM condominio_ficha f JOIN condominios c ON c.id = f.condominio_id
   WHERE privado.condominio_ano(f.ano_lancamento, f.ano_construcao) >= extract(year FROM now())::int - 5
     AND NOT EXISTS (SELECT 1 FROM condominio_proximo p WHERE p.condo_id = c.id)
  ON CONFLICT (nome) DO NOTHING;
  -- recente = a marca da planilha OU lançado nos últimos 5 anos
  UPDATE condominio_proximo SET recente = recente_planilha OR coalesce(ano >= extract(year FROM now())::int - 5, false)
   WHERE recente IS DISTINCT FROM (recente_planilha OR coalesce(ano >= extract(year FROM now())::int - 5, false));
$f$;

CREATE OR REPLACE FUNCTION privado.condominio_proximo_anos_tg() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'privado' AS $f$
BEGIN
  PERFORM privado.condominio_proximo_anos();
  RETURN NULL;
END
$f$;
DROP TRIGGER IF EXISTS condominio_proximo_anos_tg ON public.condominio_ficha;
CREATE TRIGGER condominio_proximo_anos_tg AFTER INSERT OR UPDATE OF ano_lancamento, ano_construcao, condominio_id
  ON public.condominio_ficha FOR EACH STATEMENT EXECUTE FUNCTION privado.condominio_proximo_anos_tg();

SELECT privado.condominio_proximo_anos();
COMMIT;
