/*
===============================================================================
         DOCUMENTO DE DIRETRIZES — ESPELHO DO PIPELINE SIMPLES (NÍVEL 1)
===============================================================================
PROJETO: Pipeline Multicamadas SuperStore — Estudo Inicial Base
AUTOR: Engenharia de Dados
ESTRUTURA: Arquivos Nível Simples (Bronze, Silver, Gold e Dashboard)

OBJETIVO DO ARQUIVO:
Este ficheiro em formato de comentários SQL atua como o espelho absoluto dos 
teus scripts originais do Nível Simples e da demanda do Power BI. Ele traduz 
em conceitos de engenharia as decisões de carga total, validações estruturais 
e a entrega eficaz do modelo estrela inicial.
===============================================================================
*/

-- ===============================================================================
-- 🟫 1. CAMADA BRONZE (Ingestão de Dados — Versão Simples Base)
-- ===============================================================================

/*
[✓] ETAPA 1 — Criar Schema Bronze
-------------------------------------------------------------------------------
* Decisão no Código Simples:* Execução do comando direto 'CREATE SCHEMA Bronze;'.
* Justificativa:* Define a separação lógica inicial do ambiente. Cria uma pasta 
específica para armazenar as tabelas de origem, isolando o dado bruto do resto do banco.

[✓] ETAPA 2 — Criar Tabela Raw para Receber os Dados
-------------------------------------------------------------------------------
* Decisão no Código Simples:* Criação da tabela 'Bronze.SuperStore_Raw' definindo 
todas as 21 colunas de negócio (de Row_ID até Profit) estritamente como NVARCHAR.
* Justificativa:* Aplicação do princípio de que a Bronze não trata dados. Ao tipar 
tudo como texto (NVARCHAR), garantimos que o banco de dados não rejeite nenhuma 
linha se o arquivo CSV contiver erros de digitação, falhas de formatação ou nulos.

[✓] ETAPA 3 — Definir Metadados de Controlo de Carga e Origem
-------------------------------------------------------------------------------
* Decisão no Código Simples:* Inclusão das colunas '_ingested_at' com o valor padrão 
'GETDATE()' e '_source_file' NVARCHAR(255).
* Justificativa:* Garante a rastreabilidade da carga no portfólio. Permite saber 
exatamente o momento em que o script rodou e a origem do arquivo, gerando histórico 
cumulativo (sem sobrescrever) para fins de auditoria visual.

[✓] ETAPA 4 — Carregar Dados via BULK INSERT
-------------------------------------------------------------------------------
* Decisão no Código Simples:* Uso do comando BULK INSERT apontando diretamente 
para a tabela 'Bronze.SuperStore_Raw'.
* Justificativa:* É a forma nativa mais rápida de carregar um arquivo plano (CSV) 
para o SQL Server, permitindo mapear o delimitador e ler as linhas eficientemente.

[✓] ETAPA 5 — Validar Carga e Análise Inicial de Qualidade
-------------------------------------------------------------------------------
* Decisão no Código Simples:* Execução de queries de contagem total (COUNT), amostragem 
(TOP 5) ordenada por 'Row_ID ASC' e 'Row_ID DESC', intervalo de datas (MIN/MAX) e a 
query de soma de CASE WHEN para detetar valores nulos por coluna.
* Justificativa:* Auditoria manual essencial do Nível Simples. A verificação do 
intervalo de datas e a contagem de nulos servem para conferir visualmente se o 
separador do CSV foi interpretado corretamente pelo banco e se os dados estão completos.
*/


-- ===============================================================================
-- ⬜ 2. CAMADA SILVER (Tratamento, Correção Regional e Deduplicação)
-- ===============================================================================

