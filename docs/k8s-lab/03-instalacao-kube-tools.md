# Fase 3 — Instalação do kubeadm / kubelet / kubectl

**Objetivo:** instalar as três ferramentas do repositório oficial da comunidade
(`pkgs.k8s.io`), na minor `K8S_MINOR` (ver
[README → Variáveis](README.md#variáveis-do-lab)), e **travar** a versão.

**Rodar em:** `k8s-cp`, `k8s-w1`, `k8s-w2` (idêntico nos 3).

📖 **Referência oficial (liberada na prova):**
[Installing kubeadm, kubelet and kubectl](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#installing-kubeadm-kubelet-and-kubectl)

> ⚠️ O repo antigo `apt.kubernetes.io` / `packages.cloud.google.com` foi
> **descontinuado**. Use só `pkgs.k8s.io`, sempre com a URL da minor específica
> (`.../stable:/v1.35/...`). Trocar de minor = editar essa URL e o keyring.

---

## Passo 1 — dependências

```bash
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
```

- Pacotes que o apt precisa pra baixar de repo HTTPS e lidar com a chave GPG.

---

## Passo 2 — chave GPG do repositório

```bash
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
```

- Baixa a chave pública do repo e a converte pro formato binário (`--dearmor`)
  em `/etc/apt/keyrings/`. O apt usa essa chave pra validar a assinatura dos
  pacotes (garante que vieram mesmo do projeto).
- **A minor na URL (`v1.35`) tem que bater** com a que você vai instalar.

---

## Passo 3 — adicionar o repositório

```bash
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /' \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

- Registra o repo, amarrado (`signed-by=`) àquela chave. Só pacotes assinados por
  ela serão aceitos deste repo.

---

## Passo 4 — instalar e travar a versão

```bash
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```

- `kubelet` — agente que roda em todo nó e gerencia os pods/containers.
- `kubeadm` — ferramenta que bootstrapa o cluster (`init`/`join`).
- `kubectl` — cliente de linha de comando do cluster.
- `apt-mark hold` — **congela** as 3 versões. **Por quê:** upgrade de Kubernetes
  é um procedimento controlado (drain do nó → `kubeadm upgrade` → kubelet), nunca
  um `apt upgrade` acidental. Segurar a versão evita quebrar o cluster sem querer.
  (Isso também é conteúdo de CKA — upgrade é tarefa da prova.)

---

## Passo 5 — habilitar o kubelet

```bash
sudo systemctl enable --now kubelet
```

- Habilita o kubelet no boot e já sobe o serviço. Neste momento ele vai ficar
  num **crashloop** (reiniciando), o que é **normal**: ele ainda não tem
  configuração de cluster — isso só chega no `kubeadm init`/`join` (fases 4 e 6).
  Confirme com `sudo journalctl -u kubelet -n 20` (vai ver ele tentando e falhando).

---

## Passo 6 — conferir versões

```bash
kubeadm version
kubectl version --client
kubelet --version
```

- As três devem reportar a mesma minor (`v1.35.x`). `kubectl` pode ser ±1 minor
  do cluster e ainda funcionar, mas no lab mantemos tudo igual.

---

## Resultado

```text
# cole a saída de: kubeadm version | kubectl version --client
```

| Check | k8s-cp | k8s-w1 | k8s-w2 |
|-------|--------|--------|--------|
| kubeadm v1.35.x | | | |
| kubelet instalado + hold | | | |
| repo pkgs.k8s.io OK | | | |

---

## Checklist de saída da Fase 3

- [ ] `pkgs.k8s.io` configurado com a minor certa (nos 3)
- [ ] kubelet/kubeadm/kubectl instalados e em `hold` (nos 3)
- [ ] kubelet habilitado (crashloop nesse ponto é esperado)

➡️ Próxima: [Fase 4 — kubeadm init](04-init-control-plane.md).

## Notas / gotchas

- _(anote aqui — ex.: 404 na URL do keyring por minor inexistente, `apt-mark`
  esquecido, etc.)_
