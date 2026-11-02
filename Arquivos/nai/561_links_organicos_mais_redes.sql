-- 561 (Pedro, 02/11/2026): "um link para o meu Instagram, do insta vai ser /bio, e também para todas as redes sociais, e deixa
-- lá para eu copiar e usar futuramente": mais redes na página Links orgânicos (a 559 criou 11).
BEGIN;
INSERT INTO privado.link_organico (codigo, canal, nome, mensagem, marca, utm_source, utm_medium, criado_por) VALUES
  ('whatsapp-status','WhatsApp',  'Status do WhatsApp',           'Olá! Vim do status do WhatsApp da Imob Easy e quero saber mais sobre imóveis.', 'Vim do status do WhatsApp da Imob Easy', 'whatsapp', 'status', '561'),
  ('whatsapp-canal', 'WhatsApp',  'Canal do WhatsApp',            'Olá! Vim do canal do WhatsApp da Imob Easy e quero saber mais sobre imóveis.',  'Vim do canal do WhatsApp da Imob Easy',  'whatsapp', 'canal',  '561'),
  ('threads',        'Threads',   'Threads: perfil',              'Olá! Vim do Threads da Imob Easy e quero saber mais sobre imóveis.',            'Vim do Threads da Imob Easy',            'threads',  'bio',    '561'),
  ('x-twitter',     'X',         'X (Twitter): perfil',          'Olá! Vim do X da Imob Easy e quero saber mais sobre imóveis.',                  'Vim do X da Imob Easy',                  'x',        'bio',    '561'),
  ('pinterest',      'Pinterest', 'Pinterest: perfil e pins',     'Olá! Vim do Pinterest da Imob Easy e quero saber mais sobre imóveis.',          'Vim do Pinterest da Imob Easy',          'pinterest','pin',    '561'),
  ('kwai',           'Kwai',      'Kwai: perfil',                 'Olá! Vim do Kwai da Imob Easy e quero saber mais sobre imóveis.',               'Vim do Kwai da Imob Easy',               'kwai',     'bio',    '561'),
  ('telegram',       'Telegram',  'Telegram: canal',              'Olá! Vim do Telegram da Imob Easy e quero saber mais sobre imóveis.',           'Vim do Telegram da Imob Easy',           'telegram', 'canal',  '561'),
  ('olx',            'Portais',   'OLX: anúncios (link no texto)','Olá! Vim da OLX e quero saber mais sobre os imóveis da Imob Easy.',            'Vim da OLX',                             'olx',      'anuncio','561'),
  ('indicacao',      'Outros',    'Indicação (cartão, QR, panfleto)','Olá! Vim por indicação da Imob Easy e quero saber mais sobre imóveis.',      'Vim por indicação da Imob Easy',         'indicacao','offline','561')
ON CONFLICT (codigo) DO NOTHING;
COMMIT;
