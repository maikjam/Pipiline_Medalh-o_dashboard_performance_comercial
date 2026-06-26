/*
└── Gold
    ├── Fato_Vendas
    ├── Dim_Cliente
    ├── Dim_Produto
    ├── Dim_Localizacao
    └── Dim_Data
*/
-- 1. Criar schema Gold
-- Verifica se NÃO existe um schema chamado 'Gold'
IF NOT EXISTS (
    -- Consulta os schemas existentes no banco
    SELECT *
    -- Tabela interna do SQL Server que armazena os schemas
    FROM sys.schemas
    -- Filtra procurando apenas o schema chamado Gold
    WHERE name = 'Gold'
)
-- Se não encontrar o schema Gold, executa a criação
EXEC('CREATE SCHEMA Gold');


-- ================================
-- TABELA Dim_Clientes
-- ================================

-- Objetivo:
-- Dimensão de clientes, com granularidade de 1 linha por
-- Customer_ID. Atributos descritivos para análises de venda
-- por segmento e por cliente.
-- =========================================================

-- 🛡️ Cria a tabela apenas se ela ainda não existir.
-- Diferente do DROP TABLE usado na Silver (que apaga e recria
-- toda vez), esse padrão nunca derruba dados já carregados —
-- se a tabela já existe, o bloco simplesmente não faz nada.
-- Padrão usado em produção, onde a Gold pode já estar
-- alimentando dashboards em uso.
IF OBJECT_ID('Gold.Dim_Clientes', 'U') IS NULL
BEGIN
    CREATE TABLE Gold.Dim_Clientes (

        -- 🔑 Surrogate key: PK técnica, usada como FK na Fact
        Customer_SK     INT IDENTITY(1,1) PRIMARY KEY,  

        -- 🔑 Chave natural (vinda da Silver, já tratada contra nulos).
        -- UNIQUE garante 1 linha por cliente na dimensão — sem isso,
        -- um Customer_ID duplicado não quebra o INSERT, mas duplica
        -- as vendas desse cliente nos JOINs com a Fact_Sales,
        -- inflando os números do relatório silenciosamente.
        Customer_ID     NVARCHAR(50) NOT NULL UNIQUE,

        Customer_Name   NVARCHAR(150),
        Segment         NVARCHAR(50)
    );
END;


-- ================================
-- TABELA Dim_Data
-- ================================

-- Objetivo:
-- Dimensão de calendário enxuta — apenas as datas brutas.
-- Atributos derivados (ano, mês, trimestre, dia da semana,
-- tempo de entrega) NÃO ficam aqui: serão calculados no
-- Power BI (DAX/Power Query), para facilitar ajustes se a
-- regra de negócio mudar, sem precisar reprocessar o ETL.
-- =========================================================

-- 🛡️ Cria a tabela apenas se ela ainda não existir.
-- Nunca derruba dados já carregados — se a tabela já existe,
-- o bloco simplesmente não faz nada.
IF OBJECT_ID('Gold.Dim_Data', 'U') IS NULL
BEGIN
    CREATE TABLE Gold.Dim_Data (

        -- 🔑 Surrogate key: PK técnica, usada como FK na Fact
        Data_SK     INT IDENTITY(1,1) PRIMARY KEY,

        -- 📅 Datas brutas, já tratadas/validadas na Silver.
        -- Order_Date é NOT NULL: todo pedido obrigatoriamente
        -- tem data de criação — não existe pedido sem ela.
        Order_Date  DATE NOT NULL,

        -- Ship_Date é NULL: pedido pode ainda estar em aberto,
        -- sem entrega — não é dado faltante, é estado de negócio.
        Ship_Date   DATE NULL,

        -- 🔒 Garante 1 linha por combinação de Order_Date + Ship_Date.
        -- Não impede repetição de cada data isolada (vários pedidos
        -- ocorrem no mesmo dia) — só proíbe a dupla exata se repetir.
        -- Segunda camada de proteção além do SELECT DISTINCT da carga.
        CONSTRAINT UQ_Dim_Data UNIQUE (Order_Date, Ship_Date)
    );
END;


-- ================================
-- TABELA Gold.Dim_Localidade
-- ================================

