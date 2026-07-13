# Prática — Arquitetura, Instalação & Config (25%)

Operação do cluster: **etcd (backup/restore)**, **upgrade de versão**,
**certificados TLS**, **RBAC** e **HA**. Muitas tarefas pedem `ssh` no nó + `sudo`.

📖 Docs liberadas: [Backup/restore de etcd](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/)
· [Upgrade kubeadm](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/)
· [Certificados](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/)
· [RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)

> 🚧 **Semente** — alguns exercícios prontos + espaço pra você adicionar mais.

---

## Ex 1 — Backup e restore do etcd ⏱️ ~10min (quase garantido na prova)

**Tarefa:** faça um snapshot do etcd em `/opt/etcd-backup.db`. Depois, restaure-o
para um novo data-dir e aponte o etcd pra ele.

<details><summary>Dica</summary>

`etcdctl snapshot save/restore`, com os certs em `/etc/kubernetes/pki/etcd/`. No
restore, o passo que custa ponto é **editar o `hostPath` do etcd.yaml** pro novo
data-dir.
</details>

<details><summary>Solução</summary>

```bash
ssh k8s-cp
# Backup
sudo ETCDCTL_API=3 etcdctl snapshot save /opt/etcd-backup.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
sudo ETCDCTL_API=3 etcdctl snapshot status /opt/etcd-backup.db --write-out=table

# Restore para novo data-dir
sudo ETCDCTL_API=3 etcdctl snapshot restore /opt/etcd-backup.db \
  --data-dir /var/lib/etcd-restore

# Apontar o etcd pro novo data-dir:
sudo vi /etc/kubernetes/manifests/etcd.yaml
#   volume 'etcd-data' -> hostPath.path: /var/lib/etcd-restore
# o kubelet recria o static pod sozinho
```
</details>

