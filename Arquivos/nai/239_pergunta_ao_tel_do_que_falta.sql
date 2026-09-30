-- 239 (30/09/2026): a pergunta ao Tel do que falta no cadastro dos imóveis de locação (pedido do Pedro:
-- "se não achar no banco pergunta para o Tel no pv dele"). Uma mensagem só, pela caixa da Nay. A resposta dele
-- NÃO entra sozinha no cadastro: quem aplica é o Pedro/Claude.
BEGIN;
SET LOCAL lock_timeout = '3s';
WITH a AS (
  SELECT i.codigo, coalesce(nullif(nai_condominio_ok(i.condominio_nome), ''), i.tipo) AS nome,
         array_remove(ARRAY[
           CASE WHEN coalesce(btrim(i.mobilia),'')='' AND i.tipo ~* '^(apartamento|casa|flat|cobertura)' THEN 'mobília' END,
           CASE WHEN coalesce(btrim(i.andar),'')='' AND i.tipo ILIKE 'Apartamento%' THEN 'andar' END,
           CASE WHEN i.taxa_condominio IS NULL AND i.condo_id IS NOT NULL AND lower(unaccent(coalesce(i.extras->>'incluso no aluguel',''))) !~ 'condom' THEN 'condomínio' END,
           CASE WHEN i.iptu IS NULL AND lower(unaccent(coalesce(i.extras->>'incluso no aluguel',''))) !~ 'iptu' THEN 'IPTU' END,
           CASE WHEN i.vagas IS NULL THEN 'vagas' END,
           CASE WHEN NOT EXISTS (SELECT 1 FROM imovel_fotos f WHERE f.codigo=i.codigo) THEN 'fotos' END], NULL) AS falta
    FROM imoveis i
   WHERE NOT coalesce(e_parceiro,false) AND coalesce(valor_aluguel,0) > 0 AND nay_esta_no_mercado(disponivel, bloqueado, publicado_no_site)
)
SELECT nai_avisar_tel(NULL, NULL,
  'Tel, revisei hoje o cadastro dos imóveis de locação que eu ofereço aos corretores. Faltam estes dados, que não estão no site novo nem no antigo. Quando puder, me responde aqui, um imóvel por linha, do jeito que for mais fácil (ex.: "5718 andar 3, IPTU incluso"). Condomínio e IPTU: o valor, ou se já está incluso no aluguel.'
  || E'\n\n' || string_agg(codigo || ' ' || nome || ': ' || array_to_string(falta, ', '), E'\n' ORDER BY codigo)
  || E'\n\n' || 'E um aviso: 17 imóveis que estavam como Disponível no cadastro mas escondidos de mim voltaram a ser oferecidos hoje. Quatro deles estão sem foto: 2465 Claudio Santoro, 5036 Itapuranga III, 5326 Conquista Tarumã (R$ 1.100) e 5512 Reserva do Parque. Se algum não estiver mais disponível, me avisa.'
  || E'\n\n' || 'O que você responder o Pedro aplica no cadastro.',
  'cadastro_faltando') AS saida_id
  FROM a WHERE cardinality(falta) > 0;
SELECT id, papel_destino, estado, coalesce(bloqueio,'') bloqueio, length(texto) tamanho FROM nai_saida WHERE motivo = 'cadastro_faltando' ORDER BY id DESC LIMIT 1;
COMMIT;
