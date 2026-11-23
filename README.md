# Projeto Banco de Dados — Sistema de Ordens de Serviço

**Repositório GitHub deste projeto:** [https://github.com/andreluizcnunes/banco-dados-ordem-de-servico.git](https://github.com/andreluizcnunes/banco-dados-ordem-de-servico.git)

**Estratégia de repositórios:** projeto independente, não monorepo.

**Referências:** [`../PROJETO.md`](../PROJETO.md), [`../PADROES_DESENVOLVIMENTO.md`](../PADROES_DESENVOLVIMENTO.md) e [`../backend/README.md`](../backend/README.md).

## 1. Finalidade

Centralizar a definição do modelo relacional, scripts SQL de criação/evolução e restrições de integridade para dar suporte à API de ordens de serviço. Evitar mudanças manuais de estrutura sem versionamento e duplicação de esquema entre repositórios.

**Banco de referência:** PostgreSQL 17 em Docker, com migrações aplicadas pelo Flyway (ver seção 5).

## 2. Entidades propostas

| Tabela lógica | Responsabilidade |
| --- | --- |
| `usuarios` | Identidade e perfil: DONO, ADMINISTRATIVO ou TECNICO. |
| `clientes` | Dados de identificação e contato. |
| `ordens_servico` | Cliente, abertura, descrição, local do atendimento, status operacional e datas. |
| `ordens_servico_tecnicos` | Associação N:N entre OS e técnicos, sem limite fixo de membros. |
| `registros_atendimento` | Histórico de atividades em texto livre, autor, data e impedimentos. |
| `itens_ordem_servico` | Produtos, serviços e mão de obra estruturados pelo administrativo, quantidade e preço. |
| `cobrancas` | OS, valor consolidado, status PENDENTE/PAGA e eventual vencimento. |
| `pagamentos` | Registro de quitação e valor recebido. |
| `lancamentos_caixa` | Entrada financeira derivada do pagamento. |

Os nomes físicos de tabela e coluna são **propostas**, sujeitas à modelagem e aprovação técnica. Os perfis, regras e campos funcionais devem continuar alinhados ao [`../PROJETO.md`](../PROJETO.md).

## 3. Integridade e relacionamento

- `ordens_servico` referencia um cliente; seus dados de endereço/contato do atendimento podem precisar ser preservados como instantâneo histórico.
- `ordens_servico_tecnicos` representa relação muitos-para-muitos, com unicidade por par `(ordem_servico_id, tecnico_id)` para evitar vínculo duplicado.
- `registros_atendimento` preserva autor e momento do registro, além do texto operacional livre.
- `itens_ordem_servico` distingue PRODUTO, SERVICO e MAO_DE_OBRA. `quantidade` e `preco_unitario` usam tipos numéricos decimais adequados; não utilizar `FLOAT` para moeda.
- `cobrancas` associa-se à OS sem permitir cobranças duplicadas indevidas pelo fluxo de criação.
- `pagamentos` e `lancamentos_caixa` devem ter referências e restrições que impeçam registrar duas entradas no caixa para o mesmo pagamento.
- Mudanças de atribuição, estado e pagamentos devem ocorrer sob transações do backend, com apoio de constraints e índices.

## 4. Estados e regras persistidas

**Atendimento:** `ABERTA`, `EM_ATENDIMENTO`, `AGUARDANDO`, `CONCLUIDA`.

**Cobrança:** `NAO_ENVIADA`, `PENDENTE`, `PAGA` (o desenho de tabelas pode representar o primeiro estado pela ausência de cobrança).

A atribuição de técnicos é uma associação, **não um status**. A OS concluída permanece persistida para o administrativo e o financeiro, mas não pode ser exibida para os técnicos. O bloqueio de acesso também deve ser aplicado no backend.

O controle de inadimplência só deve sinalizar atraso se houver uma data de vencimento definida e ultrapassada; caso contrário, apresentar a OS como pendente.

## 5. Estratégia de migrações e repositório

- Versionar scripts de criação e alteração em ordem reprodutível (exemplo de organização: `migrations/`).
- Registrar convenção de nomes, versionamento e ferramenta efetivamente adotada neste `README.md` antes de executar migrações.
- Não adicionar segredos, senhas, dados pessoais de clientes ou backups reais ao Git.
- Desenvolver com dados fictícios e documentar como inicializar um ambiente local após a escolha da infraestrutura.
- Preferir alterar estruturas com migrações incrementais, sem apagar informações de pagamentos ou OS existentes.
- O backend deve aplicar/consumir as migrações conforme o procedimento acordado, sem manter outra versão concorrente do esquema.

### 5.1 Ambiente Docker

| Arquivo | Função |
| --- | --- |
| `compose.yaml` | Serviço `postgres` (PostgreSQL 17 Alpine, volume persistente) e serviço `migracoes` (Flyway, aplica `migrations/` e encerra). |
| `.env.example` | Variáveis sem segredos. Copiar para `.env` e trocar a senha. O `.env` está no `.gitignore`. |

```bash
cp .env.example .env
docker compose up -d
docker compose logs migracoes
```

- O serviço `migracoes` só começa depois que o PostgreSQL passa no `healthcheck`. Ele aplica as migrações pendentes e termina. Ao rodar de novo, apenas valida o que já foi aplicado.
- Para aplicar uma migração nova sem reiniciar o banco: `docker compose run --rm migracoes`.
- Os dados ficam no volume `ordem-servico-dados-postgres`. `docker compose down` preserva os dados; `docker compose down -v` **apaga** o banco.
- A porta é publicada em `127.0.0.1:5432` por padrão, então só a própria máquina acessa. Para mudar, ajuste `POSTGRES_PORTA` e `POSTGRES_HOST_BIND` no `.env`.
- Um backend em container pode entrar na rede Docker externa `ordem-servico` e se conectar em `jdbc:postgresql://postgres:5432/<POSTGRES_DB>`.
- O fuso do servidor e das sessões é `America/Sao_Paulo` (variável `TZ`). As colunas de data e hora são `TIMESTAMPTZ`, então o valor gravado não depende do fuso.
- A tabela `flyway_schema_history` registra as migrações aplicadas e não deve ser alterada manualmente.

### 5.2 Convenção de migrações

- Formato de nome compatível com Flyway: `migrations/V<número>__<descricao_em_snake_case>.sql`. Uma migração aplicada nunca é editada; toda mudança vira um novo arquivo `V2__...`, `V3__...`.
- Versão mínima: PostgreSQL 12 (colunas geradas). O ambiente usa PostgreSQL 17.
- Ferramenta: Flyway 13, em container próprio definido neste repositório. Este repositório é o único que aplica migrações; o backend apenas se conecta ao banco já migrado e deve manter o Flyway dele desativado (`spring.flyway.enabled=false`, se usar Spring Boot), para não existir uma segunda versão do esquema.

| Migração | Conteúdo |
| --- | --- |
| `V1__criar_esquema_inicial.sql` | Todas as tabelas do MVP, constraints, índices e gatilho de `atualizado_em`. |

### 5.3 Decisões do esquema inicial

- **Identificadores:** `BIGINT GENERATED ALWAYS AS IDENTITY`. O `id` da OS serve como número da OS.
- **Datas:** `TIMESTAMPTZ` para momentos e `DATE` para vencimento, pagamento e lançamento de caixa.
- **Domínios:** `VARCHAR` com `CHECK` em vez de `ENUM` do PostgreSQL. Assim fica mais simples evoluir por migração e mapear `EnumType.STRING` no Java.
- **Dinheiro:** `NUMERIC(12,2)` para preço unitário, `NUMERIC(12,3)` para quantidade e `NUMERIC(14,2)` para totais. `itens_ordem_servico.valor_total` é coluna gerada `round(quantidade * preco_unitario, 2)`.
- **Preço obrigatório:** `preco_unitario` é `NOT NULL`. Um item gratuito precisa receber `0` de forma explícita, para que preço ausente nunca vire zero por engano.
- **Auditoria:** `criado_por`, `criado_em` e `atualizado_em`. O `atualizado_em` é mantido pela função `atualizar_coluna_atualizado_em()`.
- **Instantâneo do atendimento:** a OS guarda `endereco_atendimento`, `contato_atendimento`, `telefone_atendimento` e `email_atendimento`, independentes do cadastro do cliente.
- **Status de cobrança:** `NAO_ENVIADA` é a ausência de linha em `cobrancas`. A tabela guarda apenas `PENDENTE` e `PAGA`.
- **Vencimento:** `data_vencimento` é opcional, enquanto a questão 3 do `PROJETO.md` não for decidida.
- **Pagamento parcial e cancelamento:** fora do MVP. Por isso vale uma cobrança por OS e um pagamento por cobrança.
- **Exclusões:** nenhuma chave estrangeira usa `ON DELETE CASCADE`. Não é possível apagar OS, cobrança ou pagamento com histórico vinculado.

### 5.4 Integridade garantida pelo banco

Algumas regras entre tabelas são garantidas por chaves estrangeiras compostas, sem gatilhos:

| Regra | Mecanismo |
| --- | --- |
| Só usuários `TECNICO` são associados a uma OS | `ordens_servico_tecnicos (tecnico_id, tecnico_perfil)` → `usuarios (id, perfil)`, com `tecnico_perfil = 'TECNICO'`. Por consequência, o perfil de um técnico com OS associada não pode ser alterado. |
| Cobrança só para OS `CONCLUIDA` | `cobrancas (ordem_servico_id, ordem_servico_status)` → `ordens_servico (id, status_atendimento)`. Uma OS com cobrança não pode sair de `CONCLUIDA`. |
| Pagamento só para cobrança `PAGA` | `pagamentos (cobranca_id, cobranca_status)` → `cobrancas (id, status)`. Uma cobrança com pagamento não volta a `PENDENTE`. |
| Caixa com o mesmo valor do pagamento | `lancamentos_caixa (pagamento_id, valor)` → `pagamentos (id, valor_recebido)`. |
| Uma entrada de caixa por pagamento | `UNIQUE (pagamento_id)`. |
| `AGUARDANDO` exige motivo | `CHECK` em `ordens_servico`. O motivo é apagado ao sair desse estado; o histórico fica em `registros_atendimento` com `tipo = 'IMPEDIMENTO'`. |
| `CONCLUIDA` exige data e autor | `CHECK` sobre `data_conclusao` e `concluida_por`. |

### 5.5 Procedimentos transacionais esperados do backend

**Captura de OS disponível**, em uma transação `READ COMMITTED`:

```sql
SELECT id FROM ordens_servico WHERE id = :os AND status_atendimento = 'ABERTA' FOR UPDATE;

INSERT INTO ordens_servico_tecnicos (ordem_servico_id, tecnico_id, atribuido_por)
SELECT :os, :tecnico, :tecnico
WHERE NOT EXISTS (SELECT 1 FROM ordens_servico_tecnicos WHERE ordem_servico_id = :os);
```

Se o `INSERT` afetar zero linhas, outro técnico capturou a OS primeiro. Esse cenário foi validado com duas sessões concorrentes.

**Registro de pagamento**, nesta ordem e na mesma transação:

1. `UPDATE cobrancas SET status = 'PAGA' WHERE id = :cobranca AND status = 'PENDENTE'`
2. `INSERT INTO pagamentos (...)`
3. `INSERT INTO lancamentos_caixa (...)` com o mesmo valor do pagamento

**Envio à cobrança:** antes de inserir em `cobrancas`, o backend confere se a OS tem itens e grava em `valor_total` a soma de `itens_ordem_servico.valor_total`.

## 6. Consultas e índices importantes

- Buscar OS por cliente, data e status operacional.
- Listar OS `ABERTA` sem qualquer associação em `ordens_servico_tecnicos` (fila disponível).
- Listar OS `ABERTA`, `EM_ATENDIMENTO` ou `AGUARDANDO` associadas a determinado técnico.
- Consultar OS concluídas para precificação administrativa.
- Filtrar cobranças por `PENDENTE` e `PAGA` e, quando houver vencimento, identificar atrasadas.
- Somar entradas de caixa por período e mostrar valores pendentes sem contá-los como receita recebida.

Projetar índices com base em consultas reais; evitar criar índices sem justificativa ou medições.

## 7. Testes de integridade mínimos

1. Não permitir duas linhas de associação idênticas entre OS e técnico.
2. Garantir captura concorrente de uma OS sem técnicos, com apoio de transação e restrição aplicadas no backend.
3. Calcular e armazenar valores monetários sem erro de ponto flutuante.
4. Impedir duas entradas de caixa associadas ao mesmo pagamento.
5. Manter histórico de OS e pagamentos mesmo após sua conclusão.
6. Não confundir cobrança pendente com inadimplência sem vencimento.

## 8. Padrão de documentação

**Nenhum comentário em SQL, scripts, funções, testes ou arquivos de configuração de autoria do projeto.** Documentar modelagem, alterações e razões das migrações em Markdown. Seguir [`../PADROES_DESENVOLVIMENTO.md`](../PADROES_DESENVOLVIMENTO.md).

## 9. Fora do escopo atual

Migração de documentos Word antigos, conciliação bancária, controle completo de estoque, integrações fiscais, cobrança recorrente e parcelamentos avançados.