-- Objetivo:
-- Dimensão geográfica, agrupando Country, State, City,
-- Region e Postal_Code.
--
-- Observação sobre granularidade:
-- não existe ID único de localização vindo da origem — a
-- unicidade só existe na combinação completa dos campos.
-- =========================================================


-- 🛡️ Cria a tabela apenas se ela ainda não existir.
-- Nunca derruba dados já carregados — se a tabela já existe,
-- o bloco simplesmente não faz nada.
IF OBJECT_ID('Gold.Dim_Localidade', 'U') IS NULL
BEGIN
    CREATE TABLE Gold.Dim_Localidade (

        -- 🔑 Surrogate key: PK técnica, usada como FK na Fact
        Localidade_SK   INT IDENTITY(1,1) PRIMARY KEY,

        -- 📋 Atributos geográficos, já tratados na Silver.
        -- NOT NULL aqui não é tratamento de nulo — isso já foi feito
        -- na Silver. É o contrato da Gold reforçando essa garantia,
        -- caso algum dado entre nesta tabela por fora do pipeline
        -- Silver → Gold.
        Country         NVARCHAR(50) NOT NULL,
        City            NVARCHAR(50) NOT NULL,
        State           NVARCHAR(50) NOT NULL,
        Postal_Code     NVARCHAR(20) NOT NULL,
        Region          NVARCHAR(50) NOT NULL,

        -- 🔒 Garante 1 linha por combinação geográfica completa.
        -- Sem isso, a mesma localidade pode duplicar na dimensão
        -- e inflar os números nos JOINs com a Fact_Sales.
        CONSTRAINT UQ_Dim_Localidade UNIQUE (Country, State, City, Postal_Code)
    );
END;


-- ================================
-- TABELA Gold.Dim_Produto
-- ================================

-- Objetivo:
-- Dimensão de produtos, com granularidade de 1 linha por
-- Product_ID. Usada para análises de venda por categoria,
-- subcategoria e produto.
-- =========================================================

-- 🛡️ Cria a tabela apenas se ela ainda não existir.
-- Nunca derruba dados já carregados — se a tabela já existe,
-- o bloco simplesmente não faz nada.

IF OBJECT_ID('Gold.Dim_Produto', 'U') IS NULL
BEGIN
    CREATE TABLE Gold.Dim_Produto (

        -- 🔑 Surrogate key: PK técnica, usada como FK na Fact
        Product_SK      INT IDENTITY(1,1) PRIMARY KEY,

        -- 🔑 Chave natural (vinda da Silver, já tratada contra nulos).
        -- UNIQUE garante 1 linha por produto na dimensão — sem isso,
        -- um Product_ID duplicado não quebra o INSERT, mas duplica
        -- as vendas desse produto nos JOINs com a Fact_Sales,
        -- inflando os números do relatório silenciosamente.
        Product_ID      NVARCHAR(50)  NOT NULL UNIQUE,

        -- 📋 Atributos descritivos, já tratados na Silver.
        -- NOT NULL aqui não é tratamento de nulo — é o contrato da
        -- Gold reforçando essa garantia, caso algum dado entre nesta
        -- tabela por fora do pipeline Silver → Gold.
        Category        NVARCHAR(150) NOT NULL,
        Sub_Category    NVARCHAR(150) NOT NULL,
        Product_Name    NVARCHAR(250) NOT NULL
    );
END;

-- ================================
-- TABELA Gold.Fato_Vendas
-- ================================

-- Objetivo:
-- Tabela fato no modelo estrela, no grão de 1 linha por venda
-- (Row_ID). Conecta-se às dimensões via surrogate keys e
-- guarda apenas as métricas numéricas do negócio.
-- =========================================================

