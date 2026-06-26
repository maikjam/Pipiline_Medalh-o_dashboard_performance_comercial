/*
=========================================================
CAMADA BRONZE — INGESTÃO DE DADOS
Versão preparada para cargas frequentes (hora a hora)
=========================================================

Objetivo:
Receber o dado exatamente como ele chega da origem,
sem aplicar nenhuma regra de negócio, limpeza ou conversão.

Princípio desta camada:
A Bronze NÃO trata dado. Ela só recebe, registra a origem,
registra o horário, e preserva histórico completo — inclusive
se o mesmo arquivo for carregado mais de uma vez no dia.

Fluxo:
Arquivo CSV → Tabela temporária (#Temp) → Bronze.SuperStore_Raw
=========================================================
*/


-- =========================================================
-- ETAPA 1 — CRIAÇÃO DO SCHEMA
-- =========================================================

-- Verifica se o schema 'Bronze' ainda não existe no banco.
-- Isso evita erro ao rodar o script várias vezes por dia —
-- CREATE SCHEMA falha se o schema já existir, então protegemos
-- com essa checagem antes.
IF NOT EXISTS (
    SELECT 1
    FROM sys.schemas        -- tabela interna do SQL Server com a lista de schemas
    WHERE name = 'Bronze'
)
BEGIN
    -- EXEC(...) roda o comando como texto dinâmico.
    -- Necessário aqui porque CREATE SCHEMA precisa ser o único
    -- comando do lote — não pode estar misturado com outros.
    EXEC('CREATE SCHEMA Bronze');
END;


-- =========================================================
-- ETAPA 2 — CRIAÇÃO DA TABELA BRONZE
-- =========================================================

-- Cria a tabela só se ela ainda não existir. Em produção, o
-- pipeline roda várias vezes ao dia — não podemos derrubar a
-- tabela (e o histórico acumulado) a cada execução.
IF OBJECT_ID('Bronze.SuperStore_Raw', 'U') IS NULL
BEGIN
    CREATE TABLE Bronze.SuperStore_Raw (

        -- 🔑 Identificação
        -- Tudo aqui é NVARCHAR de propósito: a Bronze guarda o
        -- dado bruto, sem se importar se é um número, uma data
        -- ou um texto. A conversão de tipo é trabalho da Silver.
        Row_ID          NVARCHAR(50),
        Order_ID        NVARCHAR(50),

        -- 📅 Datas — ainda como texto, podem vir em qualquer
        -- formato ou até inválidas; tratamos isso na Silver.
        Order_Date      NVARCHAR(50),
        Ship_Date       NVARCHAR(50),

        -- 🚚 Envio
        Ship_Mode       NVARCHAR(50),

        -- 👤 Cliente
        Customer_ID     NVARCHAR(50),
        Customer_Name   NVARCHAR(150),
        Segment         NVARCHAR(50),

        -- 🌎 Localidade
        Country         NVARCHAR(50),
        City            NVARCHAR(50),
        State           NVARCHAR(50),
        Postal_Code     NVARCHAR(50),
        Region          NVARCHAR(50),

        -- 📦 Produto
        Product_ID      NVARCHAR(50),
        Category        NVARCHAR(150),
        Sub_Category    NVARCHAR(150),
        Product_Name    NVARCHAR(250),

        -- 📊 Métricas — também como texto na Bronze. Um valor
        -- corrompido (ex: "12,34" em vez de "12.34") não pode
        -- travar a carga bruta; isso é resolvido na Silver com
        -- TRY_CONVERT.
        Sales           NVARCHAR(50),
        Quantity        NVARCHAR(50),
        Discount        NVARCHAR(50),
        Profit          NVARCHAR(50),

        -- 🕒 Metadados de carga — não vêm do CSV, são gerados
        -- pelo próprio processo de ingestão.

        -- Marca o momento exato em que a linha entrou na Bronze.
        -- DATETIME2 tem mais precisão que DATETIME — importante
        -- quando há múltiplas cargas na mesma hora.
        _ingested_at    DATETIME2 DEFAULT SYSDATETIME(),

        -- Nome do arquivo de origem — permite saber de qual CSV
        -- cada linha veio, útil para auditoria e troubleshooting.
        _source_file    NVARCHAR(255),

        -- Identificador único gerado por execução do pipeline.
        -- Diferente de _ingested_at (que é só um horário), o
        -- _load_id permite agrupar todas as linhas que entraram
        -- numa MESMA execução, mesmo que tenha durado vários
        -- segundos. Essencial para isolar o efeito de uma carga
        -- específica em caso de erro.
        _load_id        UNIQUEIDENTIFIER DEFAULT NEWID()
    );
