# Prática CKAD — Observability & Maintenance (15%)

Probes, logs, `kubectl debug`, métricas e o cuidado com **APIs depreciadas** — o
domínio onde a CKA e a CKAD mais se encostam.

📖 Docs liberadas: [Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
· [Debug de pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pods/)
· [Logs](https://kubernetes.io/docs/concepts/cluster-administration/logging/)
· [Deprecated API migration guide](https://kubernetes.io/docs/reference/using-api/deprecation-guide/)

> 🚧 **Semente** — exercícios prontos + espaço pra adicionar mais.
> Todos assumem `kubectl config set-context --current --namespace=ckad`.

---

## Ex 1 — As três probes, e quando usar cada uma ⏱️ ~8min

**Tarefa:** no pod `saude` (nginx), configure: `readinessProbe` HTTP em `/` (só entra
no Service quando responder), `livenessProbe` HTTP que reinicie o container se travar,
e `startupProbe` que dê **60s** de tolerância na subida.

<details><summary>Dica</summary>

- **readiness** → "posso receber tráfego?" Falhou, sai do Service (não reinicia).
- **liveness** → "estou travado?" Falhou, o kubelet **reinicia** o container.
- **startup** → "ainda estou bootando?" Enquanto ela não passa, liveness e readiness
  ficam **suspensas** — é o jeito certo de lidar com app lenta pra subir, em vez de
  inflar o `initialDelaySeconds` da liveness.

Tolerância total da startup = `failureThreshold × periodSeconds`.
</details>

<details><summary>Solução</summary>

```yaml
    readinessProbe:
      httpGet: { path: /, port: 80 }
      periodSeconds: 5
    livenessProbe:
      httpGet: { path: /, port: 80 }
      periodSeconds: 10
      failureThreshold: 3
    startupProbe:
      httpGet: { path: /, port: 80 }
      periodSeconds: 5
      failureThreshold: 12          # 12 x 5s = 60s pra subir
```
```bash
kubectl apply -f saude.yaml
kubectl describe pod saude | grep -E 'Liveness|Readiness|Startup'
# provocar falha de liveness e ver o restart:
kubectl exec saude -- rm /usr/share/nginx/html/index.html
kubectl get pod saude -w        # RESTARTS aumenta
```
Variantes que também caem: `exec` (`command: ['cat','/tmp/ok']`) e `tcpSocket`
(`port: 3306`).
</details>

📖 [Configurar probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)

---

## Ex 2 — CrashLoopBackOff: ler o motivo certo ⏱️ ~6min

**Tarefa:** um pod reinicia sem parar. Descubra a causa e o **exit code**, sem
adivinhar.

<details><summary>Dica</summary>

`kubectl logs` mostra o container **atual** — que acabou de nascer e ainda não falhou.
O que interessa está em `--previous`. E o `describe` traz `Last State` com o exit
code: `1` = erro da app, `137` = SIGKILL (OOM ou liveness), `143` = SIGTERM.
</details>

<details><summary>Solução</summary>

```bash
# injetar a falha:
kubectl run quebra --image=busybox --command -- sh -c 'echo iniciando; sleep 2; exit 1'

kubectl get pod quebra -w                        # CrashLoopBackOff
kubectl logs quebra --previous                   # saída da execução que MORREU
kubectl describe pod quebra | grep -A6 'Last State'
kubectl get pod quebra -o jsonpath='{.status.containerStatuses[0].lastState.terminated.exitCode}{"\n"}'
```
- `BackOff` é só o **atraso crescente** entre tentativas (10s, 20s, 40s… até 5min) —
  não é a causa. A causa está nos logs/exit code.
- Exit `137` com `Reason: OOMKilled` = estourou o `limits.memory`.
</details>

📖 [Debug pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/)

---

## Ex 3 — Logs: multi-container, tempo e seleção por label ⏱️ ~5min

**Tarefa:** pegue os logs do sidecar do pod `logapp`, só os últimos 5 minutos, depois
as 20 últimas linhas de **todos** os pods de um deployment.

<details><summary>Solução</summary>

```bash
kubectl logs logapp -c sidecar --since=5m
kubectl logs logapp --all-containers=true --prefix
kubectl logs -l app=web --tail=20 --prefix        # todos os pods do label
kubectl logs deploy/web -f                        # segue (um pod do deploy)
kubectl logs logapp --timestamps | tail -5
```
- Sem `-c` num pod multi-container, o `kubectl logs` **erra** pedindo o container.
- Pro grosso do debug: `kubectl logs ... | grep -i error` continua sendo o mais rápido.
</details>

📖 [Logging](https://kubernetes.io/docs/concepts/cluster-administration/logging/)

---

## Ex 4 — `kubectl debug`: container efêmero e cópia do pod ⏱️ ~8min

**Tarefa:** a imagem do pod `distro` não tem shell nem `curl`. Investigue a rede dele
mesmo assim; depois crie uma **cópia** do pod com shell pra mexer à vontade.

<details><summary>Dica</summary>

`kubectl debug -it <pod> --image=busybox --target=<container>` injeta um **container
efêmero** no pod que já está rodando, compartilhando o namespace de processos do alvo
— sem reiniciar nada. `--copy-to` cria um pod novo, cópia do original, sem afetar o
que está em produção.
</details>

<details><summary>Solução</summary>

```bash
# imagem sem shell nenhum (é esse o cenário):
kubectl run distro --image=registry.k8s.io/pause:3.9
kubectl exec -it distro -- sh        # falha: executable file not found

kubectl debug -it distro --image=busybox --target=distro -- sh
  # dentro: wget -qO- web ; nslookup web ; ps aux

# cópia pra mexer sem risco:
kubectl debug distro --copy-to=distro-debug --image=busybox -it -- sh
kubectl delete pod distro-debug
```
- Container efêmero **não** pode ter probes nem ports, e não é removido — ele vive até
  o pod morrer.
</details>

📖 [Ephemeral containers / kubectl debug](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pods/#ephemeral-container)

---

## Ex 5 — Métricas: achar quem consome ⏱️ ~5min

**Tarefa:** descubra qual pod do cluster está usando mais memória e qual nó está mais
carregado.

<details><summary>Solução</summary>

```bash
kubectl top nodes
kubectl top pods -A --sort-by=memory | head
kubectl top pods -A --sort-by=cpu | head
kubectl top pod <pod> --containers          # quebra por container
```
- `error: Metrics API not available` = metrics-server ausente ou não-Ready (ver
  [README](README.md#1-metrics-server--habilita-kubectl-top-e-hpa)).
- `kubectl top` mostra o **uso**; `kubectl describe node` mostra o **requests
  alocado**. Um nó pode estar "cheio" de requests com uso baixíssimo — e é isso que
  faz pod ficar `Pending`.
</details>

📖 [Resource metrics pipeline](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/)

---

## Ex 6 — API depreciada: migrar um manifesto ⏱️ ~7min

**Tarefa:** o manifesto abaixo é antigo e o cluster o recusa. Descubra as versões
corretas e migre.

```yaml
apiVersion: extensions/v1beta1          # Deployment
kind: Deployment
---
apiVersion: networking.k8s.io/v1beta1   # Ingress
kind: Ingress
---
apiVersion: policy/v1beta1              # PodDisruptionBudget
kind: PodDisruptionBudget
```

<details><summary>Dica</summary>

`kubectl api-resources` lista o **APIVERSION atual** de cada kind.
`kubectl explain <kind>` mostra a versão que o cluster usaria. Pra saber quando algo
saiu, o **Deprecated API Migration Guide** é doc liberada na prova.
</details>

<details><summary>Solução</summary>

```bash
kubectl api-resources | grep -iE 'deployment|ingress|poddisruption'
kubectl explain deployment | head -3        # apps/v1
kubectl api-versions | grep policy          # policy/v1
```
| Antigo | Atual |
|--------|-------|
| `extensions/v1beta1` Deployment | `apps/v1` |
| `networking.k8s.io/v1beta1` Ingress | `networking.k8s.io/v1` (muda também `backend` → `backend.service`) |
| `policy/v1beta1` PDB | `policy/v1` |

```bash
kubectl apply -f antigo.yaml --dry-run=server     # valida contra o apiserver de verdade
kubectl convert -f antigo.yaml --output-version apps/v1   # plugin kubectl-convert, se instalado
```
- `--dry-run=server` é o atalho honesto: o apiserver responde se aceita ou não, sem
  criar nada.
</details>

📖 [Deprecated API migration guide](https://kubernetes.io/docs/reference/using-api/deprecation-guide/)

---

## Ex 7 — Events: a linha do tempo do que deu errado ⏱️ ~4min

**Tarefa:** liste os eventos do namespace em ordem cronológica e depois só os de um
pod específico.

<details><summary>Solução</summary>

```bash
kubectl get events --sort-by=.lastTimestamp
kubectl get events --field-selector involvedObject.name=<pod>
kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp | tail -20
kubectl describe pod <pod> | sed -n '/Events:/,$p'
```
- Eventos **expiram** (1h por padrão) — se o problema é antigo, eles já sumiram e
  sobra o `describe`/logs.
</details>

📖 [Debug de aplicação](https://kubernetes.io/docs/tasks/debug/debug-application/)

---

## Ex 8 — Pod `Pending`: scheduling ou recurso? ⏱️ ~6min

**Tarefa:** um pod não sai de `Pending`. Determine se é falta de recurso, taint, ou
volume — em menos de 1 minuto.

<details><summary>Solução</summary>

```bash
kubectl describe pod <pod> | sed -n '/Events:/,$p'
```
| Mensagem no Event | Causa | Saída |
|---|---|---|
| `Insufficient cpu/memory` | requests maiores que a folga dos nós | baixar requests ou escalar o nó |
| `node(s) had untolerated taint` | taint no nó (ex.: control-plane) | adicionar toleration ou mandar pro worker |
| `didn't match Pod's node affinity/selector` | `nodeSelector`/affinity sem nó correspondente | corrigir o label ou o selector |
| `pod has unbound immediate PersistentVolumeClaims` | PVC `Pending` | criar PV/StorageClass |
| `0/3 nodes are available` + nada mais | ver `kubectl describe node` | conferir taints e alocação |

```bash
kubectl describe node <nó> | grep -A6 'Allocated resources'
kubectl get pvc
```
</details>

📖 [Debug pods — Pending](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/)

---

## Espaço pra seus exercícios

<!-- Duplique o bloco: ## Ex N — título ⏱️ ~Xmin / Tarefa / <details>Dica</details> / <details>Solução</details> / 📖 doc -->

---

🎉 Rodou os 5 domínios? Volte pro [README da trilha](README.md#sugestão-de-rotação-de-estudo)
e repita cronometrando — na CKAD o que falta quase sempre é **tempo**, não conteúdo.
