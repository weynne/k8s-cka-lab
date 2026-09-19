# Terraform / OpenTofu — infra do lab na AWS

Provisiona a **infra** do lab em EC2 com um comando: VPC, sub-rede pública,
Internet Gateway, Security Group, key pair e as instâncias (1 control plane + N
workers) com **IP privado fixo**.

> **Para que serve:** montar o ambiente na mão é o exercício da **primeira vez**
> ([Caminho C](../../docs/k8s-lab/00b-aws-ec2.md), passo a passo pela CLI/console).
> Da segunda em diante, recriar rede e SG a cada `terraform destroy` não ensina
> mais nada — é aqui que a automação paga.

## 🚧 O que este código NÃO faz — de propósito

**Nada de Kubernetes.** Sem containerd, sem kubeadm, sem `init`, sem `join`, sem
CNI. O `user_data` só define hostname e popula `/etc/hosts` (o
[C6](../../docs/k8s-lab/00b-aws-ec2.md#c6--hostname-e-etchosts-o-que-sobra-da-fase-1)
do runbook).

É o mesmo contrato do Vagrantfile do lab local: **infra automatizada, Kubernetes na
mão**. As [Fases 2 a 6](../../docs/k8s-lab/02-preparacao-nos.md) continuam sendo
digitadas comando a comando — é o que a prova cobra.

## Pré-requisitos

```bash
terraform version     # >= 1.6   (ou: tofu version — os comandos são idênticos)
aws sts get-caller-identity    # credenciais válidas, com permissão de EC2/VPC
```

- Uma chave SSH pública em `~/.ssh/id_ed25519.pub` (ou aponte outra em
  `public_key_path`, ou reuse uma key pair da AWS com `key_name`).

## Uso

```bash
cd terraform/aws
cp terraform.tfvars.example terraform.tfvars

# obrigatório: seu IP para a regra de SSH
curl -s https://checkip.amazonaws.com        # cole como "<ip>/32" em allowed_ssh_cidr
vim terraform.tfvars

terraform init
terraform plan
terraform apply

terraform output proximo_passo               # o que fazer agora, com os IPs já preenchidos
terraform output ssh
```

Com `tofu`, troque o binário: `tofu init`, `tofu plan`, `tofu apply`.

## O que é criado (e quanto custa)

| Recurso | Qtde | Observação |
|---|---|---|
| VPC + sub-rede + IGW + route table | 1 de cada | de graça |
| Security Group | 1 | tráfego livre **entre os nós** + SSH do seu IP |
| Key pair | 1 | sua chave pública; nada é gerado no servidor |
| EC2 `t3.medium` (control plane) | 1 | ~US$ 0,042/h |
| EC2 `t3.small` (worker) | `worker_count` (2) | ~US$ 0,021/h cada |
| EBS gp3 20 GB criptografado | 1 por nó | ~US$ 1,6/mês cada — **cobra parado** |
| IP público IPv4 | 1 por nó | ~US$ 0,005/h cada (desde 2024) |
| Elastic IP | opcional | só com `allocate_eip = true` |

**Total ligado:** ~US$ 0,10/h (~US$ 2,40/dia se esquecer ligado) em `us-east-1`.
Em `sa-east-1`, some ~50%. Crie um **billing alarm**.

## Variáveis que mais importam

| Variável | Default | Quando mexer |
|---|---|---|
| `allowed_ssh_cidr` | **(obrigatória)** | sempre. Seu IP `/32` — sem default de propósito |
| `worker_count` | `2` | `1` economiza ~US$ 0,02/h e 2 GB; cobre quase tudo |
| `expose_apiserver` | `false` | `true` pra rodar `kubectl` da sua máquina/WSL (libera 6443) |
| `allocate_eip` | `false` | `true` junto com o de cima: o IP público do CP para de mudar |
| `expose_nodeports` | `false` | `true` só pra testar NodePort no navegador |
| `region` | `us-east-1` | `sa-east-1` se latência de SSH incomodar |
| `source_dest_check` | `true` | `false` apenas pra testar Calico em modo **roteado** |
| `manage_hostnames` | `true` | `false` se quiser fazer hostname/`/etc/hosts` na mão |

> ⚠️ Se `expose_apiserver = true`, lembre do
> `--apiserver-cert-extra-sans=<ip público>` no `kubeadm init` da **Fase 4** —
> depois do init, só regerando o certificado
> ([C8](../../docs/k8s-lab/00b-aws-ec2.md#c8--kubectl-da-sua-máquina-wsl-apontando-pro-cluster)).

> ⚠️ O `vpc_cidr` tem validação contra as faixas do lab (`10.244.0.0/16` de pod e
> `10.96.0.0/12` de service). Se trocar pra uma faixa que colida, o `plan` falha
> antes de criar nada.

## Parar e religar (a rotina do dia a dia)

`terraform destroy` **apaga o cluster junto**. Para só pausar a cobrança de compute:

```bash
IDS=$(terraform output -json instance_ids | jq -r 'join(" ")')
aws ec2 stop-instances  --instance-ids $IDS    # fim da sessão de estudo
aws ec2 start-instances --instance-ids $IDS    # próxima sessão
```

- **IP privado e hostname sobrevivem** → o cluster volta sozinho (kubelet e
  containerd estão `enabled`).
- **IP público muda** a cada religada, salvo com `allocate_eip = true`. Depois do
  `start`, rode `terraform refresh` (ou `terraform apply`) pra os outputs pegarem os
  endereços novos.
- **EBS continua cobrando** parado.

## Destruir

```bash
terraform destroy      # remove TUDO: instâncias, rede, SG, key pair
```

Depois, confirme que não sobrou volume órfão:

```bash
aws ec2 describe-volumes --filters Name=status,Values=available \
  --query 'Volumes[].{Id:VolumeId,GB:Size}' --output table
```

## Mapa: este código × o runbook

| Seção do [Caminho C](../../docs/k8s-lab/00b-aws-ec2.md) | Aqui |
|---|---|
| C1 — criar as EC2 | `terraform apply` |
| C2/C3 — inventário e plano de IPs | `terraform output nodes` (IPs fixos `.10`/`.11`/`.12`) |
| C4 — Security Group | `aws_security_group` + as regras, controladas por variável |
| C5 — source/dest check | `source_dest_check` |
| C6 — hostname e `/etc/hosts` | `user_data` (`manage_hostnames`) |
| C7 — SSH entre nós | **manual** (agent forwarding ou chave própria) |
| C8 — kubectl do WSL | `expose_apiserver` + `allocate_eip`; kubeconfig é manual |
| C10 — ciclo de vida | seções acima |
| Fases 2–6 | **manual**, como deve ser |

> 📌 Este código foi validado com `terraform validate`/`fmt`, mas **não foi
> aplicado numa conta AWS real**. Na primeira execução, leia o `plan` com
> atenção antes de confirmar.
