# Prática CKA — exercícios por domínio

Depois que o cluster está de pé (Fases 0–6), é **aqui** que mora o que mais vale
ponto na prova. A CKA é **100% prática**: 15–20 tarefas em **2 horas** num terminal,
sobre um cluster que já existe. Cada arquivo abaixo é um conjunto de exercícios no
estilo da prova.

## Domínios (por peso)

| Peso | Domínio | Arquivo |
|------|---------|---------|
| 30% | Troubleshooting | [01-troubleshooting-30.md](01-troubleshooting-30.md) |
| 25% | Arquitetura, Instalação & Config | [02-arquitetura-instalacao-config-25.md](02-arquitetura-instalacao-config-25.md) |
| 20% | Serviços & Redes | [03-services-redes-20.md](03-services-redes-20.md) |
| 15% | Workloads & Scheduling | [04-workloads-scheduling-15.md](04-workloads-scheduling-15.md) |
| 10% | Storage | [05-storage-10.md](05-storage-10.md) |

Formato de cada exercício: **Tarefa** (estilo prova) → `<details>` com **Dica** e
**Solução** (tente antes de abrir) → 📖 **doc liberada na prova** → ⏱️ **tempo-alvo**.
Vários trazem **🔧 Como injetar a falha** pra você quebrar o lab de propósito e treinar.

---

## ⏱️ Mecânica de prova (leia antes)

O currículo você já sabe; **isto aqui é o que separa quem passa**:

- **Orçamento de tempo:** ~**6–8 min por tarefa**. Empacou? **Marca e pula** — não
  há nota negativa e há **crédito parcial**. Voltar depois > travar numa só.
- **Contexto SEMPRE primeiro:** cada questão diz o cluster/contexto. Rode
  `kubectl config use-context <ctx>` **antes de tudo** — resolver no cluster errado
  = **zero**.
- **Setup no início da prova** (vale os 30s):
  ```bash
  alias k=kubectl
  export do='--dry-run=client -o yaml'
  export now='--grace-period=0 --force'
  source <(kubectl completion bash); complete -F __start_kubectl k
  ```
- **Imperativo primeiro:** gere o YAML e edite só o que falta —
  `k create deploy web --image=nginx $do > d.yaml`. Escrever YAML do zero é lento.
- **Docs:** só `kubernetes.io/docs` (+subdomínios) e `kubernetes.io/blog`. Treine a
  **busca do site** e `kubectl explain <recurso> --recursive`.
- **Sem manifestos externos:** na prova você não fica dando `curl` em URLs de fora.
  Treine **gerar YAML** (`k ... $do`) e copiar exemplos da doc oficial. Pro
  CNI/ingress do lab, **vendore** o manifesto (salve o `calico.yaml`/controller
  localmente) pra reproduzir offline — ver [../05-cni.md](../05-cni.md).
- **ssh + sudo:** tarefas de etcd, kubelet, certificados e static pods pedem
  `ssh <nó>` e `sudo`. Volte pro nó de origem com `exit` (não esqueça, pra não rodar
  o comando seguinte no nó errado).
- **Verifique o que fez:** `k get`/`describe` depois de cada tarefa. Pontos se perdem
  por typo, não por falta de conhecimento.
- **killer.sh:** a compra do exame dá 2 sessões do simulador (mais difícil que a
  prova real). Faça as duas — é o melhor termômetro.

---

## Sugestão de rotação de estudo

1. Monte o cluster (Fases 0–6) uma vez, na mão.
2. Rode os exercícios de **Troubleshooting (30%)** — maior peso, maior ROI.
3. Suba pra **Instalação/Config (25%)**: etcd backup/restore, upgrade, certs, RBAC.
4. **Redes (20%)** → **Workloads (15%)** → **Storage (10%)**.
5. Quebrou algo? Registre em [../07-troubleshooting.md](../07-troubleshooting.md).
6. `vagrant snapshot save limpo` antes de exercícios destrutivos; `restore` pra
   voltar rápido.
