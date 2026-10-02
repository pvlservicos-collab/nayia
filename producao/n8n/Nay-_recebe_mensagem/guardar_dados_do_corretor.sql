WITH entrada AS (
  SELECT $1::text AS telefone,
         NULLIF(NULLIF(NULLIF(btrim($2::text),''),'null'),'undefined') AS creci,
         NULLIF(NULLIF(NULLIF(btrim($3::text),''),'null'),'undefined') AS nome
), valida AS (
  SELECT telefone,
         CASE WHEN length(creci) BETWEEN 3 AND 30 THEN creci END AS creci,
         CASE WHEN length(nome)  BETWEEN 2 AND 80 THEN nome  END AS nome
  FROM entrada
), gravado AS (
  -- `nome_origem` marcado como manual: sem isso o `nay_sincronizar_nome`
  -- do `Gravar na fila` sobrescreve na mensagem seguinte, e ela pergunta
  -- o nome de novo para sempre.
  INSERT INTO corretores (telefone, creci, nome, nome_origem, ultima_interacao)
  SELECT telefone, creci, nome, CASE WHEN nome IS NOT NULL THEN 'manual' END, now() FROM valida
  WHERE creci IS NOT NULL OR nome IS NOT NULL
  ON CONFLICT (telefone) DO UPDATE
     SET creci = COALESCE(EXCLUDED.creci, corretores.creci),
         nome  = COALESCE(EXCLUDED.nome,  corretores.nome),
         nome_origem = COALESCE(EXCLUDED.nome_origem, corretores.nome_origem),
         ultima_interacao = now()
  RETURNING creci, nome
)
SELECT COALESCE(
  (SELECT 'guardei. creci ' || COALESCE(creci,'(nao informado)') || ', nome ' || COALESCE(nome,'(nao informado)')
          || '. nao peca esses dados de novo a este corretor.' FROM gravado),
  'nao guardei nada: o valor recebido nao serve como creci nem como nome. peca de novo ao corretor.'
) AS instrucao_para_voce
