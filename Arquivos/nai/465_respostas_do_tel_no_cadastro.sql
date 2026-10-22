-- 465: as respostas do Tel à Nay entram no cadastro, para ela não perguntar de novo (Pedro, 22/10/2026: "olha as respostas
-- do Tel de sempre, e já inclui lá no nosso sistema para ela não ficar perguntando de novo, revisa todas as respostas").
--
-- Revisadas as ~40 respostas diferentes das 5 fontes (imovel_conhecimento, nai_saber, pergunta_fila, pendencias, DEVOLVER).
-- A Nay nova não lê imovel_conhecimento nem nai_saber: o que é FATO do imóvel vai para o campo do cadastro que ela lê.
-- Ficaram de fora: o que já estava certo (andar do 5758, mobília do 9045, taxa do 9021, financiamento do 3495), o que não
-- é fato ("ela nunca responde", "descartar", negociação e prazo do dia), imóvel já alugado/removido (1327, 3495), e o que
-- não tem campo no cadastro (a localização do Conquista Tarumã, 5722: "entrando na Av. do Setur, no final").
--
--   5707  "Já foi alugada a casa" (19/10)                         status Disponível -> Alugado (o aviso de saída segue o de sempre)
--   5001  "o Acácias está de 175.000 agora, baixou o valor" (19/10) valor_venda 190.800 -> 175.000
--   2944  "Igual as fotos, todo mobiliado" (16/10)                características: Semi-Mobiliado -> Mobiliado
--   9027  "fica no último andar" (19/10)                          andar vazio -> Último
--   9021  "incluso na taxa é apenas o gás" (16/10)                condomínio (Estilo Golf): taxa_inclui + Gás
--   2539  "tem vaga coberta"; "porcelanato em toda a área útil" vagas_cobertas 1; característica + Piso porcelanato
-- O de antes fica em privado.respostas_do_tel_antes_465.

BEGIN;

CREATE TABLE IF NOT EXISTS privado.respostas_do_tel_antes_465 (
  codigo integer, campo text, antes text, depois text, resposta text, em timestamptz NOT NULL DEFAULT now());

INSERT INTO privado.respostas_do_tel_antes_465 (codigo, campo, antes, depois, resposta)
SELECT 5707, 'status', status, 'Alugado', 'Já foi alugada a casa (Tel, 19/10)' FROM imoveis WHERE codigo = 5707
UNION ALL SELECT 5001, 'valor_venda', valor_venda::text, '175000', 'Lily o Acacias está de 175.000 agora, baixou o valor (Tel, 19/10)' FROM imoveis WHERE codigo = 5001
UNION ALL SELECT 2944, 'caracteristicas', caracteristicas::text, 'Semi-Mobiliado -> Mobiliado', 'Igual as fotos todo mobiliado (Tel, 16/10)' FROM imoveis WHERE codigo = 2944
UNION ALL SELECT 9027, 'andar', andar, 'Último', 'fica no ultimo andar (Tel, 19/10)' FROM imoveis WHERE codigo = 9027
UNION ALL SELECT 9021, 'condominio_ficha.taxa_inclui', cf.taxa_inclui::text, '+ Gás', 'incluso na taxa é apenas o gás (Tel, 16/10)'
            FROM imoveis i JOIN condominio_ficha cf ON cf.condominio_id = i.condo_id WHERE i.codigo = 9021
UNION ALL SELECT 2539, 'vagas_cobertas/caracteristicas', coalesce(vagas_cobertas::text, '') || ' / ' || caracteristicas::text, '1 / + Piso porcelanato',
                 'tem vaga coberta; porcelanato em toda a area util (Tel, 20/08)' FROM imoveis WHERE codigo = 2539;

UPDATE imoveis SET status = 'Alugado' WHERE codigo = 5707 AND status = 'Disponível';
UPDATE imoveis SET valor_venda = 175000 WHERE codigo = 5001 AND valor_venda = 190800;
UPDATE imoveis SET caracteristicas = array_replace(caracteristicas, 'Semi-Mobiliado', 'Mobiliado') WHERE codigo = 2944;
UPDATE imoveis SET andar = 'Último' WHERE codigo = 9027 AND coalesce(btrim(andar), '') = '';
UPDATE condominio_ficha SET taxa_inclui = taxa_inclui || ARRAY['Gás']
 WHERE condominio_id = (SELECT condo_id FROM imoveis WHERE codigo = 9021) AND NOT 'Gás' = ANY (taxa_inclui);
UPDATE imoveis SET vagas_cobertas = 1,
       caracteristicas = CASE WHEN 'Piso porcelanato' = ANY (caracteristicas) THEN caracteristicas
                              ELSE caracteristicas || ARRAY['Piso porcelanato'] END
 WHERE codigo = 2539 AND vagas_cobertas IS NULL;

COMMIT;
