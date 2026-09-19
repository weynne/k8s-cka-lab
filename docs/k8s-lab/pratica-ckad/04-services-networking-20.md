# Prática CKAD — Services & Networking (20%)

Services (ClusterIP, NodePort), DNS interno, Ingress e NetworkPolicy — da ótica de
quem publica a aplicação.

📖 Docs liberadas: [Service](https://kubernetes.io/docs/concepts/services-networking/service/)
· [DNS para Services e Pods](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)
· [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
· [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

> 🚧 **Semente** — exercícios prontos + espaço pra adicionar mais.
> Todos assumem `kubectl config set-context --current --namespace=ckad`.
> Os exercícios de **Ingress** precisam do controller e os de **NetworkPolicy**
> precisam do **Calico** — veja o [README](README.md#preparar-o-lab-pra-ckad-uma-vez).

---

## Ex 1 — ClusterIP + DNS interno ⏱️ ~6min

**Tarefa:** exponha o deploy `web` (nginx, porta 80) como ClusterIP `web` e alcance-o
de outro pod **pelo nome**, primeiro curto e depois pelo FQDN.

<details><summary>Dica</summary>

Dentro do mesmo namespace basta `web`. De outro namespace: `web.ckad`. O FQDN
completo é `web.ckad.svc.cluster.local` — e é esse que você usa quando quer ter
certeza de que não há ambiguidade.
</details>

<details><summary>Solução</summary>

```bash
kubectl create deploy web --image=nginx --replicas=2
kubectl expose deploy web --port=80 --target-port=80        # cria o Service ClusterIP
kubectl get svc web -o wide
kubectl get endpoints web                                    # 2 IPs (um por pod)

kubectl run cliente --image=busybox --restart=Never --rm -it -- sh
  # dentro do pod:
  wget -qO- web
  wget -qO- web.ckad.svc.cluster.local
  nslookup web
  cat /etc/resolv.conf          # search ckad.svc.cluster.local svc.cluster.local ...
```
</details>

📖 [DNS para Services](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/)

---

## Ex 2 — NodePort e named port ⏱️ ~7min

**Tarefa:** publique `web` como NodePort e acesse do host. Depois faça o Service
apontar pra uma **porta nomeada** do container em vez do número.

<details><summary>Dica</summary>

`targetPort` aceita o **nome** da porta declarada no container (`ports[].name`) — isso
desacopla o Service da porta real, e é o que permite trocar a porta da app sem mexer
no Service. Nome de porta tem no máximo 15 caracteres.
</details>

<details><summary>Solução</summary>

```bash
kubectl expose deploy web --type=NodePort --port=80 --name=web-np
kubectl get svc web-np            # 80:3XXXX/TCP
curl http://<ip-do-nó>:3XXXX      # ☁️ na AWS: IP privado de dentro do nó, ou libere o SG
```
```yaml
# no container do deployment:
    ports:
      - { name: http, containerPort: 80 }
# no Service:
  ports:
    - { port: 80, targetPort: http }
```
```bash
kubectl get endpoints web-np      # continua resolvendo pra :80
```
</details>

📖 [Service — publicando](https://kubernetes.io/docs/concepts/services-networking/service/#publishing-services-service-types)

---

## Ex 3 — Service sem endpoints: achar o erro ⏱️ ~5min

**Tarefa:** o Service `quebrado` existe, tem ClusterIP, mas nada responde. Descubra
por quê e conserte.

<details><summary>Dica</summary>

Service é só um **selector de labels**. `ENDPOINTS: <none>` = nenhum pod casa com o
selector, ou os pods casam mas não estão `Ready`.
</details>

<details><summary>Solução</summary>

```bash
# injetar a falha:
kubectl expose deploy web --port=80 --name=quebrado
kubectl set selector svc quebrado 'app=errado'

kubectl get endpoints quebrado                       # <none>
kubectl get svc quebrado -o jsonpath='{.spec.selector}{"\n"}'
kubectl get pods --show-labels                       # qual label os pods REALMENTE têm
kubectl set selector svc quebrado 'app=web'          # corrigir
kubectl get endpoints quebrado                       # 2 IPs
```
- Se o selector estiver certo e mesmo assim não houver endpoints: olhe
  `kubectl get pods` — pod `Running` mas `0/1 READY` (readinessProbe falhando)
  **não entra** no Service.
</details>

📖 [Debug Services](https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/)

---

## Ex 4 — Ingress com host e path ⏱️ ~9min

**Tarefa:** publique dois deploys (`site` e `api`) sob o host `app.lab`, sendo `/` →
`site` e `/api` → `api`, usando a ingressClass `nginx`.

<details><summary>Dica</summary>

`kubectl create ingress` gera quase tudo: a sintaxe é
`--rule="host/path=service:port"`. O `pathType` importa: `Prefix` casa
`/api`, `/api/x`; `Exact` casa só `/api`. E lembre do `--class=nginx`.
</details>

<details><summary>Solução</summary>

```bash
kubectl create deploy site --image=nginx && kubectl expose deploy site --port=80
kubectl create deploy api  --image=nginx && kubectl expose deploy api  --port=80

kubectl create ingress app --class=nginx \
  --rule="app.lab/*=site:80" \
  --rule="app.lab/api*=api:80"

kubectl get ingress app
kubectl describe ingress app                     # confira as regras e o backend

NP=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.spec.ports[0].nodePort}')
curl -H 'Host: app.lab' http://<ip-do-nó>:$NP/
curl -H 'Host: app.lab' http://<ip-do-nó>:$NP/api
```
- Sem controller instalado, o Ingress é criado mas **não faz nada** (ADDRESS vazio) —
  é o erro nº 1 de quem testa Ingress em lab.
- Reescrita de path (`/api` → `/`) é anotação **específica do nginx**
  (`nginx.ingress.kubernetes.io/rewrite-target`), não do Ingress padrão.
</details>

📖 [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)

---

## Ex 5 — NetworkPolicy: default-deny + liberar por label ⏱️ ~9min

**Tarefa:** no namespace `ckad`, bloqueie **todo** tráfego de entrada nos pods e
depois libere que apenas pods com `role=frontend` falem com os pods `app=web` na
porta 80.

<details><summary>Dica</summary>

NetworkPolicy é **aditiva e allowlist**: assim que um pod é selecionado por alguma
policy de Ingress, tudo que não for explicitamente permitido é negado. Um
`podSelector: {}` seleciona **todos** os pods do namespace.
</details>

<details><summary>Solução</summary>

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: default-deny-ingress, namespace: ckad }
spec:
  podSelector: {}
  policyTypes: [Ingress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: frontend-para-web, namespace: ckad }
spec:
  podSelector:
    matchLabels: { app: web }
  policyTypes: [Ingress]
  ingress:
    - from:
        - podSelector:
            matchLabels: { role: frontend }
      ports:
        - { protocol: TCP, port: 80 }
```
```bash
kubectl apply -f netpol.yaml

kubectl run curl-bloqueado --image=busybox --restart=Never --rm -it -- wget -T3 -qO- web   # trava/falha
kubectl run curl-ok --image=busybox --restart=Never --labels=role=frontend --rm -it -- wget -T3 -qO- web   # responde
```
- **Só funciona com CNI que implementa policy** (Calico sim, Flannel **não**) — ver
  [Fase 5](../05-cni.md).
</details>

📖 [Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)

---

## Ex 6 — NetworkPolicy de egress e a pegadinha do DNS ⏱️ ~8min

**Tarefa:** faça os pods `app=web` só poderem **sair** para pods `app=db` na porta
5432. Descubra por que a app passa a falhar mesmo alcançando o IP do banco — e
conserte.

<details><summary>Dica</summary>

Policy de egress também bloqueia a consulta ao **CoreDNS** (UDP/TCP 53 no namespace
`kube-system`). Sem liberar o DNS, o pod resolve nada — e o sintoma parece "rede
quebrada", não "DNS bloqueado".
</details>

<details><summary>Solução</summary>

```yaml
spec:
  podSelector: { matchLabels: { app: web } }
  policyTypes: [Egress]
  egress:
    - to:
        - podSelector: { matchLabels: { app: db } }
      ports: [{ protocol: TCP, port: 5432 }]
    - to:                                   # <- o que faltava
        - namespaceSelector:
            matchLabels: { kubernetes.io/metadata.name: kube-system }
      ports:
        - { protocol: UDP, port: 53 }
        - { protocol: TCP, port: 53 }
```
```bash
kubectl exec <pod-web> -- nslookup db          # antes: timeout | depois: resolve
```
- O label `kubernetes.io/metadata.name` é posto automaticamente em **todo** namespace
  — é o jeito mais curto de selecionar um namespace pelo nome.
</details>

📖 [Network Policies — egress](https://kubernetes.io/docs/concepts/services-networking/network-policies/#default-deny-all-egress-traffic)

---

## Ex 7 — Testar um pod sem Service: port-forward ⏱️ ~4min

**Tarefa:** acesse a porta 80 de um pod específico da sua máquina, sem criar Service
nem Ingress.

<details><summary>Solução</summary>

```bash
kubectl port-forward pod/<nome> 8080:80          # ou deploy/web, svc/web
curl localhost:8080

# ouvir em todas as interfaces (útil no WSL/host remoto):
kubectl port-forward --address 0.0.0.0 svc/web 8080:80
```
- `port-forward` passa pelo **apiserver** — funciona mesmo sem NodePort e sem
  liberar porta no firewall/Security Group. É a forma mais rápida de testar algo
  (☁️ útil no lab AWS, onde abrir porta dá trabalho).
</details>

📖 [Port forward](https://kubernetes.io/docs/tasks/access-application-cluster/port-forward-access-application-cluster/)

---

## Ex 8 — Headless service e DNS por pod ⏱️ ~6min

**Tarefa:** crie um Service headless pra `web` e veja o DNS devolver os **IPs dos
pods** em vez de um ClusterIP.

<details><summary>Dica</summary>

Headless = `clusterIP: None`. Não há balanceamento nem IP virtual: o DNS responde com
o conjunto de endereços dos pods. É a base de StatefulSet (cada pod com nome estável).
</details>

<details><summary>Solução</summary>

```yaml
apiVersion: v1
kind: Service
metadata: { name: web-hl }
spec:
  clusterIP: None
  selector: { app: web }
  ports: [{ port: 80 }]
```
```bash
kubectl apply -f headless.yaml
kubectl run dig --image=busybox --restart=Never --rm -it -- nslookup web-hl
# retorna um Address por pod, em vez de um único ClusterIP
```
</details>

📖 [Headless Services](https://kubernetes.io/docs/concepts/services-networking/service/#headless-services)

---

## Espaço pra seus exercícios

<!-- Duplique o bloco: ## Ex N — título ⏱️ ~Xmin / Tarefa / <details>Dica</details> / <details>Solução</details> / 📖 doc -->

---

➡️ Próximo domínio: [Observability & Maintenance (15%)](05-observability-maintenance-15.md).
