# Troubleshooting

Registro de problemas do lab. Formato: **sintoma → diagnóstico → correção**.
Isso é ouro pra CKA (a prova cobra muito debug), então documente até o que
resolveu rápido.

📖 **Referência oficial (liberada na prova):**
[Troubleshooting kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/troubleshooting-kubeadm/)
· [Debug running pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pods/)
· [Debug a cluster](https://kubernetes.io/docs/tasks/debug/debug-cluster/)

---

## Gotchas conhecidos deste setup (leia antes)

Estes são específicos do ambiente Hyper-V + ICS + Calico e valem por
antecipação:

### 1. Pod CIDR do Calico conflita com a rede dos nós
- **Sintoma:** pods sem rede, CoreDNS em `CrashLoopBackOff`, roteamento
  esquisito, nós que não estabilizam em Ready.
- **Causa:** o CIDR default do Calico é `192.168.0.0/16`, que **engloba** a rede
  dos nós `192.168.137.0/24` (ICS).
- **Correção:** usar pod CIDR `10.244.0.0/16` no `kubeadm init` **e** no
  manifesto do Calico — os dois têm que bater.

### 2. netplan estático some depois do reboot
- **Sintoma:** IP volta pra DHCP (ou some) após reiniciar a VM.
- **Causa:** cloud-init da box Vagrant regenera o netplan no boot.
- **Correção:** `network: {config: disabled}` em
  `/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg`
  (ver [Fase 1, Passo 3](01-vms-e-rede.md#passo-3--impedir-o-cloud-init-de-sobrescrever-o-netplan)).

### 3. `netplan apply` reclama de permissão
- **Sintoma:** warning "Permissions for ... are too open".
- **Correção:** `sudo chmod 600 /etc/netplan/99-k8s-static.yaml`.

### 4. kubelet não sobe / cgroup driver
- **Sintoma:** após `kubeadm init`, kubelet em loop; logs citam cgroup.
- **Causa:** containerd sem `SystemdCgroup = true` (mismatch com o kubelet).
- **Correção:** ativar no `/etc/containerd/config.toml` e
  `systemctl restart containerd` (Fase 2).

### 5. preflight: swap ligado
- **Sintoma:** `kubeadm init/join` falha no preflight por swap.
- **Correção:** `sudo swapoff -a` + comentar a linha de swap no `/etc/fstab`.

### 6. token do join expirou
- **Sintoma:** `kubeadm join` falha (token inválido) horas depois do init.
- **Correção:** no control plane, `kubeadm token create --print-join-command`.

---

## Comandos de diagnóstico que sempre ajudam

```bash
# Kubelet (o serviço que mais quebra)
sudo systemctl status kubelet
sudo journalctl -u kubelet -f

# Runtime de container
sudo systemctl status containerd
sudo crictl ps -a                 # containers pela ótica do CRI
sudo crictl pods                  # pods pela ótica do CRI

# Cluster
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl describe node <nó>
kubectl -n kube-system logs <pod>
kubectl get events -A --sort-by=.lastTimestamp

# Rede / preflight
ip -brief address ; ip route
sudo kubeadm init phase preflight   # revalida preflight sem executar tudo
```

---

## Log de incidentes

| # | Data | Fase | Sintoma | Causa | Correção |
|---|------|------|---------|-------|----------|
| | | | | | |

### Detalhamento

<!-- Duplique este bloco por incidente relevante -->

#### #NN — título curto
- **Fase:**
- **Sintoma:**
- **Como diagnostiquei:**
- **Causa raiz:**
- **Correção:**
- **Aprendizado / o que checar da próxima:**