END;


-- =========================================================
-- ETAPA 3 — TABELA TEMPORÁRIA (ESPELHO DO CSV)
-- =========================================================

-- O CSV tem 21 colunas; a Bronze tem 24 (21 + 3 metadados).
-- O BULK INSERT copia coluna por coluna na ordem exata do
-- arquivo — se a tabela de destino tiver colunas a mais, ele
-- não sabe o que fazer e falha. Por isso usamos uma tabela
-- temporária como "ponte": ela tem exatamente as mesmas 21
-- colunas do arquivo, nem uma a mais.
--
-- O prefixo "#" cria uma tabela temporária local — ela existe
-- só durante essa sessão e é apagada automaticamente ao final
-- (ou explicitamente na Etapa 6).
CREATE TABLE #Temp_SuperStore (
    Row_ID          NVARCHAR(50),
    Order_ID        NVARCHAR(50),
    Order_Date      NVARCHAR(50),
    Ship_Date       NVARCHAR(50),
    Ship_Mode       NVARCHAR(50),
    Customer_ID     NVARCHAR(50),
    Customer_Name   NVARCHAR(150),
    Segment         NVARCHAR(50),
    Country         NVARCHAR(50),
    City            NVARCHAR(50),
    State           NVARCHAR(50),
    Postal_Code     NVARCHAR(50),
    Region          NVARCHAR(50),
    Product_ID      NVARCHAR(50),
    Category        NVARCHAR(150),
    Sub_Category    NVARCHAR(150),
    Product_Name    NVARCHAR(250),
    Sales           NVARCHAR(50),
    Quantity        NVARCHAR(50),
    Discount        NVARCHAR(50),
    Profit          NVARCHAR(50)
);


-- =========================================================
-- ETAPA 4 — CARGA DO ARQUIVO (BULK INSERT)
-- =========================================================

-- BULK INSERT é o comando mais rápido do SQL Server para
-- carregar arquivos grandes — muito mais eficiente que fazer
-- INSERT linha a linha.
BULK INSERT #Temp_SuperStore
FROM 'C:\Import\superstore.csv'   -- caminho do arquivo de origem
WITH (
    FIRSTROW = 2,               -- pula a linha 1 (cabeçalho do CSV)
    FIELDTERMINATOR = ',',      -- vírgula separa as colunas
    ROWTERMINATOR = '0x0d0a',   -- \r\n separa as linhas (padrão Windows)
    FORMAT = 'CSV',             -- ativa o parser de CSV (trata aspas corretamente)
    CODEPAGE = 'RAW',           -- carrega os bytes como estão, sem reinterpretar

    -- TABLOCK aplica um bloqueio de tabela inteira durante a
    -- carga, em vez de bloquear linha por linha. Isso acelera
    -- bastante cargas grandes, ao custo de bloquear outras
    -- operações na #Temp_SuperStore durante a execução — não é
    -- um problema aqui porque a tabela é exclusiva dessa sessão.
    TABLOCK
);


-- =========================================================
-- ETAPA 5 — INSERÇÃO NA BRONZE (APPEND-ONLY)
-- =========================================================