/*
[✓] ETAPA 1 e 2 — Criar Schema e Tabela com Definição de Estrutura Final
-------------------------------------------------------------------------------
* Decisão no Código Simples:* Validação do Schema Silver e criação da tabela 
'Silver.SuperStore' com campos rigorosos (Row_ID INT, Order_Date DATE, Sales DECIMAL, etc.).
* Justificativa:* Estabelece os tipos de dados reais que o negócio necessita. Campos 
como 'Row_ID', 'Order_ID', 'Customer_ID' e 'Product_ID' são marcados como NOT NULL 
porque são os pilares de segurança e integridade do registro.

[✓] ETAPA 3 — Estratégia de Limpeza via DROP TABLE
-------------------------------------------------------------------------------
* Decisão no Código Simples:* Uso do comando 'DROP TABLE Silver.SuperStore' no início 
do bloco de processamento (ou TRUNCATE na estrutura de reexecução).
* Justificativa:* Decisão clássica de um ambiente de desenvolvimento/estudo inicial. Como 
o foco está em testar as regras de transformação e garantir que a query rode sem erros, 
limpar a tabela evita conflitos de chaves primárias enquanto ajustamos os tratamentos de texto.

[✓] ETAPA 4 — Remoção de Duplicados Baseada na Chave de Negócio Ampla
-------------------------------------------------------------------------------
* Decisão no Código Simples:* Criação de uma CTE 'Bronze_Deduplicada' utilizando a 
função 'ROW_NUMBER() OVER(PARTITION BY Order_ID, Product_ID, Customer_ID ORDER BY Row_ID)'.
* Justificativa:* O código identifica e remove registros repetidos com base no conjunto 
do pedido, garantindo a unicidade do dado. O filtro final 'WHERE rn = 1' assegura que 
apenas uma ocorrência válida seja inserida na Silver.

[✓] ETAPA 5 — Conversão de Tipos Regionalizada e Tratamento de Nulos
-------------------------------------------------------------------------------
* Decisão no Código Simples:* Uso de 'TRY_CONVERT(DATE, Order_Date, 101)' (Estilo 101 - USA) 
e 'TRY_CAST' combinado com 'COALESCE' e 'NULLIF(TRIM(...), '')' para campos de texto e métricas.
* Justificativa:* Resolve problemas críticos de arquivos vindos do exterior. O estilo 101 
corrige o formato de data americano (MM/DD/YYYY) que costuma falhar em servidores em português. 
O 'TRIM' limpa os espaços, o 'UPPER' padroniza categorias em caixa alta, e o 'COALESCE' 
mascara nulos textuais como 'UNKNOWN' e métricas numéricas como 0, blindando a qualidade do dado.

[✓] ETAPA 6 — Prova de Deduplicação e Validação Extra de Datas
-------------------------------------------------------------------------------
* Decisão no Código Simples:* Consultas cruzadas comparando o volume da Bronze versus Silver, 
uma query com 'HAVING COUNT(*) > 1' para mapear as duplicidades tratadas e a contagem de 
'Order_Date IS NULL' (que deve resultar em zero).
* Justificativa:* Validação matemática rigorosa do analista. Prova que a conversão regional 
de data funcionou perfeitamente e que a diferença de linhas entre as camadas corresponde 
exatamente à quantidade de lixo e duplicados eliminados.
*/


-- ===============================================================================
-- 🟨 3. CAMADA GOLD (Modelagem Dimensional Star Schema Base)
-- ===============================================================================

/*
[✓] ETAPA 1 — Criação do Schema Gold Analítico
-------------------------------------------------------------------------------
* Decisão no Código Simples:* Validação e criação do isolamento lógico 'Gold' via SQL Dinâmico.
* Justificativa:* Garante que a estrutura dimensional focada em Business Intelligence 
fique totalmente separada das transformações operacionais das camadas anteriores.

[✓] ETAPA 2 — Identificar Dimensões e Criar Chaves Substitutas (Surrogate Keys)
-------------------------------------------------------------------------------
* Decisão no Código Simples:* Criação de 'Gold.Dim_Clientes', 'Gold.Dim_Produto' e 
'Gold.Dim_Data' utilizando chaves numéricas primárias com 'IDENTITY(1,1)'.
* Justificativa:* Substitui as chaves textuais de negócio por inteiros sequenciais (INT). 
Isto acelera a velocidade dos JOINs e otimiza a compressão de memória do banco de dados.

[✓] ETAPA 3 — Carga das Dimensões com Consolidação (GROUP BY)
-------------------------------------------------------------------------------
* Decisão no Código Simples:* Uso de 'GROUP BY' combinado com 'MAX()' nas colunas textuais 
para preencher as tabelas 'Dim_Clientes' e 'Dim_Produto'.
* Justificativa:* Como a Silver possui registros transacionais (o mesmo cliente aparece 
várias vezes), o agrupamento condensa os dados para respeitar a granularidade analítica 
estrita de **1 linha única por entidade**, evitando a replicação de IDs.

[✓] ETAPA 4 — Criação da Tabela Fato Centralizadora
-------------------------------------------------------------------------------
* Decisão no Código Simples:* Criação de 'Gold.Fato_Vendas' contendo chaves estrangeiras 
(SKs), a chave de integridade 'Row_ID INT NOT NULL' e as métricas numéricas puras.
* Justificativa:* Desenha o Star Schema perfeito exigido no mercado. A Fato guarda 
apenas os ponteiros numéricos das dimensões e os valores agregáveis (Sales, Profit, Quantity).

[✓] ETAPA 5 — Preenchimento da Fato com o De-Para de Chaves
-------------------------------------------------------------------------------
* Decisão no Código Simples:* Uso de 'INNER JOINs' entre a Silver e as Dimensões Gold, 
conectando os IDs de negócio para extrair as respectivas Surrogate Keys (SK).
* Justificativa:* Conecta as pontas do modelo em estrela. Garante que a fato aponte 
estritamente para os códigos numéricos gerados nas dimensões, preparando o modelo para o BI.

[✓] ETAPA 6 — Validação de Integridade Referencial (Busca por Órfãos)
-------------------------------------------------------------------------------
* Decisão no Código Simples:* Queries utilizando 'LEFT JOIN' entre a Fato e as Dimensões, 
filtrando onde a chave da dimensão resulta em 'NULL'.
* Justificativa:* Garante o critério de aceite da Gold. Se o resultado for 0 linhas órfãs, 
significa que o relacionamento está perfeito e que nenhuma venda ficou sem cliente ou produto.
*/


