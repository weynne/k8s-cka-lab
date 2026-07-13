# Cheatsheet CKA

Referência rápida de comandos. Foco em velocidade na prova (a CKA é cronometrada
e mão-na-massa).

📖 **Docs oficiais liberados na prova** (treine achar rápido):
[kubectl Quick Reference](https://kubernetes.io/docs/reference/kubectl/quick-reference/)
· [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
· [Tasks](https://kubernetes.io/docs/tasks/)

---

## Setup de produtividade (rode no começo de cada sessão)

```bash
alias k=kubectl
export do="--dry-run=client -o yaml"     # gerar manifest sem aplicar
export now="--grace-period=0 --force"    # delete imediato
source <(kubectl completion bash)
complete -F __start_kubectl k
```

Namespace default pro contexto (evita `-n` repetido):
```bash
kubectl config set-context --current --namespace=<ns>
```

---

## Gerar manifests rápido (`$do`)

```bash
k run nginx --image=nginx $do > pod.yaml
k create deploy web --image=nginx --replicas=3 $do > deploy.yaml
k create job hello --image=busybox $do -- echo hi > job.yaml
k create cronjob tick --image=busybox --schedule="*/1 * * * *" $do -- date > cj.yaml
k expose deploy web --port=80 --target-port=80 $do > svc.yaml
k create cm app --from-literal=key=val $do > cm.yaml
k create secret generic s --from-literal=pass=1234 $do > secret.yaml
```

Expor como NodePort e achar a porta:
```bash
k expose deploy web --type=NodePort --port=80
k get svc web -o wide      # veja a porta 3xxxx; acesse via IP-do-nó:porta
```

---

## Inspeção / debug

```bash
k get pods -A -o wide
k describe pod <p>
k logs <p> [-c <container>] [--previous]
k exec -it <p> -- sh
k get events -A --sort-by=.lastTimestamp
k get <recurso> <nome> -o yaml
k top nodes ; k top pods            # precisa do metrics-server
```

---

## Nós: drain / cordon / uncordon (aparece muito na CKA)

📖 [Safely drain a node](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/)

```bash
k cordon <nó>                                   # não agenda novos pods
k drain <nó> --ignore-daemonsets --delete-emptydir-data   # esvazia pra manutenção
k uncordon <nó>                                 # volta a agendar
```

---

## kubeadm — ciclo de vida & upgrade

📖 [Upgrading kubeadm clusters](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/)
· [Certificate management](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/)

```bash
# Join tardio: regenerar comando no control plane
kubeadm token create --print-join-command

# Ver config atual do cluster
kubeadm config print init-defaults

# Upgrade (padrão de prova) — no control plane:
# (minor: antes, aponte /etc/apt/sources.list.d/kubernetes.list pra nova minor + apt-get update)
kubeadm upgrade plan
sudo kubeadm upgrade apply v1.36.0
# depois, por nó: drain -> apt install kubelet/kubeadm da versão -> restart kubelet -> uncordon
```

Certificados:
```bash
kubeadm certs check-expiration
sudo kubeadm certs renew all
```

---

## etcd — backup e restore (tópico garantido na CKA)

📖 [Backing up an etcd cluster](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/#backing-up-an-etcd-cluster)

```bash
# Backup
ETCDCTL_API=3 etcdctl snapshot save /opt/snap.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Conferir o snapshot
ETCDCTL_API=3 etcdctl snapshot status /opt/snap.db --write-out=table

# Restore para um novo data-dir
ETCDCTL_API=3 etcdctl snapshot restore /opt/snap.db --data-dir /var/lib/etcd-restore
```

Passo que mais custa ponto: **apontar o etcd pro data-dir restaurado**. Edite
`/etc/kubernetes/manifests/etcd.yaml` e troque o `hostPath` do volume `etcd-data`
para `/var/lib/etcd-restore`. O kubelet detecta a mudança no static pod e reinicia
o etcd sozinho. (`ETCDCTL_API=3` é opcional em etcd ≥ 3.4, mas não atrapalha.)

---

## RBAC rápido

📖 [Using RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)

```bash
k create role r --verb=get,list --resource=pods $do
k create rolebinding rb --role=r --user=jane $do
k create clusterrole cr --verb=get --resource=nodes $do
k auth can-i get pods --as=jane -n dev      # testar permissão
```

---

## Runtime pela ótica do CRI (quando kubectl não ajuda)

```bash
sudo crictl ps -a
sudo crictl pods
sudo crictl logs <container-id>
sudo crictl inspect <container-id>
```

---

## Systemd / logs dos componentes

```bash
sudo systemctl status kubelet
sudo journalctl -u kubelet -f
# static pods do control plane (editar aqui reinicia o componente):
ls /etc/kubernetes/manifests/     # etcd, kube-apiserver, controller-manager, scheduler
```

---

## 🔖 Índice de docs oficiais por domínio da CKA

Na prova você só acessa **`kubernetes.io/docs`** (e subdomínios) e
**`kubernetes.io/blog`**. Treine navegar rápido: use a busca do site,
`kubectl explain <recurso> --recursive` e copie YAML dos exemplos. Confirme a
lista permitida no handbook do exame.

**Cluster architecture, install & config**
- [Upgrade de cluster kubeadm](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/)
- [RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Backup/restore de etcd](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/)
- [Kustomize](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/)

**Workloads & scheduling**
- [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/) · [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
- [Requests/limits de recursos](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [Taints & tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/) · [Afinidade / nodeSelector](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/)

**Services & networking**
- [Service](https://kubernetes.io/docs/concepts/services-networking/service/)
- [NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/) · [Gateway API](https://kubernetes.io/docs/concepts/services-networking/gateway/)
- [Debug de DNS](https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/)

**Storage**
- [PersistentVolumes / PVC](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [StorageClasses](https://kubernetes.io/docs/concepts/storage/storage-classes/)
- [Configurar Pod com PV](https://kubernetes.io/docs/tasks/configure-pod-container/configure-persistent-volume-storage/)

**Troubleshooting**
- [Debug de pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pods/)
- [Debug de cluster](https://kubernetes.io/docs/tasks/debug/debug-cluster/)
- [Troubleshooting kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/troubleshooting-kubeadm/)

**Referências kubectl**
- [Quick Reference](https://kubernetes.io/docs/reference/kubectl/quick-reference/) · [Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/) · [JSONPath](https://kubernetes.io/docs/reference/kubectl/jsonpath/)
