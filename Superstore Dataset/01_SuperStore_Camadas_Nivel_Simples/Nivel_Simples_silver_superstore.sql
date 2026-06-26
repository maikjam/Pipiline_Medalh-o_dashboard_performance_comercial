-- ================================
-- CRIAÇÃO DO SCHEMA SILVER
-- (camada de dados tratados)
-- ================================
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'Silver')
BEGIN
    EXEC('CREATE SCHEMA Silver');
END;

-- ================================
-- TABELA SILVER (DADOS TRATADOS)
-- ================================

    IF OBJECT_ID('Silver.SuperStore', 'U') IS NULL
BEGIN
    CREATE TABLE Silver.SuperStore (
      

    -- 🔑 CAMPOS DE SEGURANÇA (CRÍTICOS)
    -- Não podem ser nulos porque garantem integridade do registro
    Row_ID          INT NOT NULL,
    Order_ID        NVARCHAR(50) NOT NULL,
    Customer_ID     NVARCHAR(50) NOT NULL,
    Product_ID      NVARCHAR(50) NOT NULL,

    -- 📅 DATAS (devem vir tratadas na carga)
    Order_Date      DATE,
    Ship_Date       DATE,
    Ship_Mode       NVARCHAR(50),

    -- 👤 DIMENSÃO CLIENTE
    Customer_Name   NVARCHAR(150),
    Segment         NVARCHAR(50),

    -- 🌎 GEOGRAFIA
    Country         NVARCHAR(50),
    City            NVARCHAR(50),
    State           NVARCHAR(50),
    Postal_Code     NVARCHAR(20),
    Region          NVARCHAR(50),

    -- 📦 DIMENSÃO PRODUTO
    Category        NVARCHAR(150),
    Sub_Category    NVARCHAR(150),
    Product_Name    NVARCHAR(250),

    -- 📊 MÉTRICAS (BASE PARA BI)
    Sales           DECIMAL(18,2),
    Quantity        INT,
    Discount        DECIMAL(5,2),
    Profit          DECIMAL(18,2)
)
END;

-- =========================================================
-- ETL | Bronze → Silver | Carga + Tratamento + Deduplicação
--
-- Objetivo:
-- Receber dados brutos da camada Bronze e gerar uma camada
-- Silver com dados consistentes, padronizados e preparados
-- para consumo analítico.
--
-- Responsabilidades desta etapa:
-- • Limpar textos e remover espaços desnecessários
-- • Tratar valores vazios e nulos
-- • Converter tipos de dados corretamente
-- • Padronizar informações para evitar inconsistência
-- • Eliminar registros duplicados
-- • Garantir que os dados possam ser usados em BI
--
-- Origem : Bronze.SuperStore_Raw
-- Destino: Silver.SuperStore
-- =========================================================


-- =========================================================
-- Limpeza da carga anterior
--
-- Remove os registros já carregados anteriormente na Silver
-- sem apagar a estrutura da tabela.
--
-- Objetivo:
-- evitar duplicação entre execuções do processo.
--
-- Observação:
-- TRUNCATE remove apenas dados e mantém:
-- • tabela
-- • colunas
-- • tipos
-- • índices
-- =========================================================

TRUNCATE TABLE Silver.SuperStore;



-- =========================================================
-- Etapa de deduplicação
--
-- Cria uma visão temporária (CTE) contendo todos os registros
-- da Bronze e identifica possíveis duplicidades.
--
-- Regra adotada:
--
-- Um registro será considerado duplicado quando possuir:
-- • mesmo Order_ID
-- • mesmo Product_ID
-- • mesmo Customer_ID
--
-- ROW_NUMBER gera uma numeração dentro de cada grupo:
--
-- Exemplo:
--
-- Pedido Produto Cliente rn
-- A001   P01     C01     1 ← mantém
-- A001   P01     C01     2 ← remove
-- A001   P01     C01     3 ← remove
--
-- Apenas registros rn = 1 serão carregados.
-- =========================================================

