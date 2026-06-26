/*
===============================================================================
       DOCUMENTO DE DIRETRIZES — ESPELHO DO PIPELINE DE PRODUÇÃO (NÍVEL 3)
===============================================================================
PROJETO: Pipeline Multicamadas Escalável SuperStore
AUTOR: Engenharia de Dados
ESTRUTURA: Arquivos de Produção Reais (Bronze, Silver, Gold e Dashboard)

OBJETIVO DO ARQUIVO:
Este arquivo em formato de comentários SQL é o espelho absoluto das queries e da 
demanda do Power BI desenvolvidas no projeto. Ele documenta a justificativa de 
cada etapa do código, provando o domínio sobre arquiteturas escaláveis de Big Data.
===============================================================================
*/

-- ===============================================================================
-- 🟫 1. CAMADA BRONZE (Ingestão de Dados — Versão Escalável)
-- ===============================================================================

/*
[✓] ETAPA 1 — Criar Schema
-------------------------------------------------------------------------------
* Decisão no Código:* Validação de existência usando "IF NOT EXISTS" na 'sys.schemas'.
* Justificativa:* Em ambiente de produção, o pipeline executa dezenas de vezes por dia. 
Se tentássemos rodar um 'CREATE SCHEMA' direto, o script falharia nas execuções seguintes. 
A validação garante idoneidade e continuidade ao fluxo.

[✓] ETAPA 2 — Criar Tabela Raw (Estrutura de Armazenamento)
-------------------------------------------------------------------------------
* Decisão no Código:* Uso de "IF OBJECT_ID" para checar a existência antes de criar a 
tabela 'Bronze.SuperStore_Raw'. Todas as colunas de negócio foram tipadas como NVARCHAR.
* Justificativa:* A Bronze segue o princípio de que NÃO trata dados. Ela aceita 100% dos 
registros brutos da origem. Se definíssemos tipos rígidos (como INT ou DATE) e o arquivo 
viesse corrompido, a carga seria rejeitada. A tipagem flexível impede a falha do pipeline.

[✓] ETAPA 2 — Definir Metadados de Ingestão e Auditoria
-------------------------------------------------------------------------------
* Decisão no Código:* Criação das colunas adicionais '_ingested_at' (DATETIME2), 
'_source_file' (NVARCHAR) e '_load_id' (UNIQUEIDENTIFIER com DEFAULT NEWID()).
* Justificativa:* Garante a rastreabilidade completa (Linhagem de Dados). O '_load_id' e 
o timestamp provam exatamente quando e em qual lote de execução aquela linha foi inserida, 
enquanto o '_source_file' identifica a origem física do arquivo caso seja necessária uma auditoria.

[✓] ETAPA 3 e 4 — Área Temporária (#Temp) e BULK INSERT de Alta Performance
-------------------------------------------------------------------------------
* Decisão no Código:* Criação de uma tabela temporária física (#Temp_SuperStore) para 
receber o comando BULK INSERT com a dica de tabela 'TABLOCK', 'FORMAT=CSV' e 'CODEPAGE=RAW'.
* Justificativa:* Cenário de milhões de linhas exige performance. O 'TABLOCK' ativa o 
bloqueio de tabela e permite o "minimal logging" (gravação mínima no log de transações do SQL), 
fazendo com que arquivos gigantescos entrem na área de staging em segundos sem estourar o disco.

[✓] ETAPA 5 — Inserção na Bronze Preservando Histórico
-------------------------------------------------------------------------------
* Decisão no Código:* 'INSERT INTO Bronze.SuperStore_Raw' selecionando os dados da tabela #Temp.
* Justificativa:* O pipeline nunca usa DROP ou TRUNCATE na tabela principal da Bronze. Ela 
funciona como um Data Lake acumulativo. Preservar o histórico completo garante que, se uma 
regra de negócio mudar no futuro, os dados brutos estarão disponíveis para reprocessamento.

[✓] ETAPA 6 — Limpeza da Área de Staging
-------------------------------------------------------------------------------
* Decisão no Código:* Execução explícita do comando 'DROP TABLE #Temp_SuperStore'.
* Justificativa:* Boa prática crítica em servidores de produção para liberar imediatamente 
a memória RAM e o espaço do banco de dados temporário (tempdb) após a conclusão da ingestão.

[✓] ETAPA 7 e 8 — Validação da Carga e Índices de Performance
-------------------------------------------------------------------------------
* Decisão no Código:* Consultas rápidas de contagem (COUNT) e amostragem (TOP 5), seguidas 
pela criação dos índices 'IX_Load' em '_ingested_at' e 'IX_Row' em 'Row_ID'.
* Justificativa:* A validação garante que o volume esperado entrou com sucesso. Os índices 
são criados de forma preventiva para que a próxima camada (Silver) consiga buscar os dados 
novos e realizar cruzamentos de forma extremamente veloz, sem sofrer lentidão por Table Scans.
*/


