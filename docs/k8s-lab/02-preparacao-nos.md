# Fase 2 — Preparação dos nós

**Objetivo:** deixar os 3 nós prontos para o kubelet — runtime de container
(containerd) com o cgroup driver certo, swap desligado, módulos de kernel e
sysctl de rede aplicados.

**Rodar em:** `k8s-cp`, `k8s-w1`, `k8s-w2` (idêntico nos 3).

📖 **Referência oficial (liberada na prova):**
[Container Runtimes](https://kubernetes.io/docs/setup/production-environment/container-runtimes/)
· [Install kubeadm → prerequisites](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)

---

## Passo 1 — desligar o swap

```bash
sudo swapoff -a                              # desliga swap agora (em memória)
sudo sed -i.bak '/\bswap\b/ s/^/#/' /etc/fstab   # comenta swap no fstab (persiste no boot)
# Ubuntu 24.04 às vezes usa zram/swap.target:
sudo systemctl mask swap.target 2>/dev/null || true
free -h                                      # confirma: linha Swap zerada
```

- **Por quê:** por padrão o kubelet se recusa a subir com swap ligado (o
  scheduler assume que a memória do nó é real). `swapoff -a` resolve agora;
  comentar o `/etc/fstab` impede o swap de voltar após reboot.
- `sed ... /etc/fstab` — comenta qualquer linha com `swap`. O `.bak` guarda backup.

📖 [Swap memory management](https://kubernetes.io/docs/concepts/cluster-administration/swap-memory-management/)

---

## Passo 2 — módulos de kernel

```bash
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay        # carrega agora
sudo modprobe br_netfilter   # carrega agora
lsmod | grep -E 'overlay|br_netfilter'   # confirma carregados
```

- `overlay` — filesystem usado pelo containerd para as camadas de imagem.
- `br_netfilter` — faz o tráfego que passa por uma bridge Linux ser visto pelo
  `iptables` (necessário pro kube-proxy/CNI filtrarem tráfego de pod).
- `/etc/modules-load.d/k8s.conf` — recarrega esses módulos automaticamente no boot.

---

## Passo 3 — sysctl de rede

```bash
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system    # aplica todos os arquivos sysctl.d agora
# conferir:
sysctl net.ipv4.ip_forward net.bridge.bridge-nf-call-iptables
```

- `bridge-nf-call-iptables` — habilita o filtro de iptables no tráfego em bridge
  (par do módulo `br_netfilter`). Sem isso, regras do Service/NetworkPolicy não
  pegam no tráfego de pods.
- `ip_forward = 1` — liga o roteamento de pacotes no nó. **Essencial**: pods em
  nós diferentes só se falam se o nó encaminhar pacotes.
- `sysctl --system` — reaplica sem reboot.

📖 [Forwarding IPv4 and letting iptables see bridged traffic](https://kubernetes.io/docs/setup/production-environment/container-runtimes/#forwarding-ipv4-and-letting-iptables-see-bridged-traffic)

---

## Passo 4 — instalar o containerd

Neste lab usamos o `containerd` do repositório do Ubuntu (simples e suficiente):

```bash
sudo apt-get update
sudo apt-get install -y containerd
containerd --version     # anote a versão (define o formato do config.toml — ver Passo 5)
```

- **Por quê containerd:** é um runtime CRI-compatível, o padrão de fato para
  kubeadm (leve, sem o daemon do Docker no meio). O kubeadm fala com ele via o
  socket `unix:///run/containerd/containerd.sock`.

> Alternativa "de produção" (containerd 2.x, mais novo): instalar `containerd.io`
> do repo oficial do Docker. Funciona igual; só muda o caminho no `config.toml`
> (Passo 5). Pro lab, o do Ubuntu basta.

---

## Passo 5 — configurar o cgroup driver (SystemdCgroup)

Gere o config default e ligue o cgroup driver **systemd**:

```bash
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
```

Agora edite `/etc/containerd/config.toml` e deixe `SystemdCgroup = true`.
O caminho da opção **depende da versão** (Passo 4):

- **containerd 1.x** (o do Ubuntu 24.04):
  ```toml
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
    SystemdCgroup = true
  ```
- **containerd 2.x** (repo do Docker):
  ```toml
  [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]
    SystemdCgroup = true
  ```

Atalho para a 1.x (troca `false`→`true`):
```bash
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
grep SystemdCgroup /etc/containerd/config.toml   # confirma = true
```

Reinicie e habilite no boot:
```bash
sudo systemctl restart containerd
sudo systemctl enable containerd
sudo systemctl status containerd --no-pager
```

- **Por quê isso importa:** o Ubuntu 24.04 usa **cgroup v2**, cujo driver
  recomendado é o `systemd`. O kubelet (via kubeadm) também usa `systemd` por
  padrão. Se o containerd ficar em `cgroupfs` e o kubelet em `systemd`, há dois
  gestores de cgroup brigando → kubelet instável, pods reiniciando. Os dois
  **têm que** usar `systemd`.

📖 [cgroup drivers](https://kubernetes.io/docs/setup/production-environment/container-runtimes/#cgroup-drivers)
· [containerd config](https://kubernetes.io/docs/setup/production-environment/container-runtimes/#containerd)

---

## Passo 6 — sanidade do runtime

```bash
sudo ctr version                  # cliente + servidor do containerd respondem?
sudo systemctl is-active containerd   # deve dizer "active"
```

> `crictl` (mais útil no debug) só vem junto com o pacote do Kubernetes — vamos
> tê-lo após a Fase 3. Aí dá pra rodar `sudo crictl info`.

---

## Resultado

```text
# cole: containerd --version | free -h (Swap) | grep SystemdCgroup | systemctl is-active containerd
```

Repita a confirmação nos 3 nós:

| Check | k8s-cp | k8s-w1 | k8s-w2 |
|-------|--------|--------|--------|
| swap off (`free -h`) | | | |
| overlay + br_netfilter | | | |
| ip_forward = 1 | | | |
| containerd active | | | |
| SystemdCgroup = true | | | |

---

## Checklist de saída da Fase 2

- [ ] Swap desligado e comentado no fstab (nos 3)
- [ ] Módulos `overlay` + `br_netfilter` carregados (nos 3)
- [ ] sysctl `ip_forward` e `bridge-nf-call-iptables` = 1 (nos 3)
- [ ] containerd ativo com `SystemdCgroup = true` (nos 3)

➡️ Próxima: [Fase 3 — instalação kubeadm/kubelet/kubectl](03-instalacao-kube-tools.md).

## Notas / gotchas

- _(anote aqui — ex.: config.toml do Ubuntu vindo "minimal", versão 2.x com outro
  caminho de SystemdCgroup, etc.)_
