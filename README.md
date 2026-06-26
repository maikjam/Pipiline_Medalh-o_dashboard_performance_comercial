# Análise de Performance Comercial - Superstore

Este projeto consiste num dashboard estratégico de Business Intelligence focado na avaliação do impacto de vendas, faturamento por região e análise de margem de produtos. Os dados utilizados foram extraídos do clássico dataset *Superstore* do Kaggle.

## 🛠️ Estrutura e Metodologia

O projeto foi desenvolvido seguindo boas práticas de engenharia e design de dados, dividido nas seguintes etapas:

* **Arquitetura Medalhão:** Organização e estruturação dos dados brutos através de camadas de processamento (Bronze, Silver e Gold) utilizando scripts SQL (`.sql`), garantindo dados limpos, modelados e otimizados para a camada final.
* **Design de UI/UX (Canvas):** Criação de um plano de fundo personalizado utilizando o Canvas, focado numa navegação fluida, moderna (Dark Mode) e intuitiva para facilitar a leitura dos principais KPIs.
* **Modelagem e Visualização:** Construção de métricas de negócio (Ticket Médio, Margem %, Total de Vendas e Qtd. Pedidos) com análise de evolução temporal e distribuição geográfica.

## 📊 Principais Insights do Painel

* Evolução de Vendas por Período.
* Distribuição Geográfica de faturamento.
* Top 10 Produtos por Faturamento.
* Detalhamento de Vendas por Categoria e Segmento.

## 🚀 Como Executar o Projeto

1. Os scripts SQL de tratamento de dados estão organizados na pasta `Superstore Dataset`.
2. Para visualizar o dashboard, basta descarregar o ficheiro do relatório (se incluir o `.pbix` no repositório) e abri-lo no **Power BI Desktop**.
