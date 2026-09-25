-- Script de consultas e testes de enquadramento (D-03)
USE calculo_juros;

-- ============================================================================
-- 1. BUSCA DE TAXA/FAIXA POR SCORE E MODALIDADE (ENQUADRAMENTO DE CRÉDITO)
-- Exemplo: Cliente com Score 750 buscando empréstimo Consignado INSS
-- ============================================================================
SET @modalidade_busca = 'CONSIGNADO_INSS' COLLATE utf8mb4_unicode_ci;
SET @score_cliente = 750;

SELECT 
    m.codigo AS modalidade_codigo,
    m.nome AS modalidade_nome,
    fj.faixa,
    fj.score_min,
    fj.score_max,
    fj.taxa_mes,
    fj.taxa_ano,
    fj.descricao AS risco_descricao
FROM modalidades m
INNER JOIN faixas_juros fj ON m.codigo = fj.modalidade_codigo
WHERE m.codigo = @modalidade_busca
  AND m.ativo = TRUE
  AND @score_cliente BETWEEN fj.score_min AND fj.score_max;


-- ============================================================================
-- 2. LISTAGEM DE TODAS AS MODALIDADES ATIVAS
-- Utilizado pelo frontend para preencher o select/dropdown de modalidades
-- ============================================================================
SELECT 
    codigo,
    nome,
    modalidade_bcb,
    publico,
    regime_indexacao,
    teto_taxa_mes,
    prazo_min_meses,
    prazo_max_meses
FROM modalidades
WHERE ativo = TRUE
ORDER BY nome ASC;


-- ============================================================================
-- 3. CONSULTA DE FAIXAS DE JUROS DE UMA MODALIDADE ESPECÍFICA
-- Exemplo: Consultar a tabela de risco/taxas para Financiamento de Veículos
-- ============================================================================
SELECT 
    faixa,
    score_min,
    score_max,
    taxa_mes,
    taxa_ano,
    descricao
FROM faixas_juros
WHERE modalidade_codigo = 'VEICULOS'
ORDER BY faixa ASC;


-- ============================================================================
-- 4. CONSULTA DE HISTÓRICO DE OPERAÇÕES SIMULADAS/REGISTRADAS
-- Mapeado para as colunas reais: identificador, valor, faixa_risco, taxa_final_mes
-- ============================================================================
SELECT 
    o.id,
    o.identificador,
    o.modalidade_codigo,
    m.nome AS modalidade_nome,
    o.valor,
    o.score,
    o.faixa_risco,
    o.prazo_meses,
    o.taxa_final_mes,
    o.cet_price_ano,
    o.cet_sac_ano,
    o.criado_em
FROM operacoes o
INNER JOIN modalidades m ON o.modalidade_codigo = m.codigo
ORDER BY o.criado_em DESC
LIMIT 10;


-- ============================================================================
-- 5. RELATÓRIO AGREGADO: TOTAL DE OPERAÇÕES E VALORES POR MODALIDADE
-- ============================================================================
SELECT 
    m.codigo,
    m.nome,
    COUNT(o.id) AS total_operacoes,
    COALESCE(SUM(o.valor), 0.00) AS montante_total_solicitado,
    COALESCE(AVG(o.taxa_final_mes), 0.00) AS taxa_media_aplicada
FROM modalidades m
LEFT JOIN operacoes o ON m.codigo = o.modalidade_codigo
GROUP BY m.codigo, m.nome
ORDER BY total_operacoes DESC;