-- 🛡️ Cria a tabela apenas se ela ainda não existir.
-- Nunca derruba dados já carregados — se a tabela já existe,
-- o bloco simplesmente não faz nada.
IF OBJECT_ID('Gold.Fato_Vendas', 'U') IS NULL
BEGIN
    CREATE TABLE Gold.Fato_Vendas (

        -- 🔑 Chave técnica da própria fato
        Fato_SK         INT IDENTITY(1,1) PRIMARY KEY,

        -- 🔑 Chave de rastreabilidade com a Silver (não é FK de dimensão).
        -- Não tem REFERENCES porque não aponta para uma dimensão —
        -- serve só para auditoria, rastrear de qual linha da Silver
        -- essa venda veio.
        Row_ID          INT NOT NULL,

        -- 🔗 REFERENCES cria uma Foreign Key (chave estrangeira):
        -- o banco passa a EXIGIR que todo valor inserido aqui já
        -- exista na coluna referenciada da dimensão. Sem isso, seria
        -- possível inserir um Customer_SK = 9999 que não existe em
        -- Dim_Clientes, e o JOIN no relatório simplesmente não
        -- encontraria nada — um erro silencioso. Com REFERENCES,
        -- o INSERT é recusado na hora, denunciando o problema.
        --
        -- NOT NULL aqui é regra de negócio: toda venda tem que ter
        -- um cliente, um produto, uma localidade e uma data — não
        -- existe linha de fato "órfã", sem ligação com as dimensões.
        Customer_SK     INT NOT NULL REFERENCES Gold.Dim_Clientes(Customer_SK),
        Product_SK      INT NOT NULL REFERENCES Gold.Dim_Produto(Product_SK),
        Localidade_SK   INT NOT NULL REFERENCES Gold.Dim_Localidade(Localidade_SK),
        Data_SK         INT NOT NULL REFERENCES Gold.Dim_Data(Data_SK),

        -- 📦 Atributo de transação (não vira dimensão própria
        -- pois tem poucos valores possíveis e baixa cardinalidade).
        -- NOT NULL porque toda venda obrigatoriamente tem uma
        -- modalidade de envio definida.
        Ship_Mode       NVARCHAR(50) NOT NULL,

        -- 📊 Métricas — base para SUM/AVG nos relatórios de BI.
        -- NOT NULL porque toda venda tem, por definição, valor,
        -- quantidade, desconto e lucro registrados — mesmo que
        -- o valor seja 0, ele não pode ser ausente. A Silver já
        -- garante isso (COALESCE com TRY_CONVERT), então aqui é
        -- o contrato da Gold reforçando essa garantia.
        Sales           DECIMAL(18,2) NOT NULL,
        Quantity        INT           NOT NULL,
        Discount        DECIMAL(5,2)  NOT NULL,
        Profit          DECIMAL(18,2) NOT NULL
    );
END;


/*
=========================================================
CARGA GOLD — MODELO JÚNIOR (CORRIGIDO)
Origem: Silver.SuperStore
=========================================================

Fluxo:
1. Inserir Dim_Clientes
2. Inserir Dim_Produto
3. Inserir Dim_Localidade
4. Inserir Dim_Data
5. Inserir Fato_Vendas

Regra:
• Nunca apagar Gold
• Inserir apenas registros novos

CORREÇÃO APLICADA NESTA VERSÃO:
A Silver tem granularidade "1 linha por venda" — o mesmo
Product_ID (ou Customer_ID) pode aparecer várias vezes, e em
alguns casos a origem (CSV) tem inconsistência real: o mesmo
ID com um texto descritivo diferente (ex: o mesmo Product_ID
salvo com dois Product_Name distintos). Um SELECT DISTINCT
simples não resolve isso — ele mantém as duas variações como
linhas "diferentes", e o UNIQUE da Gold rejeita a segunda
tentativa de INSERT com erro de chave duplicada.
A correção é agrupar por ID (GROUP BY) e usar MAX() para
escolher um único valor entre as variações.
=========================================================
*/

