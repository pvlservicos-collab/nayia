"""O que o serviço lê do ambiente (arquivo .env do servidor, fora do git).

O que LIGA e DESLIGA não mora aqui: mora no banco, em `privado.olx_config` (publicar, conta_que_publica, teto,
nay_responde...), e a tela Chat OLX › Anúncios do CRM muda. O serviço relê a cada volta, sem reiniciar.
"""
import os

DATABASE_URL = os.environ.get("DATABASE_URL", "")
# 21/10: o crmdb mora no mesmo Postgres; a Nay lê de lá o que a equipe mandou pelo CRM (WhatsApp Leads). Sem a variável,
# o mesmo endereço com o banco trocado
CRM_DATABASE_URL = os.environ.get("CRM_DATABASE_URL", "") or (DATABASE_URL.rsplit("/", 1)[0] + "/crmdb" if DATABASE_URL else "")
# a API da OLX (developers.olx.com.br)
OLX_APPS = os.environ.get("OLX_APPS", "https://apps.olx.com.br").rstrip("/")
ESPERA_S = int(os.environ.get("OLX_ESPERA_S", "40"))
# de quanto em quanto tempo: a rodada dos anúncios, a situação de cada um na OLX e a olhada no chat
ANUNCIOS_A_CADA_S = int(os.environ.get("OLX_ANUNCIOS_A_CADA_S", "300"))
SITUACAO_A_CADA_S = int(os.environ.get("OLX_SITUACAO_A_CADA_S", "3600"))
# 24/10: o anúncio do imóvel vendido ou alugado sai da OLX em até este tempo
RETIRADA_A_CADA_S = int(os.environ.get("OLX_RETIRADA_A_CADA_S", "60"))
CHAT_A_CADA_S = int(os.environ.get("OLX_CHAT_A_CADA_S", "5"))
# a OLX disse não (sem permissão, sem vaga, bloqueado): espera isto antes de perguntar de novo
ESPERA_DEPOIS_DO_NAO_S = int(os.environ.get("OLX_ESPERA_DEPOIS_DO_NAO_S", str(6 * 3600)))
BATIMENTO = os.environ.get("OLX_BATIMENTO", "/tmp/nay-olx.batimento")
# o nome que fica na conversa quando é a Nay que responde. Começar com "Nay" é o que diz ao banco que não foi gente:
# resposta de gente cala a Nay naquela conversa (olx_nay_fila).
QUEM_RESPONDE = os.environ.get("OLX_QUEM_RESPONDE", "Nay OLX")
