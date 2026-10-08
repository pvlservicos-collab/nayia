-- 318 (08/10/2026): IMÓVEL QUE JÁ ESTÁ NO NOSSO CADASTRO -> SÓ O VALOR DO ALUGUEL, E SEGUE.
-- Pedro, depois do teste dele com a Nay de captação: "a nay de captação tem que saber o
-- imóvel que está linkado ao cliente; tipo, no meu cadastro não tinha imóveis então ela
-- foi cadastrar um novo, mas quando for o do cliente e ele disser que tá disponível mas
-- ele já tiver imóvel, ela vai atualizar só o valor do aluguel e seguir".
--
-- ANTES: disponível + valor abria a FICHA do imóvel da campanha (164/165) e ela
-- perguntava o que faltava (cômodos, área, condomínio e IPTU, mobília, fotos) -- mesmo
-- para imóvel que já existe em `imoveis`: taxas e fotos eram perguntadas sempre.
--
-- AGORA: se o código do lead existe em `imoveis`, a ficha nasce PRONTA com o que ele
-- disse (o valor) e a ordem é seguir o roteiro: perguntar dos outros imóveis. A ficha
-- pronta aparece para a equipe aplicar, como antes. O que ele disser a mais sobre o
-- imóvel continua sendo anotado nela (o caminho "a ficha já está completa").
-- Lead sem imóvel no cadastro (o de teste do Pedro, código fictício) e imóvel NOVO
-- (o "outro imóvel" que ele cita) continuam com a ficha inteira.
--
-- Vale para as duas Nays de captação (a do n8n e a em Python): a regra mora no banco.
-- Patch na função viva, a troca conferida uma vez.
BEGIN;
SET LOCAL lock_timeout = '3s';
DO $do$
DECLARE
  v_def text := pg_get_functiondef('public.captacao_ficha(text,text,jsonb,boolean)'::regprocedure);
  VELHO CONSTANT text := $a$    INSERT INTO captacao_cadastro (lead_id, tipo, codigo)
    VALUES (l.id, v_tipo, CASE WHEN v_tipo = 'atualizar' AND l.codigo ~ '^\d+$' THEN l.codigo::int END)
    RETURNING * INTO c;$a$;
  NOVO CONSTANT text := $b$    -- 318: o imóvel dele JÁ ESTÁ no nosso cadastro -> só o valor do aluguel, sem as perguntas da ficha
    IF v_tipo = 'atualizar' AND l.codigo ~ '^\d+$' AND EXISTS (SELECT 1 FROM imoveis x WHERE x.codigo = l.codigo::int) THEN
      INSERT INTO captacao_cadastro (lead_id, tipo, codigo, estado, dados)
      VALUES (l.id, v_tipo, l.codigo::int, 'pronto', v_novos);
      RETURN 'o imovel dele ja esta no nosso cadastro'
          || CASE WHEN v_novos ? 'valor' THEN ', e o valor do aluguel ficou anotado' ELSE '' END
          || '. NAO pergunte mais nada sobre este imovel (quartos, area, condominio, IPTU, mobilia, fotos). '
          || 'siga o roteiro: se ainda nao perguntou, pergunte se ' || v_pron
          || ' tem algum outro imovel alem desse que queira vender ou alugar.';
    END IF;
    INSERT INTO captacao_cadastro (lead_id, tipo, codigo)
    VALUES (l.id, v_tipo, CASE WHEN v_tipo = 'atualizar' AND l.codigo ~ '^\d+$' THEN l.codigo::int END)
    RETURNING * INTO c;$b$;
BEGIN
  IF (length(v_def) - length(replace(v_def, VELHO, ''))) / length(VELHO) <> 1 THEN
    RAISE EXCEPTION '318: o trecho que abre a ficha não aparece exatamente uma vez em captacao_ficha';
  END IF;
  EXECUTE replace(v_def, VELHO, NOVO);
END
$do$;
COMMIT;
