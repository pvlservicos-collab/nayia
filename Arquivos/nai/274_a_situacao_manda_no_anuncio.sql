-- 274 (02/10/2026): A SITUAÇÃO MANDA. RASCUNHO NUNCA PARECE APROVADO.
--
-- Pedro, 02/10: "não tá claro para mim se todos os imóveis disponíveis estão disponíveis para a
-- Nay atender; se tá disponível para mim é para estar para a Nay; se tiver algum imóvel em
-- rascunho que apareça lá rascunho na categoria certa e não como falso aprovado."
--
-- Medido antes de mexer:
--   * 263 imóveis nossos em "Disponível"; 261 chegam na Nay. Os 2 que não: 3050 (a varredura do
--     site antigo tirou do site) e 5747 (bloqueado em 23/09). Estes NÃO mudam aqui: a lista do
--     admin passa a dizer "a Nay NÃO oferece" e o porquê, para alguém decidir.
--   * 24 imóveis sem situação gravada (novos, vindos do site antigo): a lista mostrava
--     "Disponível" por dedução. Agora fica gravado.
--   * 16 imóveis que NÃO estão disponíveis (Rascunho, Alugado, Vendido, Removido, Arquivado) mas
--     seguiam marcados "no site" -- entre eles o rascunho 9001 da OLX. A Nay não oferecia nenhum
--     (ela exige `disponivel`), mas na lista pareciam publicados. Saem do site.
--
-- A regra do Tel de 27/09 ("nosso e Disponível fica no site e na Nay; o resto sai") só era
-- aplicada pela tela de edição. A varredura diária do site antigo e o botão "No site" passavam
-- por fora. Agora a regra é uma parede na tabela:
--   - situação diferente de Disponível -> fora do site e indisponível, sempre;
--   - sem situação, disponível e no site -> a situação vira "Disponível" (fica escrito).
-- O caminho contrário (Disponível que alguém tirou do site) continua permitido: é o que tira do
-- ar um imóvel que saiu do site antigo. Ele aparece marcado na lista.
BEGIN;
SET LOCAL lock_timeout = '3s';

-- a cópia de antes, para desfazer se precisar
CREATE TABLE IF NOT EXISTS privado.imoveis_antes_274 AS
  SELECT codigo, status, disponivel, publicado_no_site, now() AS guardado_em
    FROM imoveis
   WHERE (coalesce(btrim(status), '') = '' AND disponivel AND publicado_no_site)
      OR (coalesce(btrim(status), '') NOT IN ('', 'Disponível') AND (publicado_no_site OR disponivel));

CREATE OR REPLACE FUNCTION public.imoveis_a_situacao_manda()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF coalesce(btrim(NEW.status), '') = '' THEN
    IF coalesce(NEW.disponivel, false) AND coalesce(NEW.publicado_no_site, false) THEN
      NEW.status := 'Disponível';
    END IF;
  ELSIF NEW.status <> 'Disponível' THEN
    NEW.disponivel := false;
    NEW.publicado_no_site := false;
  END IF;
  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.imoveis_a_situacao_manda() IS
  '274: imóvel que não está Disponível nunca fica no site nem disponível (rascunho não parece aprovado); sem situação e no ar vira Disponível.';

-- os dados de hoje (sem tocar em `disponivel`: nenhum dos 16 estava disponível, e mexer nele
-- dispararia o aviso de saída nos grupos)
UPDATE imoveis SET status = 'Disponível'
 WHERE coalesce(btrim(status), '') = '' AND disponivel AND publicado_no_site;
UPDATE imoveis SET publicado_no_site = false
 WHERE coalesce(btrim(status), '') NOT IN ('', 'Disponível') AND publicado_no_site AND NOT coalesce(disponivel, false);

DROP TRIGGER IF EXISTS imoveis_a_situacao_manda ON public.imoveis;
CREATE TRIGGER imoveis_a_situacao_manda
  BEFORE INSERT OR UPDATE ON public.imoveis
  FOR EACH ROW EXECUTE FUNCTION public.imoveis_a_situacao_manda();

COMMIT;
