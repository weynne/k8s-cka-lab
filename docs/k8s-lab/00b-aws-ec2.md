# Fase 0 — Caminho C: nós na AWS (EC2)

**Quando usar:** você quer montar o cluster em **instâncias EC2** — seja porque já
tem um lab AWS de pé (de curso, do trabalho) ou porque prefere estudar na nuvem em
vez de subir VMs locais. Este arquivo **substitui a
[Fase 0](00-preparacao-host-vms.md)** (Hyper-V/KVM + Vagrant) e **encolhe a
[Fase 1](01-vms-e-rede.md)** — as **Fases 2 a 6 continuam idênticas**, trocando só
os IPs.

- **Não tem as instâncias ainda?** Comece no [C1 — criar as EC2](#c1--criar-as-ec2-passo-a-passo).
- **Já tem?** Pule pro [C2 — inventário](#c2--inventário-dos-nós-preencha).

**Quando NÃO usar:** se você não faz questão da AWS, **o lab local sai de graça**
(Caminho A/B) e ensina exatamente a mesma coisa de CKA. Na AWS, só conta nova
(free tier por créditos, pós-07/2025) roda o lab sem pagar — e mesmo assim
consumindo crédito ([detalhes no C1](#topologia-3-ec2--1-control-plane--2-workers)).

> 💸 **Custo — leia antes de criar qualquer coisa.** Ordem de grandeza em
> `us-east-1` (on-demand): `t3.medium` ≈ **US$ 0,042/h**, `t3.small` ≈ **US$
> 0,021/h** → os 3 nós ligados ≈ **US$ 0,08/h** (~US$ 2/dia se esquecer ligado).
> Em `sa-east-1` (São Paulo) some ~50%. Os **60 GB de EBS cobram mesmo com a
> instância parada** (≈ US$ 5/mês). Portanto:
> **pare as instâncias ao terminar de estudar** ([C10](#c10--ciclo-de-vida-parar-religar-e-destruir)),
> crie um **billing alarm** e confira o console de faturamento nos primeiros dias.

🔧 **Referência de montagem (não abre na prova):**
[EC2 — instâncias Linux](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/EC2_GetStarted.html)
· [Security Groups](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-security-groups.html)
· [VPC e sub-redes](https://docs.aws.amazon.com/vpc/latest/userguide/configure-subnets.html)
· [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)

📖 **Doc liberada na prova (é o que o exame cobra aqui):**
[kubeadm — antes de começar (portas, hostname único)](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#before-you-begin)
· [Ports and Protocols](https://kubernetes.io/docs/reference/networking/ports-and-protocols/)

> ⚠️ **Isto é kubeadm em EC2 "cru", não EKS.** O ponto do lab é montar o control
> plane na mão — que é o que a CKA cobra. EKS esconde exatamente a parte que você
> precisa aprender. Também **não** use `--cloud-provider=aws`: sem o CCM
> instalado o cluster nem sobe; aqui os nós são máquinas Linux comuns.

---

## C0 — o que muda em relação ao lab local

| Tema | Lab local (Vagrant) | Na AWS | Onde |
|------|---------------------|--------|------|
| Criar as máquinas | `vagrant up` | `aws ec2 run-instances` (ou console) | [C1](#c1--criar-as-ec2-passo-a-passo) |
| Rede dos nós | `192.168.137.0/24` | CIDR da sua **sub-rede VPC** | [C3](#c3--plano-de-ips-na-aws) |
| IP estático | netplan à mão (Fase 1, passos 1–3) | **não mexer** — o IP privado da EC2 já é fixo | [C6](#c6--hostname-e-etchosts-o-que-sobra-da-fase-1) |
| Firewall | inexistente (rede interna) | **Security Group** — precisa abrir as portas | [C4](#c4--security-group-as-regras-a-parte-que-mais-quebra) |
| Acesso ao nó | `vagrant ssh k8s-cp` | `ssh -i chave.pem ubuntu@<ip>` | [C7](#c7--ssh-entre-os-nós-a-prática-da-cka-precisa) |
| Snapshot p/ exercício destrutivo | `vagrant snapshot save` | AMI / snapshot EBS (mais lento) | [C10](#c10--ciclo-de-vida-parar-religar-e-destruir) |
| Desligar | `vagrant halt` | `aws ec2 stop-instances` (EBS continua cobrando) | [C10](#c10--ciclo-de-vida-parar-religar-e-destruir) |
| Fases 2–6 | — | **iguais**, trocando os IPs | [C9](#c9--mapa-de-ajustes-nas-fases-2-a-6) |

---

## C1 — criar as EC2 (passo a passo)

> Já tem as instâncias? Confira a **topologia** e os **pré-requisitos** logo abaixo
> e vá pro [C2](#c2--inventário-dos-nós-preencha).
>
> 🤖 **Já fez isso na mão uma vez?** Existe um Terraform/OpenTofu pronto em
> [terraform/aws/](../../terraform/aws/README.md) que cria VPC, sub-rede, SG, key
> pair e as instâncias (com os IPs privados `.10`/`.11`/`.12` já fixos) num
> `apply`. Ele **não instala nada de Kubernetes** — Fases 2–6 seguem na mão. Faça
> pelo menos a primeira vez por aqui: entender o que o SG e o plano de IPs fazem é
> o que evita horas de debug depois.

### Topologia: 3 EC2 = **1 control plane + 2 workers**

Exatamente **três** instâncias — mesma topologia do lab local e do ambiente da
prova:

| Nome (tag e hostname) | Papel | Quantidade | Tipo | IP privado fixo |
|-----------------------|-------|:----------:|------|-----------------|
| `k8s-cp` | **control plane** (apiserver, etcd, scheduler, controller-manager) | **1** | `t3.medium` (ou `t3.small`, ver abaixo) | `10.0.1.10` |
| `k8s-w1` | **worker** | **1** | `t3.small` | `10.0.1.11` |
| `k8s-w2` | **worker** | **1** | `t3.small` | `10.0.1.12` |

- **Por que 1 CP só:** CP em HA (3 CPs + load balancer) está fora do escopo da
  CKA e triplica o custo. Um CP basta pra treinar `init`, etcd backup/restore e
  upgrade.
- **Por que 2 workers:** com um só, não dá pra treinar `drain`/`cordon`, afinidade,
  taints e "o pod foi pro outro nó". Dois é o mínimo que torna isso visível.
- **Os IPs fixos** (`.10`/`.11`/`.12`) espelham o `192.168.137.10-12` do lab local e
  batem com o Terraform — o `/etc/hosts` do [C6](#c6--hostname-e-etchosts-o-que-sobra-da-fase-1)
  fica igual em todo lab. A AWS reserva os 4 primeiros IPs da sub-rede, por isso
  começamos no `.10`.

**O que as instâncias precisam ter** (e o porquê de cada escolha):

| Item | Valor | Por quê |
|------|-------|---------|
| SO | **Ubuntu 24.04 LTS, x86_64** | o runbook é escrito pra ele (netplan, apt, cgroup v2). Amazon Linux ou ARM (Graviton) funcionam, mas mudam comandos de pacote e binários |
| Control plane | **`t3.medium`** (2 vCPU / 4 GB) — mínimo viável: `t3.small` | preflight do kubeadm exige ≥ 2 vCPU e ≥ 1700 MB **no CP**. Ver "CP em `t3.small`" abaixo |
| Workers | **`t3.small`** (2 vCPU / 2 GB) | join não checa CPU; 2 GB roda liso. **`t2/t3.micro` (1 GB) não serve** nem de worker |
| Disco | **20 GB gp3** cada | imagens de container comem espaço; com 8 GB você bate em `DiskPressure` |
| Rede | **VPC dedicada**, as 3 na **mesma sub-rede (mesma AZ)** | rede plana entre os nós + zero custo de tráfego cross-AZ + CIDR que não colide com o do cluster |
| Saída pra internet | sub-rede **pública** (IGW + IP público) | as Fases 2/3 baixam pacotes e imagens. Sub-rede privada só com NAT Gateway (que custa ~US$ 32/mês — evite no lab) |
| Acesso | **uma** key pair SSH, a mesma nas 3 | é como você entra nos nós |

> 🆓 **CP em `t3.small` (free tier)?** Dá. O `t3.small` tem 2 vCPU / 2 GB e passa
> no preflight do kubeadm (≥ 2 vCPU, ≥ 1700 MB). O preço é a folga: apiserver +
> etcd + controller-manager + scheduler + Calico já ocupam ~1,3–1,5 GB, então
> sobra pouco. No estudo do dia a dia vai bem; onde aperta é no **etcd restore**, no
> **`kubeadm upgrade`** e se você rodar workload no CP. Sintomas: apiserver
> reiniciando, `kubectl` dando timeout, `dmesg | grep -i oom`. Se acontecer, pare a
> instância e troque o tipo (`aws ec2 modify-instance-attribute --instance-id $CP
> --instance-type t3.medium`, com ela **parada**) — nada do cluster se perde.
>
> Sobre o "gratuito": contas criadas **a partir de 15/07/2025** entram no free
> tier novo, que é **por créditos** (US$ 100 na criação + até US$ 100 em
> atividades, válidos por 6 meses) e aceita `t3.micro`/`t3.small`, entre outros.
> Ou seja, o `t3.small` **gasta crédito** (não é "de graça ilimitado"), e o
> `t3.medium` também sai do mesmo crédito. Na diferença de ~US$ 0,02/h, os
> créditos cobrem o lab com qualquer um dos dois. Contas **anteriores** a essa
> data seguem no free tier antigo (750 h/mês só de `t2.micro`/`t3.micro`, que
> **não servem** pro lab) — pra elas, tudo aqui é cobrado. Confira em **Billing →
> Free Tier** qual é o seu caso.

**Ordem de criação** — cada recurso depende do anterior, e **nenhuma EC2 é criada
antes do C1.5**:

```text
C1.1 CLI  →  C1.2 VPC + sub-rede + IGW  →  C1.3 key pair  →  C1.4 Security Group + regras  →  C1.5 as 3 EC2
```

### C1.1 — preparar a AWS CLI

```bash
aws --version                 # precisa ser v2.x
aws configure                 # access key, secret, região default, output
aws sts get-caller-identity   # confirma com qual conta/usuário você está falando
```

- O usuário/role precisa de permissão de **EC2 e VPC** (criar VPC, sub-rede, key
  pair, security group e instâncias). `AmazonEC2FullAccess` resolve num lab
  pessoal (ela já inclui as ações de VPC).
- Fixe a região na sessão (use a mesma em **todos** os comandos daqui pra frente):
  ```bash
  export AWS_REGION=us-east-1      # mais barata; sa-east-1 (SP) tem menos latência de SSH e custa mais
  ```
- ⚠️ **Faça tudo no mesmo terminal.** Os passos seguintes guardam IDs em variáveis
  (`$VPC`, `$SUBNET`, `$SG`, `$CP`...). Abriu outro terminal? Recupere-as pelo
  `describe-*` de cada passo, ou anote os IDs conforme aparecem.

> Prefere clicar? O passo a passo pelo console está em
> [C1.6](#c16--alternativa-pelo-console-sem-cli) — os conceitos são os mesmos.

### C1.2 — criar a VPC do lab (rede isolada)

Uma VPC **só pro lab**: `10.0.0.0/16`, com uma sub-rede pública `10.0.1.0/24`.
Isolar tem três vantagens: o CIDR é conhecido (não colide com o pod/service CIDR
— [C3](#c3--plano-de-ips-na-aws)), nada do lab se mistura com outros recursos da
conta, e a limpeza no fim é completa.

São 5 peças — é a mesma coisa que o console monta no *"VPC and more"*:

```bash
# 1) a VPC (DNS habilitado: as instâncias ganham nome interno resolvível)
VPC=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 \
      --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=k8s-lab}]' \
      --query Vpc.VpcId --output text)
aws ec2 modify-vpc-attribute --vpc-id $VPC --enable-dns-hostnames

# 2) a sub-rede — UMA, numa AZ só, para as 3 instâncias
AZ=$(aws ec2 describe-availability-zones --query 'AvailabilityZones[0].ZoneName' --output text)
SUBNET=$(aws ec2 create-subnet --vpc-id $VPC --cidr-block 10.0.1.0/24 \
         --availability-zone $AZ \
         --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=k8s-lab-publica}]' \
         --query Subnet.SubnetId --output text)
aws ec2 modify-subnet-attribute --subnet-id $SUBNET --map-public-ip-on-launch

# 3) o Internet Gateway (a "porta" da VPC pra internet)
IGW=$(aws ec2 create-internet-gateway \
      --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=k8s-lab}]' \
      --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --internet-gateway-id $IGW --vpc-id $VPC

# 4) a route table: rota default (0.0.0.0/0) saindo pelo IGW
RTB=$(aws ec2 create-route-table --vpc-id $VPC \
      --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=k8s-lab}]' \
      --query RouteTable.RouteTableId --output text)
aws ec2 create-route --route-table-id $RTB --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW

# 5) associar a route table à sub-rede (é isso que a torna "pública")
aws ec2 associate-route-table --route-table-id $RTB --subnet-id $SUBNET

echo "VPC=$VPC SUBNET=$SUBNET IGW=$IGW RTB=$RTB AZ=$AZ"
```

Peça a peça:
- **VPC** — a rede privada em si. `--enable-dns-hostnames` dá nome DNS interno às
  instâncias (não é o hostname do Linux — esse é o [C6](#c6--hostname-e-etchosts-o-que-sobra-da-fase-1)).
- **Sub-rede** `10.0.1.0/24` — onde as 3 EC2 moram. `--map-public-ip-on-launch`
  faz toda instância nascer com IP público (pra você entrar por SSH).
- **Internet Gateway + route table** — sem eles, a sub-rede não tem saída e o `apt`
  da Fase 2 falha. "Sub-rede pública" = sub-rede cuja route table aponta
  `0.0.0.0/0` pro IGW; não existe uma flag chamada "pública".
- **As 3 instâncias na mesma sub-rede** — não espalhe por AZs: tráfego entre AZs é
  cobrado e não traz nada pro estudo.

Confira:

```bash
aws ec2 describe-route-tables --route-table-ids $RTB \
  --query 'RouteTables[0].Routes[].{Destino:DestinationCidrBlock,Via:GatewayId}' --output table
# deve listar 10.0.0.0/16 → local  e  0.0.0.0/0 → igw-...
```

> **Atalho: usar a VPC default.** Toda conta vem com uma VPC default
> (`172.31.0.0/16`) já pública. Funciona, mas os IPs `10.0.1.x` deste guia não
> valem lá — você teria que adaptar o `--private-ip-address` do C1.5 e o
> `/etc/hosts` do C6 ao CIDR da sub-rede escolhida. Se optar por ela:
> ```bash
> VPC=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)
> SUBNET=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC --query 'Subnets[0].SubnetId' --output text)
> aws ec2 describe-subnets --subnet-ids $SUBNET --query 'Subnets[0].CidrBlock' --output text   # anote
> ```

### C1.3 — criar a key pair (uma só, pras 3 instâncias)

```bash
aws ec2 create-key-pair --key-name k8s-lab --key-type ed25519 \
  --query KeyMaterial --output text > ~/.ssh/k8s-lab.pem
chmod 400 ~/.ssh/k8s-lab.pem
aws ec2 describe-key-pairs --key-names k8s-lab --output table    # confirma que existe na AWS
```

- **Uma key pair, reusada nos 3 nós** — a AWS guarda só a parte pública e injeta
  no `~ubuntu/.ssh/authorized_keys` de cada instância que usar `--key-name k8s-lab`.
- A chave privada é mostrada **uma única vez**, por esse comando. Perdeu, criou
  outra (e as instâncias antigas ficam inacessíveis).
- A key pair é **por região**: criou em `us-east-1`, não aparece em `sa-east-1`.
- `chmod 400` — o SSH recusa chave com permissão aberta.

> Já tem uma chave SSH sua (`~/.ssh/id_ed25519.pub`)? Dá pra importar em vez de
> criar: `aws ec2 import-key-pair --key-name k8s-lab --public-key-material fileb://~/.ssh/id_ed25519.pub`
> — aí o SSH usa a sua chave e você dispensa o `-i`.

### C1.4 — criar o Security Group (com as regras)

```bash
SG=$(aws ec2 create-security-group \
      --group-name k8s-lab --description "CKA lab kubeadm" \
      --vpc-id $VPC --query GroupId --output text)

MEUIP=$(curl -s https://checkip.amazonaws.com)/32

# regra 1: tráfego irrestrito ENTRE os nós (self-reference) — a indispensável
aws ec2 authorize-security-group-ingress --group-id $SG --protocol -1 --source-group $SG

# regra 2: SSH do seu IP
aws ec2 authorize-security-group-ingress --group-id $SG --protocol tcp --port 22 --cidr $MEUIP

echo "SG=$SG"
```

- **O SG nasce fechado** (só saída liberada) — sem essas duas regras, nem o SSH
  entra e o `kubeadm join` nunca fecha.
- **Um SG, anexado às 3 instâncias** — a regra 1 só vale entre instâncias que
  estão no mesmo SG.
- O porquê de cada regra, as opcionais (6443, NodePort) e a lista de portas do
  Kubernetes estão no [C4](#c4--security-group-as-regras-a-parte-que-mais-quebra).

### C1.5 — subir as 3 instâncias (1 control plane + 2 workers)

Pegue a AMI oficial do Ubuntu 24.04 (parâmetro público da Canonical no SSM — já
vem sempre na versão mais recente):

```bash
AMI=$(aws ssm get-parameters \
  --names /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
  --query 'Parameters[0].Value' --output text)
echo "AMI=$AMI"

# alternativa, se o parâmetro SSM falhar (owner 099720109477 = Canonical):
# AMI=$(aws ec2 describe-images --owners 099720109477 \
#   --filters 'Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*' \
#             'Name=state,Values=available' \
#   --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)
```

Uma função pra não repetir o comando três vezes (`subir <nome> <tipo> <ip-privado>`):

```bash
subir() {
  aws ec2 run-instances \
    --image-id "$AMI" \
    --instance-type "$2" \
    --key-name k8s-lab \
    --security-group-ids "$SG" \
    --subnet-id "$SUBNET" \
    --private-ip-address "$3" \
    --associate-public-ip-address \
    --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":20,"VolumeType":"gp3","DeleteOnTermination":true}}]' \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$1}]" \
    --count 1 --query 'Instances[0].InstanceId' --output text
}

CP=$(subir k8s-cp t3.medium 10.0.1.10)    # 1 control plane
W1=$(subir k8s-w1 t3.small  10.0.1.11)    # worker 1
W2=$(subir k8s-w2 t3.small  10.0.1.12)    # worker 2
echo "CP=$CP W1=$W1 W2=$W2"

aws ec2 wait instance-running --instance-ids $CP $W1 $W2    # bloqueia até as 3 subirem
```

Flag a flag:
- `--instance-type` — o sizing da topologia acima (CP maior que os workers).
- `--key-name k8s-lab` — **a mesma key pair** do C1.3 nas três.
- `--security-group-ids` / `--subnet-id` — **o mesmo SG e a mesma sub-rede nas
  três**. SGs diferentes = nós que não se enxergam (gotcha nº 1 da AWS).
- `--private-ip-address` — fixa o IP privado do plano (`.10`/`.11`/`.12`). Sem
  ela a AWS sorteia um IP livre da sub-rede — funciona, mas aí você adapta o
  `/etc/hosts` e o `kubeadm init` ao que saiu.
- `--associate-public-ip-address` — IP público pra você fazer SSH.
- `--block-device-mappings` — 20 GB gp3. `/dev/sda1` é o nome do disco raiz nas
  AMIs da Canonical. `DeleteOnTermination: true` evita EBS órfão cobrando.
- `--tag-specifications ... Name=k8s-cp` — a tag `Name` é o que aparece no console
  e o que você vai usar pra achar as instâncias depois. **Não** é o hostname do
  Linux: renomear o SO é o [C6](#c6--hostname-e-etchosts-o-que-sobra-da-fase-1).

> 💸 **A cobrança começa agora.** Se for parar o estudo no meio, `stop`
> ([C10](#c10--ciclo-de-vida-parar-religar-e-destruir)).

Primeiro acesso:

```bash
aws ec2 describe-instances --instance-ids $CP $W1 $W2 \
  --query 'Reservations[].Instances[].{Nome:Tags[?Key==`Name`]|[0].Value,Privado:PrivateIpAddress,Publico:PublicIpAddress,Estado:State.Name}' \
  --output table

ssh -i ~/.ssh/k8s-lab.pem ubuntu@<ip-publico-do-cp>    # usuário da AMI Ubuntu = ubuntu
```

- A primeira conexão pergunta sobre o fingerprint do host — responda `yes`.
- Levar ~30–60 s pra aceitar SSH depois do `running` é normal (boot + cloud-init).

### C1.6 — alternativa: pelo console (sem CLI)

Mesma ordem da CLI: **rede → key pair → security group → instâncias**. Tudo na
mesma região (canto superior direito do console).

**1. VPC** — **VPC → Your VPCs → Create VPC → *VPC and more***:
- **Name tag auto-generation:** `k8s-lab`
- **IPv4 CIDR block:** `10.0.0.0/16`
- **Number of Availability Zones:** `1`
- **Number of public subnets:** `1` · **private subnets:** `0`
- **Customize subnets CIDR blocks:** `10.0.1.0/24`
- **NAT gateways:** `None` (custa caro e não é necessário) · **VPC endpoints:** `None`
- **DNS options:** marque as duas (*hostnames* e *resolution*)
- **Create VPC.** Ele cria VPC, sub-rede, IGW e route table já ligados.
- Depois: **Subnets** → a sub-rede `k8s-lab-subnet-public1-...` → **Actions → Edit
  subnet settings** → marque **Enable auto-assign public IPv4 address**.

**2. Key pair** — **EC2 → Network & Security → Key Pairs → Create key pair**:
- **Name:** `k8s-lab` · **Type:** `ED25519` · **Format:** `.pem`
- O download acontece **uma vez só**. Mova pra `~/.ssh/k8s-lab.pem` e
  `chmod 400` (no WSL, copie do `/mnt/c/Users/<você>/Downloads/`).

**3. Security Group** — **EC2 → Security Groups → Create security group**:
- **Name:** `k8s-lab` · **VPC:** a `k8s-lab-vpc` (⚠️ não a default)
- **Inbound rules:** *Add rule* → Type **SSH**, Source **My IP**
- **Create.** Depois, abra o SG criado → *Edit inbound rules* → *Add rule* → Type
  **All traffic**, Source **Custom** → digite `sg-` e escolha **o próprio
  `k8s-lab`** (a self-reference só dá pra fazer depois que o SG existe).

**4. Instâncias** — **EC2 → Instances → Launch instances**, **três vezes**, uma por
linha:

| Launch | Name | Instance type | Primary IP (Advanced network configuration) |
|:------:|------|---------------|---------------------------------------------|
| 1º | `k8s-cp` | `t3.medium` | `10.0.1.10` |
| 2º | `k8s-w1` | `t3.small` | `10.0.1.11` |
| 3º | `k8s-w2` | `t3.small` | `10.0.1.12` |

Em cada uma:
1. **Application and OS Images:** Ubuntu → **Ubuntu Server 24.04 LTS**, arquitetura **64-bit (x86)**.
2. **Key pair:** `k8s-lab` (a do passo 2 — **não** crie outra).
3. **Network settings → Edit:**
   - **VPC:** `k8s-lab-vpc` · **Subnet:** a pública do passo 1 (a mesma nas três)
   - **Auto-assign public IP:** `Enable`
   - **Firewall:** *Select existing security group* → `k8s-lab`
   - **Advanced network configuration → Primary IP:** o IP da tabela
4. **Configure storage:** `20 GiB`, `gp3`.
5. **Launch instance.**

> Por que não *Number of instances: 2* pros workers? Porque saem com a **mesma tag
> Name** e sem IP fixo. Três launches separados é mais trabalho e zero surpresa.

---

## C2 — inventário dos nós (preencha)

Levante os dados das 3 instâncias (criadas agora ou pré-existentes):

```bash
aws ec2 describe-instances \
  --filters 'Name=instance-state-name,Values=running' \
  --query 'Reservations[].Instances[].{Nome:Tags[?Key==`Name`]|[0].Value,Id:InstanceId,Tipo:InstanceType,Privado:PrivateIpAddress,Publico:PublicIpAddress,Subnet:SubnetId,SG:SecurityGroups[0].GroupId}' \
  --output table
```

**Resultado — inventário:**

| Papel | Nome/Tag | Instance ID | Tipo | IP **privado** | IP público | Sub-rede |
|-------|----------|-------------|------|----------------|------------|----------|
| control plane | | | | | | |
| worker 1 | | | | | | |
| worker 2 | | | | | | |

> Confira que a coluna **SG é a mesma nas três** e a **Subnet também**. Se não
> for, corrija agora (`aws ec2 modify-instance-attribute --instance-id i-xxx
> --groups $SG`) — sub-rede só se resolve recriando a instância.

---

## C3 — plano de IPs na AWS

Aqui o `192.168.137.x` do runbook vira o CIDR da **sua** sub-rede. Duas regras:

1. **Tudo interno usa o IP PRIVADO** — `--apiserver-advertise-address`, o
   `kubeadm join`, o `/etc/hosts`. O IP privado é **estável**: sobrevive a
   stop/start e só some quando a instância é terminada.
2. **O IP público é descartável** — muda a cada stop/start. Use-o pra SSH, pro
   NodePort e pro `kubectl` da sua máquina. Vai usar kubectl do **WSL**? Então
   associe um **Elastic IP** ao control plane, senão o endereço troca e derruba
   kubeconfig **e** certificado a cada religada
   ([C8](#c8--kubectl-da-sua-máquina-wsl-apontando-pro-cluster)).

> ⚠️ **Confira colisão de CIDR** antes do `kubeadm init`. O pod CIDR do lab é
> `10.244.0.0/16` e o de Service é `10.96.0.0/12` (= `10.96.0.0`–`10.111.255.255`).
> Eles **não podem** se sobrepor ao CIDR da VPC:
> ```bash
> aws ec2 describe-vpcs --query 'Vpcs[].{Vpc:VpcId,Cidr:CidrBlock}' --output table
> ```
> - VPC default da AWS (`172.31.0.0/16`) ou `10.0.0.0/16` → **sem conflito**, siga.
> - VPC em `10.244.x`, `10.96.x`–`10.111.x` ou um `10.0.0.0/8` largo → **troque o
>   pod CIDR** para `172.20.0.0/16` nas Fases 4 e 5 (e no manifesto do CNI).
>
> É o mesmo problema do Calico local descrito no
> [troubleshooting](07-troubleshooting.md) — só muda a rede que colide.

**Resultado — plano de IPs deste lab AWS:**

| Host | Papel | IP privado | Substitui, no runbook |
|------|-------|-----------|------------------------|
| `k8s-cp` | control plane | `10.0.1.10` | `192.168.137.10` |
| `k8s-w1` | worker | `10.0.1.11` | `192.168.137.11` |
| `k8s-w2` | worker | `10.0.1.12` | `192.168.137.12` |
| CIDR da sub-rede | rede dos nós | `10.0.1.0/24` | `192.168.137.0/24` |

> Preenchido com o plano do [C1](#topologia-3-ec2--1-control-plane--2-workers)
> (VPC dedicada). Usou a VPC default ou instâncias pré-existentes? Substitua pelos
> IPs privados do seu inventário ([C2](#c2--inventário-dos-nós-preencha)).

---

## C4 — Security Group: as regras (a parte que mais quebra)

No lab local não há firewall entre as VMs; na AWS há — e **é aqui que o cluster
falha em silêncio**: `kubeadm join` travando, nó `NotReady`, `kubectl logs`
dando timeout. Na dúvida, suspeite do SG primeiro.

### Perfil mínimo — **só SSH** (é o que basta pra estudar)

Se você faz tudo **por SSH dentro do `k8s-cp`** (que é o modo mais parecido com a
prova), são **duas regras** e ponto:

| # | Tipo | Porta | Origem | Por quê |
|---|------|-------|--------|---------|
| 1 | All traffic | all | **o próprio SG** (self-reference) | nós falam **entre si** sem restrição — apiserver, etcd, kubelet, CNI, NodePort |
| 2 | SSH | 22 | **seu IP /32** (ou `0.0.0.0/0`, ver nota) | seu acesso ao lab |

```bash
# Já criou pelo C1.4? Essas duas regras já estão aplicadas — pule este bloco.
# $SG do C1.4 (ou pegue no inventário do C2)
MEUIP=$(curl -s https://checkip.amazonaws.com)/32

# 1) tráfego irrestrito ENTRE os nós (self-reference) — a regra indispensável
aws ec2 authorize-security-group-ingress --group-id $SG \
  --protocol -1 --source-group $SG

# 2) SSH
aws ec2 authorize-security-group-ingress --group-id $SG \
  --protocol tcp --port 22 --cidr $MEUIP
```

> ℹ️ **"Acesso o lab por SSH, então não preciso me preocupar com porta/IP?"**
> Metade certo — vale separar as três coisas:
> - **Seu acesso:** sim, com SSH basta a **22**. Não precisa abrir 6443 nem
>   NodePort pra estudar.
> - **Entre os nós:** **não escapa** — kubelet, etcd, apiserver e o CNI conversam
>   por IP/porta dentro da VPC, e o SG bloqueia isso por padrão. Sem a **regra 1**,
>   o `kubeadm join` trava mesmo com o SSH perfeito. É a regra que não pode faltar.
> - **Plano de IPs ([C3](#c3--plano-de-ips-na-aws)):** também não é sobre o seu
>   acesso — é o endereço que o apiserver publica, o do `join`, o do `/etc/hosts` e
>   a checagem de colisão de CIDR com pod/service. Isso vale por SSH ou não.
>
> Sobre restringir o SSH ao seu IP: é a boa prática, mas **IP residencial/4G muda**
> e aí você perde o acesso (refaça a regra com o `$MEUIP` novo, ou revogue a
> antiga com `revoke-security-group-ingress`). Num lab pessoal, `22` aberto pra
> `0.0.0.0/0` **com autenticação só por chave** (a AMI Ubuntu já vem com senha
> desabilitada) é um risco aceitável — vai levar scan, não invasão. O que **não**
> se abre pra `0.0.0.0/0` é a **6443**: apiserver na internet é convite pra
> cryptominer.

### Regras extras — **só se** quiser acessar de fora do nó (opcional)

| # | Tipo | Porta | Origem | Quando |
|---|------|-------|--------|--------|
| 3 | TCP | 6443 | **seu IP /32** | `kubectl` rodando na **sua máquina/WSL** com contexto no cluster ([C8](#c8--kubectl-da-sua-máquina-wsl-apontando-pro-cluster)) — comum, e exige decisão **antes da Fase 4** |
| 4 | TCP | 30000-32767 | **seu IP /32** | abrir o NodePort no **navegador** (smoke test da Fase 6) |

```bash
# 3) apiserver — só se for usar kubectl de fora
aws ec2 authorize-security-group-ingress --group-id $SG \
  --protocol tcp --port 6443 --cidr $MEUIP

# 4) NodePort — só se quiser testar pelo navegador
aws ec2 authorize-security-group-ingress --group-id $SG \
  --protocol tcp --port 30000-32767 --cidr $MEUIP

aws ec2 describe-security-groups --group-ids $SG \
  --query 'SecurityGroups[0].IpPermissions' --output json    # confira o que ficou
```

- **Dá pra viver sem as duas:** o smoke test da Fase 6 funciona de dentro do nó
  (`curl http://<ip-privado-do-worker>:<nodeport>`), que é inclusive o que você
  faria na prova.
- Mas se o seu plano é rodar `kubectl` do **WSL** (contexto apontando pra EC2), a
  regra **3 é obrigatória** — e tem um pré-requisito que se decide **antes** do
  `kubeadm init`: leia o [C8](#c8--kubectl-da-sua-máquina-wsl-apontando-pro-cluster)
  agora, não depois.

**Pelo console:** EC2 → **Security Groups** → `k8s-lab` → **Inbound rules** →
*Edit inbound rules* → *Add rule*:
- regra 1: Type **All traffic**, Source **Custom** → comece a digitar `sg-` e
  escolha **o próprio `k8s-lab`**;
- regra 2: Type **SSH**, Source **My IP**.

- **Security Group é stateful:** resposta de conexão permitida volta sozinha —
  não existe "regra de saída" pra criar. A saída default já é liberada.
- **Anexe o mesmo SG nas 3 instâncias**, senão a regra 1 não vale entre elas.
- **NACL** da sub-rede: o default libera tudo; se o seu lab tem NACL customizada,
  ela é *stateless* e também precisa liberar as portas efêmeras (1024-65535).

### Quais portas são, afinal (abrindo uma a uma)

A regra 1 cobre tudo isso de uma vez. Mas **saber cada porta é matéria de CKA** —
e se você quiser um SG mais apertado, é esta a lista (📖
[Ports and Protocols](https://kubernetes.io/docs/reference/networking/ports-and-protocols/),
também no [README](README.md#plano-de-ips)), com as do CNI somadas:

| Porta/protocolo | Componente | Nós |
|-----------------|-----------|-----|
| 6443/tcp | kube-apiserver | control plane |
| 2379-2380/tcp | etcd | control plane |
| 10250/tcp | kubelet (`logs`, `exec`, métricas) | todos |
| 10257/tcp, 10259/tcp | controller-manager, scheduler | control plane |
| 30000-32767/tcp | NodePort | todos |
| 179/tcp | Calico BGP | todos (se Calico sem overlay) |
| IP protocol 4 (IPIP) | Calico IPIP | todos (default do `calico.yaml`) |
| 4789/udp | VXLAN (Calico VXLAN) | todos |
| 8472/udp | VXLAN (Flannel) | todos |

Todas essas têm **origem = os outros nós** (o próprio SG), nunca a internet.

> ⚠️ Esquecer o **IPIP (protocolo 4)** ou o **4789/udp** é o erro clássico: os nós
> ficam `Ready`, mas pod de um nó não pinga pod do outro — e o sintoma não aponta
> pro firewall. Por isso a recomendação é a **regra 1** (`--protocol -1` vindo do
> próprio SG): num lab, rede plana entre os nós evita horas de debug que não
> ensinam nada de Kubernetes.

---

## C5 — source/dest check e MTU

Duas particularidades de rede da AWS que não existem no lab local:

**Source/destination check.** A EC2 descarta pacotes cuja origem/destino não seja
a própria instância. Isso **quebra CNI em modo roteado** (Calico com
`CALICO_IPV4POOL_IPIP=Never`, sem encapsulamento).

- **Solução preguiçosa e recomendada:** mantenha o CNI **com encapsulamento**
  (o `calico.yaml` da [Fase 5](05-cni.md) já vem com IPIP `Always`; Flannel é VXLAN
  por natureza). Pacote encapsulado tem origem/destino = IP do nó → passa liso.
- **Se for testar Calico roteado**, desligue o check nas 3 instâncias:
  ```bash
  aws ec2 modify-instance-attribute --instance-id i-xxxx --no-source-dest-check
  ```

**MTU.** Dentro da VPC a MTU é **9001** (jumbo), fora dela 1500. O Calico
autodetecta e costuma acertar. Sintoma de MTU errada: `kubectl exec` e ping
pequeno funcionam, mas `curl`/download **trava no meio**. Se acontecer, fixe a
MTU do CNI (`veth_mtu`/`FELIX_IPINIPMTU`) em `8941` (jumbo − overhead IPIP) ou,
conservador, `1440`.

---

## C6 — hostname e /etc/hosts (o que sobra da Fase 1)

> 🚫 **Não faça o netplan estático da [Fase 1](01-vms-e-rede.md) (passos 1–3).** Na
> EC2 o IP privado já é fixo e vem por DHCP da VPC; escrever IP estático à mão é a
> maneira mais rápida de **perder o acesso SSH à instância**. Pule direto pros
> passos de hostname e `/etc/hosts`.

**Hostname.** A EC2 nomeia o nó como `ip-10-0-1-10`. O kubeadm aceita isso
(é o nome que aparece no `kubectl get nodes`), mas nomes assim atrapalham na hora
de estudar. Renomeie — **em cada nó**:

```bash
sudo hostnamectl set-hostname k8s-cp      # k8s-w1 / k8s-w2 nos workers
exec bash

# impede o cloud-init de devolver o nome ip-x-x-x-x no reboot
# (é o análogo AWS do "cloud-init sobrescrevendo o netplan" da Fase 1)
echo 'preserve_hostname: true' | sudo tee /etc/cloud/cloud.cfg.d/99-hostname.cfg
```

**`/etc/hosts`** — nos 3 nós, com os **IPs privados** do [C3](#c3--plano-de-ips-na-aws):

```bash
sudo tee -a /etc/hosts >/dev/null <<'EOF'

# --- k8s lab (AWS) ---
10.0.1.10 k8s-cp
10.0.1.11 k8s-w1
10.0.1.12 k8s-w2
EOF
```

> Renomeou **depois** de já ter rodado `kubeadm init`/`join`? O nó não muda de nome
> sozinho — o nome foi gravado no registro do nó. Renomeie **antes** das Fases 4/6,
> ou passe `--node-name=k8s-cp` no `init`/`join`.

---

## C7 — SSH entre os nós (a prática da CKA precisa)

Na prova, várias tarefas mandam `ssh node01` + `sudo` (etcd, kubelet, static pods,
certificados). Com o `.pem` só no seu notebook, **os nós não se alcançam** — e você
perde esse treino. Escolha uma:

**Opção 1 — agent forwarding (nada a instalar nos nós):**
```bash
ssh-add ~/.ssh/k8s-lab.pem
ssh -A ubuntu@<ip-publico-cp>     # de dentro do cp: ssh ubuntu@k8s-w1 funciona
```

**Opção 2 — chave própria do control plane (mais parecido com a prova):**
```bash
# no k8s-cp:
ssh-keygen -t ed25519 -N '' -f ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub
# cole o conteúdo em ~/.ssh/authorized_keys de k8s-w1 e k8s-w2
# depois, do cp:  ssh k8s-w1   (resolve pelo /etc/hosts do C6)
```

Atalho no **seu** notebook (`~/.ssh/config`) pra não repetir `-i`:

```
Host k8s-cp
  HostName <ip-publico-do-cp>
  User ubuntu
  IdentityFile ~/.ssh/k8s-lab.pem
  ForwardAgent yes
```

---

## C8 — kubectl da sua máquina (WSL) apontando pro cluster

Este é o fluxo mais confortável: `kubectl` no **WSL**, com um **contexto** do
cluster da EC2 ao lado dos outros que você já tenha. Precisa de três coisas — e
**uma delas é decidida antes da Fase 4**, então leia agora.

**1. O certificado do apiserver tem que conhecer o IP público.** O SAN gerado pelo
kubeadm só cobre o IP **privado**; conectando pelo público, o TLS falha. Acrescente
ao `kubeadm init` da [Fase 4](04-init-control-plane.md):

```bash
--apiserver-cert-extra-sans=<ip-publico-ou-EIP-do-cp>
```

> Esqueceu e o cluster já está de pé? Não precisa recriar nada — regere só o cert
> do apiserver **no `k8s-cp`** (e isso é **exercício legítimo de CKA**):
> ```bash
> sudo rm /etc/kubernetes/pki/apiserver.crt /etc/kubernetes/pki/apiserver.key
> sudo kubeadm init phase certs apiserver --apiserver-cert-extra-sans=<ip-publico>
>
> # trocar o arquivo NÃO reinicia o static pod: mate o container e o kubelet recria
> sudo crictl ps --name kube-apiserver -q | xargs -r sudo crictl stop
> sleep 20 && kubectl get --raw /healthz     # apiserver de volta?
>
> # confirme o novo SAN:
> openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -text | grep -A1 'Subject Alternative Name'
> ```
> O jeito "oficial" de persistir isso é acrescentar `certSANs` em
> `kubectl -n kube-system edit cm kubeadm-config` e rodar o `phase certs` com
> `--config` — assim o SAN sobrevive ao próximo `kubeadm upgrade`. Com a flag
> solta funciona no lab (os defaults batem), mas some num upgrade.

**2. A porta 6443 aberta pro seu IP** — regra 3 do
[C4](#c4--security-group-as-regras-a-parte-que-mais-quebra). No WSL, o IP que
importa é o da sua **internet** (o mesmo do Windows):

```bash
curl -s https://checkip.amazonaws.com        # rode no WSL mesmo
aws ec2 authorize-security-group-ingress --group-id $SG \
  --protocol tcp --port 6443 --cidr <esse-ip>/32
```

**3. Um endereço que não mude.** Sem Elastic IP, o IP público troca a cada
stop/start e você refaz kubeconfig **e** certificado toda vez. Associe um **EIP ao
control plane** e pare de se preocupar:

```bash
EIP=$(aws ec2 allocate-address --domain vpc --query AllocationId --output text)
aws ec2 associate-address --instance-id $CP --allocation-id $EIP
aws ec2 describe-addresses --allocation-ids $EIP --query 'Addresses[0].PublicIp' --output text
```

> 💸 Desde 2024 **todo IPv4 público é cobrado** (~US$ 0,005/h ≈ US$ 3,6/mês). Com a
> instância **ligada**, o EIP não custa mais que o IP automático que ela já teria.
> Com a instância **parada**, o EIP continua reservado e **cobrando** — se for
> hibernar o lab por semanas, libere (`aws ec2 release-address --allocation-id $EIP`).

### Trazer o kubeconfig pro WSL, como um contexto separado

```bash
# 1) copiar o admin.conf do control plane
scp -i ~/.ssh/k8s-lab.pem ubuntu@<ip-publico-cp>:/home/ubuntu/.kube/config /tmp/awslab.conf

# 2) apontar pro endereço público
sed -i "s#server: https://.*:6443#server: https://<ip-publico-cp>:6443#" /tmp/awslab.conf

# 3) renomear cluster/usuário/contexto pra não colidir com o que você já tem
sed -i 's/kubernetes-admin@kubernetes/awslab/; s/\bkubernetes-admin\b/awslab-admin/g; s/\bkubernetes\b/awslab/g' /tmp/awslab.conf

# 4) mesclar no seu ~/.kube/config (preserva os contextos existentes)
cp ~/.kube/config ~/.kube/config.bak 2>/dev/null || true
KUBECONFIG=~/.kube/config:/tmp/awslab.conf kubectl config view --flatten > /tmp/merged
mv /tmp/merged ~/.kube/config && chmod 600 ~/.kube/config && rm /tmp/awslab.conf

# 5) usar
kubectl config get-contexts
kubectl config use-context awslab
kubectl get nodes -o wide
```

- O passo **3** é o que evita dois clusters chamados `kubernetes` brigando no seu
  kubeconfig. O passo **4** mescla sem apagar nada (o `--flatten` embute os certs).
- `kubectl config use-context` é **exatamente** o primeiro comando de toda questão
  da CKA — treinar isso no dia a dia já é ganho.
- ⚠️ O `admin.conf` é credencial de **admin do cluster**. Ele está no
  [.gitignore](../../.gitignore), mas confira antes de commitar qualquer coisa.

### O que o kubectl local **não** substitui

Tarefas de nó da CKA — etcd (backup/restore), static pods em
`/etc/kubernetes/manifests`, kubelet, certificados, upgrade — só se fazem **dentro
do nó**, com `ssh` + `sudo`. Então o fluxo real fica:

| Tarefa | Onde |
|--------|------|
| `kubectl` do dia a dia (workloads, services, RBAC, troubleshooting de pod) | **WSL**, contexto `awslab` |
| etcd, kubelet, static pods, certs, `kubeadm upgrade` | **`ssh` no nó** ([C7](#c7--ssh-entre-os-nós-a-prática-da-cka-precisa)) |

O `kubectl` também fica instalado nos nós (Fase 3), então dá pra alternar sem dor.

---

## Validação (antes de seguir pra Fase 2)

Nos 3 nós:

```bash
hostname                       # k8s-cp / k8s-w1 / k8s-w2
ip -brief address              # anote o IP privado (é o do C3)
ping -c2 k8s-cp                # nó a nó por nome (testa /etc/hosts + SG regra 1)
ping -c2 1.1.1.1               # saída pra internet (IGW ou NAT)
curl -sI https://pkgs.k8s.io | head -1   # DNS + HTTPS de saída (a Fase 3 depende disso)
nc -zv k8s-cp 22               # TCP entre nós liberado no SG
```

Os 5 têm que passar. Falhou o `ping` **entre nós** → Security Group (regra 1) ou
SGs diferentes por instância. Falhou só o `curl`/internet → sub-rede sem IGW/NAT
ou sem IP público.

## Resultado

```text
# cole: hostname + ip -brief address dos 3 nós, o ping entre nós e o curl ao pkgs.k8s.io
```

---

## C9 — mapa de ajustes nas Fases 2 a 6

| Fase | Muda algo na AWS? | O quê |
|------|-------------------|-------|
| [1 — VMs e rede](01-vms-e-rede.md) | **substituída** | Passos 1–3 (netplan) **não se aplicam**; passos 4–5 (hostname/hosts/ping) viraram [C6](#c6--hostname-e-etchosts-o-que-sobra-da-fase-1) e a validação acima |
| [2 — preparação dos nós](02-preparacao-nos.md) | **não** | igual. A AMI Ubuntu da AWS já vem **sem swap** — confirme com `free -h` e siga |
| [3 — kubeadm/kubelet/kubectl](03-instalacao-kube-tools.md) | **não** | igual (exige a saída pra internet validada acima) |
| [4 — `kubeadm init`](04-init-control-plane.md) | **sim** | `--apiserver-advertise-address=<IP privado do cp>`; opcional `--apiserver-cert-extra-sans=<IP público>` ([C8](#c8--kubectl-da-sua-máquina-wsl-apontando-pro-cluster)) e `--node-name=k8s-cp`. Pod CIDR `10.244.0.0/16` **se** não colidir com a VPC ([C3](#c3--plano-de-ips-na-aws)) |
| [5 — CNI](05-cni.md) | **quase** | mesmos manifestos. Mantenha **encapsulamento** (IPIP/VXLAN) por causa do source/dest check ([C5](#c5--sourcedest-check-e-mtu)). A pegadinha do CIDR do Calico (`192.168.0.0/16`) só importa se sua VPC for `192.168.x` |
| [6 — join dos workers](06-join-workers.md) | **sim** | `kubeadm join <IP privado do cp>:6443 ...`. No smoke test, teste o NodePort **de dentro de um nó** (`curl http://<ip-privado-do-worker>:<nodeport>`); pelo navegador só com a regra 4 do SG |
| [prática/](pratica/README.md) | **sim** | `vagrant snapshot` não existe aqui — veja [C10](#c10--ciclo-de-vida-parar-religar-e-destruir) |

---

## C10 — ciclo de vida: parar, religar e destruir

```bash
aws ec2 stop-instances  --instance-ids $CP $W1 $W2   # fim do estudo (para a cobrança de compute)
aws ec2 start-instances --instance-ids $CP $W1 $W2   # próxima sessão
```

- **IP privado e hostname sobrevivem** ao stop/start → o cluster volta sozinho
  (containerd e kubelet estão `enabled`). Confirme com `kubectl get nodes` — pode
  levar ~1 min pros nós saírem de `NotReady`.
- **IP público muda** (sem Elastic IP) → refaça o `~/.ssh/config` e o `server:` do
  contexto `awslab` (`kubectl config set-cluster awslab --server=https://<novo-ip>:6443`).
  Com **EIP no control plane** ([C8](#c8--kubectl-da-sua-máquina-wsl-apontando-pro-cluster)),
  nada disso é necessário.
- **EBS continua cobrando** com a instância parada (~US$ 5/mês pelos 60 GB). Se for
  parar por semanas, tire uma **AMI** e termine as instâncias.

**Substituto do `vagrant snapshot` (pré-exercício destrutivo):**

```bash
aws ec2 create-image --instance-id $CP --name "k8s-cp-limpo-$(date +%F)" --no-reboot
```

- Criar/restaurar AMI é **bem mais lento** que snapshot de VM. Na prática, para
  exercícios destrutivos compensa mais **reconstruir o cluster**: `sudo kubeadm
  reset -f` nos 3 nós e repetir Fases 4–6 (leva ~10 min e **é treino de prova**).
- O que vale mesmo snapshotar é o estado **antes** dos exercícios de etcd
  restore e de upgrade.

> 🤖 Subiu o lab com o [Terraform](../../terraform/aws/README.md)? Então
> `terraform destroy` faz toda a limpeza abaixo de uma vez — e `terraform apply`
> reconstrói quando quiser voltar.

**Destruir o lab de vez** (acabou o estudo — evita cobrança esquecida):

```bash
aws ec2 terminate-instances --instance-ids $CP $W1 $W2
aws ec2 wait instance-terminated --instance-ids $CP $W1 $W2
aws ec2 delete-security-group --group-id $SG      # só depois das instâncias sumirem
aws ec2 delete-key-pair --key-name k8s-lab && rm -f ~/.ssh/k8s-lab.pem

# a VPC do C1.2 — na ordem inversa da criação (cada peça depende da anterior)
aws ec2 disassociate-route-table --association-id $(aws ec2 describe-route-tables \
  --route-table-ids $RTB --query 'RouteTables[0].Associations[0].RouteTableAssociationId' --output text)
aws ec2 delete-route-table --route-table-id $RTB
aws ec2 delete-subnet --subnet-id $SUBNET
aws ec2 detach-internet-gateway --internet-gateway-id $IGW --vpc-id $VPC
aws ec2 delete-internet-gateway --internet-gateway-id $IGW
aws ec2 delete-vpc --vpc-id $VPC
# (se tiver alocado EIP no C8: aws ec2 release-address --allocation-id $EIP)

# confira que não ficou volume EBS órfão cobrando:
aws ec2 describe-volumes --filters Name=status,Values=available \
  --query 'Volumes[].{Id:VolumeId,GB:Size}' --output table
```

> ⚠️ `terminate` **destrói** a instância e o cluster junto — não é o `vagrant
> halt`. Pra só pausar, é `stop-instances`.

---

## Checklist de saída (Caminho C)

- [ ] VPC `10.0.0.0/16` com sub-rede pública `10.0.1.0/24` (IGW + rota `0.0.0.0/0`)
- [ ] 3 instâncias Ubuntu 24.04 `running` — **1 control plane (`k8s-cp`) + 2 workers
      (`k8s-w1`, `k8s-w2`)** — mesma sub-rede, CP com ≥ 2 vCPU/2 GB
- [ ] **Uma** key pair `.pem` salva com `chmod 400` e SSH funcionando nas 3
- [ ] Inventário e plano de **IPs privados** preenchidos ([C2](#c2--inventário-dos-nós-preencha)/[C3](#c3--plano-de-ips-na-aws))
- [ ] CIDR da VPC **não** colide com `10.244.0.0/16` nem `10.96.0.0/12`
- [ ] Security Group único nas 3, com **self-reference** (tráfego entre nós) + SSH;
      6443/NodePort só se for acessar de fora
- [ ] Hostnames `k8s-cp`/`k8s-w1`/`k8s-w2` + `preserve_hostname` + `/etc/hosts`
- [ ] ping entre nós por nome, internet e `pkgs.k8s.io` OK nos 3
- [ ] SSH nó-a-nó funcionando (agent forwarding ou chave própria)
- [ ] Vai usar kubectl do WSL? EIP no CP + regra 6443 + `--apiserver-cert-extra-sans`
      anotado pra Fase 4 ([C8](#c8--kubectl-da-sua-máquina-wsl-apontando-pro-cluster))
- [ ] Billing alarm criado / rotina de `stop-instances` definida

➡️ Próxima: [Fase 2 — preparação dos nós](02-preparacao-nos.md) (daqui em diante é
igual ao lab local, trocando `192.168.137.x` pelos IPs privados do [C3](#c3--plano-de-ips-na-aws)).

## Notas / gotchas

- _(anote aqui — ex.: regra de SG esquecida derrubando o join, IPIP bloqueado,
  IP público mudando após stop/start, hostname voltando pra `ip-x-x-x-x`, MTU,
  seu IP residencial mudando e derrubando o SSH, instância pequena demais dando
  DiskPressure/OOM, EBS órfão cobrando depois do terminate, etc.)_
