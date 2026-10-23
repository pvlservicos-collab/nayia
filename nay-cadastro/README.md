# nay-cadastro: o cadastro de imóvel pelo WhatsApp

Pedro, 20/10/2026: "criei esse grupo [CADASTRO DE IMÓVEL IMOBEASY] e deixei a nay parceria cuidando dele. Nesse grupo o
tel vai encaminhar os imóveis e a nay vai montar um checklist de cadastro ... as fotos que o tel mandar ela vai
cadastrar no nosso servidor, e as informações que faltar ela vai listar no grupo e perguntar ela mesma pelo número da
parceria ... qualquer erro ela vai avisar no grupo, se o corretor não respondeu uma pergunta ou se o cadastro foi
concluído."

## Como anda

1. **Grupo** (`no_grupo.py`). Cada rajada de mensagens encaminhadas é UM imóvel (a leva fecha com 90 s de silêncio).
   O modelo lê o texto (`modelo.ler_leva`), o telefone vem do cartão de contato ("👤 Contato: NOME — FONE", migração
   428) ou do texto. O imóvel nasce no site como **Rascunho** pela mesma API da aba Editar imóvel, com o contato como
   proprietário (corretor = imóvel parceiro; dono = imóvel próprio) e as fotos baixadas da Z-API e subidas para o nosso
   servidor. Ela posta no grupo o checklist: o que já tem e as **dúvidas**. Sem telefone, pede o contato no grupo.
1b. **Autorização no grupo** (`autorizacao.py`, Pedro 23/10). Numa mensagem separada: "🙋 @quem mandou, posso falar com FULANO
   (corretor/proprietário, fone) pelo número de leads sobre o imóvel X? Vou perguntar: ...". Nada sai no privado antes do
   "pode". Ela escuta quem mandou o imóvel (e o Tel) no grupo, marcando a mensagem dela ou sobre a ficha que espera:
   pode / não (ele mesmo vê: a ficha fecha sem falar com ninguém) / espera / para / "não pergunta X" / "pergunta só Y"
   (`modelo.ler_decisao`); o dado do imóvel que ele disser entra no cadastro (complemento).
2. **Privado** (`no_privado.py`). "Só para concluir o cadastro do imóvel, pode me confirmar umas informações por
   favor?" e uma pergunta por vez. A resposta chega pela porta da Nay (`nai_abrir_turno`, bloco 428): enquanto a ficha
   está aberta, a NAI e a Nay nova não respondem essa pessoa. A pergunta que já saiu não volta (regra do Tel de 20/10).
3. **Fim** (`fluxo.concluir`). Condomínio novo vira cadastro de condomínio; com tipo, bairro e valor o imóvel fica
   **Disponível** (parceiro fica fora do site, como sempre); o grupo recebe o resumo e o link do editor. Sem resposta:
   aviso no grupo em 3 h, a ficha fecha em 24 h com o que tem.

## O modelo de cadastro (`campos.py`)

As famílias e campos do `imovel-editar.js` (`POR_TIPO`): vertical, sala, casa, terreno, outro. O condomínio vem antes:
se já está cadastrado (busca flexível `cadastro_whats_condominio`: sem acento, sem "residencial/condomínio", tolera
erro de digitação), nada do condomínio é perguntado; parecido demais para afirmar, ela confirma ("É o condomínio X?");
condomínio novo, ela pergunta endereço, elevador, lazer e segurança.

## Operação

- Liga/desliga: `nai_config.cadastro_whats` (`nao` para tudo na hora).
- Ver: `journalctl -u nay-cadastro -f`; fichas em `privado.cadastro_whats` (estado, pergunta, ficha, erro).
- Ensaiar sem gravar nem enviar: `.venv/bin/python -m cadastro.ensaio "texto do anúncio" "resposta 1" ...`
- Testes: `python -m pytest tests` (sem banco nem rede).
- `.env` (fora do git): `DATABASE_URL`, `OPENAI_API_KEY`, `CRM_PAINEL_SEGREDO` (o mesmo do nay-site-api), e as
  credenciais da Z-API da Parceria são lidas de `/root/nay-publicador/.env` (`CADASTRO_ZAPI_ENV`).
- Instalar: `python3 -m venv .venv && .venv/bin/pip install -r requirements.txt`, `cp nay-cadastro.service
  /etc/systemd/system/ && systemctl daemon-reload && systemctl enable --now nay-cadastro`.
