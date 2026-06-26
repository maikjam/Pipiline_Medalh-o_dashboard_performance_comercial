/*
📋 Demanda — Dashboard SuperStore | Power BI
1 página única | Portfólio pessoal | 8 a 12 horas

O que entregar
Um dashboard completo de vendas que mostre domínio técnico de ponta a ponta: 
do modelo estrela no SQL até os visuais no Power BI.

Checklist de execução
Conexão e modelo
    [x] Conectar ao SQL Server, importar tabelas Gold
    [x] Conferir relacionamentos (Fato → Dims pelas surrogate keys)
    [x] Marcar Dim_Data como tabela de datas
    [x] Criar na Dim_Data: Ano, Mês, Trimestre, Tempo de Entrega
    [x] Criar Plano de Fundo de Visuais da Pagina

Medidas DAX (tabela _Medidas)
    [x] Total Vendas = SUM(Fato_Vendas[Sales])
    [x] Total Lucro  = SUM(Fato_Vendas[Profit])
    [x] Margem %     = DIVIDE([Total Lucro], [Total Vendas])
    [x] Total Pedidos = COUNTROWS(Fato_Vendas)
    [x] Ticket Médio  = DIVIDE([Total Vendas], [Total Pedidos])

Visuais na página
    [x] 4 KPI cards — Vendas, Lucro, Margem %, Pedidos
    [x] Gráfico de linha — Vendas por mês
    [x] Barras — Vendas por Categoria/Sub_Category
    [x] Barras — Vendas por Segmento de cliente
    [x] Mapa — Vendas por Estado
    [x] Tabela — Top 10 produtos (Vendas + Lucro + Margem)

Slicers
    [x] Ano / Trimestre
    [x] Região
    [x] Categoria

Critério de aceite para portfólio
O dashboard precisa mostrar que você sabe modelar, escrever DAX e 
contar uma história com dados — não só jogar gráfico na tela.
*/