"""O que o serviço lê do ambiente (arquivo .env do servidor, fora do git)."""
import os

DATABASE_URL = os.environ.get("DATABASE_URL", "")
OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "")
# o mesmo modelo do nó "GPT (captação)" do fluxo
MODELO = os.environ.get("CAPTACAO_MODELO", "gpt-6-luna")
# a resposta e o modelo (template) saem pelo CRM: é ele que tem o token da Meta e grava a conversa
CRM_URL = os.environ.get("CRM_URL", "https://crm.imobeasy.online").rstrip("/")
SEGREDO = os.environ.get("CAPTACAO_OFICIAL_SEGREDO", "")
# o modelo que abre a conversa pelo número oficial (Pedro, 08/10)
MODELO_DE_ABERTURA = os.environ.get("CAPTACAO_MODELO_ABERTURA", "situacao_imovel_cadastrado_1")
IDIOMA_DO_MODELO = os.environ.get("CAPTACAO_MODELO_IDIOMA", "pt_BR")
# "nao" enquanto roda só no número de teste: a escalada e a foto ficam gravadas, mas o Tel não recebe aviso
AVISAR_TEL = os.environ.get("CAPTACAO_AVISAR_TEL", "nao") == "sim"
# segundos de silêncio antes de responder (o "Janela de 20s" do fluxo)
SILENCIO_S = int(os.environ.get("CAPTACAO_SILENCIO_S", "20"))
BATIMENTO = os.environ.get("CAPTACAO_BATIMENTO", "/tmp/nay-captacao.batimento")
