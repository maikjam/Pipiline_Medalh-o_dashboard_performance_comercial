

-- versão nova pra ser revisada 
/*
=========================================================
CAMADA SILVER — TRATAMENTO E PADRONIZAÇÃO
(VERSÃO ESCALÁVEL)
=========================================================

Objetivo:
Transformar dados brutos da Bronze em dados consistentes.

Cenário:
• milhões de linhas
• múltiplas cargas por dia
• reprocessamento parcial
• atualização incremental

Princípio:

Bronze
→ guarda tudo

Silver
→ limpa
→ converte
→ remove duplicidade

Importante:
A Silver NÃO será recriada.

Não usamos:
✗ DROP
✗ TRUNCATE

Usamos:
✓ INSERT incremental
✓ anti-join
✓ processamento por carga

Fluxo:

Bronze
↓
Filtrar nova carga
↓
Tratar
↓
Deduplicar
↓
Inserir Silver

=========================================================
*/


/*=========================================================
ETAPA 1 — CRIAR SCHEMA
=========================================================*/

IF NOT EXISTS(

SELECT 1
FROM sys.schemas
WHERE name='Silver'

)

BEGIN

EXEC('CREATE SCHEMA Silver');

END;


/*=========================================================
ETAPA 2 — CRIAR TABELA
(cria apenas uma vez)
=========================================================*/

IF OBJECT_ID('Silver.SuperStore','U') IS NULL

BEGIN

CREATE TABLE Silver.SuperStore(

Row_ID INT PRIMARY KEY,

Order_ID NVARCHAR(50) NOT NULL,
Customer_ID NVARCHAR(50) NOT NULL,
Product_ID NVARCHAR(50) NOT NULL,

Order_Date DATE,
Ship_Date DATE,

Ship_Mode NVARCHAR(50),

Customer_Name NVARCHAR(150),
Segment NVARCHAR(50),

Country NVARCHAR(50),
City NVARCHAR(50),
State NVARCHAR(50),
Postal_Code NVARCHAR(20),
Region NVARCHAR(50),

Category NVARCHAR(150),
Sub_Category NVARCHAR(150),
Product_Name NVARCHAR(250),

Sales DECIMAL(18,2),
Quantity INT,
Discount DECIMAL(5,2),
Profit DECIMAL(18,2),

_processed_at DATETIME2
DEFAULT SYSDATETIME()

);

END;


/*=========================================================
ETAPA 3 — FILTRAR APENAS NOVOS REGISTROS

Objetivo:
Não reprocessar Bronze inteira.

Lógica:
Só carregar Row_ID que ainda não existe.
=========================================================*/

WITH Bronze_Nova AS(

SELECT

b.*

FROM Bronze.SuperStore_Raw b

LEFT JOIN Silver.SuperStore s

ON
TRY_CONVERT(INT,b.Row_ID)=s.Row_ID

WHERE s.Row_ID IS NULL

),


/*=========================================================
ETAPA 4 — DEDUPLICAÇÃO

Objetivo:
Eliminar registros repetidos.

Observação:
Executa apenas sobre carga nova.
=========================================================*/

Bronze_Deduplicada AS(

SELECT

*,

ROW_NUMBER() OVER(

PARTITION BY
Order_ID,
Product_ID,
Customer_ID

ORDER BY
TRY_CONVERT(INT,Row_ID)

) rn

FROM Bronze_Nova

)


/*=========================================================
ETAPA 5 — TRATAMENTO

Objetivo:
Converter e padronizar.
=========================================================*/

INSERT INTO Silver.SuperStore(

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

TRY_CONVERT(INT,Row_ID),

COALESCE(NULLIF(TRIM(Order_ID),''),'UNKNOWN'),

TRY_CONVERT(DATE,Order_Date),

TRY_CONVERT(DATE,Ship_Date),

COALESCE(NULLIF(TRIM(Ship_Mode),''),'UNKNOWN'),

COALESCE(NULLIF(TRIM(Customer_ID),''),'UNKNOWN'),

COALESCE(NULLIF(TRIM(Customer_Name),''),'UNKNOWN'),

UPPER(COALESCE(NULLIF(TRIM(Segment),''),'UNKNOWN')),

UPPER(COALESCE(NULLIF(TRIM(Country),''),'UNKNOWN')),

UPPER(COALESCE(NULLIF(TRIM(City),''),'UNKNOWN')),

UPPER(COALESCE(NULLIF(TRIM(State),''),'UNKNOWN')),

COALESCE(NULLIF(TRIM(Postal_Code),''),'UNKNOWN'),

UPPER(COALESCE(NULLIF(TRIM(Region),''),'UNKNOWN')),

COALESCE(NULLIF(TRIM(Product_ID),''),'UNKNOWN'),

UPPER(COALESCE(NULLIF(TRIM(Category),''),'UNKNOWN')),

UPPER(COALESCE(NULLIF(TRIM(Sub_Category),''),'UNKNOWN')),

COALESCE(NULLIF(TRIM(Product_Name),''),'UNKNOWN'),

COALESCE(
TRY_CONVERT(DECIMAL(18,2),Sales),
0
),

COALESCE(
TRY_CONVERT(INT,Quantity),
0
),

COALESCE(
TRY_CONVERT(DECIMAL(5,2),Discount),
0
),

COALESCE(
TRY_CONVERT(DECIMAL(18,2),Profit),
0
)

FROM Bronze_Deduplicada

WHERE rn=1;


/*=========================================================
ETAPA 6 — VALIDAÇÃO

Objetivo:
Confirmar carga.
=========================================================*/

SELECT
COUNT(*) Total_Silver
FROM Silver.SuperStore;


SELECT
TOP 10
*
FROM Silver.SuperStore
ORDER BY _processed_at DESC;


/*=========================================================
ETAPA 7 — ÍNDICES

Objetivo:
Acelerar carga e leitura.
=========================================================*/

IF NOT EXISTS(

SELECT 1
FROM sys.indexes
WHERE name='IX_Silver_Row'

)

CREATE INDEX IX_Silver_Row
ON Silver.SuperStore(Row_ID);


IF NOT EXISTS(

SELECT 1
FROM sys.indexes
WHERE name='IX_Silver_Customer'

)

CREATE INDEX IX_Silver_Customer
ON Silver.SuperStore(Customer_ID);

```