-- ===============================================================================
-- ⬜ 2. CAMADA SILVER (Tratamento, Padronização e Atualização Incremental)
-- ===============================================================================

/*
[✓] ETAPA 1 e 2 — Schema e Criação de Tabela com Tipagem Forte
-------------------------------------------------------------------------------
* Decisão no Código:* Criação da tabela 'Silver.SuperStore' com chaves primárias estruturadas 
('Row_ID INT PRIMARY KEY') e colunas com tipos de dados exatos (DATE, DECIMAL, INT).
* Justificativa:* A Silver estabelece a governança e a segurança. A partir desta camada, os 
dados possuem tipos matemáticos rígidos e restrições que impedem a degradação da qualidade da base.

[✓] ETAPA 3 — Filtrar Nova Carga com Estratégia de Anti-Join (Incremental)
-------------------------------------------------------------------------------
* Decisão no Código:* Criação da CTE 'Bronze_Nova' utilizando um 'LEFT JOIN' entre a Bronze e 
a Silver, aplicando o filtro 'WHERE s.Row_ID IS NULL'.
* Justificativa:* Princípio da Inserção Incremental. Em vez de apagar tudo com TRUNCATE (técnica 
amadora), o pipeline compara o que está na origem com o que já foi processado no destino. O 
Anti-Join isola **apenas as linhas inéditas**, poupando processamento e custos de nuvem.

[✓] ETAPA 4 — Deduplicação no Nível de Transação
-------------------------------------------------------------------------------
* Decisão no Código:* Criação da CTE 'Bronze_Deduplicada' aplicando a função de janela 
'ROW_NUMBER() OVER (PARTITION BY Order_ID, Product_ID, Customer_ID ORDER BY TRY_CONVERT(INT, Row_ID))'.
* Justificativa:* Garante a qualidade da granularidade da tabela. Se o mesmo pedido com o mesmo 
produto entrou duplicado por erro na origem, a função numera essas ocorrências e o filtro 
final 'WHERE rn = 1' elimina o lixo, garantindo que apenas o registro correto seja inserido.

[✓] ETAPA 5 — Transformação, Limpeza de Strings e Funções Defensivas
-------------------------------------------------------------------------------
* Decisão no Código:* Uso massivo de 'TRIM' para remover espaços, 'UPPER' para padronizar caixas 
altas em categorias/regiões, e a combinação de 'COALESCE(NULLIF(..., ''), 'UNKNOWN')' para nulos.
* Justificativa:* Padronização total para o negócio. O 'TRIM' e 'UPPER' evitam que "Vendas" e "vendas " 
sejam tratadas como duas categorias diferentes. O 'NULLIF/COALESCE' impede que linhas textuais fiquem 
em branco nos relatórios, mascarando-as de forma amadora; elas assumem o padrão 'UNKNOWN'.

[✓] ETAPA 5 — Conversão Blindada de Métricas e Datas
-------------------------------------------------------------------------------
* Decisão no Código:* Aplicação de 'TRY_CONVERT(DATE, ...)' para datas e 'COALESCE(TRY_CONVERT(DECIMAL...), 0)' 
para colunas de valores como Sales, Quantity e Profit.
* Justificativa:* Código defensivo de produção. Se uma linha vier com um caractere inválido nas 
métricas, o 'TRY_CONVERT' transforma a falha em NULL (em vez de derrubar a query inteira) e o 
'COALESCE' assume o valor padrão zero, garantindo a resiliência do pipeline ponta a ponta.

[✓] ETAPA 6 e 7 — Validação Silver e Índices de Relacionamento
-------------------------------------------------------------------------------
* Decisão no Código:* Validação do total processado e criação dos índices não-clusterizados 
'IX_Silver_Row' e 'IX_Silver_Customer'.
* Justificativa:* Confirma que a transformação gerou o volume esperado. Os índices são criados 
nas chaves que serão utilizadas como pontes para alimentar a camada seguinte (Gold).
*/


