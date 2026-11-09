# ExecucaoProducao-InfraKubernete — Infra e deploy da Execução

Terraform e manifestos Kubernetes do microsserviço de **Execução e Produção** (Fase 4).
O cluster k3s, a VPC e o ALB interno são compartilhados e ficam no
[InfraKubernete](https://github.com/Fiap-Mecanic-Ltda/InfraKubernete). Este repositório guarda só o
que é do serviço.

## Os três repositórios da Execução

| # | Repositório | Conteúdo | CI/CD |
|---|---|---|---|
| 1 | [ExecucaoProducao-service](https://github.com/Fiap-Mecanic-Ltda/ExecucaoProducao-service) | API .NET 9 + participante da Saga | build, testes, cobertura e push da imagem no ECR |
| 2 | **ExecucaoProducao-InfraKubernete** (este) | ECR, role OIDC, target group/regra no ALB, policy das tabelas nos nós + manifestos `k8s/` | `terraform plan/apply` + deploy no k3s |
| 3 | [ExecucaoProducao-InfraSGBD](https://github.com/Fiap-Mecanic-Ltda/ExecucaoProducao-InfraSGBD) | Tabelas DynamoDB próprias da Execução | `terraform plan/apply` |

## Trava de publicação

Nada vai para a AWS enquanto a Repository Variable **`PUBLICAR_AWS`** não for `true`
(Settings → Secrets and variables → Actions → Variables). A mesma variável trava os três
repositórios da Execução:

| Repositório | Com `PUBLICAR_AWS` desligada | Com `PUBLICAR_AWS=true` |
|---|---|---|
| ExecucaoProducao-service | build, testes e build da imagem | + push no ECR e disparo do deploy |
| ExecucaoProducao-InfraSGBD | só `terraform plan` | + `apply` na `main` |
| ExecucaoProducao-InfraKubernete | `terraform plan` e render do kustomize | + `apply` e deploy na `main` |

Mesmo com a publicação ligada, o **tráfego continua no monolito** até a virada. Com
`rotear_trafego_alb = false`, o target group fica pronto, mas sem a regra no listener.

## Como este stack conversa com os outros

```text
InfraKubernete (state prod/terraform.tfstate)
   │  outputs: vpc_id, ec2_instance_id, worker_asg_name, alb_listener_arn,
   │           github_oidc_provider_arn
ExecucaoProducao-InfraSGBD (state prod/execucao-sgbd/terraform.tfstate)
   │  output: policy_arn (acesso às tabelas execucao-*)
   ▼  (terraform_remote_state, somente leitura)
ExecucaoProducao-InfraKubernete (state prod/execucao-k8s/terraform.tfstate)
   │  cria: ECR mechanicltda-execucao, role mechanicltda-prod-execucao-github-actions,
   │        target group :8082 (server + ASG), anexo da policy nas roles
   │        mechanicltda-prod-ec2-role e mechanicltda-prod-worker-role,
   │        regra do ALB (só na virada)
   ▼
deploy.yml → namespace execucao no k3s
   lê do SSM: /mechanicltda/prod/execucao/dynamodb-prefixo-tabelas e dynamodb-regiao (InfraSGBD)
              /mechanicltda/prod/jwt-secret-key, newrelic-license-key, mensageria/* (InfraKubernete)
```

### Acesso ao DynamoDB

A API usa a cadeia padrão de credenciais do AWS SDK. No k3s, as credenciais chegam pela role da
instância via IMDSv2: a AMI Amazon Linux 2023 vem com hop limit 2, o que basta para um pod.
Por isso a policy das tabelas é anexada às roles do server e dos workers, já que o pod pode rodar
em qualquer nó, e nenhuma access key fica em Secret.

Isso tem um custo: qualquer pod do cluster pode usar essas permissões. Para o projeto isso é
aceitável, porque o cluster só roda os serviços da Mechanic e a policy só alcança as tabelas
`execucao-*`.

### Entrada de tráfego depois da virada

O caminho é API Gateway (`ANY /api/{proxy+}`, repositório Lambda) → VPC Link → ALB interno → regra
de prioridade 110 com `/api/execucao*`, `/api/estoque*` e `/api/servicos-oficina*` → NodePort 8082
→ pod da Execução. Estoque e serviços da oficina saem do monolito nessa virada. O resto continua
na ação padrão do listener (monolito) ou na regra do OS Service (prioridade 100).

## Estrutura

```text
ExecucaoProducao-InfraKubernete/
├── infra/
│   ├── versions.tf          # backend S3 (prod/execucao-k8s/terraform.tfstate) e provider
│   ├── data.tf              # remote state do InfraKubernete e do InfraSGBD + locals
│   ├── variables.tf         # nomes, NodePort, rotear_trafego_alb, repositórios do OIDC
│   ├── ecr.tf               # repositório mechanicltda-execucao
│   ├── alb.tf               # target group, registro do server e do ASG, regra do listener
│   ├── dynamodb.tf          # policy das tabelas nas roles dos nós
│   ├── github_oidc.tf       # role de CI/CD do serviço (ECR, SSM, S3 deploy/execucao/)
│   └── outputs.tf
├── k8s/
│   ├── base/                # Namespace, ConfigMap, Deployment, Service, HPA
│   └── overlays/prod/       # NodePort 8082 + imagePullSecrets do ECR
├── scripts/
│   ├── esperar-ssm.sh       # espera o Run Command terminar
│   └── instalar-refresh-ecr.sh  # timer que renova o ecr-creds do namespace a cada 6h
└── .github/workflows/
    ├── terraform.yml
    └── deploy.yml
```

## Configuração da aplicação no cluster

O ConfigMap (`k8s/base/configmap.yaml`) sobe o serviço com **`Mensageria__Habilitada=false`**.
Nesse modo a API atende só pelas rotas REST e nem conecta no RabbitMQ. Na virada, com o OS
Service usando a Saga e o RabbitMQ instalado pelo InfraKubernete, basta trocar para `"true"` e
fazer o deploy. `DynamoDb__CriarTabelas` fica `false`, porque as tabelas vêm do Terraform.

A cada deploy, o `deploy.yml` monta dois recursos a partir do SSM:

- o ConfigMap `execucao-service-dynamodb`, com o prefixo e a região das tabelas;
- o Secret `execucao-service-secrets`, com JWT, RabbitMQ e New Relic.

Nenhum segredo fica versionado.

## Secrets e variáveis do repositório

| Nome | Tipo | Uso |
|---|---|---|
| `PUBLICAR_AWS` | Variable | `true` libera `apply` e deploy (ver Trava de publicação) |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | Secret | Chave do `terraform-deployer` para o `terraform.yml` |
| `AWS_ROLE_ARN` | Secret | Output `github_actions_role_arn`, usado pelo `deploy.yml` (OIDC) |

O Environment `production` precisa existir para o apply e o deploy. O ExecucaoProducao-service
precisa do secret `EXECUCAO_INFRA_DISPATCH_TOKEN` para disparar o `deploy.yml` daqui.

## Primeira subida (ordem)

1. Aplique o InfraKubernete com a porta 8082 em `microsservicos_node_ports` e, para a Saga, o
   `RABBITMQ_SEGREDO`.
2. Aplique o ExecucaoProducao-InfraSGBD. Ele cria as tabelas, a policy e os parâmetros no SSM.
3. Rode o `terraform.yml` deste repositório. Ele cria o ECR, a role, o target group e o anexo da
   policy. Depois copie `github_actions_role_arn` para o secret `AWS_ROLE_ARN` daqui e do
   ExecucaoProducao-service.
4. Publique o ExecucaoProducao-service na `main`. Ele publica a imagem e dispara o `deploy.yml`
   daqui.
5. Na virada, ponha `rotear_trafego_alb = true` aqui e `Mensageria__Habilitada = "true"` no
   ConfigMap.

## Fluxo de trabalho no Git

As mudanças entram por uma branch `feature/...` com Pull Request para `homologacao`. Depois a
`homologacao` vai para a `main` por outro Pull Request. Em `homologacao` só rodam o `plan` e o
render dos manifestos. O `apply` e o deploy rodam só na `main` e só com `PUBLICAR_AWS=true`.
