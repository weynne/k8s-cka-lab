# Fase 5 — CNI (Calico ou Flannel)

**Objetivo:** instalar um plugin de rede (CNI) para os pods, com o pod CIDR
batendo o do `kubeadm init` (`10.244.0.0/16`), e ver os nós saírem de
**NotReady** para **Ready** e o CoreDNS subir.

**Rodar em:** **só** `k8s-cp` (via kubectl; o CNI se distribui pelos nós sozinho
via DaemonSet).

📖 **Doc liberada na prova:**
[Install a Pod network add-on](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/#pod-network)

🔧 **Referência de montagem (não abre na prova):**
[Calico — self-managed on-premises](https://docs.tigera.io/calico/latest/getting-started/kubernetes/self-managed-onprem/onpremises)
· [Flannel](https://github.com/flannel-io/flannel)

> Na CKA o CNI normalmente **já vem instalado** (ou você aplica um manifesto que a
> questão fornece) — você não depende dos sites do Calico/Flannel. Aqui usamos
> esses manifestos só pra montar o lab.

> 💾 **Treino offline — vendore o manifesto.** Pra reproduzir o lab sem depender de
> URL externa (e treinar o hábito de não puxar coisa de fora na prova), salve o
> manifesto **localmente** uma vez e versione junto:
> ```bash
> curl -sL https://raw.githubusercontent.com/projectcalico/calico/v3.32.1/manifests/calico.yaml \
>   -o manifests/calico.yaml       # depois: kubectl apply -f manifests/calico.yaml
> ```
> Assim, num `vagrant destroy`/rebuild sem internet você reaplica o arquivo local.

---

## Escolher o CNI

Os dois caem na CKA; a diferença que importa é **NetworkPolicy**:

| CNI | NetworkPolicy | Quando usar no estudo |
|-----|---------------|-----------------------|
| **Calico** | ✅ suporta | **Principal** — tarefas de NetworkPolicy só funcionam com ele |
| **Flannel** | ❌ não suporta | Alternativa simples; bom pra saber instalar, mas **não** pratica policy |

> Roda **um CNI por cluster** — não instale os dois juntos. Pra treinar o outro,
> reconstrua o cluster (`kubeadm reset` nos nós, ou `vagrant destroy && vagrant
> up` + Fases 2–6). Recomendo montar com **Calico** e, num rebuild, experimentar
> Flannel.

> ⚠️ **CIDR — a pegadinha é só do Calico:** o pool default do Calico é
> `192.168.0.0/16`, que engloba a rede dos nós `192.168.137.0/24` → roteamento
> quebrado (por isso fixamos `--pod-network-cidr=10.244.0.0/16` na Fase 4). Já o
> **Flannel** usa `10.244.0.0/16` por padrão — **casa** com o nosso, zero edição.
> Detalhe em [troubleshooting](07-troubleshooting.md).

---

## Calico — Opção A (mais simples): via manifesto

Para cluster pequeno (≤ 50 nós) com datastore no próprio Kubernetes:

```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.1/manifests/calico.yaml
```

- Cria o DaemonSet `calico-node` (um pod por nó), o `calico-kube-controllers` e
  os CRDs do Calico, no namespace `kube-system`.
- **CIDR:** nas versões atuais o Calico **detecta automaticamente** o
  `--pod-network-cidr` do kubeadm — `10.244.0.0/16` é herdado sem edição. Se
  quiser fixar à mão, baixe o `calico.yaml`, descomente `CALICO_IPV4POOL_CIDR` e
  ponha `10.244.0.0/16` antes do `apply`:
  ```bash
  curl -O https://raw.githubusercontent.com/projectcalico/calico/v3.32.1/manifests/calico.yaml
  # editar: name CALICO_IPV4POOL_CIDR / value "10.244.0.0/16"
  kubectl apply -f calico.yaml
  ```

## Calico — Opção B: via operator (Tigera)

```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.1/manifests/operator-crds.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.1/manifests/tigera-operator.yaml
curl -O https://raw.githubusercontent.com/projectcalico/calico/v3.32.1/manifests/custom-resources.yaml
# editar custom-resources.yaml: spec.calicoNetwork.ipPools[0].cidr = 10.244.0.0/16
kubectl create -f custom-resources.yaml
```

- O operator (`custom-resources.yaml`) vem com `cidr: 192.168.0.0/16` **por
  padrão** — aqui você **precisa** trocar pra `10.244.0.0/16`, senão cai no
  conflito de rede acima.

## Flannel — Opção C (alternativa simples)

```bash
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

- Cria o DaemonSet `kube-flannel-ds` no namespace `kube-flannel`.
- **CIDR:** o default do Flannel é `10.244.0.0/16` = o nosso → **zero edição**. (Se
  o cluster usasse outro CIDR, você baixaria o `kube-flannel.yml` e editaria o
  campo `Network` dentro do `net-conf.json`.)
- **Sem NetworkPolicy:** com Flannel, as tarefas de policy da CKA não funcionam —
  pra isso, use Calico.

> Escolha **uma** opção (A, B **ou** C). Para o lab, a **Opção A (Calico)** é a
> mais direta e destrava NetworkPolicy.

---

## Passo — acompanhar a subida

```bash
# Calico (manifesto):   kubectl get pods -n kube-system -w   (calico-node / calico-kube-controllers)
# Calico (operator):    watch kubectl get tigerastatus
# Flannel:              kubectl get pods -n kube-flannel -w  (kube-flannel-ds)
```

Espere os pods do CNI ficarem `Running` e `READY`. Então:

```bash
kubectl get nodes                          # k8s-cp deve virar Ready
kubectl get pods -n kube-system            # coredns deve sair de Pending -> Running
```

- Assim que o CNI está pronto, o kubelet reporta `NetworkReady=true`, o nó vira
  **Ready** e o CoreDNS (que dependia de rede de pod) sobe.

---

## Passo — validar rede de pod e DNS

```bash
kubectl run test --image=busybox --restart=Never -- sleep 3600
kubectl exec test -- nslookup kubernetes.default    # DNS interno resolve?
kubectl exec test -- ping -c2 1.1.1.1               # pod sai pra internet?
kubectl delete pod test
```

- `nslookup kubernetes.default` testa o CoreDNS. `ping` externo testa
  NAT/roteamento do pod. Os dois OK = CNI saudável.

---

## Resultado

```text
# cole: kubectl get nodes ; kubectl get pods -A | grep -E 'calico|flannel|coredns' ; nslookup kubernetes.default
```

---

## Checklist de saída da Fase 5

- [ ] CNI aplicado (Calico **ou** Flannel — um só)
- [ ] Pods do CNI Running (`calico-node` / `kube-flannel-ds`) e `k8s-cp` **Ready**
- [ ] CoreDNS `Running`
- [ ] pod de teste resolve DNS interno e alcança a internet

➡️ Próxima: [Fase 6 — join dos workers](06-join-workers.md).

## Notas / gotchas

- _(anote aqui — ex.: coredns preso em Pending = CNI não subiu; pods sem IP =
  CIDR conflitando (Calico); `calico-node` CrashLoop = detecção de interface
  errada (`IP_AUTODETECTION_METHOD`); Flannel sem tráfego entre nós = checar
  `br_netfilter`/firewall, etc.)_