WITH Bronze_Deduplicada AS (

    SELECT *,

        ROW_NUMBER() OVER(

            PARTITION BY
                Order_ID,
                Product_ID,
                Customer_ID

            ORDER BY Row_ID

        ) AS rn

    FROM Bronze.SuperStore_Raw
)



-- =========================================================
-- Inserção na Silver
--
-- Nesta etapa os dados passam pelas regras de limpeza,
-- padronização e conversão antes de serem persistidos.
-- =========================================================

INSERT INTO Silver.SuperStore (

    Row_ID,
    Order_ID,
    Order_Date,
    Ship_Date,

    Ship_Mode,
    Customer_ID,
    Customer_Name,

    Segment,
    Country,
    City,
    State,
    Postal_Code,
    Region,

    Product_ID,
    Category,
    Sub_Category,
    Product_Name,

    Sales,
    Quantity,
    Discount,
    Profit
)

SELECT


-- =========================================================
-- Chave técnica
--
-- Mantida sem alteração para permitir rastreabilidade
-- entre Bronze e Silver.
-- =========================================================

Row_ID,


-- =========================================================
-- Identificadores
--
-- Fluxo aplicado:
--
-- TRIM
-- → remove espaços extras
--
-- NULLIF
-- → transforma texto vazio ('') em NULL
--
-- COALESCE
-- → substitui NULL por valor padrão
--
-- Resultado:
-- nenhum identificador crítico ficará vazio.
-- =========================================================

COALESCE(NULLIF(TRIM(Order_ID), ''), 'UNKNOWN'),



-- =========================================================
-- Datas
--
-- TRY_CONVERT converte texto em DATE.
--
-- Se houver valor inválido:
--
-- Exemplo:
-- '99/99/2025'
--
-- o processo não falha.
-- O valor será armazenado como NULL.
-- =========================================================

TRY_CONVERT(DATE, Order_Date),
TRY_CONVERT(DATE, Ship_Date),



-- =========================================================
-- Dados de cliente e envio
--
-- Aplicação do padrão de limpeza para manter consistência.
-- =========================================================

COALESCE(NULLIF(TRIM(Ship_Mode), ''), 'UNKNOWN'),
COALESCE(NULLIF(TRIM(Customer_ID), ''), 'UNKNOWN'),
COALESCE(NULLIF(TRIM(Customer_Name), ''), 'UNKNOWN'),



-- =========================================================
-- Dimensões de negócio
--
-- UPPER padroniza os valores em maiúsculo.
--
-- Evita cenários como:
--
-- Consumer
-- consumer
-- CONSUMER
--
-- Todos passam a ser:
-- CONSUMER
-- =========================================================

UPPER(COALESCE(NULLIF(TRIM(Segment), ''), 'UNKNOWN')),
UPPER(COALESCE(NULLIF(TRIM(Country), ''), 'UNKNOWN')),
UPPER(COALESCE(NULLIF(TRIM(City), ''), 'UNKNOWN')),
UPPER(COALESCE(NULLIF(TRIM(State), ''), 'UNKNOWN')),

COALESCE(NULLIF(TRIM(Postal_Code), ''), 'UNKNOWN'),
UPPER(COALESCE(NULLIF(TRIM(Region), ''), 'UNKNOWN')),



-- =========================================================
-- Produto
--
-- Mantém consistência dos atributos utilizados em análises.
--
-- Product_Name permanece original para preservar leitura.
-- =========================================================

COALESCE(NULLIF(TRIM(Product_ID), ''), 'UNKNOWN'),

UPPER(COALESCE(NULLIF(TRIM(Category), ''), 'UNKNOWN')),

UPPER(COALESCE(NULLIF(TRIM(Sub_Category), ''), 'UNKNOWN')),

COALESCE(NULLIF(TRIM(Product_Name), ''), 'UNKNOWN'),



