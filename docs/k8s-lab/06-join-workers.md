# Fase 6 — Join dos workers

**Objetivo:** juntar `k8s-w1` e `k8s-w2` ao cluster com `kubeadm join`, confirmar
os 3 nós **Ready** e rodar um smoke test end-to-end.

**Rodar em:** `kubeadm join` nos **workers**; verificação no `k8s-cp`.

📖 **Referência oficial (liberada na prova):**
[Join your nodes](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/#join-nodes)
· [kubeadm join (reference)](https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-join/)
· [kubeadm token](https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-token/)

---

## Passo 1 — obter o comando de join

Use o que o `kubeadm init` imprimiu (salvo em `kubeadm-init.out` na Fase 4). Se o
token já expirou (>24h), **regenere no `k8s-cp`**:

```bash
kubeadm token create --print-join-command
```

- Imprime um `kubeadm join ...` novo, com token válido e o hash do CA atual.
- Para conferir tokens existentes: `kubeadm token list`.

---

## Passo 2 — juntar cada worker

**Em `k8s-w1` e `k8s-w2`** (com sudo), rode o comando obtido:

```bash
sudo kubeadm join 192.168.137.10:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --cri-socket=unix:///run/containerd/containerd.sock
```

O que acontece:
- `192.168.137.10:6443` — endereço do apiserver (o advertise-address do control
  plane, porta 6443).
- `--token` — credencial de bootstrap temporária que autoriza o nó a entrar.
- `--discovery-token-ca-cert-hash sha256:...` — o worker usa esse hash pra
  **verificar** que está falando com o control plane certo (não um impostor),
  antes de confiar nele. É a proteção contra MITM no bootstrap.
- Sob o capô: o kubelet do worker faz o TLS bootstrap, recebe seu certificado e
  se registra no apiserver como nó.

> Preflight aqui exige as mesmas condições da Fase 2 (swap off, containerd,
> sysctl). Se pular a Fase 2 num worker, o join falha no preflight.

---

## Passo 3 — verificar do control plane

**No `k8s-cp`:**

```bash
kubectl get nodes -o wide
```

- Espere os 3 nós **Ready**. Os workers podem levar ~1 min pra virar Ready
  (o pod do CNI precisa subir neles primeiro — veja com
  `kubectl get pods -A -o wide`).

(Opcional) rotular os workers pra aparecer o ROLES:

```bash
kubectl label node k8s-w1 node-role.kubernetes.io/worker=worker
kubectl label node k8s-w2 node-role.kubernetes.io/worker=worker
```

---

## Passo 4 — smoke test end-to-end

```bash
kubectl create deployment nginx --image=nginx --replicas=2
kubectl expose deployment nginx --type=NodePort --port=80
kubectl get pods -o wide          # os 2 pods devem cair em nós diferentes
kubectl get svc nginx             # anote a porta NodePort (3xxxx)
```

Do host (Windows/Linux, ou de outra VM), acesse `http://192.168.137.11:<NodePort>`
e `http://192.168.137.12:<NodePort>` — deve responder o nginx pelos dois workers.

- Valida a stack inteira: scheduling nos workers, rede de pod (CNI), Service e
  NodePort. Limpe depois: `kubectl delete deploy,svc nginx`.

---

## Resultado

```text
# cole: kubectl get nodes -o wide  (3x Ready)  e  kubectl get svc nginx
```

---

## Checklist de saída da Fase 6

- [ ] `k8s-w1` e `k8s-w2` juntados sem erro
- [ ] `kubectl get nodes` mostra os **3 Ready**
- [ ] pod do CNI (calico-node / kube-flannel-ds) Running nos 3 nós
- [ ] smoke test: nginx acessível via NodePort nos dois workers

---

🎉 **Cluster completo.** Atualize o [progresso no README](README.md#progresso) e
vá pra **[pratica/](pratica/README.md)** — exercícios estilo prova pelos 5 domínios
da CKA (por peso). Referência rápida de comandos no [cheatsheet](08-cheatsheet-cka.md).

## Notas / gotchas

- _(anote aqui — ex.: token expirado, hash do CA errado, worker sem preparo da
  Fase 2, nó Ready mas pod não agenda, etc.)_
