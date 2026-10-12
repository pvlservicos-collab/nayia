# nayia: a verdade está em `producao/`

Este repositório é o arquivo do sistema velho da Nay (n8n + funções `nai_*`/`nay_*`
no `naydb`). O que roda de verdade é o que está no servidor, e a foto disso é
`producao/`, regerada por um comando.

## Onde está a verdade
- `producao/funcoes/<nome>(<tipos>).sql`: cada função viva do schema public, como está no banco.
- `producao/tabelas/<tabela>.md`: colunas, índices, restrições, gatilhos, **permissões por papel**
  e as funções que escrevem nela e que a citam (public e privado).
- `producao/quem_chama.tsv`: para cada função, quem a chama.
- `producao/n8n/`: os fluxos ativos do n8n (segredos redigidos), em JSON e **abertos em pasta**:
  `producao/n8n/<fluxo>/<nó>.js|.sql|.prompt.txt` e `_mapa.md` (tipo, modelo, ligações).
- `producao/cron/`: o crontab do root e o /etc/cron.d do srv1894338.
- `producao/nai_config.tsv`, `producao/prompts/` (nai_prompt com versão) e
  `producao/n8n_variaveis_de_ambiente.txt` (só os nomes).
- Regerar: `./scripts/foto_producao.sh` (só leitura; uns 10 s).

## Achar antes de perguntar ao servidor
Medido em 01/10: num pedido da Nay, de cada 10 comandos, 5 a 7 eram para DESCOBRIR
(que coluna existe, quem chama a função, o que tem no nó do n8n) indo ao servidor — e
vários voltavam com "column does not exist". Tudo isso está na foto. A ordem é:
1. `./scripts/nay onde "<frase ou nome>"`: acha em banco, nós do n8n, CRM e site (0,3 s).
2. `./scripts/nay fn <função>`: o arquivo vivo, quem a chama, as migrações que a citam.
3. `./scripts/nay tabela <tabela>`: colunas e permissões. **Antes de escrever SQL**, e antes de
   usar uma tabela numa rota do site ou do CRM (o papel pode não ter acesso).
4. Só então `./scripts/nay q` (naydb) ou `./scripts/nay crmq` (crmdb), para DADO, não para estrutura.
5. `./scripts/nay ensaio migracao.sql testes.sql` ensaia a própria migração (o COMMIT vira
   ROLLBACK): não se monta mais cópia "_ensaio" à mão.

## `Arquivos/nai` é histórico
Os `.sql` numerados contam como se chegou aqui, mas o banco está à frente deles:
há correções feitas direto em produção que nunca voltaram para o arquivo
(entrevista de 29/09, pergunta 45). **Nunca reaplique um `.sql` antigo**: ele desfaz
o que foi corrigido no banco.

## Antes de mexer em uma função
1. Leia `producao/funcoes/<nome>(...).sql`: é o que roda hoje.
2. Guarde o `pg_get_functiondef` em `/root/backups-funcoes/<nome>-<data>.sql`, ensaie
   em transação que termina em ROLLBACK e aplique só com a aprovação do Tel.
3. Depois de aplicar, rode `./scripts/foto_producao.sh` e commite a foto junto.

## Antes de gravar por cima de qualquer coisa: AVISO E PERGUNTA
Ordem do Pedro (12/10/2026), depois que uma publicação desta pasta desligou o popup "Ver imóvel", feito por outra
sessão direto no servidor: **"coloque uma regra de aviso e pergunta"**.
- Há outras sessões mexendo no servidor. Esta pasta NÃO é a única fonte. O que está lá e não está aqui é trabalho de alguém.
- Publicar página, script ou estilo do site: só por `./scripts/nay estatico <arquivos>` (ou `nay site`, que também
  reconstrói a API); CRM por `./scripts/nay crm`. **Nunca** por `cat >`, `scp` ou edição direta no servidor.
- O comando compara o arquivo do servidor com o último commit daqui. Se for diferente, ele PARA, mostra o que só existe
  no servidor e não sobe nada. Aí: **avise o Pedro, diga o que seria apagado e PERGUNTE**. Enquanto ele não responder,
  não publique aquele arquivo. O caminho certo é baixar a versão do servidor, juntar com a daqui e subir a soma.
- `NAY_SOBRESCREVER=sim` só depois do "pode" dele, para aquele arquivo.
- Vale igual para apagar, mover ou trocar arquivo, tabela, chave, cron ou configuração que você não criou nesta
  sessão: aviso com o que vai sumir, pergunta, e espera.

## O que mora onde
- O núcleo novo da Nay: repositório próprio `pvlservicos-collab/nay-core`
  (`C:\Users\pedro\nay-core`), com a entrevista de produção em `docs/ENTREVISTA-2026-09-29.md`.
- `crm/`, `nay-publicador/`: cada um com o seu CLAUDE.md.
- O CLAUDE.md antigo (varredura do catálogo, 687 linhas): `Arquivos/CLAUDE-antigo.md`.
  Regras e bugs da Nay: `Arquivos/REGRAS-E-BUGS.md`.

## O que não muda
- Nunca apagar linha de `imoveis`.
- Nada de segredo no git: token, senha, chave, URL da Z-API com instância.
- Import de fluxo no n8n só de madrugada, pelo procedimento do espelho-madrugada.
- Atalhos: `./scripts/nay` (onde, fn, tabela, q, crmq, ensaio, backup, aplicar, bateria, conversa, estatico, site, crm)
  e o mapa pedido → função em `MAPA.md`. Mudou algo que o mapa não cobre? Acrescente a linha no mesmo commit.
- Script com aspas ou barras invertidas vai em ARQUIVO (Write) e depois roda; em heredoc do Git Bash
  as aspas quebram e `\\` vira `\`.