-- =========================================================
-- Métricas
--
-- TRY_CONVERT:
-- garante tipo numérico
--
-- COALESCE:
-- substitui valores inválidos ou ausentes por zero
--
-- Objetivo:
-- evitar falhas em:
-- • SUM
-- • AVG
-- • KPIs
-- • dashboards
-- =========================================================

COALESCE(TRY_CONVERT(DECIMAL(18,2), Sales),0),

COALESCE(TRY_CONVERT(INT, Quantity),0),

COALESCE(TRY_CONVERT(DECIMAL(5,2), Discount),0),

COALESCE(TRY_CONVERT(DECIMAL(18,2), Profit),0)



-- =========================================================
-- Origem dos dados
--
-- Apenas registros marcados como rn=1 permanecem.
--
-- Isso elimina duplicidade antes da entrada na Silver.
-- =========================================================

FROM Bronze_Deduplicada

WHERE rn = 1;



-- =========================================================
-- Validação pós-carga
--
-- Confirma quantidade final carregada.
-- =========================================================
-- =========================================================
-- Validação pós-carga | Bronze → Silver
--
-- Objetivo:
-- Confirmar integridade da carga e provar que a deduplicação
-- funcionou corretamente.
--
-- Resultado esperado:
-- Silver deve ter menos registros que a Bronze.
-- A diferença representa os duplicados eliminados.
-- =========================================================


-- =========================================================
-- Contagem Silver
-- Quantidade final de registros carregados e tratados.
-- =========================================================

SELECT COUNT(*) AS Total_Linhas
FROM Silver.SuperStore;


-- =========================================================
-- Contagem Bronze
-- Quantidade bruta antes do tratamento.
-- A diferença entre Bronze e Silver = duplicatas removidas.
-- =========================================================

SELECT COUNT(*) AS Total_Linhas
FROM Bronze.SuperStore_Raw;


-- =========================================================
-- Prova da deduplicação
--
-- Identifica combinações que aparecem mais de uma vez
-- na Bronze com base na chave de deduplicação adotada:
--
-- • Order_ID
-- • Product_ID
-- • Customer_ID
--
-- A soma de (Qtd_Ocorrencias - 1) de todos os grupos
-- deve ser igual à diferença entre Bronze e Silver.
-- =========================================================

SELECT
    Order_ID,
    Product_ID,
    Customer_ID,
    COUNT(*) AS Qtd_Ocorrencias
FROM Bronze.SuperStore_Raw
GROUP BY
    Order_ID,
    Product_ID,
    Customer_ID
HAVING COUNT(*) > 1
ORDER BY Qtd_Ocorrencias DESC;


-- =========================================================
-- LIMPEZA PARA RECARGA — AMBIENTE DE ESTUDO
--
-- Ordem importa: a Fato_Vendas tem REFERENCES apontando para-- ================================
-- CRIAÇÃO DO SCHEMA SILVER
-- (camada de dados tratados)
-- ================================
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'Silver')
BEGIN
    EXEC('CREATE SCHEMA Silver');
END;

-- ================================
-- RECRIAR TABELA (AMBIENTE DE ESTUDO)
-- CUIDADO: ISSO APAGA OS DADOS
--
-- Motivo da recarga total:
-- A versão anterior convertia as datas sem especificar o
-- formato de origem (TRY_CONVERT(DATE, Order_Date)), e o CSV
-- vem no padrão americano M/D/YYYY (ex: 11/8/2016 = 8 de
-- novembro). Sem informar isso, o SQL Server interpretava como
-- D/M/YYYY (padrão da configuração regional do servidor):
--   • datas como 8/29/2016 (mês 29 não existe) falhavam e
--     viravam NULL — isso descartou ~60% das vendas na Gold
--   • datas como 11/8/2016 convertiam "com sucesso", mas para
--     o dia/mês ERRADO (virou 11 de agosto, deveria ser 8 de
--     novembro) — silenciosamente, sem nenhum erro
-- Por isso não basta corrigir só as que viraram NULL: é preciso
-- reprocessar a Silver inteira do zero com o formato certo.
-- ================================
DROP TABLE IF EXISTS Silver.SuperStore;