-- ===============================================================================
-- 🟨 3. CAMADA GOLD (Modelagem Dimensional e Carga Incremental Avançada)
-- ===============================================================================

/*
[✓] CONCEITO — Montagem da Camada Analítica (Star Schema Puro)
-------------------------------------------------------------------------------
* Decisão no Código:* Criação de tabelas de Dimensão e Fato independentes no schema 'Gold'.
* Justificativa:* Rompe a estrutura plana ("flat") da Silver. Isolar textos descritivos em 
dimensões e métricas puras na fato reduz o tamanho do banco e otimiza as consultas analíticas de BI.

[✓] DIM_CLIENTE e DIM_PRODUTO — Criação de Surrogate Keys e Restrições de Unicidade
-------------------------------------------------------------------------------
* Decisão no Código:* Definição de chaves substitutas 'Customer_SK' e 'Product_SK' como 
'INT IDENTITY(1,1) PRIMARY KEY', acompanhadas por uma restrição 'CONSTRAINT UNIQUE' nos IDs de negócio.
* Justificativa:* Chaves numéricas inteiras processam JOINs muito mais rápido do que chaves textuais 
alfanuméricas. A restrição 'UNIQUE' funciona como um escudo físico que impede duplicidades na dimensão.

[✓] CARGA INCREMENTAL DAS DIMENSÕES — Consolidação e Idempotência
-------------------------------------------------------------------------------
* Decisão no Código:* 'INSERT INTO Gold.Dim_Cliente' utilizando 'LEFT JOIN ... WHERE d.Customer_ID IS NULL' 
combinado com agrupamento 'GROUP BY s.Customer_ID' e funções agregadoras 'MAX()'.
* Justificativa:* O pipeline nunca usa TRUNCATE na Gold. Ele avalia quem é o cliente novo via Anti-Join 
e insere apenas o registro inédito. Se o cliente houver comprado mais de uma vez no mesmo lote, o 
'GROUP BY' e o 'MAX()' resolvem o conflito, trazendo apenas uma linha consolidada por ID (Idempotência).

[✓] DIM_DATA — Inteligência de Tempo Isolada
-------------------------------------------------------------------------------
* Decisão no Código:* Extração incremental de datas únicas via 'SELECT DISTINCT Order_Date' 
inserindo na 'Gold.Dim_Data'.
* Justificativa:* Fornece uma linha do tempo contínua para o modelo analítico, permitindo que 
o Power BI filtre métricas por períodos de forma padronizada sem forçar o banco a calcular 
funções de data em tempo real durante a exibição dos gráficos.

[✓] FATO_VENDAS — Centralização de Métricas e de "De-Para" de Chaves
-------------------------------------------------------------------------------
* Decisão no Código:* Criação da tabela com 'Fato_SK BIGINT IDENTITY' e amarração com as 
Surrogate Keys das dimensões através de 'INNER JOINs' com a Silver, aplicando um 'LEFT JOIN ... WHERE f.Row_ID IS NULL'.
* Justificativa:* A Fato armazena apenas números (SKs de ligação e métricas como Sales, Profit). 
O Anti-Join garante que se uma venda já foi carregada ontem, ela não será reinserida hoje. O modelo 
torna-se extremamente leve, escalável para bilhões de linhas e protegido contra duplicidades.

[✓] ÍNDICES DA GOLD — Otimização de Performance Analítica
-------------------------------------------------------------------------------
* Decisão no Código:* Criação de índices não-clusterizados específicos nas colunas de chaves 
estrangeiras da Fato: 'IX_FATO_CLIENTE', 'IX_FATO_PRODUTO' e 'IX_FATO_DATA'.
* Justificativa:* Como as ferramentas de visualização (Power BI) realizam consultas baseadas 
em filtros cruzados constantes entre dimensões e fatos, estes índices eliminam os gargalos de 
processamento, garantindo respostas subsegundo nos painéis.
*/