BEGIN TRY

    BEGIN TRANSACTION;

    -- =====================================================
    -- DIM_CLIENTES
    -- =====================================================

    INSERT INTO Gold.Dim_Clientes (
        Customer_ID, Customer_Name, Segment
    )
    SELECT
        s.Customer_ID,

        -- MAX() em vez de simplesmente "s.Customer_Name": se o
        -- mesmo Customer_ID tiver nomes ligeiramente diferentes
        -- na Silver (espaço extra, digitação), o GROUP BY abaixo
        -- exige que toda coluna não agrupada use uma função de
        -- agregação — MAX() escolhe uma das variações.
        MAX(s.Customer_Name) AS Customer_Name,
        MAX(s.Segment)       AS Segment

    FROM Silver.SuperStore s
    WHERE NOT EXISTS (
        SELECT 1
        FROM Gold.Dim_Clientes d
        WHERE d.Customer_ID = s.Customer_ID
    )

    -- GROUP BY força "1 linha por cliente" no resultado do
    -- SELECT, mesmo que a Silver tenha o mesmo Customer_ID
    -- repetido em várias vendas (ou com pequenas variações de
    -- texto). Sem isso, voltaríamos a correr risco de duplicar.
    GROUP BY s.Customer_ID;


    -- =====================================================
    -- DIM_PRODUTO
    -- =====================================================

    -- Esse foi o bloco que travou com:
    -- "Violação da restrição UNIQUE KEY ... Dim_Produto"
    -- Causa confirmada: o Product_ID 'FUR-BO-10002213' tem dois
    -- Product_Name diferentes na Silver (inconsistência vinda
    -- da Bronze/CSV original). GROUP BY + MAX() resolve.
    INSERT INTO Gold.Dim_Produto (
        Product_ID, Category, Sub_Category, Product_Name
    )
    SELECT
        s.Product_ID,
        MAX(s.Category)     AS Category,
        MAX(s.Sub_Category) AS Sub_Category,
        MAX(s.Product_Name) AS Product_Name

    FROM Silver.SuperStore s
    WHERE NOT EXISTS (
        SELECT 1
        FROM Gold.Dim_Produto d
        WHERE d.Product_ID = s.Product_ID
    )
    GROUP BY s.Product_ID;


    -- =====================================================
    -- DIM_LOCALIDADE
    -- =====================================================

    -- Aqui o GROUP BY é pelos 4 campos que formam a chave
    -- composta (não existe um único ID de localidade). Como
    -- não sobra nenhuma coluna "de fora" do agrupamento além
    -- de Region, ela também entra como MAX() — protege contra
    -- o mesmo cenário de inconsistência de texto.
    INSERT INTO Gold.Dim_Localidade (
        Country, City, State, Postal_Code, Region
    )
    SELECT
        s.Country,
        s.City,
        s.State,
        s.Postal_Code,
        MAX(s.Region) AS Region

    FROM Silver.SuperStore s
    WHERE NOT EXISTS (
        SELECT 1
        FROM Gold.Dim_Localidade d
        WHERE d.Country     = s.Country
          AND d.City        = s.City
          AND d.State       = s.State
          AND d.Postal_Code = s.Postal_Code
    )
    GROUP BY s.Country, s.City, s.State, s.Postal_Code;


    -- =====================================================
    -- DIM_DATA
    -- =====================================================

    -- Aqui não precisa de GROUP BY/MAX(): a combinação completa
    -- de Order_Date + Ship_Date já é a própria chave (não há
    -- nenhuma outra coluna "descritiva" que possa variar para
    -- o mesmo par de datas). DISTINCT é suficiente.
    INSERT INTO Gold.Dim_Data (
        Order_Date, Ship_Date
    )
    SELECT DISTINCT
        s.Order_Date,
        s.Ship_Date

    FROM Silver.SuperStore s

    -- Order_Date é NOT NULL na Gold.Dim_Data — vendas com data
    -- de pedido ausente na Silver ficam de fora aqui (e,
    -- consequentemente, de fora da Fato_Vendas também).
    WHERE s.Order_Date IS NOT NULL
      AND NOT EXISTS (
          SELECT 1
          FROM Gold.Dim_Data d
          WHERE d.Order_Date = s.Order_Date

            -- ISNULL trata Ship_Date NULL (pedido ainda não
            -- enviado) como igual a outro Ship_Date NULL, já
            -- que NULL = NULL não funciona em SQL.
            AND ISNULL(d.Ship_Date, '19000101') = ISNULL(s.Ship_Date, '19000101')
      );


    -- =====================================================
    -- FATO_VENDAS
    -- =====================================================

    -- Sem GROUP BY aqui: a Fato é no grão de 1 linha por venda
    -- (Row_ID), que já é único na Silver (PRIMARY KEY). Não há
    -- risco de duplicidade de texto nesse nível — cada Row_ID
    -- aparece exatamente uma vez.
    INSERT INTO Gold.Fato_Vendas (
        Row_ID,
        Customer_SK, Product_SK, Localidade_SK, Data_SK,
        Ship_Mode,
        Sales, Quantity, Discount, Profit
    )
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
    -- dimensões. Vendas com Order_Date NULL não encontram
    -- correspondência em Dim_Data e ficam de fora aqui também
    -- — efeito em cadeia da decisão tomada na Dim_Data acima.
    INNER JOIN Gold.Dim_Clientes   dc ON s.Customer_ID = dc.Customer_ID
    INNER JOIN Gold.Dim_Produto    dp ON s.Product_ID  = dp.Product_ID
    INNER JOIN Gold.Dim_Localidade dl ON s.Country = dl.Country
                                      AND s.City    = dl.City
                                      AND s.State   = dl.State
                                      AND s.Postal_Code = dl.Postal_Code
    INNER JOIN Gold.Dim_Data       dd ON s.Order_Date = dd.Order_Date
                                      AND ISNULL(s.Ship_Date, '19000101') = ISNULL(dd.Ship_Date, '19000101')

    WHERE NOT EXISTS (
        SELECT 1
        FROM Gold.Fato_Vendas f
        WHERE f.Row_ID = s.Row_ID
    );

    COMMIT TRANSACTION;

