# Prática CKAD — exercícios por domínio

Mesmo cluster das Fases 0–6, outra prova. A **CKAD** olha pro Kubernetes da ótica de
**quem desenvolve e implanta a aplicação** — não de quem opera o cluster. São
**~15–20 tarefas em 2 horas**, 100% práticas, num cluster que já existe.

> Está estudando pra **CKA**? A trilha dela é a [pratica/](../pratica/README.md).
> Dá pra alternar entre as duas no mesmo lab — e vale a pena: os assuntos se
> reforçam.

## Domínios (por peso)

| Peso | Domínio | Arquivo |
|------|---------|---------|
| 25% | Environment, Configuration & Security | [01-environment-config-security-25.md](01-environment-config-security-25.md) |
| 20% | Application Design & Build | [02-app-design-build-20.md](02-app-design-build-20.md) |
| 20% | Application Deployment | [03-app-deployment-20.md](03-app-deployment-20.md) |
| 20% | Services & Networking | [04-services-networking-20.md](04-services-networking-20.md) |
| 15% | Observability & Maintenance | [05-observability-maintenance-15.md](05-observability-maintenance-15.md) |

Formato de cada exercício: **Tarefa** (estilo prova) → `<details>` com **Dica** e
**Solução** (tente antes de abrir) → 📖 **doc liberada na prova** → ⏱️ **tempo-alvo**.