-- ================================
-- TABELA SILVER (DADOS TRATADOS)
-- ================================

IF OBJECT_ID('Silver.SuperStore', 'U') IS NULL
BEGIN
    CREATE TABLE Silver.SuperStore (

        -- 🔑 CAMPOS DE SEGURANÇA (CRÍTICOS)
        -- Não podem ser nulos porque garantem integridade do registro
        Row_ID          INT NOT NULL,
        Order_ID        NVARCHAR(50) NOT NULL,
        Customer_ID     NVARCHAR(50) NOT NULL,
        Product_ID      NVARCHAR(50) NOT NULL,

        -- 📅 DATAS (devem vir tratadas na carga)
        Order_Date      DATE,
        Ship_Date       DATE,
        Ship_Mode       NVARCHAR(50),

        -- 👤 DIMENSÃO CLIENTE
        Customer_Name   NVARCHAR(150),
        Segment         NVARCHAR(50),

        -- 🌎 GEOGRAFIA
        Country         NVARCHAR(50),
        City            NVARCHAR(50),
        State           NVARCHAR(50),
        Postal_Code     NVARCHAR(20),
        Region          NVARCHAR(50),

        -- 📦 DIMENSÃO PRODUTO
        Category        NVARCHAR(150),
        Sub_Category    NVARCHAR(150),
        Product_Name    NVARCHAR(250),

        -- 📊 MÉTRICAS (BASE PARA BI)
        Sales           DECIMAL(18,2),
        Quantity        INT,
        Discount        DECIMAL(5,2),
        Profit          DECIMAL(18,2)
    );
END;

-- =========================================================
-- ETL | Bronze → Silver | Carga + Tratamento + Deduplicação
--
-- Objetivo:
-- Receber dados brutos da camada Bronze e gerar uma camada
-- Silver com dados consistentes, padronizados e preparados
-- para consumo analítico.
--
-- Responsabilidades desta etapa:
-- • Limpar textos e remover espaços desnecessários
-- • Tratar valores vazios e nulos
-- • Converter tipos de dados corretamente
-- • Padronizar informações para evitar inconsistência
-- • Eliminar registros duplicados
-- • Garantir que os dados possam ser usados em BI
--
-- Origem : Bronze.SuperStore_Raw
-- Destino: Silver.SuperStore
-- =========================================================


-- =========================================================
-- Limpeza da carga anterior
--
-- Remove os registros já carregados anteriormente na Silver
-- sem apagar a estrutura da tabela.
--
-- Objetivo:
-- evitar duplicação entre execuções do processo.
--
-- Observação:
-- TRUNCATE remove apenas dados e mantém:
-- • tabela
-- • colunas
-- • tipos
-- • índices
-- =========================================================

TRUNCATE TABLE Silver.SuperStore;



-- =========================================================
-- Etapa de deduplicação
--
-- Cria uma visão temporária (CTE) contendo todos os registros
-- da Bronze e identifica possíveis duplicidades.
--
-- Regra adotada:
--
-- Um registro será considerado duplicado quando possuir:
-- • mesmo Order_ID
-- • mesmo Product_ID
-- • mesmo Customer_ID
--
-- ROW_NUMBER gera uma numeração dentro de cada grupo:
--
-- Exemplo:
--
-- Pedido Produto Cliente rn
-- A001   P01     C01     1 ← mantém
-- A001   P01     C01     2 ← remove
-- A001   P01     C01     3 ← remove
--
-- Apenas registros rn = 1 serão carregados.
-- =========================================================

WITH Bronze_Deduplicada AS (

    SELECT *,

        ROW_NUMBER() OVER(

            PARTITION BY
                Order_ID,
                Product_ID,
                Customer_ID

            ORDER BY Row_ID

        ) AS rn

    FROM Bronze.SuperStore_Raw
)