END TRY
BEGIN CATCH

    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;

END CATCH;


-- =========================================================
-- VALIDAÇÃO
-- =========================================================

SELECT COUNT(*) AS Total_Clientes   FROM Gold.Dim_Clientes;
SELECT COUNT(*) AS Total_Produtos   FROM Gold.Dim_Produto;
SELECT COUNT(*) AS Total_Localidade FROM Gold.Dim_Localidade;
SELECT COUNT(*) AS Total_Data       FROM Gold.Dim_Data;
SELECT COUNT(*) AS Total_Fato       FROM Gold.Fato_Vendas;

-- =========================================================
-- DIAGNÓSTICO EXTRA — vendas descartadas por Order_Date NULL
--
-- Como essas vendas nunca entram na Fato (não há correspondência
-- em Dim_Data), é útil saber o tamanho desse descarte.
-- =========================================================

SELECT COUNT(*) AS Vendas_Sem_Order_Date
FROM Silver.SuperStore
WHERE Order_Date IS NULL;


-- Ver como a data realmente está armazenada na Bronze (texto puro)
SELECT TOP 20 Row_ID, Order_Date
FROM Bronze.SuperStore_Raw
ORDER BY Row_ID;




-- Validação de Integridade Referencial (Devem retornar 0)
SELECT COUNT(*) AS Orfãos_Cliente 
FROM Gold.Fato_Vendas f LEFT JOIN Gold.Dim_Clientes d ON f.Customer_SK = d.Customer_SK WHERE d.Customer_SK IS NULL;

SELECT COUNT(*) AS Orfãos_Produto 
FROM Gold.Fato_Vendas f LEFT JOIN Gold.Dim_Produto d ON f.Product_SK = d.Product_SK WHERE d.Product_SK IS NULL;


/* para postar no link din qdo tiver o dahs board

Projeto Acadêmico — Pipeline de Dados com Arquitetura Bronze → Silver → Gold (SQL Server)

Desenvolvimento de um pipeline ETL em SQL Server utilizando arquitetura em camadas (Bronze, Silver e Gold) para ingestão, tratamento e modelagem analítica de dados.

Atividades realizadas:
• Construção da camada Bronze para ingestão de arquivos CSV e rastreabilidade da origem dos dados
• Implementação da camada Silver com limpeza, padronização, conversão de tipos e deduplicação de registros
• Construção da camada Gold utilizando modelo estrela (Star Schema) com tabelas fato e dimensões
• Criação de regras de integridade com chaves primárias, estrangeiras e restrições UNIQUE
• Tratamento de datas com conversão de formatos regionais (MM/DD/YYYY → DATE)
• Estratégia incremental utilizando INSERT + NOT EXISTS
• Validação da qualidade dos dados entre camadas

Tecnologias:
SQL Server • ETL • Data Warehouse • Modelagem Dimensional • Star Schema • Power BI • SQL

Estrutura:
Bronze → Silver → Gold
CSV → Tratamento → Camada Analítica
*/