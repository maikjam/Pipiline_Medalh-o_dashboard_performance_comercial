/*
=========================================================
CAMADA SILVER — TRATAMENTO, PADRONIZAÇÃO E DEDUPLICAÇÃO
Versão preparada para cargas frequentes (hora a hora)
=========================================================

Objetivo:
Transformar o dado bruto da Bronze em dado limpo, padronizado
e confiável para análise — processando SOMENTE o que ainda não
foi tratado, sem nunca apagar o que já existe.

Princípio desta camada:
Bronze guarda tudo (inclusive duplicado). A Silver decide o
que é novo, limpa, converte tipos e elimina duplicidade.

Por que MERGE em vez de "LEFT JOIN + INSERT":
Numa automação hora a hora, é possível que duas execuções do
pipeline rodem muito próximas (ex: a carga das 14h atrasou e
ainda está rodando quando a das 15h começa). Um "LEFT JOIN +
WHERE IS NULL" não é uma operação atômica — entre o momento em
que ele checa "esse Row_ID já existe?" e o momento em que insere,
outra sessão pode ter inserido a mesma linha, gerando duplicata.
O MERGE faz a checagem e a inserção como uma ÚNICA operação
atômica, protegida contra essa corrida.

Fluxo:
Bronze → filtrar carga não processada → tratar → deduplicar
→ MERGE na Silver
=========================================================
*/


-- =========================================================
-- ETAPA 1 — CRIAÇÃO DO SCHEMA
-- =========================================================

IF NOT EXISTS (
    SELECT 1
    FROM sys.schemas
    WHERE name = 'Silver'
)
BEGIN
    EXEC('CREATE SCHEMA Silver');
END;


-- =========================================================
-- ETAPA 2 — CRIAÇÃO DA TABELA SILVER
-- =========================================================

-- Cria só se não existir — nunca derruba dados já tratados.
IF OBJECT_ID('Silver.SuperStore', 'U') IS NULL
BEGIN
    CREATE TABLE Silver.SuperStore (

        -- 🔑 Row_ID como PRIMARY KEY: além de NOT NULL, isso
        -- garante que não pode haver duas linhas com o mesmo
        -- Row_ID na Silver. É essa unicidade que torna o MERGE
        -- da Etapa 5 confiável — sem ela, a condição de
        -- correspondência do MERGE poderia bater com mais de
        -- uma linha.
        Row_ID          INT NOT NULL PRIMARY KEY,

        -- Identificadores críticos — nunca podem ficar vazios,
        -- a Silver sempre preenche com 'UNKNOWN' se faltar dado.
        Order_ID        NVARCHAR(50)  NOT NULL,
        Customer_ID     NVARCHAR(50)  NOT NULL,
        Product_ID      NVARCHAR(50)  NOT NULL,

        -- 📅 Datas — Order_Date pode ficar NULL aqui mesmo
        -- (decisão tomada: a Silver permite NULL: a Gold é quem
        -- vai aplicar a regra rígida de "todo pedido tem data").
        Order_Date      DATE,
        Ship_Date       DATE,
        Ship_Mode       NVARCHAR(50),

        -- 👤 Cliente
        Customer_Name   NVARCHAR(150),
        Segment         NVARCHAR(50),

        -- 🌎 Geografia
        Country         NVARCHAR(50),
        City            NVARCHAR(50),
        State           NVARCHAR(50),
        Postal_Code     NVARCHAR(20),
        Region          NVARCHAR(50),

        -- 📦 Produto
        Category        NVARCHAR(150),
        Sub_Category    NVARCHAR(150),
        Product_Name    NVARCHAR(250),

        -- 📊 Métricas — base para SUM/AVG no BI
        Sales           DECIMAL(18,2),
        Quantity        INT,
        Discount        DECIMAL(5,2),
        Profit          DECIMAL(18,2),

        -- 🕒 Marca quando essa linha foi processada pela Silver
        -- (diferente de _ingested_at da Bronze, que marca quando
        -- chegou). Permite saber quanto tempo o dado levou entre
        -- a ingestão bruta e o tratamento.
        _processed_at   DATETIME2 DEFAULT SYSDATETIME()
    );
