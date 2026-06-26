

-- versão nova pra ser revisada 

/*
=========================================================
CAMADA BRONZE — INGESTÃO DE DADOS (VERSÃO ESCALÁVEL)
=========================================================

Objetivo:
Receber dados exatamente como chegam da origem.

Cenário pensado:
• milhões de linhas
• dezenas de cargas por dia
• ambiente próximo de produção
• manter histórico completo

Princípio desta camada:
A Bronze NÃO trata dados.

O que ela faz:
✓ recebe
✓ registra origem
✓ registra horário
✓ preserva histórico

O que ela NÃO faz:
✗ deduplicação
✗ limpeza
✗ transformação
✗ regra de negócio

Fluxo:

Arquivo CSV
↓
Tabela temporária (#Temp)
↓
Bronze.SuperStore_Raw
↓
Validação
↓
Próxima camada (Silver)

=========================================================
*/


/*=========================================================
ETAPA 1 — CRIAÇÃO DO SCHEMA

Objetivo:
Criar o agrupador lógico Bronze.

Por que validar existência:
Em produção o pipeline executa diversas vezes.

Se tentar recriar:
CREATE SCHEMA falha.

Resultado:
Executa apenas uma vez.
=========================================================*/

IF NOT EXISTS (

    SELECT 1
    FROM sys.schemas
    WHERE name='Bronze'

)

BEGIN

EXEC('CREATE SCHEMA Bronze');

END;


/*=========================================================
ETAPA 2 — CRIAÇÃO DA TABELA BRONZE

Objetivo:
Criar tabela apenas se ainda não existir.

Decisão:
Não apagar tabela.

Motivo:
Preservar histórico.

Observação:
Todos os campos permanecem texto.

Por quê?
Bronze guarda dado bruto.

Tratamento acontece depois.
=========================================================*/

IF OBJECT_ID('Bronze.SuperStore_Raw','U') IS NULL

BEGIN

CREATE TABLE Bronze.SuperStore_Raw(

    -----------------------------------------------------
    -- IDENTIFICAÇÃO
    -----------------------------------------------------

    Row_ID NVARCHAR(50),
    Order_ID NVARCHAR(50),

    -----------------------------------------------------
    -- DATAS
    -----------------------------------------------------

    Order_Date NVARCHAR(50),
    Ship_Date NVARCHAR(50),

    -----------------------------------------------------
    -- ENVIO
    -----------------------------------------------------

    Ship_Mode NVARCHAR(50),

    -----------------------------------------------------
    -- CLIENTE
    -----------------------------------------------------

    Customer_ID NVARCHAR(50),
    Customer_Name NVARCHAR(150),
    Segment NVARCHAR(50),

    -----------------------------------------------------
    -- LOCALIDADE
    -----------------------------------------------------

    Country NVARCHAR(50),
    City NVARCHAR(50),
    State NVARCHAR(50),
    Postal_Code NVARCHAR(50),
    Region NVARCHAR(50),

    -----------------------------------------------------
    -- PRODUTO
    -----------------------------------------------------

    Product_ID NVARCHAR(50),
    Category NVARCHAR(150),
    Sub_Category NVARCHAR(150),
    Product_Name NVARCHAR(250),

    -----------------------------------------------------
    -- MÉTRICAS
    -----------------------------------------------------

    Sales NVARCHAR(50),
    Quantity NVARCHAR(50),
    Discount NVARCHAR(50),
    Profit NVARCHAR(50),

    -----------------------------------------------------
    -- METADADOS
    -----------------------------------------------------

    _ingested_at DATETIME2
    DEFAULT SYSDATETIME(),

    _source_file NVARCHAR(255),

    _load_id UNIQUEIDENTIFIER
    DEFAULT NEWID()

);

END;


/*=========================================================
ETAPA 3 — ÁREA TEMPORÁRIA

Objetivo:
Receber exatamente o formato do CSV.

Por que usar temp:
Bronze possui metadados extras.

Fluxo:
CSV
↓
Temp
↓
Bronze
=========================================================*/

CREATE TABLE #Temp_SuperStore(

Row_ID NVARCHAR(50),
Order_ID NVARCHAR(50),

Order_Date NVARCHAR(50),
Ship_Date NVARCHAR(50),

Ship_Mode NVARCHAR(50),

Customer_ID NVARCHAR(50),
Customer_Name NVARCHAR(150),
Segment NVARCHAR(50),

Country NVARCHAR(50),
City NVARCHAR(50),
State NVARCHAR(50),
Postal_Code NVARCHAR(50),
Region NVARCHAR(50),

Product_ID NVARCHAR(50),
Category NVARCHAR(150),
Sub_Category NVARCHAR(150),
Product_Name NVARCHAR(250),

Sales NVARCHAR(50),
Quantity NVARCHAR(50),
Discount NVARCHAR(50),
Profit NVARCHAR(50)

);


/*=========================================================
ETAPA 4 — BULK INSERT

Objetivo:
Carregar alto volume.

Decisão:
Usar TABLOCK.

Benefício:
Maior velocidade.

Importante:
Nenhum tratamento acontece aqui.
=========================================================*/

BULK INSERT #Temp_SuperStore

FROM 'C:\Import\superstore.csv'

WITH(

FIRSTROW=2,

FIELDTERMINATOR=',',

ROWTERMINATOR='0x0d0a',

FORMAT='CSV',

CODEPAGE='RAW',

TABLOCK

);


/*=========================================================
ETAPA 5 — INSERÇÃO NA BRONZE

Objetivo:
Persistir histórico.

Decisão:
APPEND ONLY.

Importante:
Não existe WHERE NOT EXISTS.

Duplicidade será tratada depois.
=========================================================*/

INSERT INTO Bronze.SuperStore_Raw(

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
Profit,

_source_file

)

SELECT

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
Profit,

'superstore.csv'

FROM #Temp_SuperStore;


/*=========================================================
ETAPA 6 — LIMPEZA

Objetivo:
Liberar memória.

Importante:
Apaga apenas temp.
=========================================================*/

DROP TABLE #Temp_SuperStore;


/*=========================================================
ETAPA 7 — VALIDAÇÃO

Objetivo:
Confirmar sucesso.

Sem consultas pesadas.
=========================================================*/

SELECT
COUNT(*) AS Total_Registros
FROM Bronze.SuperStore_Raw;


SELECT
TOP 5 *
FROM Bronze.SuperStore_Raw
ORDER BY _ingested_at DESC;


/*=========================================================
ETAPA 8 — ÍNDICES

Objetivo:
Melhorar busca.

Criados uma única vez.
=========================================================*/

IF NOT EXISTS(

SELECT 1
FROM sys.indexes
WHERE name='IX_Load'

)

CREATE INDEX IX_Load
ON Bronze.SuperStore_Raw(_ingested_at);


IF NOT EXISTS(

SELECT 1
FROM sys.indexes
WHERE name='IX_Row'

)

CREATE INDEX IX_Row
ON Bronze.SuperStore_Raw(Row_ID);

```
