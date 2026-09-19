# k8s-lab

Runbook de estudo para a **CKA** e a **CKAD** — cluster Kubernetes on-premise montado 100% na
mão (kubeadm), em VMs locais (Hyper-V no Windows **ou** KVM/libvirt no Linux — ver
[Fase 0](docs/k8s-lab/00-preparacao-host-vms.md)). Já tem um **lab na AWS**? Dá pra
montar o mesmo cluster em EC2 pelo
[Caminho C](docs/k8s-lab/00b-aws-ec2.md) — as Fases 2–6 não mudam.

A documentação viva fica em **[docs/k8s-lab/](docs/k8s-lab/README.md)**.
👉 **Comece pela [Fase 0](docs/k8s-lab/00-preparacao-host-vms.md).**

## Filosofia deste repo

- Nada de Kubernetes é automatizado. Cada comando é rodado à mão, entendido e o
  resultado é documentado. O objetivo é aprender fazendo — igual à prova.
- O Vagrantfile (local) e o [Terraform](terraform/aws/README.md) (AWS) só
  provisionam máquinas + rede. As Fases 0–1 cuidam de host, VMs e rede; a parte de
  Kubernetes na mão começa na [Fase 2](docs/k8s-lab/02-preparacao-nos.md).

## Índice rápido

"Runbook" = documentação pronta pra seguir. Seu progresso real de execução fica
no checklist em [docs/k8s-lab/README.md](docs/k8s-lab/README.md#progresso).

| Fase | Arquivo | Runbook |
|------|---------|---------|
| — | [README / ambiente](docs/k8s-lab/README.md) | ✅ |
| 0 | [Preparação do host + vagrant up](docs/k8s-lab/00-preparacao-host-vms.md) | ✅ |
| 0-C | [Alternativa: nós na AWS (EC2)](docs/k8s-lab/00b-aws-ec2.md) — opcional | ☁️ |
| 0-C | [Terraform/OpenTofu da infra AWS](terraform/aws/README.md) — para repetir o lab | 🤖 |
| 1 | [VMs e rede (netplan)](docs/k8s-lab/01-vms-e-rede.md) | ✅ |
| 2 | [Preparação dos nós (containerd, swap, sysctl)](docs/k8s-lab/02-preparacao-nos.md) | ✅ |
| 3 | [Instalação kubeadm/kubelet/kubectl](docs/k8s-lab/03-instalacao-kube-tools.md) | ✅ |
| 4 | [kubeadm init (control plane)](docs/k8s-lab/04-init-control-plane.md) | ✅ |
| 5 | [CNI — Calico / Flannel](docs/k8s-lab/05-cni.md) | ✅ |
| 6 | [Join dos workers](docs/k8s-lab/06-join-workers.md) | ✅ |
| — | [Troubleshooting](docs/k8s-lab/07-troubleshooting.md) | 📓 |
| — | [Cheatsheet CKA](docs/k8s-lab/08-cheatsheet-cka.md) | 📓 |
| — | [**Prática CKA por domínio**](docs/k8s-lab/pratica/README.md) | 🎯 |
| — | [**Prática CKAD por domínio**](docs/k8s-lab/pratica-ckad/README.md) | 🎯 |

Depois do cluster de pé (Fases 0–6), os exercícios estilo prova ficam organizados
pelos 5 domínios de cada certificação (por peso):

- [**pratica/**](docs/k8s-lab/pratica/README.md) — **CKA**: operar e consertar o
  cluster (troubleshooting, etcd, upgrade, certs, RBAC).
- [**pratica-ckad/**](docs/k8s-lab/pratica-ckad/README.md) — **CKAD**: construir e
  implantar a aplicação (config/secrets, probes, Jobs, Helm/Kustomize, policies).
  Pede alguns add-ons no lab — a página traz a receita.

O mesmo cluster serve às duas provas.
