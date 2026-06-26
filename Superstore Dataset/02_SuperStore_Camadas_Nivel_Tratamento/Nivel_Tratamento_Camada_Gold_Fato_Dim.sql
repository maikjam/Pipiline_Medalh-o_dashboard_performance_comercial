/*
=========================================================
CAMADA GOLD — MODELO DIMENSIONAL (STAR SCHEMA)
Versão preparada para cargas frequentes (hora a hora)
=========================================================

Objetivo:
Organizar o dado limpo da Silver em um modelo dimensional
(dimensões + fato), pronto para consumo direto em ferramentas
de BI como Power BI.

Estrutura:

         Dim_Cliente
              |
Dim_Produto — Fato_Vendas — Dim_Data
              |
        Dim_Localidade

Princípio desta camada:
Nunca recriar tabelas, nunca apagar histórico. Toda carga é
incremental: só insere dimensão nova ou venda nova, usando
MERGE para evitar duplicidade mesmo com execuções simultâneas.

Ordem de execução OBRIGATÓRIA:
1º Schema Gold
2º Todas as dimensões (qualquer ordem entre elas)
3º Fato_Vendas (sempre por último — depende das FKs das dims)
=========================================================
*/


-- =========================================================
-- ETAPA 1 — CRIAÇÃO DO SCHEMA
-- =========================================================

IF NOT EXISTS (
    SELECT 1
    FROM sys.schemas
    WHERE name = 'Gold'
)
BEGIN
    EXEC('CREATE SCHEMA Gold');
END;


-- =========================================================
-- ETAPA 2 — TABELA Gold.Dim_Cliente
-- =========================================================

-- Dimensão de clientes: 1 linha por Customer_ID.
IF OBJECT_ID('Gold.Dim_Cliente', 'U') IS NULL
BEGIN
    CREATE TABLE Gold.Dim_Cliente (

        -- Surrogate key: PK técnica, usada como FK na Fato.
        -- Mais rápida e mais leve que usar Customer_ID (texto)
        -- diretamente nos joins da Fato.
        Customer_SK     INT IDENTITY(1,1) PRIMARY KEY,

        -- Chave natural, vinda da Silver já tratada contra nulos.
        -- UNIQUE garante 1 linha por cliente — sem isso, um
        -- Customer_ID duplicado não quebraria o INSERT, mas
        -- duplicaria as vendas desse cliente nos JOINs da Fato.
        Customer_ID     NVARCHAR(50)  NOT NULL UNIQUE,

        Customer_Name   NVARCHAR(150) NOT NULL,
        Segment         NVARCHAR(50)  NOT NULL
    );
END;

-- Carga incremental: insere só clientes que ainda não existem
-- na dimensão. MERGE garante atomicidade — se duas cargas
-- rodarem próximas uma da outra, não duplicam o mesmo cliente.
MERGE Gold.Dim_Cliente AS target
USING (
    -- GROUP BY colapsa o histórico de transações da Silver em
    -- 1 linha por cliente. MAX() pega o valor mais recente
    -- encontrado entre as repetições (já que todos os valores
    -- de um mesmo Customer_ID deveriam ser iguais; MAX() é só
    -- uma forma segura de escolher um quando há variação).
    SELECT
        Customer_ID,
        MAX(Customer_Name) AS Customer_Name,
        MAX(Segment)       AS Segment
    FROM Silver.SuperStore
    GROUP BY Customer_ID
) AS source
ON target.Customer_ID = source.Customer_ID
WHEN NOT MATCHED BY TARGET THEN
    INSERT (Customer_ID, Customer_Name, Segment)
    VALUES (source.Customer_ID, source.Customer_Name, source.Segment);


-- =========================================================
-- ETAPA 3 — TABELA Gold.Dim_Produto
-- =========================================================

IF OBJECT_ID('Gold.Dim_Produto', 'U') IS NULL
BEGIN
    CREATE TABLE Gold.Dim_Produto (
        Product_SK      INT IDENTITY(1,1) PRIMARY KEY,
        Product_ID      NVARCHAR(50)  NOT NULL UNIQUE,
        Category        NVARCHAR(150) NOT NULL,
        Sub_Category    NVARCHAR(150) NOT NULL,
        Product_Name    NVARCHAR(250) NOT NULL
    );
END;

MERGE Gold.Dim_Produto AS target
USING (
    SELECT
        Product_ID,
        MAX(Category)     AS Category,
        MAX(Sub_Category) AS Sub_Category,
        MAX(Product_Name) AS Product_Name
    FROM Silver.SuperStore
    GROUP BY Product_ID
) AS source
ON target.Product_ID = source.Product_ID
WHEN NOT MATCHED BY TARGET THEN
    INSERT (Product_ID, Category, Sub_Category, Product_Name)
    VALUES (source.Product_ID, source.Category, source.Sub_Category, source.Product_Name);


-- =========================================================
-- ETAPA 4 — TABELA Gold.Dim_Localidade
-- =========================================================

