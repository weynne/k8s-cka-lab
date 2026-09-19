# Prática CKAD — Environment, Configuration & Security (25%)

O domínio mais pesado da CKAD. ConfigMaps, Secrets, ServiceAccounts, RBAC,
SecurityContext, requests/limits, ResourceQuota/LimitRange, CRDs e admission.

📖 Docs liberadas: [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)
· [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
· [Security Context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)
· [RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
· [Resource quotas](https://kubernetes.io/docs/concepts/policy/resource-quotas/)

> 🚧 **Semente** — exercícios prontos + espaço pra adicionar mais.
> Todos assumem `kubectl config set-context --current --namespace=ckad`.

---

## Ex 1 — ConfigMap das 3 formas ⏱️ ~6min

**Tarefa:** crie o ConfigMap `app-cfg` com `APP_MODE=prod` e `LOG_LEVEL=debug`, e um
pod `reader` (busybox) que receba **as duas chaves como variáveis de ambiente** e
também monte o ConfigMap como **volume** em `/etc/app`.

<details><summary>Dica</summary>

`envFrom` injeta o ConfigMap inteiro de uma vez (nomes das chaves viram os nomes das
variáveis). `env[].valueFrom.configMapKeyRef` injeta **uma** chave — útil quando o
nome da variável é diferente do nome da chave. Como volume, cada chave vira um
**arquivo**.
</details>

<details><summary>Solução</summary>

```bash
kubectl create cm app-cfg --from-literal=APP_MODE=prod --from-literal=LOG_LEVEL=debug
kubectl run reader --image=busybox $do --command -- sleep 3600 > reader.yaml
```
```yaml
# em spec.containers[0]:
    envFrom:
      - configMapRef: { name: app-cfg }
    volumeMounts:
      - name: cfg
        mountPath: /etc/app
# em spec:
  volumes:
    - name: cfg
      configMap: { name: app-cfg }
```
```bash
kubectl apply -f reader.yaml
kubectl exec reader -- env | grep -E 'APP_MODE|LOG_LEVEL'
kubectl exec reader -- ls /etc/app          # APP_MODE  LOG_LEVEL (um arquivo por chave)
kubectl exec reader -- cat /etc/app/APP_MODE
```
</details>

📖 [Configure a pod to use a ConfigMap](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/)

---

## Ex 2 — Secret + a pegadinha do base64 ⏱️ ~6min

**Tarefa:** crie o Secret `db-sec` com `user=admin` e `pass=s3cr3t`, injete `pass`
como a variável `DB_PASSWORD` num pod e comprove que o valor chegou certo. Depois
leia o valor do Secret pelo `kubectl`.

<details><summary>Dica</summary>

`kubectl create secret generic --from-literal` já faz o base64 por você. Se for
escrever o YAML na mão, ou você usa `data:` (valor **em base64**) ou `stringData:`
(valor em texto puro — o apiserver codifica). Trocar os dois é o erro clássico.
</details>

<details><summary>Solução</summary>

```bash
kubectl create secret generic db-sec --from-literal=user=admin --from-literal=pass=s3cr3t
```
```yaml
# no container:
    env:
      - name: DB_PASSWORD
        valueFrom:
          secretKeyRef: { name: db-sec, key: pass }
```
```bash
kubectl exec <pod> -- printenv DB_PASSWORD             # s3cr3t
kubectl get secret db-sec -o jsonpath='{.data.pass}' | base64 -d ; echo
```
- Secret **não é criptografia**: é base64 e qualquer um com permissão de leitura vê.
</details>

📖 [Distribuir credenciais com Secret](https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/)

---

## Ex 3 — SecurityContext: usuário, root e capabilities ⏱️ ~8min

**Tarefa:** rode um pod `hardened` (nginx) que (a) rode como **UID 1001**, (b) **não**
possa rodar como root, (c) tenha **root filesystem somente-leitura** e (d) sem
nenhuma capability extra. Depois descubra por que o nginx quebra e conserte.

<details><summary>Dica</summary>

`securityContext` existe em **dois níveis**: no `pod.spec` (vale pra todos os
containers, e é onde mora `fsGroup`) e em `container.securityContext` (onde moram
`capabilities`, `allowPrivilegeEscalation` e `readOnlyRootFilesystem`). O nginx
precisa escrever em `/var/cache/nginx` e `/var/run` — com root FS read-only, monte
`emptyDir` nesses caminhos.
</details>

<details><summary>Solução</summary>

```yaml
spec:
  securityContext:
    runAsUser: 1001
    runAsNonRoot: true
  containers:
    - name: nginx
      image: nginxinc/nginx-unprivileged      # a imagem oficial só escuta na 80 como root
      securityContext:
        readOnlyRootFilesystem: true
        allowPrivilegeEscalation: false
        capabilities: { drop: ["ALL"] }
      volumeMounts:
        - { name: cache, mountPath: /var/cache/nginx }
        - { name: run,   mountPath: /var/run }
  volumes:
    - { name: cache, emptyDir: {} }
    - { name: run,   emptyDir: {} }
```
```bash
kubectl apply -f hardened.yaml
kubectl exec hardened -- id                 # uid=1001
kubectl exec hardened -- touch /teste       # Read-only file system
```
- Diagnóstico do erro original: `kubectl logs` mostra `Permission denied` num path
  de escrita, ou o pod fica em `CreateContainerConfigError` se a imagem exigir root
  com `runAsNonRoot: true`.
</details>

📖 [Security context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)

---

## Ex 4 — ServiceAccount + RBAC mínimo ⏱️ ~8min

**Tarefa:** crie a SA `app-sa`, dê a ela permissão de **listar e ver pods só no
namespace `ckad`**, rode um pod com essa SA e comprove de dentro dele que consegue
listar pods — mas **não** deletar.

<details><summary>Dica</summary>

`kubectl create role` / `create rolebinding` fazem tudo sem YAML. Pra testar sem
entrar no pod: `kubectl auth can-i --as=system:serviceaccount:ckad:app-sa`.
</details>

<details><summary>Solução</summary>

```bash
kubectl create sa app-sa
kubectl create role pod-reader --verb=get,list,watch --resource=pods
kubectl create rolebinding app-sa-reader --role=pod-reader --serviceaccount=ckad:app-sa

kubectl auth can-i list pods --as=system:serviceaccount:ckad:app-sa            # yes
kubectl auth can-i delete pods --as=system:serviceaccount:ckad:app-sa          # no
kubectl auth can-i list pods --as=system:serviceaccount:ckad:app-sa -n default # no (Role é namespaced)

kubectl run api-client --image=bitnami/kubectl \
  --overrides='{"apiVersion":"v1","spec":{"serviceAccountName":"app-sa"}}' \
  --command -- sleep 3600
kubectl exec api-client -- kubectl get pods
```
- No pod, o token da SA é montado em
  `/var/run/secrets/kubernetes.io/serviceaccount/`. Pra **não** montá-lo:
  `automountServiceAccountToken: false` no pod ou na SA.
- ⚠️ `--overrides` **exige** o campo `apiVersion` no JSON, senão o kubectl recusa
  com *"cannot be handled as a Pod"*. Na prova costuma sair mais rápido gerar com
  `$do` e editar o YAML do que montar JSON na linha de comando.
</details>

📖 [RBAC](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
· [Configure SA para pods](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/)

---

## Ex 5 — requests/limits e as classes de QoS ⏱️ ~7min

**Tarefa:** crie três pods no namespace `ckad` — um **Guaranteed**, um **Burstable**
e um **BestEffort** — e comprove a classe de cada um.

<details><summary>Dica</summary>

**Guaranteed** = requests **iguais** aos limits, pra CPU **e** memória, em **todos**
os containers. **Burstable** = tem request ou limit, mas não bate. **BestEffort** =
nenhum dos dois. A classe decide quem é despejado primeiro sob pressão de memória.
</details>

<details><summary>Solução</summary>

```yaml
# guaranteed
resources:
  requests: { cpu: "200m", memory: "128Mi" }
  limits:   { cpu: "200m", memory: "128Mi" }
# burstable
resources:
  requests: { cpu: "100m", memory: "64Mi" }
  limits:   { cpu: "300m", memory: "256Mi" }
# besteffort: sem bloco resources
```
```bash
kubectl get pod -o custom-columns=NOME:.metadata.name,QOS:.status.qosClass
```
</details>

📖 [Quality of Service](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/)
· [Manage resources](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)

---

## Ex 6 — ResourceQuota + LimitRange ⏱️ ~8min

**Tarefa:** no namespace `dev`, limite o total a **2 CPU / 2Gi de memória e 5 pods**,
e faça todo container sem `resources` nascer com `100m/128Mi` por padrão. Depois
comprove que um pod que estoura a quota é **recusado**.

<details><summary>Dica</summary>

Com ResourceQuota de CPU/memória ativo, **todo** pod passa a ser obrigado a declarar
requests/limits — é aí que o LimitRange salva, aplicando os defaults.
</details>

<details><summary>Solução</summary>

```bash
kubectl create quota dev-quota -n dev \
  --hard=requests.cpu=2,requests.memory=2Gi,limits.cpu=2,limits.memory=2Gi,pods=5
```
```yaml
apiVersion: v1
kind: LimitRange
metadata: { name: dev-defaults, namespace: dev }
spec:
  limits:
    - type: Container
      default:        { cpu: "200m", memory: "256Mi" }   # vira o limit
      defaultRequest: { cpu: "100m", memory: "128Mi" }   # vira o request
```
```bash
kubectl apply -f limitrange.yaml
kubectl run semrecurso --image=nginx -n dev
kubectl get pod semrecurso -n dev -o jsonpath='{.spec.containers[0].resources}' ; echo   # defaults aplicados

kubectl describe quota dev-quota -n dev          # Used vs Hard
# (kubectl run --requests foi REMOVIDO no 1.21 — hoje se faz por YAML/overrides)
kubectl run gordo -n dev --image=nginx \
  --overrides='{"apiVersion":"v1","spec":{"containers":[{"name":"gordo","image":"nginx","resources":{"requests":{"cpu":"3"}}}]}}'
# Error ... exceeded quota: dev-quota, requested: requests.cpu=3, limited: requests.cpu=2
```
- A recusa vem do **admission controller** (`ResourceQuota`) — o pod nem chega a ser
  criado. É admission control em ação, que a CKAD cobra conceitualmente.
</details>

📖 [Resource quotas](https://kubernetes.io/docs/concepts/policy/resource-quotas/)
· [LimitRange](https://kubernetes.io/docs/concepts/policy/limit-range/)

---

## Ex 7 — Pod Security Admission (admission na prática) ⏱️ ~6min

**Tarefa:** faça o namespace `prod` **recusar** pods privilegiados aplicando o padrão
`restricted`, e comprove com um pod que viola a regra.

<details><summary>Dica</summary>

PSA é configurado por **label no namespace**: `pod-security.kubernetes.io/<modo>`,
com `<modo>` em `enforce` / `audit` / `warn` e valor `privileged|baseline|restricted`.
</details>

<details><summary>Solução</summary>

```bash
kubectl label ns prod pod-security.kubernetes.io/enforce=restricted --overwrite

kubectl run mau -n prod --image=nginx \
  --overrides='{"apiVersion":"v1","spec":{"containers":[{"name":"mau","image":"nginx","securityContext":{"privileged":true}}]}}'
# Error ... violates PodSecurity "restricted:latest"

# um pod que obedece:
kubectl run bom -n prod --image=nginxinc/nginx-unprivileged --overrides='{"apiVersion":"v1","spec":{"securityContext":{"runAsNonRoot":true,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"bom","image":"nginxinc/nginx-unprivileged","securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}'
```
- Use `warn`/`audit` quando quiser só avisar sem bloquear — útil pra migrar
  namespace existente.
</details>

📖 [Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/)
· [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)

---

## Ex 8 — CRD: descobrir e usar um recurso customizado ⏱️ ~7min

**Tarefa:** o cluster tem CRDs instaladas (o Calico trouxe várias). Liste-as, descubra
os campos de uma e crie um recurso customizado próprio a partir da CRD abaixo.

<details><summary>Dica</summary>

`kubectl api-resources` mostra tudo que o apiserver entende, inclusive o que veio de
CRD. `kubectl explain <kind> --recursive` funciona com CRD também, desde que ela tenha
schema.
</details>

<details><summary>Solução</summary>

```bash
kubectl get crd
kubectl api-resources --api-group=crd.projectcalico.org
kubectl explain ippool --recursive | head -30
```
```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata: { name: backups.lab.exemplo.io }
spec:
  group: lab.exemplo.io
  names: { kind: Backup, plural: backups, singular: backup, shortNames: [bk] }
  scope: Namespaced
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                destino: { type: string }
                retencaoDias: { type: integer }
```
```bash
kubectl apply -f crd.yaml
kubectl explain backup.spec
cat <<'EOF' | kubectl apply -f -
apiVersion: lab.exemplo.io/v1
kind: Backup
metadata: { name: diario }
spec: { destino: s3://bucket/diario, retencaoDias: 7 }
EOF
kubectl get bk diario -o yaml
```
- **CRD** = o *tipo* novo. **Operator** = o controller que age quando alguém cria um
  recurso desse tipo. A CKAD cobra saber **usar** (descobrir campos, criar o CR), não
  escrever operator.
</details>

📖 [Custom resources](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/)

---

## Espaço pra seus exercícios

<!-- Duplique o bloco: ## Ex N — título ⏱️ ~Xmin / Tarefa / <details>Dica</details> / <details>Solução</details> / 📖 doc -->

---

➡️ Próximo domínio: [Application Design & Build (20%)](02-app-design-build-20.md).
