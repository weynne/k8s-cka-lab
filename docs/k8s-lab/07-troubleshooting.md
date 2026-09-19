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

## Gotchas do [Caminho C — lab na AWS](00b-aws-ec2.md)

Só valem se você montou o cluster em EC2. **Regra de ouro: na AWS, suspeite do
Security Group antes de qualquer outra coisa** — ele falha em silêncio (timeout),
não com erro claro.

### A1. `kubeadm join` trava ou dá timeout no apiserver
- **Sintoma:** o join fica pendurado e termina em
  `couldn't validate the identity of the API Server` / connection timed out.
- **Causa:** worker não alcança a **6443** do control plane (SG sem a regra
  self-reference, ou instâncias com SGs diferentes).
- **Diagnóstico:** do worker, `nc -zv <ip-privado-cp> 6443`.
- **Correção:** [C4](00b-aws-ec2.md#c4--security-group-as-regras-a-parte-que-mais-quebra) —
  mesmo SG nas 3 instâncias, com "all traffic" vindo do próprio SG.

### A2. `kubectl logs`/`exec` dá timeout (mas `get`/`describe` funcionam)
- **Sintoma:** `Error from server: Get "https://<ip>:10250/...": dial tcp i/o timeout`.
- **Causa:** apiserver não alcança a **10250** (kubelet) do nó alvo — SG de novo.
- **Correção:** liberar 10250 entre os nós (a regra self-reference cobre).

### A3. Nós Ready, mas pod de um nó não fala com pod do outro
- **Sintoma:** ping entre nós OK, service intermitente (só responde quando cai no
  pod local), CoreDNS resolvendo às vezes.
- **Causa:** tráfego **encapsulado** do CNI bloqueado — IPIP (**protocolo 4**,
  default do `calico.yaml`), VXLAN (**4789/udp**) ou Flannel (**8472/udp**). Um SG
  aberto só em TCP não deixa passar.
- **Correção:** regra com `--protocol -1` vindo do próprio SG.
- **Variante:** se você desligou o encapsulamento (Calico roteado), é o
  **source/dest check** da EC2 descartando o pacote → veja
  [C5](00b-aws-ec2.md#c5--sourcedest-check-e-mtu).

### A4. Download/`curl` dentro do pod trava no meio
- **Sintoma:** ping e requisições pequenas OK; transferência maior congela.
- **Causa:** MTU. A VPC usa 9001 e o overlay soma cabeçalho.
- **Correção:** fixar a MTU do CNI (8941, ou 1440 conservador) —
  [C5](00b-aws-ec2.md#c5--sourcedest-check-e-mtu).

### A5. Depois de parar/religar as instâncias, o kubectl de fora não conecta
- **Sintoma:** `kubectl` do notebook dá timeout ou erro de certificado; dentro do
  `k8s-cp` está tudo Ready.
- **Causa:** sem Elastic IP, o **IP público mudou** no start — o kubeconfig aponta
  pro endereço antigo (e o SAN do certificado não cobre o novo).
- **Correção:** refazer o `server:` do kubeconfig
  ([C8](00b-aws-ec2.md#c8--kubectl-da-sua-máquina-wsl-apontando-pro-cluster)) ou associar um EIP.
  **O IP privado não muda** — o cluster em si continua íntegro.

### A6. Nó volta como `ip-10-x-x-x` depois do reboot
- **Sintoma:** o hostname renomeado some; aparece um nó duplicado no
  `kubectl get nodes`.
- **Causa:** cloud-init reescreve o hostname a cada boot.
- **Correção:** `preserve_hostname: true` em `/etc/cloud/cloud.cfg.d/99-hostname.cfg`
  ([C6](00b-aws-ec2.md#c6--hostname-e-etchosts-o-que-sobra-da-fase-1)). Se já entrou
  no cluster com o nome errado: `kubectl delete node <nome-antigo>` + `kubeadm reset`
  e join de novo (ou use `--node-name` no join).

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