-- IMPORTANTE: aqui NÃO existe nenhuma checagem de duplicidade
-- (nenhum WHERE NOT EXISTS). É uma decisão de design: a Bronze
-- é "append-only" — ela só recebe, nunca filtra, nunca decide
-- o que é novo ou repetido. Se o mesmo arquivo for carregado
-- duas vezes, as linhas aparecem duplicadas na Bronze de
-- propósito — isso é esperado e correto para essa camada.
--
-- Quem decide o que é "novo de verdade" é a Silver, na próxima
-- etapa do pipeline (usando _load_id e Row_ID).
INSERT INTO Bronze.SuperStore_Raw (
    Row_ID, Order_ID, Order_Date, Ship_Date, Ship_Mode,
    Customer_ID, Customer_Name, Segment,
    Country, City, State, Postal_Code, Region,
    Product_ID, Category, Sub_Category, Product_Name,
    Sales, Quantity, Discount, Profit,
    _source_file
    -- _ingested_at e _load_id não aparecem aqui de propósito:
    -- eles têm DEFAULT definido na tabela e são preenchidos
    -- automaticamente pelo SQL Server no momento do INSERT.
)
SELECT
    Row_ID, Order_ID, Order_Date, Ship_Date, Ship_Mode,
    Customer_ID, Customer_Name, Segment,
    Country, City, State, Postal_Code, Region,
    Product_ID, Category, Sub_Category, Product_Name,
    Sales, Quantity, Discount, Profit,
    'superstore.csv'   -- nome do arquivo fixado manualmente;
                        -- numa automação real, isso viria de um
                        -- parâmetro passado pelo orquestrador
                        -- (Airflow, Data Factory, etc.)
FROM #Temp_SuperStore;


-- =========================================================
-- ETAPA 6 — LIMPEZA DA TABELA TEMPORÁRIA
-- =========================================================

-- Libera a tabela temporária explicitamente. Embora ela seja
-- apagada sozinha ao fim da sessão, é boa prática derrubar
-- assim que não for mais necessária — libera memória mais cedo,
-- especialmente importante em cargas grandes e frequentes.
DROP TABLE #Temp_SuperStore;


-- =========================================================
-- ETAPA 7 — VALIDAÇÃO DA CARGA
-- =========================================================

-- Confirma quantas linhas existem ao todo na Bronze (soma de
-- TODAS as cargas já feitas, não só a de agora).
SELECT COUNT(*) AS Total_Registros
FROM Bronze.SuperStore_Raw;

-- Mostra as 5 linhas mais recentes, ordenando pelo horário de
-- ingestão — confirma visualmente que a carga de agora entrou.
SELECT TOP 5 *
FROM Bronze.SuperStore_Raw
ORDER BY _ingested_at DESC;


-- =========================================================
-- ETAPA 8 — ÍNDICES
-- =========================================================

-- Índices aceleram buscas e joins feitos pelas próximas camadas
-- (a Silver vai filtrar por _load_id e cruzar por Row_ID o
-- tempo todo). Criados apenas uma vez, protegidos por checagem
-- em sys.indexes — recriar um índice já existente causaria erro.

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes WHERE name = 'IX_Load'
)
    -- Acelera filtros e ordenações por data/hora de ingestão,
    -- como o "TOP 5 ORDER BY _ingested_at DESC" acima.
    CREATE INDEX IX_Load
    ON Bronze.SuperStore_Raw(_ingested_at);

IF NOT EXISTS (
    SELECT 1 FROM sys.indexes WHERE name = 'IX_Row'
)
    -- Acelera o JOIN que a Silver vai fazer entre Bronze e
    -- Silver comparando Row_ID — sem esse índice, cada carga
    -- incremental ficaria mais lenta conforme a Bronze cresce.
    CREATE INDEX IX_Row
    ON Bronze.SuperStore_Raw(Row_ID);