-- Diferente das outras dimensões, não existe um ID único de
-- localidade vindo da origem — a unicidade só existe na
-- combinação completa dos campos geográficos.
IF OBJECT_ID('Gold.Dim_Localidade', 'U') IS NULL
BEGIN
    CREATE TABLE Gold.Dim_Localidade (
        Localidade_SK   INT IDENTITY(1,1) PRIMARY KEY,
        Country         NVARCHAR(50) NOT NULL,
        City            NVARCHAR(50) NOT NULL,
        State           NVARCHAR(50) NOT NULL,
        Postal_Code     NVARCHAR(20) NOT NULL,
        Region          NVARCHAR(50) NOT NULL,

        -- Garante 1 linha por combinação geográfica completa.
        CONSTRAINT UQ_Dim_Localidade UNIQUE (Country, State, City, Postal_Code)
    );
END;

MERGE Gold.Dim_Localidade AS target
USING (
    -- DISTINCT em vez de GROUP BY aqui: como a chave é a
    -- combinação dos 5 campos (não um ID único), não há
    -- atributo "extra" para agregar com MAX() — só precisamos
    -- das combinações distintas que já existem na Silver.
    SELECT DISTINCT
        Country, City, State, Postal_Code, Region
    FROM Silver.SuperStore
) AS source
ON  target.Country     = source.Country
AND target.City         = source.City
AND target.State        = source.State
AND target.Postal_Code  = source.Postal_Code
WHEN NOT MATCHED BY TARGET THEN
    INSERT (Country, City, State, Postal_Code, Region)
    VALUES (source.Country, source.City, source.State, source.Postal_Code, source.Region);


-- =========================================================
-- ETAPA 5 — TABELA Gold.Dim_Data
-- =========================================================

-- Dimensão de calendário enxuta — só as datas brutas. Os
-- atributos derivados (ano, mês, trimestre, dia da semana,
-- tempo de entrega) são calculados no Power BI via DAX, não
-- aqui — assim, se a regra de negócio mudar, ajusta-se a
-- medida no BI sem precisar reprocessar o pipeline inteiro.
IF OBJECT_ID('Gold.Dim_Data', 'U') IS NULL
BEGIN
    CREATE TABLE Gold.Dim_Data (
        Data_SK     INT IDENTITY(1,1) PRIMARY KEY,

        -- Order_Date é NOT NULL: todo pedido obrigatoriamente
        -- tem data de criação — não existe pedido sem ela.
        Order_Date  DATE NOT NULL,

        -- Ship_Date é NULL: pedido pode ainda estar em aberto,
        -- sem entrega — não é dado faltante, é estado de negócio.
        Ship_Date   DATE NULL,

        -- Garante 1 linha por combinação de Order_Date + Ship_Date.
        CONSTRAINT UQ_Dim_Data UNIQUE (Order_Date, Ship_Date)
    );
END;

MERGE Gold.Dim_Data AS target
USING (
    SELECT DISTINCT
        Order_Date, Ship_Date
    FROM Silver.SuperStore
    -- Order_Date NULL não pode entrar na Dim_Data, já que a
    -- coluna lá é NOT NULL — filtramos aqui antes de tentar.
    -- Linhas com Order_Date NULL ficam de fora da Gold até
    -- alguém investigar por que a data não veio preenchida.
    WHERE Order_Date IS NOT NULL
) AS source

-- Comparação de Ship_Date precisa do tratamento de NULL: como
-- NULL nunca é igual a NULL em SQL, um "=" simples perderia
-- pedidos em aberto. O OR cobre o caso de ambos serem NULL.
ON  target.Order_Date = source.Order_Date
AND (
        target.Ship_Date = source.Ship_Date
        OR (target.Ship_Date IS NULL AND source.Ship_Date IS NULL)
    )
WHEN NOT MATCHED BY TARGET THEN
    INSERT (Order_Date, Ship_Date)
    VALUES (source.Order_Date, source.Ship_Date);


-- =========================================================
-- ETAPA 6 — TABELA Gold.Fato_Vendas
-- =========================================================