-- ===============================================================================
-- 🟦 4. CAMADA BI / POWER BI (Dashboard de Vendas de Página Única)
-- ===============================================================================

/*
[✓] CONEXÃO E MODELO — Consumo e Otimização do VertiPaq
-------------------------------------------------------------------------------
* Decisão na Demanda:* Conexão via Importação ao SQL Server trazendo as tabelas da camada Gold.
* Justificativa:* Blinda o Power BI contra dados instáveis. Ao consumir a Gold, garante-se 
que o relatório use chaves inteiras (SKs), permitindo que o motor em memória (VertiPaq) 
comprima o arquivo ao máximo e execute os filtros de forma instantânea.

[✓] CONFIGURAÇÃO DA DIM_DATA — Inteligência de Tempo Profissional
-------------------------------------------------------------------------------
* Decisão na Demanda:* Marcar a 'Dim_Data' como Tabela de Datas oficial e criar as colunas 
de granularidade (Ano, Mês, Trimestre) e a regra de negócio "Tempo de Entrega".
* Justificativa:* Desativa as tabelas de data automáticas e ocultas do Power BI, reduzindo o 
tamanho do arquivo. Segue a máxima da arquitetura: o dado derivado é calculado na tabela (a montante) 
e consumido de forma leve nas medidas (a jusante).

[✓] DESIGN — Plano de Fundo (Background) Estruturado
-------------------------------------------------------------------------------
* Decisão na Demanda:* Criação e importação de um layout/plano de fundo de visuais estruturado para a página.
* Justificativa:* Storytelling e ergonomia. Um background com contêineres definidos reduz a 
carga cognitiva do usuário, organizando o fluxo visual de análise das informações mais importantes.

[✓] GOVERNANÇA DA TABELA DE MEDIDAS DAX
-------------------------------------------------------------------------------
* Decisão na Demanda:* Centralização de todas as fórmulas na tabela isolada '_Medidas', utilizando 
fórmulas explícitas e a função segura 'DIVIDE' para Margem % e Ticket Médio.
* Justificativa:* Centralizar as medidas facilita auditorias e manutenção. O uso obrigatório 
da função 'DIVIDE' em vez do operador tradicional (/) protege os visuais contra erros matemáticos 
de divisão por zero, exibindo um espaço em branco ('BLANK') amigável caso ocorra falta de dados.

[✓] DISTRIBUIÇÃO DOS VISUAIS — Storytelling de Dados Eficaz
-------------------------------------------------------------------------------
* Decisão na Demanda:*
  - 4 KPI Cards (Vendas, Lucro, Margem %, Pedidos) posicionados estrategicamente no topo da página.
  - Gráfico de Linhas para demonstrar a tendência contínua de "Vendas por Mês" (Série Temporal).
  - Gráficos de Barras Horizontais para Categorias/Subcategorias e Segmentos (facilitando a leitura de textos longos).
  - Mapa para distribuição geográfica por Estado e Tabela de detalhamento cirúrgico para os Top 10 Produtos.
  - Slicers flutuantes (Ano/Trimestre, Região, Categoria) para dar autonomia de exploração ao usuário.
* Justificativa:* Respeita o padrão de leitura humana (Z-Layout). O decisor inicia compreendendo 
os números macros no topo (KPIs), analisa a tendência temporal ao meio (Linhas), compara a performance 
comercial nas laterais (Barras/Mapa) e investiga o detalhe crítico ao fim (Tabela Top 10).
*/


-- ===============================================================================
-- 🏁 CRITÉRIO DE ACEITE FINAL DO PROJETO DE PORTFÓLIO
-- ===============================================================================
/*
Este checklist comprova de forma inequívoca que:
1. A Bronze recebeu o dado bruto com segurança via Bulk Insert + TABLOCK.
2. A Silver limpou, padronizou e aplicou anti-join para carga incremental real.
3. A Gold organizou o Star Schema estruturado por Surrogate Keys e índices de performance.
4. O BI explicou a história dos dados através de DAX governado e visuais ergonômicos.

PROJETO PRONTO PARA PRODUÇÃO, AUDITADO E ALINHADO COM O MERCADO DE TRABALHO!
*/

-- ===============================================================================
-- FIM DO ARQUIVO ESPELHO DO PIPELINE SUPERSTORE
-- ===============================================================================