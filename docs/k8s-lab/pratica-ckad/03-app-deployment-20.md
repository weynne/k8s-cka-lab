# Prática CKAD — Application Deployment (20%)

Deployments e rollouts, estratégias (rolling, recreate, blue/green, canary),
escala/HPA e os dois empacotadores que caem na prova: **Helm** e **Kustomize**.

📖 Docs liberadas: [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
· [Rolling update](https://kubernetes.io/docs/tutorials/kubernetes-basics/update/update-intro/)
· [HPA](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
· [Kustomize](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/)
· 🔧 [Helm](https://helm.sh/docs/) (permitido na CKAD — confirme no handbook)

> 🚧 **Semente** — exercícios prontos + espaço pra adicionar mais.
> Todos assumem `kubectl config set-context --current --namespace=ckad`.

---

## Ex 1 — Rollout: atualizar, pausar, reverter ⏱️ ~7min

**Tarefa:** crie o deploy `web` (nginx:1.25, 4 réplicas), atualize pra `1.27`
anotando o motivo, pause no meio, retome e por fim volte pra revisão anterior.

<details><summary>Dica</summary>

`kubectl rollout` tem `status`, `history`, `pause`, `resume` e `undo`. A coluna
CHANGE-CAUSE do `history` vem da anotação `kubernetes.io/change-cause`.
</details>

<details><summary>Solução</summary>

```bash
kubectl create deploy web --image=nginx:1.25 --replicas=4
kubectl set image deploy/web nginx=nginx:1.27
kubectl annotate deploy/web kubernetes.io/change-cause="sobe pra 1.27" --overwrite

kubectl rollout pause deploy/web          # congela no meio da troca
kubectl get pods -l app=web               # convivendo as duas versões
kubectl rollout resume deploy/web
kubectl rollout status deploy/web

kubectl rollout history deploy/web
kubectl rollout undo deploy/web                      # volta 1 revisão
kubectl rollout undo deploy/web --to-revision=1      # volta pra uma específica
kubectl get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```
</details>

📖 [Deployments — rollout](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#updating-a-deployment)

---

## Ex 2 — maxSurge / maxUnavailable ⏱️ ~6min

**Tarefa:** configure o `web` pra que durante a atualização **nunca falte réplica**
(`maxUnavailable: 0`) e **suba no máximo 1 extra** por vez. Depois troque a estratégia
pra `Recreate` e observe a diferença.

<details><summary>Dica</summary>

`maxUnavailable: 0` + `maxSurge: 1` = atualização mais lenta e sem queda de
capacidade. Com `Recreate`, o Deployment **mata tudo** antes de subir o novo — há
downtime, mas é o que se usa quando duas versões não podem coexistir (migração de
schema, por exemplo).
</details>

<details><summary>Solução</summary>

```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate: { maxSurge: 1, maxUnavailable: 0 }
```
```bash
kubectl patch deploy web -p '{"spec":{"strategy":{"rollingUpdate":{"maxSurge":1,"maxUnavailable":0},"type":"RollingUpdate"}}}'
kubectl set image deploy/web nginx=nginx:1.26 && kubectl get pods -l app=web -w

# Recreate (note: rollingUpdate precisa sair junto)
kubectl patch deploy web --type=json \
  -p='[{"op":"replace","path":"/spec/strategy","value":{"type":"Recreate"}}]'
kubectl set image deploy/web nginx=nginx:1.27 && kubectl get pods -l app=web -w
```
</details>

📖 [Estratégias de Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#strategy)

---

## Ex 3 — Blue/green trocando o selector do Service ⏱️ ~8min

**Tarefa:** tenha `app-blue` (nginx:1.25) e `app-green` (nginx:1.27) rodando ao mesmo
tempo, com o Service `app` mandando tráfego **só pro blue**. Depois vire tudo pro
green num comando, e volte.

<details><summary>Dica</summary>

O truque é o **label do pod**: os dois deployments marcam os pods com um label comum
(`tier=app`) e um distinto (`versao=blue|green`); o Service seleciona
`tier=app,versao=<cor>`. Trocar de cor = `kubectl set selector` no Service — corte
instantâneo, sem esperar rollout.

⚠️ O `spec.selector` de um **Deployment é imutável** — não tente reescrevê-lo depois
de criado. **Acrescentar** labels ao `template` é permitido (o selector original
continua casando), e é isso que a solução faz.
</details>

<details><summary>Solução</summary>

```bash
kubectl create deploy app-blue  --image=nginx:1.25 --replicas=2
kubectl create deploy app-green --image=nginx:1.27 --replicas=2

# ADICIONA labels ao pod template (o selector app=app-blue/-green segue valendo)
kubectl patch deploy app-blue  -p '{"spec":{"template":{"metadata":{"labels":{"tier":"app","versao":"blue"}}}}}'
kubectl patch deploy app-green -p '{"spec":{"template":{"metadata":{"labels":{"tier":"app","versao":"green"}}}}}'
kubectl get pods --show-labels             # confirme tier=app em todos

kubectl create svc clusterip app --tcp=80:80
kubectl set selector svc app 'tier=app,versao=blue'
kubectl get endpoints app -o wide          # só IPs dos pods blue

kubectl set selector svc app 'tier=app,versao=green'   # o "switch"
kubectl get endpoints app -o wide          # agora só green
```
- Vantagem: rollback é instantâneo (troca o selector de volta). Custo: duas frotas
  ligadas ao mesmo tempo.
</details>

📖 [Service — selector](https://kubernetes.io/docs/concepts/services-networking/service/)

---

## Ex 4 — Canary por proporção de réplicas ⏱️ ~7min

**Tarefa:** mande **~20%** do tráfego pra nova versão sem nenhum ingress especial.

<details><summary>Dica</summary>

Com um Service selecionando o label **comum** às duas versões, o kube-proxy balanceia
entre **todos** os endpoints. A proporção sai do **número de réplicas**: 8 estáveis +
2 canário ≈ 80/20.
</details>

<details><summary>Solução</summary>

```bash
kubectl scale deploy app-blue --replicas=8      # estável
kubectl scale deploy app-green --replicas=2     # canário
kubectl set selector svc app 'tier=app'         # pega as DUAS versões
kubectl get endpoints app -o jsonpath='{.subsets[*].addresses[*].ip}{"\n"}' | wc -w   # 10

# promover: sobe o canário, derruba o estável
kubectl scale deploy app-green --replicas=10 && kubectl scale deploy app-blue --replicas=0
```
- Granularidade é limitada pelo número de pods (com 10 pods, o mínimo é 10%). Canário
  fino de verdade é trabalho de Ingress/service mesh — fora do escopo da CKAD.
</details>

📖 [Canary deployments](https://kubernetes.io/docs/concepts/workloads/management/#canary-deployments)

---

## Ex 5 — Escala manual e HPA ⏱️ ~7min

**Tarefa:** escale `web` pra 6 réplicas na mão; depois crie um HPA que mantenha o uso
de CPU em 50%, entre 2 e 10 réplicas, e comprove que ele está lendo métricas.

<details><summary>Dica</summary>

HPA **exige** requests de CPU no pod (o alvo é percentual do *request*) e o
metrics-server no cluster (veja o
[README](README.md#1-metrics-server--habilita-kubectl-top-e-hpa)). Sem uma das duas
coisas, a coluna TARGETS mostra `<unknown>`.
</details>

<details><summary>Solução</summary>

```bash
kubectl scale deploy web --replicas=6
kubectl set resources deploy web --requests=cpu=100m,memory=64Mi      # pré-requisito do HPA

kubectl autoscale deploy web --cpu-percent=50 --min=2 --max=10
kubectl get hpa web -w            # TARGETS: 0%/50% (se ficar <unknown>, é o metrics-server)
kubectl describe hpa web
kubectl top pods -l app=web
```
</details>

📖 [HorizontalPodAutoscaler](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)

---

## Ex 6 — Helm: instalar, customizar, atualizar, reverter ⏱️ ~9min

**Tarefa:** instale o chart `bitnami/nginx` como release `loja` no namespace `dev`
com **2 réplicas**, mude pra 3, veja o histórico e reverta. Antes, inspecione o que
o chart geraria sem instalar nada.

<details><summary>Dica</summary>

`helm template` renderiza sem tocar no cluster (equivalente ao `--dry-run` mental).
`helm show values` lista tudo que dá pra customizar. `-f valores.yaml` vence
`--set` em legibilidade quando são muitos campos.
</details>

<details><summary>Solução</summary>

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm search repo nginx
helm show values bitnami/nginx | head -40

helm template loja bitnami/nginx --set replicaCount=2 | head -40    # só renderiza

helm install loja bitnami/nginx -n dev --create-namespace --set replicaCount=2
helm list -n dev
kubectl get deploy -n dev

helm upgrade loja bitnami/nginx -n dev --set replicaCount=3
helm history loja -n dev
helm rollback loja 1 -n dev
helm uninstall loja -n dev
```
- **Release** = uma instalação nomeada do chart. O mesmo chart pode virar várias
  releases no mesmo cluster.
- ⚠️ O catálogo público da Bitnami mudou de política em 2025 e alguns charts podem
  falhar ao puxar a imagem. Se acontecer, troque o chart do exercício por um estável
  (`helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx` e use
  `ingress-nginx/ingress-nginx`) — os comandos do Helm são idênticos.
</details>

📖 🔧 [Helm — usando charts](https://helm.sh/docs/intro/using_helm/)

---

## Ex 7 — Kustomize: base + overlays ⏱️ ~9min

**Tarefa:** com um `deployment.yaml` de base, crie os overlays `dev` (1 réplica,
prefixo `dev-`) e `prod` (3 réplicas, imagem `nginx:1.27`, label comum
`ambiente=prod`). Aplique o de dev.

<details><summary>Dica</summary>

`kubectl kustomize <dir>` mostra o resultado sem aplicar; `kubectl apply -k <dir>`
aplica. `configMapGenerator` cria ConfigMap com **hash no nome** — mudou o conteúdo,
muda o nome, e o Deployment reinicia sozinho (é a graça dele).
</details>

<details><summary>Solução</summary>

```bash
mkdir -p k/base k/overlays/dev k/overlays/prod
kubectl create deploy web --image=nginx:1.25 $do > k/base/deployment.yaml

cat > k/base/kustomization.yaml <<'EOF'
resources: [deployment.yaml]
EOF

cat > k/overlays/dev/kustomization.yaml <<'EOF'
resources: [../../base]
namePrefix: dev-
replicas:
  - { name: web, count: 1 }
configMapGenerator:
  - name: app-cfg
    literals: [APP_MODE=dev]
EOF

cat > k/overlays/prod/kustomization.yaml <<'EOF'
resources: [../../base]
replicas:
  - { name: web, count: 3 }
images:
  - { name: nginx, newTag: "1.27" }
labels:
  - pairs: { ambiente: prod }
EOF

kubectl kustomize k/overlays/prod          # confira antes
kubectl apply -k k/overlays/dev
kubectl get deploy dev-web
kubectl get cm                             # app-cfg-<hash>
```
</details>

📖 [Kustomize com kubectl](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/)

---

## Ex 8 — Deployment que não avança: diagnosticar ⏱️ ~6min

**Tarefa:** `kubectl set image deploy/web nginx=nginx:naoexiste` e conserte o rollout
travado — **sem** recriar o Deployment.

<details><summary>Solução</summary>

```bash
kubectl rollout status deploy/web           # trava: waiting for rollout to finish
kubectl get pods -l app=web                 # novo pod em ImagePullBackOff
kubectl describe pod <novo>                 # Events: Failed to pull image ... not found
kubectl rollout undo deploy/web             # volta pra revisão boa
kubectl rollout status deploy/web
```
- Repare que os pods **antigos continuaram servindo** — é o RollingUpdate protegendo
  você: o Deployment não derruba o que funciona enquanto o novo não fica Ready.
- `progressDeadlineSeconds` (default 600) é o que eventualmente marca o rollout como
  `Failed`.
</details>

📖 [Troubleshooting de Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#failed-deployment)

---

## Espaço pra seus exercícios

<!-- Duplique o bloco: ## Ex N — título ⏱️ ~Xmin / Tarefa / <details>Dica</details> / <details>Solução</details> / 📖 doc -->

---

➡️ Próximo domínio: [Services & Networking (20%)](04-services-networking-20.md).
