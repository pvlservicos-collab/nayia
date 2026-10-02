SELECT COALESCE(
  (SELECT CASE WHEN COALESCE(c.creci,'') <> ''
               THEN 'o creci deste corretor ja esta guardado, nao peca de novo.'
               ELSE 'este corretor ainda nao tem creci guardado. se for confirmar visita, peca uma vez.' END
       || CASE WHEN COALESCE(c.nome,'') <> ''
               THEN ' o nome dele e ' || c.nome || '.'
               ELSE ' voce tambem nao sabe o nome dele.' END
   FROM corretores c WHERE c.telefone = $1),
  'este contato nao esta na sua lista de corretores. nao tem creci nem nome guardado.'
) AS instrucao_para_voce