END;


-- =========================================================
-- ETAPA 3 — TRANSAÇÃO
-- =========================================================

-- Inicia uma transação: tudo entre BEGIN TRANSACTION e COMMIT
-- é tratado como uma unidade só. Se algo falhar no meio do
-- caminho (rede caiu, disco encheu, etc.), o ROLLBACK no bloco
-- CATCH desfaz qualquer alteração parcial — evitando deixar a
-- Silver "pela metade" (algumas linhas tratadas, outras não).
BEGIN TRY
    BEGIN TRANSACTION;

    -- =====================================================
    -- ETAPA 4 — FILTRAR APENAS REGISTROS NÃO PROCESSADOS
    -- =====================================================

    -- Em vez de TRUNCATE + reprocessar a Bronze inteira (caro
    -- e lento conforme a Bronze cresce), filtramos só as linhas
    -- da Bronze cujo Row_ID ainda não existe na Silver.
    WITH Bronze_Nova AS (
        SELECT b.*
        FROM Bronze.SuperStore_Raw b

        -- LEFT JOIN aqui é só para IDENTIFICAR o que é novo —
        -- a proteção real contra duplicidade em corrida de
        -- execuções simultâneas vem do MERGE na Etapa 5, não
        -- deste JOIN.
        LEFT JOIN Silver.SuperStore s
            ON TRY_CONVERT(INT, b.Row_ID) = s.Row_ID

        -- Se não encontrou correspondência na Silver, é novo.
        WHERE s.Row_ID IS NULL
    ),

    -- =====================================================
    -- ETAPA 5 — DEDUPLICAÇÃO DA CARGA NOVA
    -- =====================================================

    -- Mesmo princípio de antes: dentro do que é novo, pode
    -- haver duplicidade (mesmo Order_ID + Product_ID +
    -- Customer_ID repetidos). ROW_NUMBER numera cada grupo,
    -- mantendo só a primeira ocorrência (rn = 1).
    Bronze_Deduplicada AS (
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY Order_ID, Product_ID, Customer_ID
                ORDER BY TRY_CONVERT(INT, Row_ID)
            ) AS rn
        FROM Bronze_Nova
    )

    -- =====================================================
    -- ETAPA 6 — MERGE: TRATAMENTO + CARGA ATÔMICA
    -- =====================================================

    -- MERGE compara a origem (Bronze tratada) com o destino
    -- (Silver) usando Row_ID como chave de correspondência.
    MERGE Silver.SuperStore AS target
    USING (
        SELECT
            TRY_CONVERT(INT, Row_ID)                              AS Row_ID,
            COALESCE(NULLIF(TRIM(Order_ID), ''), 'UNKNOWN')        AS Order_ID,
            TRY_CONVERT(DATE, Order_Date)                          AS Order_Date,
            TRY_CONVERT(DATE, Ship_Date)                           AS Ship_Date,
            COALESCE(NULLIF(TRIM(Ship_Mode), ''), 'UNKNOWN')       AS Ship_Mode,
            COALESCE(NULLIF(TRIM(Customer_ID), ''), 'UNKNOWN')     AS Customer_ID,
            COALESCE(NULLIF(TRIM(Customer_Name), ''), 'UNKNOWN')   AS Customer_Name,
            UPPER(COALESCE(NULLIF(TRIM(Segment), ''), 'UNKNOWN'))  AS Segment,
            UPPER(COALESCE(NULLIF(TRIM(Country), ''), 'UNKNOWN'))  AS Country,
            UPPER(COALESCE(NULLIF(TRIM(City), ''), 'UNKNOWN'))     AS City,
            UPPER(COALESCE(NULLIF(TRIM(State), ''), 'UNKNOWN'))    AS State,
            COALESCE(NULLIF(TRIM(Postal_Code), ''), 'UNKNOWN')     AS Postal_Code,
            UPPER(COALESCE(NULLIF(TRIM(Region), ''), 'UNKNOWN'))   AS Region,
            COALESCE(NULLIF(TRIM(Product_ID), ''), 'UNKNOWN')      AS Product_ID,
            UPPER(COALESCE(NULLIF(TRIM(Category), ''), 'UNKNOWN')) AS Category,
            UPPER(COALESCE(NULLIF(TRIM(Sub_Category), ''), 'UNKNOWN')) AS Sub_Category,
            COALESCE(NULLIF(TRIM(Product_Name), ''), 'UNKNOWN')    AS Product_Name,
            COALESCE(TRY_CONVERT(DECIMAL(18,2), Sales), 0)         AS Sales,
            COALESCE(TRY_CONVERT(INT, Quantity), 0)                AS Quantity,
            COALESCE(TRY_CONVERT(DECIMAL(5,2), Discount), 0)       AS Discount,
            COALESCE(TRY_CONVERT(DECIMAL(18,2), Profit), 0)        AS Profit
        FROM Bronze_Deduplicada
        WHERE rn = 1   -- só a primeira ocorrência de cada grupo duplicado
    ) AS source
    ON target.Row_ID = source.Row_ID

    -- Se o Row_ID NÃO existe ainda na Silver, insere.
    -- Como filtramos só "Bronze_Nova" antes, na prática quase
    -- sempre cai aqui — mas o MERGE garante que, mesmo que duas
    -- execuções tentem inserir o mesmo Row_ID ao mesmo tempo,
    -- só uma consegue (a outra não dá erro, simplesmente não
    -- duplica).
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            Row_ID, Order_ID, Order_Date, Ship_Date, Ship_Mode,
            Customer_ID, Customer_Name, Segment,
            Country, City, State, Postal_Code, Region,
            Product_ID, Category, Sub_Category, Product_Name,
            Sales, Quantity, Discount, Profit
        )
        VALUES (
            source.Row_ID, source.Order_ID, source.Order_Date, source.Ship_Date, source.Ship_Mode,
            source.Customer_ID, source.Customer_Name, source.Segment,
            source.Country, source.City, source.State, source.Postal_Code, source.Region,
            source.Product_ID, source.Category, source.Sub_Category, source.Product_Name,
            source.Sales, source.Quantity, source.Discount, source.Profit
        );

    -- Se a transação chegou até aqui sem erro, confirma todas
    -- as alterações de forma permanente.
    COMMIT TRANSACTION;