-- ===============================================================================
-- 🟦 4. CAMADA BI / POWER BI (Dashboard de Vendas de Página Única)
-- ===============================================================================

/*
[✓] CONEXÃO E MODELO — Consumo Direto da Camada Gold
-------------------------------------------------------------------------------
* Decisão na Demanda:* Importar as tabelas Gold para o Power BI e conferir os 
relacionamentos de 1 para Muitos (1:*) partindo das Dimensões para a Fato pelas SKs.
* Justificativa:* Garante o desempenho e evita filtros ambíguos. O motor em memória 
(VertiPaq) trabalha de forma otimizada com chaves inteiras, deixando as interações rápidas.

[✓] CONFIGURAÇÃO DA DIM_DATA — Inteligência de Tempo Eficaz
-------------------------------------------------------------------------------
* Decisão na Demanda:* Marcar 'Dim_Data' como tabela de datas oficial e criar nela as 
colunas derivadas (Ano, Mês, Trimestre) e a regra de "Tempo de Entrega".
* Justificativa:* Segue as boas práticas de modelagem dimensional. Desativa as tabelas 
ocultas do Power BI (reduzindo o tamanho do arquivo) e centraliza os atributos de tempo 
como colunas físicas para poupar escrita de medidas DAX complexas.

[✓] GOVERNANÇA DE MÉTRICAS — Tabela Dedicada de Medidas DAX
-------------------------------------------------------------------------------
* Decisão na Demanda:* Criação da tabela '_Medidas' contendo fórmulas explícitas: 
Total Vendas (SUM), Total Lucro (SUM), Total Pedidos (COUNTROWS), Margem % e Ticket Médio (DIVIDE).
* Justificativa:* Centralizar as fórmulas organiza o projeto. O uso da função 'DIVIDE' 
é uma decisão de segurança que blinda os cartões e gráficos contra o erro matemático 
de divisão por zero, exibindo um espaço vazio (BLANK) limpo e amigável na tela.

[✓] DESIGN E VISUAIS — Construção do Storytelling de Dados
-------------------------------------------------------------------------------
* Decisão na Demanda:*
  - Plano de Fundo Estruturado: Organiza e delimita as áreas visuais da página única.
  - 4 KPI Cards no topo: Resumem os macroindicadores essenciais para o Diretor Comercial.
  - Linha do Tempo (Vendas por Mês): Demonstra a tendência e sazonalidade histórica.
  - Barras Horizontais (Categoria e Segmento): Facilitam a leitura de rótulos de texto longos.
  - Mapa (Estado) e Tabela (Top 10 Produtos): Fornecem o detalhe geográfico e cirúrgico do lucro.
  - Slicers (Ano/Trimestre, Região, Categoria): Dão total autonomia de filtro ao utilizador.
* Justificativa:* Cumpre o critério de aceite do portfólio. Não é apenas jogar gráficos na tela; 
o layout guia os olhos do utilizador desde a visão geral (KPIs macros) até ao detalhe máximo (Tabela).
*/

-- ===============================================================================
-- FIM DO DOCUMENTO ESPELHO — NÍVEL SIMPLES COMPLETO
-- ===============================================================================