> Confirme o currículo vigente no [site do exame](https://training.linuxfoundation.org/certification/certified-kubernetes-application-developer-ckad/)
> antes da prova — os pesos mudam de tempos em tempos.

---

## CKA × CKAD — o que muda na prática

Você já montou o cluster na mão; isso te dá uma vantagem injusta aqui. Mas o jogo
é outro:

| | CKA | CKAD |
|---|-----|------|
| Foco | operar/consertar o **cluster** | construir e implantar a **aplicação** |
| `ssh` em nó + `sudo` | **muito** (etcd, kubelet, static pods, certs) | **quase nunca** — você vive via `kubectl` |
| YAML autoral | pouco (mais `kubectl` imperativo e edição) | **muito** — multi-container, probes, volumes, securityContext |
| Ritmo | ~6–8 min/tarefa | **~5–6 min/tarefa** (mais tarefas, cada uma menor) |
| Ferramentas extras | — | **Helm** e **Kustomize** caem |
| Domina a nota | Troubleshooting (30%) | Config & Security (25%) |

**A consequência prática:** na CKAD, quem escreve YAML do zero **não termina**.
Gerar com `$do` e editar é obrigatório, não estilo.

---

## Preparar o lab pra CKAD (uma vez)

O cluster das Fases 0–6 é mínimo: sem métricas, sem Ingress controller, sem
StorageClass e sem Helm. Vários exercícios daqui precisam disso. Rode **no
`k8s-cp`** (ou de onde seu `kubectl` fala com o cluster):

### 1. metrics-server — habilita `kubectl top` e HPA

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# lab com certificado de kubelet auto-assinado: o metrics-server não confia nele
kubectl -n kube-system patch deploy metrics-server --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

kubectl -n kube-system rollout status deploy/metrics-server
kubectl top nodes        # leva ~1 min pra popular
```

> ⚠️ `--kubelet-insecure-tls` **é aceitável em lab e não em produção** — ele
> desliga a verificação do certificado do kubelet. Sem isso, o metrics-server fica
> em `Ready 0/1` com erro de x509 (e é um bom exercício de diagnóstico, aliás).

### 2. Ingress controller (ingress-nginx) — pros exercícios de Ingress

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/baremetal/deploy.yaml
kubectl -n ingress-nginx get pods -w        # espere o controller ficar Running
kubectl get ingressclass                    # deve listar 'nginx'
kubectl -n ingress-nginx get svc ingress-nginx-controller   # anote a porta NodePort (3xxxx)
```

- Use o provider **baremetal** (NodePort) — não o `cloud`, que fica esperando um
  LoadBalancer que ninguém vai criar no lab.
- Testar: `curl -H 'Host: app.lab' http://<ip-do-nó>:<nodeport>/`.
- ☁️ **Lab na AWS?** libere a faixa NodePort no Security Group ou teste de dentro
  do nó ([C4](../00b-aws-ec2.md#c4--security-group-as-regras-a-parte-que-mais-quebra)).

### 3. StorageClass default — PVC que fica `Bound` sozinho

O lab não tem provisionador dinâmico; sem isso todo PVC fica `Pending` até você
criar um PV na mão (o que é ótimo pra CKA e chato pra CKAD).

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
kubectl patch storageclass local-path \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl get sc      # local-path deve aparecer como (default)
```

### 4. Helm (no `k8s-cp`, ou na sua máquina/WSL)

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```

- **Kustomize não precisa instalar** — já vem embutido (`kubectl apply -k`).

### 5. Namespaces de treino

```bash
for ns in ckad dev prod; do kubectl create ns $ns; done
kubectl config set-context --current --namespace=ckad
```

> 🔧 Esses add-ons são **montagem de lab** (não abrem na prova). Na CKAD o cluster
> já vem com tudo isso pronto; aqui você instala uma vez pra ter onde praticar.

**Checklist do lab pronto pra CKAD:**

- [ ] `kubectl top nodes` responde
- [ ] `kubectl get ingressclass` lista `nginx`
- [ ] `kubectl get sc` mostra uma default
- [ ] `helm version` responde
- [ ] CNI com **NetworkPolicy** (= Calico; com Flannel os exercícios de policy não
      funcionam — ver [Fase 5](../05-cni.md))
- [ ] namespaces `ckad`/`dev`/`prod` criados

---

## ⏱️ Mecânica de prova (leia antes)

- **Setup no início (vale os 30s)** — o mesmo da CKA, e aqui rende ainda mais:
  ```bash
  alias k=kubectl
  export do='--dry-run=client -o yaml'
  export now='--grace-period=0 --force'
  source <(kubectl completion bash); complete -F __start_kubectl k
  ```
- **Namespace da questão, sempre.** Quase toda tarefa da CKAD cita um namespace.
  `kubectl config set-context --current --namespace=<ns>` no começo de cada uma —
  recurso certo no namespace errado **não pontua**.
- **Gere, não escreva.** `k run`, `k create deploy|job|cronjob|cm|secret|svc` com
  `$do` cobrem a maioria. Escrever YAML do zero é o que faz gente não terminar.
- **`kubectl explain --recursive` é seu amigo** pra lembrar onde um campo mora:
  ```bash
  k explain pod.spec.containers.securityContext --recursive
  ```
- **`--dry-run=server`** valida contra o apiserver (pega campo inválido e
  admission) sem criar nada.
- **Edite o que não dá pra gerar:** probes, volumes, securityContext, initContainers
  e multi-container **não** têm flag. Treine o caminho "gerar → `vim` → apply" até
  ficar automático.
- **`k delete pod x $now`** pra não esperar 30s de grace em cada refação.
- **Docs:** só `kubernetes.io/docs` (+subdomínios) e `kubernetes.io/blog` — **mais**
  `helm.sh/docs` e `kustomize.io` (permitidos na CKAD; confirme no handbook). Treine
  achar as páginas de **probes**, **securityContext** e **NetworkPolicy** rápido:
  são as que você mais vai copiar.
- **Verifique o que fez:** `k get`/`describe` depois de cada tarefa. Ponto se perde
  por typo, não por falta de conhecimento.
- **killer.sh:** a compra do exame dá 2 sessões do simulador (bem mais difícil que a
  prova). Faça as duas.

---

## Sugestão de rotação de estudo

1. Cluster de pé (Fases 0–6) + add-ons desta página.
2. **Config & Security (25%)** — maior peso e onde mora o YAML chato
   (securityContext, SA/RBAC, quota).
3. **Design & Build (20%)** — Jobs/CronJobs, init e sidecar.
4. **Deployment (20%)** — rollout, Helm, Kustomize.
5. **Services & Networking (20%)** — Service, Ingress, NetworkPolicy.
6. **Observability (15%)** — probes e debug (você já treinou muito disso na CKA).
7. Quebrou o lab? Registre em [../07-troubleshooting.md](../07-troubleshooting.md).
8. Antes de exercícios destrutivos: `vagrant snapshot save limpo` (local) ou
   `kubeadm reset` + Fases 4–6 (AWS —
   [C10](../00b-aws-ec2.md#c10--ciclo-de-vida-parar-religar-e-destruir)).

> 🧹 **Limpe entre blocos:** `kubectl delete all --all -n ckad` devolve o namespace
> ao zero (não apaga ConfigMap/Secret/PVC — esses vão por tipo).