📖 [Backing up an etcd cluster](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/#backing-up-an-etcd-cluster)

---

## Ex 2 — RBAC: role + rolebinding pra um usuário ⏱️ ~6min

**Tarefa:** crie uma role `pod-reader` no namespace `dev` que permita `get/list/watch`
em pods, e vincule-a ao usuário `jane`. Valide.

<details><summary>Solução</summary>

```bash
kubectl create ns dev
kubectl -n dev create role pod-reader --verb=get,list,watch --resource=pods
kubectl -n dev create rolebinding jane-read --role=pod-reader --user=jane
kubectl -n dev auth can-i list pods --as=jane      # yes
kubectl -n dev auth can-i delete pods --as=jane    # no
```
</details>

📖 [Using RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)

---

## Ex 3 — Upgrade de minor: 1.35 → 1.36 ⏱️ ~15min

**Tarefa:** o lab está em **v1.35**. Faça o upgrade do control plane pra **v1.36** e
depois de um worker. É o cenário clássico da CKA — upgrade de **minor**.

<details><summary>Dica</summary>

Numa mudança de **minor** o repo `pkgs.k8s.io` está **pinado** na minor atual — o
`apt` só enxerga o 1.36 depois de apontar o repo pra `/v1.36/`. Ordem sagrada:
`kubeadm` primeiro (`upgrade apply` no cp / `upgrade node` no worker), depois
`kubelet`+`kubectl`, com `drain`/`uncordon` em volta.
</details>

<details><summary>Solução (fluxo)</summary>

```bash
# --- control plane ---
ssh k8s-cp
# 1) apontar o repo pra minor nova (senão o apt não vê o 1.36):
sudo sed -i 's#/v1.35/#/v1.36/#' /etc/apt/sources.list.d/kubernetes.list
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key | sudo gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo apt-get update
# 2) kubeadm -> plan -> apply:
sudo apt-mark unhold kubeadm && sudo apt-get install -y kubeadm=1.36.0-* && sudo apt-mark hold kubeadm
sudo kubeadm upgrade plan
sudo kubeadm upgrade apply v1.36.0
# 3) drenar, atualizar kubelet/kubectl, religar:
kubectl drain k8s-cp --ignore-daemonsets
sudo apt-mark unhold kubelet kubectl && sudo apt-get install -y kubelet=1.36.0-* kubectl=1.36.0-* && sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload && sudo systemctl restart kubelet
kubectl uncordon k8s-cp

# --- worker: k8s-w1 (repita p/ k8s-w2) ---
kubectl drain k8s-w1 --ignore-daemonsets --delete-emptydir-data   # do control plane
ssh k8s-w1
sudo sed -i 's#/v1.35/#/v1.36/#' /etc/apt/sources.list.d/kubernetes.list
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key | sudo gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo apt-get update
sudo apt-mark unhold kubeadm && sudo apt-get install -y kubeadm=1.36.0-* && sudo apt-mark hold kubeadm
sudo kubeadm upgrade node                                          # no worker é 'upgrade node', não 'apply'
sudo apt-mark unhold kubelet kubectl && sudo apt-get install -y kubelet=1.36.0-* kubectl=1.36.0-* && sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload && sudo systemctl restart kubelet
exit
kubectl uncordon k8s-w1                                            # de volta no control plane
kubectl get nodes                                                 # VERSION = v1.36.0 em todos
```
</details>

📖 [Upgrading kubeadm clusters](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/)

---

## Ex 4 — Renovar certificados TLS ⏱️ ~8min

**Tarefa:** verifique quando os certificados do control plane expiram e renove todos.

<details><summary>Dica</summary>

`kubeadm certs check-expiration` mostra as datas. `renew all` renova, mas os
componentes **só pegam os certs novos ao reiniciar** — force o restart dos static pods.
</details>

<details><summary>Solução</summary>

```bash
ssh k8s-cp
sudo kubeadm certs check-expiration          # o que expira e quando
sudo kubeadm certs renew all                 # renova todos os certs + kubeconfigs
# forçar restart dos static pods do control plane (eles releem os certs):
sudo sh -c 'cd /etc/kubernetes/manifests && mv *.yaml /tmp/ && sleep 20 && mv /tmp/*.yaml .'
sudo kubeadm certs check-expiration          # datas devem ter avançado ~1 ano
# se o admin.conf foi renovado, recopie o kubeconfig:
sudo cp /etc/kubernetes/admin.conf "$HOME/.kube/config" && sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
```
</details>

📖 [Certificate management with kubeadm](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/)

---

## Ex 5 — ClusterRole + ClusterRoleBinding + ServiceAccount ⏱️ ~7min

**Tarefa:** crie a ServiceAccount `monitor` e dê a ela permissão **cluster-wide** de
`get/list/watch` em `nodes`. Valide como a SA.

<details><summary>Dica</summary>

`nodes` é um recurso **cluster-scoped** — Role/RoleBinding (namespaced) não alcançam.
Regra de ouro: recurso sem namespace → **ClusterRole + ClusterRoleBinding**.
</details>

<details><summary>Solução</summary>

```bash
kubectl create serviceaccount monitor
kubectl create clusterrole node-reader --verb=get,list,watch --resource=nodes
kubectl create clusterrolebinding monitor-nodes \
  --clusterrole=node-reader --serviceaccount=default:monitor
kubectl auth can-i list nodes --as=system:serviceaccount:default:monitor   # yes
kubectl auth can-i delete nodes --as=system:serviceaccount:default:monitor # no
```
- Um pod passa a usar essa SA com `spec.serviceAccountName: monitor` — aí o token
  montado nele carrega exatamente essas permissões.
</details>

📖 [Using RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)

---

## Adicione mais

- [ ] Kustomize: `kubectl apply -k` (base + overlay).
- [ ] HA: segundo control plane (`kubeadm join --control-plane`).
- [ ] Trocar/expirar o token de bootstrap e refazer o join de um worker.
