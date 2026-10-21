-- teste da 452: a função responde para os corretores que falaram com o núcleo nas últimas 24 h, sem erro
SELECT coalesce(public.nai_core_pode_seguir(c.chave), 'PODE') AS resposta, count(*) AS corretores
  FROM (SELECT DISTINCT chave FROM core_turno WHERE criado_em > now() - interval '24 hours' AND papel = 'corretor') c
 GROUP BY 1 ORDER BY 2 DESC;
SELECT public.nai_core_pode_seguir('nao-existe') AS chave_que_nao_existe;
