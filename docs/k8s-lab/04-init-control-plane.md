# Fase 4 — kubeadm init (control plane)

**Objetivo:** inicializar o control plane no `k8s-cp`, configurar o `kubeconfig`
do usuário e entender o que o kubeadm gerou (etcd, apiserver, certificados,
static pods).

**Rodar em:** **só** `k8s-cp`.

📖 **Referência oficial (liberada na prova):**
[Creating a cluster with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)
· [kubeadm init (reference)](https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init/)

---

## Passo 1 (opcional, recomendado) — preflight e dry-run

```bash
sudo kubeadm init --dry-run \
  --apiserver-advertise-address=192.168.137.10 \
  --pod-network-cidr=10.244.0.0/16 \
  --cri-socket=unix:///run/containerd/containerd.sock
```

- `--dry-run` roda os preflight checks (swap, cgroup, portas, CPU/mem, runtime)
  **e** mostra tudo que o `init` faria — **sem alterar nada**. Se algo da Fase 2
  estiver errado, ele acusa aqui, que é o momento barato de descobrir.
- Se quiser só as checagens (sem simular o resto): `sudo kubeadm init phase
  preflight` (esse subcomando **não** aceita as flags de advertise/CIDR acima).

---

## Passo 2 — inicializar o control plane

```bash
sudo kubeadm init \
  --apiserver-advertise-address=192.168.137.10 \
  --pod-network-cidr=10.244.0.0/16 \
  --cri-socket=unix:///run/containerd/containerd.sock \
  | tee kubeadm-init.out
```

O que cada flag faz:
- `--apiserver-advertise-address=192.168.137.10` — IP que o apiserver publica pros
  outros nós. **Tem que ser o IP estático do `k8s-cp`** (Fase 1), não um IP de
  DHCP volátil, senão os certificados e o join apontam pro lugar errado.
- `--pod-network-cidr=10.244.0.0/16` — faixa de onde os pods vão tirar IP. Tem que
  **casar** com o CNI na Fase 5 (Calico/Flannel), e **não pode** ser `192.168.x`
  (colidiria com a rede dos nós — ver [troubleshooting](07-troubleshooting.md)).
- `--cri-socket=unix:///run/containerd/containerd.sock` — diz explicitamente qual
  runtime usar (evita ambiguidade se houver mais de um CRI instalado).
- `| tee kubeadm-init.out` — salva a saída num arquivo (está no `.gitignore`).
  **Guarde-o:** ele contém o comando `kubeadm join ...` que os workers precisam.

> O que o `init` faz por baixo: sobe o **etcd** e os componentes do control plane
> como *static pods* em `/etc/kubernetes/manifests/`, gera os **certificados** em
> `/etc/kubernetes/pki/`, configura o kubelet e cria o token de bootstrap.

---

## Passo 3 — configurar o kubeconfig do seu usuário

Copie o bloco que o próprio `init` imprime:

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

- `admin.conf` é o kubeconfig com credenciais de admin do cluster. Copiado pra
  `~/.kube/config`, o `kubectl` passa a falar com o cluster **sem** precisar de
  `--kubeconfig` toda vez.
- `chown` — passa a posse do arquivo pro seu usuário (foi copiado como root).

Teste:
```bash
kubectl get nodes
kubectl get pods -n kube-system
```

---

## Passo 4 — entender o estado inicial

- `kubectl get nodes` mostra o `k8s-cp` como **NotReady**. **Isso é esperado:**
  sem um plugin de rede (CNI), o kubelet reporta `NetworkReady=false`. Resolve na
  Fase 5 (CNI).
- Em `kube-system`, `coredns` fica **Pending** até haver rede. `etcd`,
  `kube-apiserver`, `kube-controller-manager`, `kube-scheduler` e `kube-proxy`
  devem estar `Running`.
- Explore o que subiu:
  ```bash
  ls /etc/kubernetes/manifests/     # static pods do control plane
  ls /etc/kubernetes/pki/           # certificados
  kubectl get pods -n kube-system -o wide
  ```

---

## Passo 5 — guardar o comando de join

```bash
grep -A2 'kubeadm join' kubeadm-init.out
```

- Copie o `kubeadm join 192.168.137.10:6443 --token ... --discovery-token-ca-cert-hash sha256:...`
  para a [Fase 6](06-join-workers.md). O token **expira em 24h**; se passar,
  gera-se outro (mostrado lá).

---

## Resultado

```text
# cole: fim da saída do kubeadm init (a linha "Your Kubernetes control-plane...")
# e: kubectl get nodes ; kubectl get pods -n kube-system
```

---

## Checklist de saída da Fase 4

- [ ] `kubeadm init` concluiu sem erro
- [ ] `~/.kube/config` configurado; `kubectl get nodes` responde
- [ ] control plane `Running` em kube-system (coredns Pending é ok por ora)
- [ ] comando de `kubeadm join` salvo
- [ ] `k8s-cp` NotReady (esperado — sem CNI ainda)

➡️ Próxima: [Fase 5 — CNI (Calico/Flannel)](05-cni.md).

## Notas / gotchas

- _(anote aqui — ex.: preflight reclamando de swap/cgroup, porta 6443 em uso,
  advertise-address errado, etc.)_
