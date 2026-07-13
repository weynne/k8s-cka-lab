# Prática — Serviços & Redes (20%)

Service (ClusterIP/NodePort/LoadBalancer), **NetworkPolicy**, **Ingress**, **DNS** e
**Gateway API**. Lembre: NetworkPolicy só funciona com CNI que suporta (Calico, não
Flannel — ver [../05-cni.md](../05-cni.md)).

📖 Docs liberadas: [Service](https://kubernetes.io/docs/concepts/services-networking/service/)
· [NetworkPolicy](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
· [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
· [Gateway API](https://kubernetes.io/docs/concepts/services-networking/gateway/)
· [Debug de DNS](https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/)

> 🚧 **Semente** — exercícios prontos + espaço pra adicionar mais.

---

## Ex 1 — Expor um Deployment (ClusterIP → NodePort) ⏱️ ~5min

**Tarefa:** crie o deploy `web` (nginx, 3 réplicas), exponha na porta 80 como
ClusterIP e depois como NodePort; acesse pelo IP do nó.

<details><summary>Solução</summary>

```bash
kubectl create deploy web --image=nginx --replicas=3
kubectl expose deploy web --port=80                     # ClusterIP
kubectl expose deploy web --port=80 --type=NodePort --name=web-np
kubectl get svc web-np -o wide                          # porta 3xxxx
curl http://192.168.137.11:<nodePort>
```
</details>

📖 [Service](https://kubernetes.io/docs/concepts/services-networking/service/)

---

## Ex 2 — NetworkPolicy: default-deny + liberar um app ⏱️ ~8min

**Tarefa:** no namespace `secure`, bloqueie **todo** tráfego de entrada nos pods e
depois libere ingress na porta 80 só a partir de pods com label `role=frontend`.

<details><summary>Dica</summary>

Duas policies: uma `default-deny` (podSelector `{}`, policyTypes Ingress) e uma que
permite o `from.podSelector`. Teste com dois pods (um `role=frontend`, um sem).
</details>

<details><summary>Solução (esqueleto)</summary>

```yaml
# default-deny-ingress
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: default-deny, namespace: secure }
spec:
  podSelector: {}
  policyTypes: [Ingress]
---
# allow-frontend
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: allow-frontend, namespace: secure }
spec:
  podSelector: {}
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector: { matchLabels: { role: frontend } }
    ports:
    - { protocol: TCP, port: 80 }
```
</details>

📖 [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

---

## Ex 3 — Ingress: rotear host/path pra 2 Services ⏱️ ~10min

**Tarefa:** com um ingress controller no cluster, roteie `app.lab.local/` pro Service
`web1` e `app.lab.local/v2` pro `web2`.

<details><summary>Dica</summary>

O objeto `Ingress` só **descreve** as regras — quem executa é um **ingress
controller** (a prova costuma já ter um; no lab, instale o ingress-nginx). Use
`ingressClassName` e `pathType: Prefix`.
</details>

<details><summary>Solução (esqueleto)</summary>

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app
spec:
  ingressClassName: nginx
  rules:
  - host: app.lab.local
    http:
      paths:
      - { path: /,   pathType: Prefix, backend: { service: { name: web1, port: { number: 80 } } } }
      - { path: /v2, pathType: Prefix, backend: { service: { name: web2, port: { number: 80 } } } }
```
```bash
# sem DNS, teste forçando o Host:
curl -H 'Host: app.lab.local' http://<IP-do-ingress-controller>/
curl -H 'Host: app.lab.local' http://<IP-do-ingress-controller>/v2
```
</details>

> 🔧 **Lab:** instale um controller uma vez (ingress-nginx). **Gateway API** é a
> alternativa moderna e também cai na CKA — mesma ideia com
> `GatewayClass` + `Gateway` + `HTTPRoute`.

📖 [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
· [Gateway API](https://kubernetes.io/docs/concepts/services-networking/gateway/)

---

## Ex 4 — Resolver um Service por FQDN ⏱️ ~4min

**Tarefa:** de dentro de um pod, resolva o Service `web` (ns `default`) pelo nome
completo e entenda por que o nome curto também funciona.

<details><summary>Solução</summary>

```bash
kubectl run tmp --image=busybox:1.36 --restart=Never -- sleep 3600
kubectl exec tmp -- nslookup web.default.svc.cluster.local     # FQDN
kubectl exec tmp -- nslookup web                               # curto (resolve pelo 'search')
kubectl exec tmp -- cat /etc/resolv.conf                       # 'search default.svc.cluster.local svc...'
kubectl delete pod tmp
```
- Padrão: **`<svc>.<ns>.svc.cluster.local`**. Pods: `<ip-com-hifens>.<ns>.pod.cluster.local`.
</details>

📖 [DNS for Services and Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)

---

## Ex 5 — NetworkPolicy de egress (liberar só DNS) ⏱️ ~8min

**Tarefa:** no ns `secure`, bloqueie **toda** saída dos pods, liberando apenas DNS
(porta 53). Confirme que `nslookup` funciona mas `curl` externo falha. (Requer Calico.)

<details><summary>Solução (esqueleto)</summary>

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: deny-egress-except-dns, namespace: secure }
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
  - to:
    - namespaceSelector: {}          # alcança o CoreDNS no kube-system
    ports:
    - { protocol: UDP, port: 53 }
    - { protocol: TCP, port: 53 }
```
```bash
kubectl -n secure run t --image=busybox:1.36 --restart=Never -- sleep 3600
kubectl -n secure exec t -- nslookup kubernetes.default   # OK (DNS liberado)
kubectl -n secure exec t -- wget -T3 -qO- http://1.1.1.1  # trava/timeout (egress bloqueado)
```
</details>

📖 [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

---

## Adicione mais

- [ ] Gateway API completo: `GatewayClass` + `Gateway` + `HTTPRoute` com split de tráfego.
- [ ] Service `ExternalName` apontando pra um host de fora.
- [ ] `endpoints`/`EndpointSlice` de um Service sem selector.
