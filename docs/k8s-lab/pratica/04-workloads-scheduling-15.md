# Prática — Workloads & Scheduling (15%)

Deployments, DaemonSets, **afinidade/nodeSelector**, **taints/tolerations**, limites
de recursos, ConfigMaps/Secrets.

📖 Docs liberadas: [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
· [Taints & tolerations](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/)
· [Assign pods to nodes](https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/)
· [Recursos (requests/limits)](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)

> 🚧 **Semente** — exercícios prontos + espaço pra adicionar mais.

---

## Ex 1 — Deployment: criar, escalar, rollout ⏱️ ~5min

**Tarefa:** crie o deploy `api` (nginx, 2 réplicas), escale pra 4, atualize a imagem
pra `nginx:1.27` e depois faça rollback.

<details><summary>Solução</summary>

```bash
kubectl create deploy api --image=nginx --replicas=2
kubectl scale deploy api --replicas=4
kubectl set image deploy/api nginx=nginx:1.27
kubectl rollout status deploy/api
kubectl rollout history deploy/api
kubectl rollout undo deploy/api            # rollback
```
</details>

📖 [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)

---

## Ex 2 — Prender um pod a um nó (nodeSelector/affinity) ⏱️ ~6min

**Tarefa:** rotule `k8s-w2` com `disk=ssd` e faça um pod `cache` rodar **só** nesse nó.

<details><summary>Solução</summary>

```bash
kubectl label node k8s-w2 disk=ssd
kubectl run cache --image=redis $do > cache.yaml   # editar spec.nodeSelector:
#   nodeSelector: { disk: ssd }
kubectl apply -f cache.yaml
kubectl get pod cache -o wide                       # NODE = k8s-w2
```
</details>

📖 [Assign pods to nodes](https://kubernetes.io/docs/tasks/configure-pod-container/assign-pods-nodes/)

---

## Ex 3 — Requests/limits de recursos ⏱️ ~5min

**Tarefa:** crie um pod `bench` com request `100m/128Mi` e limit `250m/256Mi`.

<details><summary>Solução (trecho do container)</summary>

```yaml
resources:
  requests: { cpu: "100m", memory: "128Mi" }
  limits:   { cpu: "250m", memory: "256Mi" }
```
```bash
kubectl apply -f bench.yaml
kubectl describe pod bench | grep -A4 Limits
```
</details>

📖 [Manage resources for containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)

---

## Ex 4 — DaemonSet com liveness/readiness probe ⏱️ ~8min

**Tarefa:** rode um pod por nó (DaemonSet, imagem nginx) com um `livenessProbe` e um
`readinessProbe` HTTP.

<details><summary>Dica</summary>

Não existe `kubectl create daemonset`. Gere um Deployment com `$do`, troque o `kind`
pra `DaemonSet` e remova `replicas`/`strategy`. Por padrão o DaemonSet **não** roda no
control plane (taint `NoSchedule`) — só nos workers, a menos que tolere.
</details>

<details><summary>Solução (esqueleto)</summary>

```bash
kubectl create deploy node-agent --image=nginx $do > ds.yaml
# editar ds.yaml: kind: DaemonSet ; remover spec.replicas, spec.strategy, status
```
```yaml
# no container, adicionar as probes:
livenessProbe:
  httpGet: { path: /, port: 80 }
  initialDelaySeconds: 5
  periodSeconds: 10
readinessProbe:
  httpGet: { path: /, port: 80 }
  periodSeconds: 5
```
```bash
kubectl apply -f ds.yaml
kubectl get pods -o wide -l app=node-agent    # um por worker
kubectl describe pod -l app=node-agent | grep -A2 -E 'Liveness|Readiness'
```
</details>

📖 [DaemonSet](https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/)
· [Liveness/Readiness probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)

---

## Ex 5 — Pod com ConfigMap + Secret + ServiceAccount ⏱️ ~8min

**Tarefa:** crie o ConfigMap `app-cfg`, o Secret `app-sec` e a SA `app-sa`, e um pod
que use a SA, injete o ConfigMap e o Secret como **env** e monte o ConfigMap como
**volume**.

<details><summary>Solução (esqueleto)</summary>

```bash
kubectl create configmap app-cfg --from-literal=LOG_LEVEL=debug --from-literal=MODE=prod
kubectl create secret generic app-sec --from-literal=API_KEY=s3cr3t
kubectl create serviceaccount app-sa
```
```yaml
# pod spec:
serviceAccountName: app-sa
containers:
- name: app
  image: busybox:1.36
  command: ["sh","-c","sleep 3600"]
  envFrom:
  - configMapRef: { name: app-cfg }     # LOG_LEVEL, MODE viram env
  - secretRef:    { name: app-sec }     # API_KEY vira env
  volumeMounts:
  - { name: cfg, mountPath: /etc/appcfg }
volumes:
- name: cfg
  configMap: { name: app-cfg }          # cada chave vira um arquivo em /etc/appcfg
```
```bash
kubectl exec app -- env | grep -E 'LOG_LEVEL|MODE|API_KEY'
kubectl exec app -- ls /etc/appcfg      # LOG_LEVEL  MODE
```
</details>

📖 [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)
· [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)

---

## Adicione mais

- [ ] `taints/tolerations` + `nodeAffinity` combinados (dedicar um nó a uma carga).
- [ ] `startupProbe` num app de boot lento.
- [ ] Pod com `initContainers` preparando um volume antes do container principal.
