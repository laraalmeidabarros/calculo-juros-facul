-- Carga inicial do banco calculo_juros: 6 modalidades + 30 faixas de juros.
-- Pode ser executado várias vezes sem erro (INSERT ... ON DUPLICATE KEY UPDATE).
-- Rode com: npm run seed   (depois do npm run schema)
--
-- Os códigos das modalidades são OS MESMOS do catálogo da API (src/dados/modalidades.js,
-- backlog-api.md T-01). A tabela operacoes tem chave estrangeira para modalidades.codigo:
-- se o código aqui for diferente do que a API envia, o POST /api/operacoes falha.
--
-- Fonte dos números: docs/backlog-db.md, Anexo A (P-03 / D-02).
--   taxa_mes = MIN(taxa_base + spread, teto); spreads A 0,00 / B 0,50 / C 1,00 / D 2,00.
--   taxa_ano = ((1 + taxa_mes/100)^12 - 1) * 100, 2 casas.
--   taxa_referencia_bcb_mes = mediana da série do BCB 11-17/08/2026 (já inclui IOF; só comparação).

USE calculo_juros;

-- ---------------------------------------------------------------------
-- 0) Limpeza: remove os códigos da primeira versão deste seed, que não
--    batiam com o catálogo da API. Não faz nada num banco recém-criado.
--    (Só falha se existir operação gravada com um desses códigos, o que
--    não deveria acontecer: a API nunca os aceitou.)
-- ---------------------------------------------------------------------
DELETE FROM faixas_juros
 WHERE modalidade_codigo IN ('CREDITO_PESSOAL_NON_CONSIGNE', 'CREDITO_PESSOAL_CONSIGNE_INSS',
                             'CREDITO_PESSOAL_CONSIGNE_PUBLICO', 'CREDITO_PESSOAL_CONSIGNE_PRIVADO',
                             'VEICULOS_AUTOMOVEIS', 'IMOBILIARIO_TP_TR');
DELETE FROM modalidades
 WHERE codigo IN ('CREDITO_PESSOAL_NON_CONSIGNE', 'CREDITO_PESSOAL_CONSIGNE_INSS',
                  'CREDITO_PESSOAL_CONSIGNE_PUBLICO', 'CREDITO_PESSOAL_CONSIGNE_PRIVADO',
                  'VEICULOS_AUTOMOVEIS', 'IMOBILIARIO_TP_TR');

-- ---------------------------------------------------------------------
-- 1) Modalidades — mesmas 6 do catálogo da API (backlog-api.md, T-01).
-- ---------------------------------------------------------------------
INSERT INTO modalidades
  (codigo, nome, modalidade_bcb, publico, regime_indexacao,
   teto_taxa_mes, taxa_referencia_bcb_mes, prazo_min_meses, prazo_max_meses, descricao)
VALUES
  ('CREDITO_PESSOAL',    'Crédito pessoal não consignado',      'Crédito pessoal não consignado - Prefixado',      'PF', 'PREFIXADO', 12.00, 5.25,  3, 48, 'Empréstimo sem garantia, pago em parcelas mensais.'),
  ('CONSIGNADO_INSS',    'Crédito pessoal consignado INSS',     'Crédito pessoal consignado INSS - Prefixado',     'PF', 'PREFIXADO',  1.85, 1.83,  6, 84, 'Parcelas descontadas diretamente do benefício do INSS. Teto regulatório CNPS (provisório).'),
  ('CONSIGNADO_PUBLICO', 'Crédito pessoal consignado público',  'Crédito pessoal consignado público - Prefixado',  'PF', 'PREFIXADO',  2.50, 1.84,  6, 96, 'Parcelas descontadas em folha de servidor público.'),
  ('CONSIGNADO_PRIVADO', 'Crédito pessoal consignado privado',  'Crédito pessoal consignado privado - Prefixado',  'PF', 'PREFIXADO',  4.50, 3.40,  6, 48, 'Parcelas descontadas em folha de empresa privada.'),
  ('VEICULOS',           'Aquisição de veículos',               'Aquisição de veículos - Prefixado',               'PF', 'PREFIXADO',  3.00, 1.77, 12, 60, 'Financiamento de veículo com o bem em garantia.'),
  ('OUTROS_BENS',        'Aquisição de outros bens',            'Aquisição de outros bens - Prefixado',            'PF', 'PREFIXADO',  5.00, 2.53,  3, 36, 'Financiamento de bens duráveis (eletrodomésticos, móveis etc.).')
AS novo
ON DUPLICATE KEY UPDATE
  nome = novo.nome, modalidade_bcb = novo.modalidade_bcb, publico = novo.publico,
  regime_indexacao = novo.regime_indexacao, teto_taxa_mes = novo.teto_taxa_mes,
  taxa_referencia_bcb_mes = novo.taxa_referencia_bcb_mes, prazo_min_meses = novo.prazo_min_meses,
  prazo_max_meses = novo.prazo_max_meses, descricao = novo.descricao, ativo = TRUE;