-- =========================================================
-- Inserção na Silver
--
-- Nesta etapa os dados passam pelas regras de limpeza,
-- padronização e conversão antes de serem persistidos.
-- =========================================================

INSERT INTO Silver.SuperStore (

    Row_ID,
    Order_ID,
    Order_Date,
    Ship_Date,

    Ship_Mode,
    Customer_ID,
    Customer_Name,

    Segment,
    Country,
    City,
    State,
    Postal_Code,
    Region,

    Product_ID,
    Category,
    Sub_Category,
    Product_Name,

    Sales,
    Quantity,
    Discount,
    Profit
)

SELECT


-- =========================================================
-- Chave técnica
--
-- Mantida sem alteração para permitir rastreabilidade
-- entre Bronze e Silver.
-- =========================================================

Row_ID,


-- =========================================================
-- Identificadores
--
-- Fluxo aplicado:
--
-- TRIM
-- → remove espaços extras
--
-- NULLIF
-- → transforma texto vazio ('') em NULL
--
-- COALESCE
-- → substitui NULL por valor padrão
--
-- Resultado:
-- nenhum identificador crítico ficará vazio.
-- =========================================================

COALESCE(NULLIF(TRIM(Order_ID), ''), 'UNKNOWN'),



-- =========================================================
-- Datas
--
-- TRY_CONVERT converte texto em DATE.
--
-- ⚠️ CORREÇÃO APLICADA: o terceiro parâmetro (101) informa
-- explicitamente que a data de origem está no formato
-- americano MM/DD/YYYY — exatamente como vem no CSV
-- (ex: '11/8/2016' = 8 de novembro de 2016).
--
-- Sem esse parâmetro, o SQL Server usa a configuração regional
-- do servidor (no Brasil, normalmente DD/MM/YYYY) para
-- interpretar a data — o que causava dois problemas:
--   • datas como '8/29/2016' (mês 29 inválido em DD/MM)
--     falhavam e viravam NULL silenciosamente
--   • datas como '11/8/2016' convertiam "com sucesso", mas
--     para o dia/mês TROCADO (virava 11 de agosto em vez de
--     8 de novembro) — erro silencioso, sem aviso nenhum
--
-- Se houver valor realmente inválido mesmo com o estilo certo:
-- Exemplo:
-- '99/99/2025'
--
-- o processo não falha.
-- O valor será armazenado como NULL.
-- =========================================================

TRY_CONVERT(DATE, Order_Date, 101),
TRY_CONVERT(DATE, Ship_Date, 101),



-- =========================================================
-- Dados de cliente e envio
--
-- Aplicação do padrão de limpeza para manter consistência.
-- =========================================================

COALESCE(NULLIF(TRIM(Ship_Mode), ''), 'UNKNOWN'),
COALESCE(NULLIF(TRIM(Customer_ID), ''), 'UNKNOWN'),
COALESCE(NULLIF(TRIM(Customer_Name), ''), 'UNKNOWN'),



-- =========================================================
-- Dimensões de negócio
--
-- UPPER padroniza os valores em maiúsculo.
--
-- Evita cenários como:
--
-- Consumer
-- consumer
-- CONSUMER
--
-- Todos passam a ser:
-- CONSUMER
-- =========================================================

UPPER(COALESCE(NULLIF(TRIM(Segment), ''), 'UNKNOWN')),
UPPER(COALESCE(NULLIF(TRIM(Country), ''), 'UNKNOWN')),
UPPER(COALESCE(NULLIF(TRIM(City), ''), 'UNKNOWN')),
UPPER(COALESCE(NULLIF(TRIM(State), ''), 'UNKNOWN')),

COALESCE(NULLIF(TRIM(Postal_Code), ''), 'UNKNOWN'),
UPPER(COALESCE(NULLIF(TRIM(Region), ''), 'UNKNOWN')),