-- Tabela fato no modelo estrela: 1 linha por venda (Row_ID).
-- Guarda só chaves estrangeiras (apontando para as dimensões)
-- e métricas numéricas — nenhum atributo descritivo é repetido
-- aqui, isso já mora nas dimensões.
IF OBJECT_ID('Gold.Fato_Vendas', 'U') IS NULL
BEGIN
    CREATE TABLE Gold.Fato_Vendas (

        Fato_SK         BIGINT IDENTITY(1,1) PRIMARY KEY,

        -- Chave de rastreabilidade com a Silver — não é FK de
        -- dimensão, é só para auditoria (de qual linha da
        -- Silver essa venda veio). UNIQUE garante que a mesma
        -- linha da Silver nunca gera duas linhas na Fato.
        Row_ID          INT NOT NULL UNIQUE,

        -- REFERENCES cria uma Foreign Key: o banco passa a
        -- EXIGIR que todo valor inserido aqui já exista na
        -- coluna referenciada da dimensão correspondente. Sem
        -- isso, seria possível inserir um Customer_SK que não
        -- existe em Dim_Cliente, e o JOIN no relatório
        -- simplesmente não encontraria nada — um erro
        -- silencioso. Com REFERENCES, o INSERT é recusado na
        -- hora, denunciando o problema imediatamente.
        --
        -- NOT NULL é regra de negócio: toda venda tem cliente,
        -- produto, localidade e data — não existe linha de
        -- fato "órfã".
        Customer_SK     INT NOT NULL REFERENCES Gold.Dim_Cliente(Customer_SK),
        Product_SK      INT NOT NULL REFERENCES Gold.Dim_Produto(Product_SK),
        Localidade_SK   INT NOT NULL REFERENCES Gold.Dim_Localidade(Localidade_SK),
        Data_SK         INT NOT NULL REFERENCES Gold.Dim_Data(Data_SK),

        -- Atributo de transação — não vira dimensão própria por
        -- ter poucos valores possíveis (baixa cardinalidade).
        Ship_Mode       NVARCHAR(50) NOT NULL,

        -- Métricas — base para SUM/AVG nos relatórios de BI.
        -- NOT NULL porque toda venda tem valor, quantidade,
        -- desconto e lucro registrados (mesmo que seja 0, não
        -- pode ser ausente — a Silver já garante isso).
        Sales           DECIMAL(18,2) NOT NULL,
        Quantity        INT           NOT NULL,
        Discount        DECIMAL(5,2)  NOT NULL,
        Profit          DECIMAL(18,2) NOT NULL
    );
END;

-- Carga incremental da Fato: busca, para cada linha nova da
-- Silver, a surrogate key correspondente em cada dimensão.
MERGE Gold.Fato_Vendas AS target
USING (
    SELECT
        s.Row_ID,
        dc.Customer_SK,
        dp.Product_SK,
        dl.Localidade_SK,
        dd.Data_SK,
        s.Ship_Mode,
        s.Sales,
        s.Quantity,
        s.Discount,
        s.Profit
    FROM Silver.SuperStore s

    -- INNER JOIN: a venda só entra na Fato se já existir nas 4
    -- dimensões. Por isso a ordem de execução deste arquivo
    -- importa — as dimensões (Etapas 2 a 5) sempre rodam antes
    -- desta carga.
    INNER JOIN Gold.Dim_Cliente    dc ON s.Customer_ID = dc.Customer_ID
    INNER JOIN Gold.Dim_Produto    dp ON s.Product_ID  = dp.Product_ID
    INNER JOIN Gold.Dim_Localidade dl ON s.Country = dl.Country
                                      AND s.State   = dl.State
                                      AND s.City    = dl.City
                                      AND s.Postal_Code = dl.Postal_Code
    INNER JOIN Gold.Dim_Data       dd ON s.Order_Date = dd.Order_Date
                                      AND (
                                              s.Ship_Date = dd.Ship_Date
                                              OR (s.Ship_Date IS NULL AND dd.Ship_Date IS NULL)
                                          )
) AS source
ON target.Row_ID = source.Row_ID
WHEN NOT MATCHED BY TARGET THEN
    INSERT (
        Row_ID, Customer_SK, Product_SK, Localidade_SK, Data_SK,
        Ship_Mode, Sales, Quantity, Discount, Profit
    )
    VALUES (
        source.Row_ID, source.Customer_SK, source.Product_SK, source.Localidade_SK, source.Data_SK,
        source.Ship_Mode, source.Sales, source.Quantity, source.Discount, source.Profit
    );


-- =========================================================
-- ETAPA 7 — ÍNDICES
-- =========================================================

-- Aceleram os JOINs que o Power BI vai fazer entre a Fato e
-- cada dimensão, toda vez que alguém abrir um relatório.

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Fato_Cliente')
    CREATE INDEX IX_Fato_Cliente ON Gold.Fato_Vendas(Customer_SK);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Fato_Produto')
    CREATE INDEX IX_Fato_Produto ON Gold.Fato_Vendas(Product_SK);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Fato_Localidade')
    CREATE INDEX IX_Fato_Localidade ON Gold.Fato_Vendas(Localidade_SK);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Fato_Data')
    CREATE INDEX IX_Fato_Data ON Gold.Fato_Vendas(Data_SK);


-- =========================================================
-- ETAPA 8 — VALIDAÇÃO
-- =========================================================

SELECT COUNT(*) AS Total_Fato        FROM Gold.Fato_Vendas;
SELECT COUNT(*) AS Total_Clientes    FROM Gold.Dim_Cliente;
SELECT COUNT(*) AS Total_Produtos    FROM Gold.Dim_Produto;
SELECT COUNT(*) AS Total_Localidades FROM Gold.Dim_Localidade;
SELECT COUNT(*) AS Total_Datas       FROM Gold.Dim_Data;