-- ---------------------------------------------------------------------
-- 2) Faixas de juros — 6 modalidades x 5 faixas = 30 linhas.
--    Limites de score iguais aos da API: A 800-1000, B 600-799, C 400-599,
--    D 200-399, E 0-199. Faixa E = recusado (taxa NULL).
-- ---------------------------------------------------------------------
INSERT INTO faixas_juros
  (modalidade_codigo, faixa, score_min, score_max, taxa_mes, taxa_ano, descricao)
VALUES
  -- CREDITO_PESSOAL: base 4,50 / teto 12,00
  ('CREDITO_PESSOAL',    'A', 800, 1000, 4.50,  69.59, 'Risco muito baixo'),
  ('CREDITO_PESSOAL',    'B', 600,  799, 5.00,  79.59, 'Risco baixo'),
  ('CREDITO_PESSOAL',    'C', 400,  599, 5.50,  90.12, 'Risco médio'),
  ('CREDITO_PESSOAL',    'D', 200,  399, 6.50, 112.91, 'Risco alto'),
  ('CREDITO_PESSOAL',    'E',   0,  199, NULL,   NULL, 'Recusado: score abaixo do mínimo'),
  -- CONSIGNADO_INSS: base 1,60 / teto 1,85 (teto atua em B, C e D)
  ('CONSIGNADO_INSS',    'A', 800, 1000, 1.60,  20.98, 'Risco muito baixo'),
  ('CONSIGNADO_INSS',    'B', 600,  799, 1.85,  24.60, 'Risco baixo'),
  ('CONSIGNADO_INSS',    'C', 400,  599, 1.85,  24.60, 'Risco médio'),
  ('CONSIGNADO_INSS',    'D', 200,  399, 1.85,  24.60, 'Risco alto'),
  ('CONSIGNADO_INSS',    'E',   0,  199, NULL,   NULL, 'Recusado: score abaixo do mínimo'),
  -- CONSIGNADO_PUBLICO: base 1,60 / teto 2,50 (teto atua em C e D)
  ('CONSIGNADO_PUBLICO', 'A', 800, 1000, 1.60,  20.98, 'Risco muito baixo'),
  ('CONSIGNADO_PUBLICO', 'B', 600,  799, 2.10,  28.32, 'Risco baixo'),
  ('CONSIGNADO_PUBLICO', 'C', 400,  599, 2.50,  34.49, 'Risco médio'),
  ('CONSIGNADO_PUBLICO', 'D', 200,  399, 2.50,  34.49, 'Risco alto'),
  ('CONSIGNADO_PUBLICO', 'E',   0,  199, NULL,   NULL, 'Recusado: score abaixo do mínimo'),
  -- CONSIGNADO_PRIVADO: base 2,80 / teto 4,50 (teto atua em D)
  ('CONSIGNADO_PRIVADO', 'A', 800, 1000, 2.80,  39.29, 'Risco muito baixo'),
  ('CONSIGNADO_PRIVADO', 'B', 600,  799, 3.30,  47.64, 'Risco baixo'),
  ('CONSIGNADO_PRIVADO', 'C', 400,  599, 3.80,  56.45, 'Risco médio'),
  ('CONSIGNADO_PRIVADO', 'D', 200,  399, 4.50,  69.59, 'Risco alto'),
  ('CONSIGNADO_PRIVADO', 'E',   0,  199, NULL,   NULL, 'Recusado: score abaixo do mínimo'),
  -- VEICULOS: base 1,50 / teto 3,00 (teto atua em D)
  ('VEICULOS',           'A', 800, 1000, 1.50,  19.56, 'Risco muito baixo'),
  ('VEICULOS',           'B', 600,  799, 2.00,  26.82, 'Risco baixo'),
  ('VEICULOS',           'C', 400,  599, 2.50,  34.49, 'Risco médio'),
  ('VEICULOS',           'D', 200,  399, 3.00,  42.58, 'Risco alto'),
  ('VEICULOS',           'E',   0,  199, NULL,   NULL, 'Recusado: score abaixo do mínimo'),
  -- OUTROS_BENS: base 2,20 / teto 5,00
  ('OUTROS_BENS',        'A', 800, 1000, 2.20,  29.84, 'Risco muito baixo'),
  ('OUTROS_BENS',        'B', 600,  799, 2.70,  37.67, 'Risco baixo'),
  ('OUTROS_BENS',        'C', 400,  599, 3.20,  45.93, 'Risco médio'),
  ('OUTROS_BENS',        'D', 200,  399, 4.20,  63.84, 'Risco alto'),
  ('OUTROS_BENS',        'E',   0,  199, NULL,   NULL, 'Recusado: score abaixo do mínimo')
AS novo
ON DUPLICATE KEY UPDATE
  score_min = novo.score_min, score_max = novo.score_max,
  taxa_mes = novo.taxa_mes, taxa_ano = novo.taxa_ano, descricao = novo.descricao;