-- =========================================================
-- Produto
--
-- Mantém consistência dos atributos utilizados em análises.
--
-- Product_Name permanece original para preservar leitura.
-- =========================================================

COALESCE(NULLIF(TRIM(Product_ID), ''), 'UNKNOWN'),

UPPER(COALESCE(NULLIF(TRIM(Category), ''), 'UNKNOWN')),

UPPER(COALESCE(NULLIF(TRIM(Sub_Category), ''), 'UNKNOWN')),

COALESCE(NULLIF(TRIM(Product_Name), ''), 'UNKNOWN'),



-- =========================================================
-- Métricas
--
-- TRY_CONVERT:
-- garante tipo numérico
--
-- COALESCE:
-- substitui valores inválidos ou ausentes por zero
--
-- Objetivo:
-- evitar falhas em:
-- • SUM
-- • AVG
-- • KPIs
-- • dashboards
-- =========================================================

COALESCE(TRY_CONVERT(DECIMAL(18,2), Sales),0),

COALESCE(TRY_CONVERT(INT, Quantity),0),

COALESCE(TRY_CONVERT(DECIMAL(5,2), Discount),0),

COALESCE(TRY_CONVERT(DECIMAL(18,2), Profit),0)



-- =========================================================
-- Origem dos dados
--
-- Apenas registros marcados como rn=1 permanecem.
--
-- Isso elimina duplicidade antes da entrada na Silver.
-- =========================================================

FROM Bronze_Deduplicada

WHERE rn = 1;



-- =========================================================
-- Validação pós-carga | Bronze → Silver
--
-- Objetivo:
-- Confirmar integridade da carga e provar que a deduplicação
-- funcionou corretamente.
--
-- Resultado esperado:
-- Silver deve ter menos registros que a Bronze.
-- A diferença representa os duplicados eliminados.
-- =========================================================


-- =========================================================
-- Contagem Silver
-- Quantidade final de registros carregados e tratados.
-- =========================================================

SELECT COUNT(*) AS Total_Linhas
FROM Silver.SuperStore;


-- =========================================================
-- Contagem Bronze
-- Quantidade bruta antes do tratamento.
-- A diferença entre Bronze e Silver = duplicatas removidas.
-- =========================================================

SELECT COUNT(*) AS Total_Linhas
FROM Bronze.SuperStore_Raw;


-- =========================================================
-- Prova da deduplicação
--
-- Identifica combinações que aparecem mais de uma vez
-- na Bronze com base na chave de deduplicação adotada:
--
-- • Order_ID
-- • Product_ID
-- • Customer_ID
--
-- A soma de (Qtd_Ocorrencias - 1) de todos os grupos
-- deve ser igual à diferença entre Bronze e Silver.
-- =========================================================

SELECT
    Order_ID,
    Product_ID,
    Customer_ID,
    COUNT(*) AS Qtd_Ocorrencias
FROM Bronze.SuperStore_Raw
GROUP BY
    Order_ID,
    Product_ID,
    Customer_ID
HAVING COUNT(*) > 1
ORDER BY Qtd_Ocorrencias DESC;


-- =========================================================
-- Validação extra | Confirma que a correção de data funcionou
--
-- Objetivo:
-- Depois da correção com TRY_CONVERT(..., 101), o número de
-- Order_Date NULL deveria cair para perto de zero (só ficam
-- NULL os casos realmente inválidos na origem, não mais os
-- ~60% que falhavam por causa do formato errado).
-- =========================================================

SELECT COUNT(*) AS Order_Date_Nulas
FROM Silver.SuperStore
WHERE Order_Date IS NULL;
-- as dimensões. Se tentar dropar uma dimensão antes da Fato,
-- o SQL Server recusa (constraint de Foreign Key impede).
-- Por isso a Fato sempre cai primeiro, as dimensões depois.
-- =========================================================
/*
