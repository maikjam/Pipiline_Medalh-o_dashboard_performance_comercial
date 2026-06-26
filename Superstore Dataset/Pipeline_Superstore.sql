/*
=========================================================
CRONOGRAMA COMPLETO — PIPELINE DE DADOS
(Estudo → Ambiente Corporativo)
=========================================================

OBJETIVO FINAL

Transformar dados brutos em informação confiável,
escalável e pronta para tomada de decisão.

Fluxo completo:

Origem
↓
Bronze
↓
Silver
↓
Gold
↓
Consumo
↓
Operação
↓
Monitoramento
↓
Evolução

=========================================================
FASE 0 — ENTENDER O NEGÓCIO
(1 semana)
=========================================================

ANTES DE ESCREVER QUALQUER LINHA:

Perguntar:

O que será analisado?
Quem usará?
Qual decisão será tomada?
Com que frequência atualiza?
Qual é a granularidade?

Exemplo:

Empresa vende produtos.

Perguntas:

Uma linha representa:
→ pedido?
→ item vendido?
→ cliente?
→ entrega?

Definir:

Origem:
CSV
ERP
CRM
API
Banco

Volume:
100 linhas?
10 milhões?

Atualização:
Tempo real?
Diária?
Mensal?

Resultado esperado:

Conseguir desenhar o fluxo em papel.

=========================================================
FASE 1 — BRONZE
(Ingestão)
(2 semanas)
=========================================================

OBJETIVO:

Receber dados exatamente como chegaram.

Responsabilidade:

Capturar
Guardar
Registrar
Preservar

A Bronze NÃO EXISTE PARA:

Corrigir
Excluir
Limpar
Modelar
Agregar

Bronze = evidência.

Deve conter:

Dado original.

Exemplo:

Nome:
" joao "

Data:
99/99/2026

Valor:
ABC

Tudo entra.

Deve armazenar:

Conteúdo original
Data da carga
Arquivo
Sistema origem
Versão
Execução
Usuário responsável

Estrutura mental:

Origem
↓

Recepção

↓

Histórico

↓

Disponibilizar

Regras:

Nunca apagar.
Nunca alterar origem.
Nunca corrigir manualmente.

Pensamento correto:

"Se precisar investigar erro,
volto na Bronze."

Validações:

Quantidade recebida
Arquivo lido
Falha de leitura
Integridade física

Ao terminar essa fase você deve saber:

Como dado entra.

=========================================================
FASE 2 — SILVER
(Tratamento)
(3 semanas)
=========================================================

OBJETIVO:

Transformar dado bruto em dado confiável.

Responsabilidade:

Limpar
Padronizar
Converter
Validar
Deduplicar

Pergunta da Silver:

"Posso confiar nesse dado?"

Entradas:

Bronze

Saída:

Dado pronto para análise.

Atividades:

Remover espaços

Padronizar textos

Padronizar datas

Converter números

Tratar vazios

Eliminar registros repetidos

Aplicar regras

Criar consistência

Exemplos:

" São Paulo "

↓

"SAO PAULO"

Valor vazio

↓

0 ou NULL

Data inválida

↓

Quarentena

Criar regras:

Pedido sem cliente

↓

Rejeitar

Venda negativa

↓

Analisar

Quantidade zerada

↓

Validar

Criar classificação:

Aprovado

↓

Silver

Inválido

↓

Quarentena

Criar indicadores:

Recebidos

Transformados

Rejeitados

Duplicados

Tempo execução

Criar rastreabilidade:

Origem
Transformação
Destino

Ao terminar essa fase você deve saber:

Como garantir qualidade.

=========================================================
FASE 3 — GOLD
(Modelagem)
(3 semanas)
=========================================================

OBJETIVO:

Organizar para consumo.

Responsabilidade:

Modelar
Relacionar
Entregar

Pergunta da Gold:

"Como o negócio quer analisar?"

Entradas:

Silver

Saída:

Modelo analítico.

Construir:

Dimensões

Fatos

Métricas

Relacionamentos

Definir grão:

Uma linha representa:

Venda?
Pedido?
Produto?

Dimensões devem conter:

Descrição

Contexto

Características

Exemplos:

Cliente

Produto

Data

Local

Fatos devem conter:

Eventos

Valores

Indicadores

Exemplos:

Valor

Lucro

Quantidade

Desconto

Regras:

Não duplicar.

Não deixar órfão.

Garantir consistência.

Criar validações:

Toda venda tem cliente.

Todo produto existe.

Toda data existe.

Pensamento correto:

"Gold responde perguntas."

Ao terminar:

Criar dashboards sem dificuldade.

=========================================================
FASE 4 — CONSUMO
(BI)
(1 semana)
=========================================================

OBJETIVO:

Entregar informação.

Responsabilidade:

Visualizar.

Analisar.

Decidir.

Ferramentas:

Power BI

Fabric

Dashboards

KPIs

Criar:

Visão executiva

Visão operacional

Indicadores

Filtros

Alertas

Separar:

Transformação → Pipeline

Visualização → BI

Ao terminar:

Conseguir responder perguntas do negócio.

=========================================================
FASE 5 — ORQUESTRAÇÃO
(2 semanas)
=========================================================

OBJETIVO:

Automatizar.

Responsabilidade:

Executar.

Controlar.

Agendar.

Fluxo:

Bronze

↓

Silver

↓

Gold

↓

Atualizar BI

Controlar:

Tempo

Falha

Execução

Dependência

Resultado

Aprender conceitos:

Job

Workflow

Pipeline

Dependência

Retentativa

Ao terminar:

Rodar sem intervenção.

=========================================================
FASE 6 — MONITORAMENTO
(2 semanas)
=========================================================

OBJETIVO:

Saber se está saudável.

Responsabilidade:

Observar.

Detectar.

Alertar.

Criar acompanhamento:

Executou?

Falhou?

Quanto demorou?

Quantas linhas?

Gerar:

Logs

Alertas

Histórico

Indicadores

Perguntas:

Carga aumentou?

Carga caiu?

Erro repetido?

Ao terminar:

Descobrir problema antes do usuário.

=========================================================
FASE 7 — ESCALABILIDADE
(3 semanas)
=========================================================

OBJETIVO:

Preparar crescimento.

Responsabilidade:

Reduzir custo.

Aumentar velocidade.

Aprender:

Carga incremental

Histórico

Partição

Versionamento

Controle mudança

Conceitos:

Processar só mudança.

Guardar histórico.

Evitar reprocessar tudo.

Ao terminar:

Pipeline suporta crescimento.

=========================================================
FASE 8 — DATABRICKS
(4 semanas)
=========================================================

OBJETIVO:

Levar o mesmo conceito para cloud.

Mapeamento:

CSV
↓

Storage

↓

Bronze

↓

Silver

↓

Gold

↓

BI

Aprender:

Lakehouse

Notebook

Workflow

Delta

Spark

Storage

O FOCO NÃO É FERRAMENTA.

O FOCO É:

Receber
↓

Confiar

↓

Modelar

↓

Entregar

↓

Operar

=========================================================
RESULTADO FINAL
=========================================================

Se dominar isso você consegue explicar:

De onde veio
↓

Como entrou

↓

Como limpou

↓

Como validou

↓

Como modelou

↓

Como entregou

↓

Como monitorou

↓

Como evoluiu

Quando conseguir explicar isso sem abrir SQL,
você começa a pensar como engenheiro/analista de dados
e o SQL vira ferramenta.
=========================================================
*/