# Prática — Troubleshooting (30%)

O maior peso da prova. A ideia aqui é **você quebrar o lab de propósito**
(🔧 injetar a falha), diagnosticar do zero e corrigir. Trabalhe sempre de
**sintoma → diagnóstico → correção**.

📖 Docs liberadas: [Troubleshooting kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/troubleshooting-kubeadm/)
· [Debug de pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pods/)
· [Debug de cluster](https://kubernetes.io/docs/tasks/debug/debug-cluster/)

> 💾 Antes de injetar falhas: `vagrant snapshot save limpo`. Pra voltar:
> `vagrant snapshot restore limpo`.

---

## Ex 1 — Nó `NotReady` (kubelet parado) ⏱️ ~6min

**Tarefa:** o nó `k8s-w1` aparece `NotReady`. Descubra a causa e volte-o a `Ready`.

🔧 **Injetar a falha:** no `k8s-w1`, `sudo systemctl stop kubelet`.

<details><summary>Dica</summary>

O kubelet é o agente do nó; se ele para, o nó vira `NotReady`. Investigue **no nó**,
não só via kubectl.
</details>

<details><summary>Solução</summary>

```bash
kubectl get nodes                       # k8s-w1 NotReady
kubectl describe node k8s-w1            # Conditions: Kubelet stopped posting status
ssh k8s-w1
sudo systemctl status kubelet          # inactive/failed
sudo journalctl -u kubelet -n 30       # confirma por quê
sudo systemctl start kubelet && sudo systemctl enable kubelet
exit
kubectl get nodes                       # volta a Ready em ~1 min
```
</details>

📖 [Debug de cluster](https://kubernetes.io/docs/tasks/debug/debug-cluster/)

---

## Ex 2 — `kube-apiserver` fora do ar (static pod quebrado) ⏱️ ~8min

**Tarefa:** `kubectl` para de responder ("connection refused" na :6443). Restaure o
control plane.

🔧 **Injetar a falha:** no `k8s-cp`, edite `/etc/kubernetes/manifests/kube-apiserver.yaml`
e ponha um valor inválido (ex.: `--etcd-servers=https://127.0.0.1:9999`).

<details><summary>Dica</summary>

Se o `kubectl` está morto, diagnostique **por baixo dele**: `crictl`, `journalctl`,
e os logs do kubelet. O apiserver é um **static pod** — o kubelet o (re)cria a partir
do manifesto em `/etc/kubernetes/manifests/`.
</details>

<details><summary>Solução</summary>

```bash
ssh k8s-cp
sudo crictl ps -a | grep apiserver        # container reiniciando/exited
sudo crictl logs <id-do-apiserver>        # ou:
sudo journalctl -u kubelet -n 50          # kubelet reclamando do static pod
ls /var/log/pods/ ; sudo cat /var/log/pods/kube-system_kube-apiserver*/*/*.log
sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml   # corrigir a flag
# o kubelet detecta a mudança e recria o pod sozinho (~30s)
sudo crictl ps | grep apiserver           # de volta Running
exit
kubectl get nodes                          # kubectl responde de novo
```
</details>

📖 [Troubleshooting kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/troubleshooting-kubeadm/)

---

## Ex 3 — Pod `Pending` (taint sem toleration) ⏱️ ~5min

**Tarefa:** o pod `web` fica `Pending` e não agenda em nenhum nó. Faça-o rodar (sem
tirar o taint do nó).

🔧 **Injetar:** `kubectl taint nodes k8s-w1 tier=db:NoSchedule` e crie um pod que só
caberia nesse nó.

<details><summary>Dica</summary>

`kubectl describe pod` mostra o motivo no fim (Events): `0/3 nodes are available: ...
untolerated taint`. A solução pode ser **tolerar o taint** ou ajustar
nodeSelector/affinidade.
</details>

<details><summary>Solução</summary>

```bash
kubectl describe pod web | tail -20      # Events: untolerated taint {tier: db}
kubectl get nodes -o wide
kubectl describe node k8s-w1 | grep -i taint
```
Adicione a toleration ao pod (spec):
```yaml
tolerations:
- key: "tier"
  operator: "Equal"
  value: "db"
  effect: "NoSchedule"
```
```bash
kubectl apply -f web.yaml
kubectl get pod web -o wide              # Running
```
</details>

📖 [Taints & tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)

---

## Ex 4 — `CrashLoopBackOff` ⏱️ ~5min

**Tarefa:** o pod `app` reinicia sem parar (`CrashLoopBackOff`). Descubra o porquê.

🔧 **Injetar:** `kubectl run app --image=busybox -- /bin/sh -c 'exit 1'`.

<details><summary>Dica</summary>

Crash = o **processo do container** morre. A resposta está nos **logs** (inclusive os
da tentativa anterior com `--previous`) e no `describe` (exit code, last state).
</details>

<details><summary>Solução</summary>

```bash
kubectl get pod app                       # CrashLoopBackOff, RESTARTS subindo
kubectl describe pod app | grep -A5 'Last State'   # Reason: Error, Exit Code
kubectl logs app --previous               # saída do container que morreu
# corrigir o comando/imagem/config que faz o processo sair
```
</details>

📖 [Debug de pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pods/)

---

## Ex 5 — `ImagePullBackOff` ⏱️ ~4min

**Tarefa:** o pod `site` não sobe: `ImagePullBackOff`. Corrija.

🔧 **Injetar:** `kubectl run site --image=nginx:versao-que-nao-existe`.

<details><summary>Solução</summary>

```bash
kubectl describe pod site | grep -A3 Events   # Failed to pull image ... not found
# corrigir a tag da imagem:
kubectl set image pod/site site=nginx:1.27     # (ou recriar o pod com a tag certa)
kubectl get pod site                            # Running
```
</details>

📖 [Debug de pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pods/)

---

## Ex 6 — Service sem endpoints (selector errado) ⏱️ ~6min

**Tarefa:** o Service `web-svc` existe mas não entrega tráfego (curl falha). Os pods
estão `Running`. Conserte.

🔧 **Injetar:** crie um deploy com label `app=web` e um Service com selector
`app=web-errado`.

<details><summary>Dica</summary>

Service sem `ENDPOINTS` = o **selector do Service** não bate com os **labels dos
pods**. `kubectl get endpoints <svc>` mostrando `<none>` confirma.
</details>

<details><summary>Solução</summary>

```bash
kubectl get endpoints web-svc             # <none>  -> selector não casa
kubectl describe svc web-svc | grep Selector
kubectl get pods --show-labels            # veja o label real dos pods
kubectl edit svc web-svc                  # ajuste spec.selector pro label certo
kubectl get endpoints web-svc             # agora lista os IPs dos pods
```
</details>

📖 [Service](https://kubernetes.io/docs/concepts/services-networking/service/)

---

## Ex 7 — DNS interno não resolve ⏱️ ~6min

**Tarefa:** pods não resolvem nomes (`nslookup kubernetes.default` falha). Diagnostique
e restaure o DNS do cluster.

🔧 **Injetar:** `kubectl -n kube-system scale deploy coredns --replicas=0`.

<details><summary>Dica</summary>

DNS do cluster = **CoreDNS** (deployment no `kube-system`). Teste com um pod
descartável; verifique se os pods do CoreDNS estão de pé e o Service `kube-dns`.
</details>

<details><summary>Solução</summary>

```bash
kubectl run t --image=busybox --restart=Never -it --rm -- nslookup kubernetes.default  # falha
kubectl -n kube-system get pods -l k8s-app=kube-dns     # 0 pods!
kubectl -n kube-system get svc kube-dns                 # o Service existe
kubectl -n kube-system scale deploy coredns --replicas=2
kubectl -n kube-system get pods -l k8s-app=kube-dns     # Running
kubectl run t --image=busybox --restart=Never -it --rm -- nslookup kubernetes.default  # resolve
```
</details>

📖 [Debug de DNS](https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/)

---

## Ex 8 — kubelet não sobe por cgroup driver ⏱️ ~7min

**Tarefa:** depois de mexer no containerd, o kubelet do `k8s-w2` entra em loop e o nó
fica `NotReady`. Os logs citam cgroup. Corrija.

🔧 **Injetar:** no `k8s-w2`, troque `SystemdCgroup = true` por `false` no
`/etc/containerd/config.toml` e `sudo systemctl restart containerd kubelet`.

<details><summary>Dica</summary>

Ubuntu 24.04 usa **cgroup v2** → driver `systemd` dos dois lados. Se o containerd
volta pra `cgroupfs` e o kubelet está em `systemd`, brigam e o kubelet não estabiliza.
</details>

<details><summary>Solução</summary>

```bash
ssh k8s-w2
sudo journalctl -u kubelet -n 30 | grep -i cgroup
grep SystemdCgroup /etc/containerd/config.toml          # = false (errado)
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl restart kubelet
exit
kubectl get nodes                                        # k8s-w2 Ready
```
</details>

📖 [cgroup drivers](https://kubernetes.io/docs/setup/production-environment/container-runtimes/#cgroup-drivers)

---

## Mais cenários pra você adicionar

- Nó com **disk/memory pressure** (evictions) — `describe node` Conditions.
- **RBAC**: `Forbidden` num `kubectl auth can-i` / ServiceAccount sem permissão.
- **NetworkPolicy** bloqueando tráfego que deveria passar.
- **PVC `Pending`** por falta de StorageClass/PV (ver [05-storage-10.md](05-storage-10.md)).
- etcd fora → apiserver não sobe (ver [02-arquitetura-instalacao-config-25.md](02-arquitetura-instalacao-config-25.md)).
