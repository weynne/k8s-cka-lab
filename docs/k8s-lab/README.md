# CKA/CKAD Lab — cluster kubeadm on-premise

Runbook de montagem manual de um cluster Kubernetes para estudo da **CKA** e da
**CKAD**. Cada fase tem seus comandos, a explicação do **que** e **por quê**, e um
bloco de **Resultado** que eu preencho conforme rodo.

> As **Fases 0–6 montam o cluster** (é o mesmo pras duas provas). Depois, a prática
> se divide por certificação: [pratica/](pratica/README.md) para a **CKA** e
> [pratica-ckad/](pratica-ckad/README.md) para a **CKAD**.

> **📖 Documentação permitida na prova:** você só acessa
> **`kubernetes.io/docs`** (e subdomínios) e **`kubernetes.io/blog`** — na CKAD
> valem também **`helm.sh/docs`** e **`kustomize.io`**. Por isso os
> links do runbook são marcados:
> - **📖 liberado na prova** → páginas do `kubernetes.io` (pode usar no exame).
> - **🔧 montagem do lab** → Vagrant, Hyper-V, Calico (`docs.tigera.io`) etc.:
>   servem só pra montar o ambiente e **não** abrem na prova.
>
> Confirme a lista vigente no handbook oficial do exame antes da prova.

---

## Ambiente

| Item | Valor |
|------|-------|
| Host | Windows 11 Pro |
| Virtualização | Hyper-V |
| Virtual Switch | `K8sLabSwitch` (interno) + ICS no adaptador de internet → DHCP/NAT p/ as VMs |
| Provisionamento | Vagrant (provider `hyperv`) — **só cria VM + rede + SO** |
| SO dos guests | Ubuntu 24.04 LTS (box Vagrant `generic/ubuntu2404`) |
| VMs | `k8s-cp` (control plane), `k8s-w1`, `k8s-w2` (workers) |

> O ambiente acima é o de **referência (Windows)**. O runbook também roda com host
> **Linux (KVM/libvirt)** — só muda a [Fase 0](00-preparacao-host-vms.md); as
> Fases 1–6 são idênticas.
>
> ☁️ **Tem um lab na AWS?** Existe um terceiro caminho, opcional:
> [Caminho C — nós na AWS (EC2)](00b-aws-ec2.md). Ele substitui a Fase 0, encolhe a
> Fase 1 (nada de netplan: o IP privado da EC2 já é fixo) e deixa as **Fases 2–6
> intactas** — troque `192.168.137.x` pelos IPs privados da sua sub-rede. O que
> aparece de novo lá é o **Security Group** (o firewall que o lab local não tem) e
> o controle de custo. Sem lab AWS pronto, prefira o local: é de graça.
> Depois de montar na mão uma vez, o [Terraform](../../terraform/aws/README.md)
> recria a infra num `apply` (e continua não instalando nada de Kubernetes).
>
> A rede do lab é **`192.168.137.0/24`** com gateway **`.1`** (NAT/DHCP/DNS). No
> Windows isso vem do **ICS** (que fixa essa faixa); no Linux, de uma rede NAT do
> **libvirt** criada na mesma faixa de propósito. Todo o plano de IPs parte disso.

---

## Variáveis do lab

Defina uma vez e reutilize em todas as fases. Valores conferidos em jul/2026.

> **Sobre a versão:** instalamos a **v1.35** (a que a CKA usa hoje) **de
> propósito**: assim o exercício de **upgrade de cluster** na prática tem pra onde
> subir — **1.35 → 1.36**, uma minor-alvo que existe de verdade. Se o lab já viesse
> na mais nova, não haveria upgrade pra treinar (o tema cai na prova). Reconfira a
> versão do exame perto da data (release notes em <https://kubernetes.io/releases/>,
> minors em <https://pkgs.k8s.io>); se mudar, troque `K8S_MINOR` abaixo e a URL nas
> fases 3/4.

| Variável | Valor | Onde é usado |
|----------|-------|--------------|
| `K8S_MINOR` | `v1.35` | repo `pkgs.k8s.io` (fase 3) |
| `CALICO_VERSION` | `v3.32.1` | manifesto do Calico (fase 5) |
| Pod CIDR | `10.244.0.0/16` | `kubeadm init` + Calico (fase 4/5) |
| Service CIDR | `10.96.0.0/12` | default do kubeadm |
| Rede dos nós | `192.168.137.0/24` | netplan (fase 1) |

> ⚠️ **Não use o pod CIDR default do Calico (`192.168.0.0/16`)** neste lab: ele
> engloba a rede dos nós (`192.168.137.0/24`) e quebra o roteamento. Por isso
> fixamos o pod CIDR em `10.244.0.0/16`. Detalhe em
> [07-troubleshooting.md](07-troubleshooting.md).

---

## Plano de IPs

> No [Caminho C (AWS)](00b-aws-ec2.md) esta tabela vira o
> [plano de IPs privados](00b-aws-ec2.md#c3--plano-de-ips-na-aws) da sua sub-rede
> VPC — o resto do runbook é o mesmo.

| Host | Papel | IP estático | Notas |
|------|-------|-------------|-------|
| gateway (host Windows/ICS) | NAT + DNS | `192.168.137.1` | não é uma VM |
| `k8s-cp` | control plane | `192.168.137.10` | `--apiserver-advertise-address` |
| `k8s-w1` | worker | `192.168.137.11` | |
| `k8s-w2` | worker | `192.168.137.12` | |

Portas que vão importar (para lembrar na CKA) —
📖 [Ports and Protocols](https://kubernetes.io/docs/reference/networking/ports-and-protocols/):

| Porta | Componente | Nó |
|-------|-----------|-----|
| 6443 | kube-apiserver | control plane |
| 2379-2380 | etcd | control plane |
| 10250 | kubelet | todos |
| 10257 | kube-controller-manager | control plane |
| 10259 | kube-scheduler | control plane |
| 30000-32767 | NodePort | todos |

---

## Progresso

- [ ] Fase 0 — host pronto (Hyper-V/switch/ICS) + `vagrant up` (3 VMs running)
      _— ou [Caminho C](00b-aws-ec2.md): 3 EC2 + Security Group + hostnames_
- [ ] Fase 1 — VMs de pé + IP estático + DNS/ping OK _(na AWS: só hostname/hosts)_
- [ ] Fase 2 — containerd + swap off + módulos/sysctl nos 3 nós
- [ ] Fase 3 — kubeadm/kubelet/kubectl instalados nos 3 nós
- [ ] Fase 4 — `kubeadm init` OK + kubeconfig + control plane Ready
- [ ] Fase 5 — CNI (Calico ou Flannel) aplicado + nós Ready + CoreDNS Running
- [ ] Fase 6 — `k8s-w1` e `k8s-w2` no cluster (Ready)
- [ ] Smoke test — deploy nginx + expose NodePort acessível

---

## Como usar este runbook

1. Antes de cada fase, leia a seção **"O que vamos fazer e por quê"**.
2. Rode os comandos **um a um**, lendo o comentário de cada um.
3. Cole a saída real no bloco **Resultado** (mesmo quando dá certo — serve de
   baseline pra comparar quando algo quebrar depois).
4. Quebrou? Registre em [07-troubleshooting.md](07-troubleshooting.md) com
   sintoma → diagnóstico → correção.
5. Cluster de pé? Vá pra prática — é onde mora o grosso da nota:
   **[pratica/](pratica/README.md)** (CKA) ou
   **[pratica-ckad/](pratica-ckad/README.md)** (CKAD, com os add-ons que o lab
   precisa ganhar antes).