END TRY
BEGIN CATCH
    -- Se qualquer coisa falhou dentro do TRY, desfaz tudo o que
    -- foi feito desde o BEGIN TRANSACTION — a Silver volta ao
    -- estado de antes da execução, sem ficar "pela metade".
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    -- Repassa o erro original para quem chamou o script (ou para
    -- o orquestrador do pipeline), preservando a mensagem real
    -- em vez de mascarar o problema.
    THROW;
END CATCH;


-- =========================================================
-- ETAPA 7 — VALIDAÇÃO PÓS-CARGA
-- =========================================================

-- Total acumulado na Silver (todas as cargas já processadas).
SELECT COUNT(*) AS Total_Silver
FROM Silver.SuperStore;

-- Últimas 10 linhas processadas, ordenadas por quando entraram
-- na Silver — confirma visualmente que a carga de agora rodou.
SELECT TOP 10 *
FROM Silver.SuperStore
ORDER BY _processed_at DESC;


-- =========================================================
-- ETAPA 8 — ÍNDICES
-- =========================================================

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes WHERE name = 'IX_Silver_Row'
)
    -- Acelera o JOIN/MERGE da Etapa 4-6, que compara Row_ID
    -- entre Bronze e Silver a cada execução.
    CREATE INDEX IX_Silver_Row
    ON Silver.SuperStore(Row_ID);

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes WHERE name = 'IX_Silver_Customer'
)
    -- Acelera consultas e futuras cargas da Gold que vão
    -- agrupar/filtrar por Customer_ID.
    CREATE INDEX IX_Silver_Customer
    ON Silver.SuperStore(Customer_ID);