# Prática CKAD — Application Design & Build (20%)

Imagens de container, Jobs e CronJobs, os padrões de pod multi-container
(init, sidecar, adapter, ambassador) e volumes efêmeros/persistentes.

📖 Docs liberadas: [Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/)
· [CronJob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/)
· [Init containers](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/)
· [Sidecar containers](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/)
· [Volumes](https://kubernetes.io/docs/concepts/storage/volumes/)

> 🚧 **Semente** — exercícios prontos + espaço pra adicionar mais.
> Todos assumem `kubectl config set-context --current --namespace=ckad`.

---

## Ex 1 — Pod imperativo com command e args ⏱️ ~4min

**Tarefa:** crie o pod `contador` (busybox) que execute
`sh -c 'for i in $(seq 1 100); do echo $i; sleep 1; done'` e **não** reinicie ao
terminar. Depois gere o YAML dele sem criar nada.

<details><summary>Dica</summary>

Tudo que vem **depois de `--`** no `kubectl run` vira `args` (ou `command`, com
`--command`). `--restart=Never` faz um **Pod**; `--restart=OnFailure` faz um **Job**;
o default (`Always`) faz um Deployment em versões antigas e Pod hoje.
</details>

<details><summary>Solução</summary>

```bash
kubectl run contador --image=busybox --restart=Never \
  --command -- sh -c 'for i in $(seq 1 100); do echo $i; sleep 1; done'

# só o YAML, sem criar:
kubectl run contador --image=busybox --restart=Never $do \
  --command -- sh -c 'echo oi' > contador.yaml

kubectl logs -f contador
```
</details>

📖 [Definir command e args](https://kubernetes.io/docs/tasks/inject-data-application/define-command-argument-container/)

---

## Ex 2 — Job: completions, parallelism e backoffLimit ⏱️ ~7min

**Tarefa:** crie o Job `processa` que rode a tarefa **6 vezes**, com **2 pods em
paralelo**, desistindo após **3 falhas** e abortando se passar de **60s**.

<details><summary>Dica</summary>

`completions` = quantas execuções bem-sucedidas o Job precisa. `parallelism` = quantas
ao mesmo tempo. `backoffLimit` = tentativas antes de marcar o Job como `Failed`.
`activeDeadlineSeconds` corta o Job no tempo, independentemente do resto.
</details>

<details><summary>Solução</summary>

```bash
kubectl create job processa --image=busybox $do -- sh -c 'echo processando; sleep 5' > job.yaml
```
```yaml
spec:
  completions: 6
  parallelism: 2
  backoffLimit: 3
  activeDeadlineSeconds: 60
```
```bash
kubectl apply -f job.yaml
kubectl get job processa -w            # COMPLETIONS deve chegar a 6/6
kubectl get pods -l job-name=processa
kubectl logs -l job-name=processa --tail=1
```
- Pods de Job **não somem** ao terminar (ficam `Completed`) — é assim que você lê os
  logs. Limpe com `kubectl delete job processa`.
</details>

📖 [Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/)

---

## Ex 3 — CronJob: agendar, suspender e disparar na mão ⏱️ ~7min

**Tarefa:** crie o CronJob `relatorio` rodando **a cada minuto**, que guarde só os
**3 últimos** jobs bem-sucedidos e **1** falho, e que **não** rode duas instâncias
sobrepostas. Depois suspenda-o e dispare um job manual a partir dele.

<details><summary>Dica</summary>

`concurrencyPolicy: Forbid` evita sobreposição. `kubectl create job --from=cronjob/<nome>`
dispara uma execução avulsa — útil pra testar sem esperar o horário.
</details>

<details><summary>Solução</summary>

```bash
kubectl create cronjob relatorio --image=busybox --schedule='*/1 * * * *' \
  $do -- sh -c 'date; echo relatorio gerado' > cj.yaml
```
```yaml
spec:
  schedule: "*/1 * * * *"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  startingDeadlineSeconds: 30
```
```bash
kubectl apply -f cj.yaml
kubectl get cronjob relatorio
kubectl get jobs -w                                   # um job novo por minuto

kubectl patch cronjob relatorio -p '{"spec":{"suspend":true}}'   # pausa
kubectl create job manual-1 --from=cronjob/relatorio             # dispara agora
kubectl logs -l job-name=manual-1
```
</details>

📖 [CronJob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/)

---

## Ex 4 — initContainer que espera uma dependência ⏱️ ~7min

**Tarefa:** faça o pod `app` (nginx) só subir **depois** que o Service `db` existir.
Crie primeiro sem o Service, observe o pod travado, e então crie o Service.

<details><summary>Dica</summary>

Init containers rodam **em ordem, até o fim, antes** dos containers normais. Enquanto
um init não termina, o pod fica em `Init:0/1`. Um loop de `nslookup` é o jeito
clássico de esperar um Service.
</details>

<details><summary>Solução</summary>

```yaml
spec:
  initContainers:
    - name: espera-db
      image: busybox
      command: ['sh','-c','until nslookup db.ckad.svc.cluster.local; do echo aguardando db; sleep 2; done']
  containers:
    - name: nginx
      image: nginx
```
```bash
kubectl apply -f app.yaml
kubectl get pod app                       # Init:0/1
kubectl logs app -c espera-db             # "aguardando db"
kubectl create deploy db --image=nginx && kubectl expose deploy db --port=80
kubectl get pod app -w                    # Init:1/1 -> Running
```
</details>

📖 [Init containers](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/)

---

## Ex 5 — Sidecar: dois containers compartilhando um volume ⏱️ ~8min

**Tarefa:** no pod `logapp`, um container escreve uma linha por segundo em
`/var/log/app.log` e um **sidecar** imprime esse arquivo no stdout (pra virar
`kubectl logs`). Use `emptyDir`.

<details><summary>Dica</summary>

`emptyDir` nasce com o pod, morre com o pod, e é **compartilhado por todos os
containers** que o montarem. Em cluster 1.29+ existe o **sidecar nativo**: um
`initContainer` com `restartPolicy: Always` — ele sobe antes dos containers
principais e fica rodando junto.
</details>

<details><summary>Solução</summary>

```yaml
spec:
  containers:
    - name: escritor
      image: busybox
      command: ['sh','-c','while true; do echo "$(date) linha" >> /var/log/app.log; sleep 1; done']
      volumeMounts: [{ name: logs, mountPath: /var/log }]
    - name: sidecar
      image: busybox
      command: ['sh','-c','tail -F /var/log/app.log']
      volumeMounts: [{ name: logs, mountPath: /var/log }]
  volumes:
    - { name: logs, emptyDir: {} }
```
```bash
kubectl apply -f logapp.yaml
kubectl logs logapp -c sidecar -f          # -c é obrigatório em pod multi-container
kubectl exec logapp -c escritor -- wc -l /var/log/app.log
```
Variante com **sidecar nativo** (garante ordem de subida e parada):
```yaml
  initContainers:
    - name: sidecar
      image: busybox
      restartPolicy: Always            # <- o que o torna um sidecar, não um init
      command: ['sh','-c','tail -F /var/log/app.log']
      volumeMounts: [{ name: logs, mountPath: /var/log }]
```
</details>

📖 [Sidecar containers](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/)
· [Padrões multi-container](https://kubernetes.io/docs/concepts/workloads/pods/#how-pods-manage-multiple-containers)

---

## Ex 6 — Adapter e ambassador (reconhecer o padrão) ⏱️ ~5min

**Tarefa:** descreva (e monte o esqueleto de) um pod para cada caso:
**(a)** a app só sabe logar em formato próprio e o coletor exige JSON;
**(b)** a app fala com `localhost:6379` e você precisa apontá-la pra um Redis remoto
sem tocar no código.

<details><summary>Solução</summary>

**(a) Adapter** — sidecar que **transforma** a saída da app pro formato que o mundo
externo espera:
```yaml
containers:
  - { name: app, image: minha-app, volumeMounts: [{ name: logs, mountPath: /var/log }] }
  - { name: adapter, image: fluent/fluent-bit, volumeMounts: [{ name: logs, mountPath: /var/log }] }
```

**(b) Ambassador** — sidecar que **proxia** a conexão: a app fala `localhost` e o
embaixador resolve o destino real.
```yaml
containers:
  - { name: app, image: minha-app, env: [{ name: REDIS_HOST, value: "127.0.0.1" }] }
  - { name: ambassador, image: haproxy, ports: [{ containerPort: 6379 }] }
```
- Os containers de um pod compartilham **rede** (mesmo `localhost`) e podem
  compartilhar **volumes** — é isso que faz os dois padrões funcionarem.
</details>

📖 [Pods — múltiplos containers](https://kubernetes.io/docs/concepts/workloads/pods/#how-pods-manage-multiple-containers)

---

## Ex 7 — Volume efêmero × persistente ⏱️ ~8min

**Tarefa:** comprove na prática a diferença: um pod com `emptyDir` e outro com **PVC**
escrevem um arquivo; delete e recrie os dois e veja quem perdeu o dado.

<details><summary>Dica</summary>

Precisa de uma **StorageClass default** pro PVC ficar `Bound` sozinho (veja o
[README](README.md#3-storageclass-default--pvc-que-fica-bound-sozinho)). Sem ela, o
PVC fica `Pending` esperando um PV manual.
</details>

<details><summary>Solução</summary>

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: dados }
spec:
  accessModes: [ReadWriteOnce]
  resources: { requests: { storage: 1Gi } }
EOF
kubectl get pvc dados         # Bound (com SC default)
```
```yaml
# no pod persistente:
  volumes:
    - name: d
      persistentVolumeClaim: { claimName: dados }
```
```bash
kubectl exec <pod> -- sh -c 'echo ola > /data/arquivo'
kubectl delete pod <pod> && kubectl apply -f <pod>.yaml
kubectl exec <pod> -- cat /data/arquivo     # emptyDir: some | PVC: sobrevive
```
</details>

📖 [Volumes](https://kubernetes.io/docs/concepts/storage/volumes/)
· [PV/PVC](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)

---

## Ex 8 — Imagem de container: escrever e corrigir um Dockerfile ⏱️ ~8min

**Tarefa:** escreva um Dockerfile que sirva um `index.html` estático, construa a
imagem **no nó** e rode um pod com ela. Depois aponte 3 problemas no Dockerfile
"ruim" abaixo.

<details><summary>Dica</summary>

O lab usa **containerd** (sem Docker). Pra construir no próprio nó, o caminho é
`nerdctl` (com buildkit) ou `buildah`. Imagem construída localmente só existe naquele
nó — use `imagePullPolicy: IfNotPresent` e agende o pod nesse nó, ou empurre pra um
registry.
</details>

<details><summary>Solução</summary>

```dockerfile
# bom
FROM nginx:1.27-alpine
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 80
```
```bash
sudo apt-get install -y buildah                      # no nó
echo '<h1>lab</h1>' > index.html
sudo buildah bud -t localhost/meuapp:1 .
sudo buildah push localhost/meuapp:1 \
  oci:/tmp/meuapp                                    # ou push pra um registry
# alternativa direta pro containerd do k8s:
sudo buildah push localhost/meuapp:1 docker-archive:/tmp/meuapp.tar:localhost/meuapp:1
sudo ctr -n k8s.io images import /tmp/meuapp.tar
kubectl run meuapp --image=localhost/meuapp:1 --image-pull-policy=IfNotPresent
```
**Dockerfile ruim — o que está errado:**
```dockerfile
FROM ubuntu:latest          # 1) tag 'latest': build não reproduzível
RUN apt-get update
RUN apt-get install -y nginx curl vim   # 2) camadas separadas + pacotes inúteis (imagem gorda)
USER root                   # 3) roda como root sem necessidade
CMD service nginx start     # 4) processo em background: o container morre na hora
```
- Correções: fixar a tag, juntar os `RUN` com `&&` e limpar o cache do apt, criar um
  usuário não-root, e rodar o processo em **foreground** (`nginx -g 'daemon off;'`).
</details>

📖 [Imagens](https://kubernetes.io/docs/concepts/containers/images/)

---

## Espaço pra seus exercícios

<!-- Duplique o bloco: ## Ex N — título ⏱️ ~Xmin / Tarefa / <details>Dica</details> / <details>Solução</details> / 📖 doc -->

---

➡️ Próximo domínio: [Application Deployment (20%)](03-app-deployment-20.md).
