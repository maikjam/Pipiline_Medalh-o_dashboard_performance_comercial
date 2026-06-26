

-- versão nova pra ser revisada 

/*=========================================================
GOLD — MODELO ESCALÁVEL
Objetivo:
Montar camada analítica sem recriar tabelas.

Princípios:
• Não apagar histórico
• Não usar TRUNCATE
• Inserir apenas novos registros
• Evitar duplicação
• JOIN rápido
=========================================================*/


/*=========================================================
CRIAR SCHEMA
=========================================================*/

IF NOT EXISTS (
SELECT 1
FROM sys.schemas
WHERE name='Gold'
)
EXEC('CREATE SCHEMA Gold');



/*=========================================================
DIM CLIENTE
1 linha por Customer_ID
=========================================================*/

IF OBJECT_ID('Gold.Dim_Cliente','U') IS NULL
BEGIN

CREATE TABLE Gold.Dim_Cliente(

Customer_SK INT IDENTITY(1,1),

Customer_ID NVARCHAR(50) NOT NULL,

Customer_Name NVARCHAR(150),

Segment NVARCHAR(50),

CONSTRAINT PK_DimCliente
PRIMARY KEY(Customer_SK),

CONSTRAINT UQ_DimCliente
UNIQUE(Customer_ID)

);

END;



/*=========================================================
CARGA INCREMENTAL CLIENTE

Carrega somente clientes novos
=========================================================*/

INSERT INTO Gold.Dim_Cliente(

Customer_ID,
Customer_Name,
Segment

)

SELECT

s.Customer_ID,
MAX(s.Customer_Name),
MAX(s.Segment)

FROM Silver.SuperStore s

LEFT JOIN Gold.Dim_Cliente d
ON s.Customer_ID=d.Customer_ID

WHERE d.Customer_ID IS NULL

GROUP BY
s.Customer_ID;



/*=========================================================
DIM PRODUTO
=========================================================*/

IF OBJECT_ID('Gold.Dim_Produto','U') IS NULL
BEGIN

CREATE TABLE Gold.Dim_Produto(

Product_SK INT IDENTITY(1,1),

Product_ID NVARCHAR(50),

Category NVARCHAR(150),

Sub_Category NVARCHAR(150),

Product_Name NVARCHAR(250),

CONSTRAINT PK_DimProduto
PRIMARY KEY(Product_SK),

CONSTRAINT UQ_DimProduto
UNIQUE(Product_ID)

);

END;



INSERT INTO Gold.Dim_Produto(

Product_ID,
Category,
Sub_Category,
Product_Name

)

SELECT

s.Product_ID,
MAX(s.Category),
MAX(s.Sub_Category),
MAX(s.Product_Name)

FROM Silver.SuperStore s

LEFT JOIN Gold.Dim_Produto p
ON s.Product_ID=p.Product_ID

WHERE p.Product_ID IS NULL

GROUP BY
s.Product_ID;



/*=========================================================
DIM DATA

1 linha por dia
=========================================================*/

IF OBJECT_ID('Gold.Dim_Data','U') IS NULL
BEGIN

CREATE TABLE Gold.Dim_Data(

Data_SK INT IDENTITY,

Data DATE UNIQUE,

PRIMARY KEY(Data_SK)

);

END;



INSERT INTO Gold.Dim_Data(Data)

SELECT DISTINCT
Order_Date

FROM Silver.SuperStore s

LEFT JOIN Gold.Dim_Data d
ON s.Order_Date=d.Data

WHERE d.Data IS NULL;



/*=========================================================
FATO VENDAS
=========================================================*/

IF OBJECT_ID('Gold.Fato_Vendas','U') IS NULL
BEGIN

CREATE TABLE Gold.Fato_Vendas(

Fato_SK BIGINT IDENTITY,

Row_ID INT NOT NULL UNIQUE,

Customer_SK INT,

Product_SK INT,

Data_SK INT,

Ship_Mode NVARCHAR(50),

Sales DECIMAL(18,2),

Quantity INT,

Discount DECIMAL(5,2),

Profit DECIMAL(18,2),

PRIMARY KEY(Fato_SK)

);

END;



/*=========================================================
INSERÇÃO INCREMENTAL FATO

Nunca duplica.
=========================================================*/

INSERT INTO Gold.Fato_Vendas(

Row_ID,
Customer_SK,
Product_SK,
Data_SK,
Ship_Mode,
Sales,
Quantity,
Discount,
Profit

)

SELECT

s.Row_ID,

c.Customer_SK,

p.Product_SK,

d.Data_SK,

s.Ship_Mode,

s.Sales,

s.Quantity,

s.Discount,

s.Profit

FROM Silver.SuperStore s

INNER JOIN Gold.Dim_Cliente c
ON s.Customer_ID=c.Customer_ID

INNER JOIN Gold.Dim_Produto p
ON s.Product_ID=p.Product_ID

INNER JOIN Gold.Dim_Data d
ON s.Order_Date=d.Data

LEFT JOIN Gold.Fato_Vendas f
ON s.Row_ID=f.Row_ID

WHERE f.Row_ID IS NULL;



/*=========================================================
ÍNDICES
Aceleram JOIN e filtros
=========================================================*/

CREATE INDEX IX_FATO_CLIENTE
ON Gold.Fato_Vendas(Customer_SK);

CREATE INDEX IX_FATO_PRODUTO
ON Gold.Fato_Vendas(Product_SK);

CREATE INDEX IX_FATO_DATA
ON Gold.Fato_Vendas(Data_SK);



/*=========================================================
VALIDAÇÃO
=========================================================*/

SELECT COUNT(*) Fato
FROM Gold.Fato_Vendas;

SELECT COUNT(*) Clientes
FROM Gold.Dim_Cliente;

SELECT COUNT(*) Produtos
FROM Gold.Dim_Produto;