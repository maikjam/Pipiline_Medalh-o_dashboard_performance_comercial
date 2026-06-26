/*
1. Criar banco (se necessário)
↓
2. Criar schema bronze
↓
3. Criar tabela bronze
↓
4. Carregar dados
↓
5. Validar carga
↓
6. Registrar execução
*/


-- cria schema
CREATE SCHEMA Bronze;


-- cria tabela bronze para receber os dados 
CREATE TABLE Bronze.SuperStore_Raw(

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
Profit NVARCHAR(50),

-- registro de inserção de dados 
--controla carga 
_ingested_at    DATETIME DEFAULT GETDATE(),
-- controla origem 
_source_file    NVARCHAR(255)
);

--Carrega dados de forma que não sobreescreve e gera historico 
/*
Arquivo CSV (21 colunas)
↓
Tabela temporária (21 colunas)
↓
Validar leitura
↓
Inserir na Bronze
↓
Adicionar metadados
(_ingested_at / _source_file)
↓
Tabela Bronze final (23 colunas)
O BULK INSERT copia o arquivo coluna por coluna na ordem exata.
O BULK INSERT copia o arquivo coluna por coluna na ordem exata. 
Se a tabela tem mais colunas que o arquivo, ele trava porque 
não sabe inventar valores.
A solução é usar uma tabela temporária como ponte:
CSV (21 colunas)
      ↓ BULK INSERT
#Temp (21 colunas)  ← espelho exato do CSV
      ↓ INSERT SELECT
Bronze (23 colunas) ← dados + GETDATE() + 'superstore.csv'
*/
-- ocomando deve ser rodado juntos as  4 partes 
-- passo 1: tabela temporária (só as colunas do arquivo, sem metadados)
-- tabela virtual criada
CREATE TABLE #Temp_SuperStore(
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

-- passo 2: carrega o CSV na temp (sem metadados)

-- comando de carga de dados e inserir em massa para uma tabela 
BULK INSERT #Temp_SuperStore 
-- localiza conteudo a ser inserido  
FROM 'C:\Import\superstore.csv'
-- configura do carregamento dos dados 
WITH (
    FIRSTROW = 2,          -- pula o cabecalho
    FIELDTERMINATOR = ',', -- virgula separa colunas
    ROWTERMINATOR = '0x0d0a',  -- quebra de linha separa registros
    CODEPAGE = 'RAW',    -- carrega do jeito que esta o dado 
    FORMAT = 'CSV'         -- trata aspas automaticamente
);

-- passo 3: insere na Bronze já com os metadados
-- inserir dentro da tabela fisica os dados da temp virtual 
INSERT INTO Bronze.SuperStore_Raw
-- comando 
SELECT
-- todos os dados da #Temp 
    *,
    -- salva data da auterado
    GETDATE()                    AS _ingested_at,
    -- salva nome do arquivo da auterado
    'superstore.csv'             AS _source_file
-- tabela temporaria com os dados que serem inseridos na tabela fisica 
FROM #Temp_SuperStore AS t
-- verificação de nova inserir de dados 
WHERE NOT EXISTS (
    -- compara id se forem diferentes carrega novos dados 
    SELECT 1 FROM Bronze.SuperStore_Raw AS b
    WHERE t.Row_id = b.Row_id
)
;

-- passo 4: limpa a tabela temporária
DROP TABLE #Temp_SuperStore;

SELECT  * 
FROM Bronze.SuperStore_Raw


SELECT * FROM Bronze.SuperStore_Raw
WHERE Row_ID IN ('1', '2', '3');


-- =========================================================
-- Validação da carga Bronze
--
-- Objetivo:
-- Confirmar que o arquivo CSV foi carregado corretamente
-- na tabela Bronze.SuperStore_Raw.
-- =========================================================
/*
Na prática o fluxo é:

Abre o CSV no Excel ou editor de texto e conta as linhas
Roda a query 1 e compara
Olha o TOP 5 e o ORDER BY DESC e bate com o que você vê no arquivo
Confirma o intervalo de datas — se o dataset é de 2014 a 2017 e a 
query retornar isso, o arquivo certo foi carregado
*/

-- =========================================================
-- 1. Contagem total
--
-- Compare com o número de linhas do CSV.
-- Desconte o cabeçalho (header) se necessário.
--
-- Resultado esperado:
-- Total_Linhas = linhas do CSV - 1 (header)
-- =========================================================

SELECT COUNT(*) AS Total_Linhas
FROM Bronze.SuperStore_Raw;


-- =========================================================
-- 2. Primeiros registros
--
-- Confira visualmente se os dados batem com o início
-- do arquivo CSV.
-- =========================================================

SELECT TOP 5 *
FROM Bronze.SuperStore_Raw
ORDER BY Row_ID ASC;


-- =========================================================
-- 3. Últimos registros
--
-- Confira visualmente se os dados batem com o final
-- do arquivo CSV.
-- =========================================================

SELECT TOP 5 *
FROM Bronze.SuperStore_Raw
ORDER BY Row_ID DESC;


-- =========================================================
-- 4. Intervalo de datas
--
-- Confirma se o período dos dados corresponde
-- ao esperado para o arquivo carregado.
-- =========================================================

SELECT
    MIN(Order_Date) AS Data_Mais_Antiga,
    MAX(Order_Date) AS Data_Mais_Recente
FROM Bronze.SuperStore_Raw;


-- =========================================================
-- 5. Valores nulos por coluna
--
-- Detecta colunas que vieram vazias do CSV.
-- Pode indicar problema na leitura do arquivo
-- ou separador incorreto.
-- =========================================================

SELECT
    SUM(CASE WHEN Order_ID       IS NULL THEN 1 ELSE 0 END) AS Nulos_Order_ID,
    SUM(CASE WHEN Order_Date     IS NULL THEN 1 ELSE 0 END) AS Nulos_Order_Date,
    SUM(CASE WHEN Customer_ID    IS NULL THEN 1 ELSE 0 END) AS Nulos_Customer_ID,
    SUM(CASE WHEN Product_ID     IS NULL THEN 1 ELSE 0 END) AS Nulos_Product_ID,
    SUM(CASE WHEN Sales          IS NULL THEN 1 ELSE 0 END) AS Nulos_Sales,
    SUM(CASE WHEN Profit         IS NULL THEN 1 ELSE 0 END) AS Nulos_Profit
FROM Bronze.SuperStore_Raw;


