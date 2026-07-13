# Prática — Storage (10%)

PersistentVolume (PV), PersistentVolumeClaim (PVC), StorageClass e como um pod monta
um volume.

📖 Docs liberadas: [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
· [Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)
· [Configurar Pod com PV](https://kubernetes.io/docs/tasks/configure-pod-container/configure-persistent-volume-storage/)

> 🚧 **Semente** — exercícios prontos + espaço pra adicionar mais.

---

## Ex 1 — PV + PVC + pod (hostPath) ⏱️ ~8min

**Tarefa:** crie um PV `pv-data` de 1Gi (hostPath `/mnt/data`, `ReadWriteOnce`), um
PVC `pvc-data` que o consuma, e um pod que monte o PVC em `/usr/share/nginx/html`.

<details><summary>Dica</summary>

O PVC casa com o PV por **capacidade + accessModes + storageClassName**. Com PV
estático, use `storageClassName: ""` nos dois (ou um nome igual) pra não cair no
provisionamento dinâmico.
</details>

<details><summary>Solução (esqueleto)</summary>

```yaml
apiVersion: v1
kind: PersistentVolume
metadata: { name: pv-data }
spec:
  capacity: { storage: 1Gi }
  accessModes: [ReadWriteOnce]
  storageClassName: ""
  hostPath: { path: /mnt/data }
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: pvc-data }
spec:
  accessModes: [ReadWriteOnce]
  resources: { requests: { storage: 1Gi } }
  storageClassName: ""
```
```bash
kubectl apply -f pv-pvc.yaml
kubectl get pv,pvc                 # PVC deve ficar Bound ao pv-data
# no pod: volumes[].persistentVolumeClaim.claimName: pvc-data + volumeMounts
```
</details>

📖 [Configurar Pod com PV](https://kubernetes.io/docs/tasks/configure-pod-container/configure-persistent-volume-storage/)

---

## Ex 2 — Diagnosticar PVC `Pending` ⏱️ ~5min

**Tarefa:** um PVC fica `Pending` e o pod que o usa não sobe. Descubra por quê.

<details><summary>Solução</summary>

```bash
kubectl describe pvc <nome>        # Events: no volume plugin matched / no PV / no StorageClass
kubectl get pv                     # existe PV compatível (tamanho/accessMode/class)?
kubectl get storageclass           # há default? (marcada "(default)")
# corrigir: criar PV compatível, ou setar storageClassName certo, ou marcar SC default
```
</details>

📖 [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)

---

## Ex 3 — reclaimPolicy: Retain vs Delete ⏱️ ~7min

**Tarefa:** com o PV estático `pv-data` (Ex 1), observe o que acontece com o PV ao
deletar o PVC, e depois torne o PV reaproveitável.

<details><summary>Solução</summary>

```bash
kubectl get pv pv-data -o jsonpath='{.spec.persistentVolumeReclaimPolicy}{"\n"}'  # Retain (default de PV estático)
kubectl delete pvc pvc-data
kubectl get pv pv-data          # STATUS = Released (não Available): o claimRef ainda aponta pro PVC velho
# reaproveitar um PV Released (Retain):
kubectl patch pv pv-data -p '{"spec":{"claimRef":null}}'
kubectl get pv pv-data          # Available -> pode ser Bound de novo
```
- **Retain** = o PV (e os dados) sobrevivem ao PVC; limpeza é manual.
- **Delete** (comum em dinâmico) = ao apagar o PVC, o PV e o volume subjacente somem.
</details>

📖 [Reclaiming](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#reclaiming)

---

## Ex 4 — accessModes: RWO vs RWX ⏱️ ~5min

**Tarefa:** entenda por que um PVC `ReadWriteOnce` não serve pra um Deployment com
réplicas espalhadas em nós diferentes, e o que muda com `ReadWriteMany`.

<details><summary>Solução</summary>

```bash
kubectl get pvc pvc-data -o jsonpath='{.spec.accessModes}{"\n"}'
# RWO (ReadWriteOnce)  -> R/W por UM nó (vários pods no mesmo nó ok)
# RWX (ReadWriteMany)  -> R/W por VÁRIOS nós ao mesmo tempo
# ROX (ReadOnlyMany)   -> read-only por vários nós
```
- Com **RWO**, se o Deployment tiver réplicas em nós diferentes, só os pods do nó que
  montou o volume sobem — os outros ficam presos (`ContainerCreating`/`Multi-Attach`).
- **RWX exige um backend que suporte** (NFS, CephFS...). `hostPath`/`local` **não**
  fazem RWX — pedir RWX com eles deixa o PVC sem casar.
</details>

📖 [Access Modes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#access-modes)

---

## Ex 5 — StorageClass com provisionamento dinâmico ⏱️ ~8min

**Tarefa:** crie uma StorageClass e um PVC que gere o PV **automaticamente** (sem PV
pré-criado). Observe o `volumeBindingMode`.

<details><summary>Dica</summary>

Provisionamento dinâmico precisa de um **provisioner**. Na prova o cluster costuma ter
uma StorageClass **default**; num kubeadm cru **não vem nenhum** — instale um simples
(ex.: local-path-provisioner) uma vez no lab.
</details>

<details><summary>Solução (esqueleto)</summary>

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata: { name: fast }
provisioner: rancher.io/local-path        # o provisioner que você instalou
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer   # só provisiona quando um POD usa o PVC
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: pvc-dyn }
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: fast
  resources: { requests: { storage: 1Gi } }
```
```bash
kubectl apply -f dyn.yaml
kubectl get pvc pvc-dyn      # com WaitForFirstConsumer fica Pending até um pod montar
# marcar uma SC como default (o que a prova às vezes pede):
kubectl annotate sc fast storageclass.kubernetes.io/is-default-class=true
```
</details>

📖 [Storage Classes](https://kubernetes.io/docs/concepts/storage/storage-classes/)
· [Dynamic Provisioning](https://kubernetes.io/docs/concepts/storage/dynamic-provisioning/)

---

## Adicione mais

- [ ] Redimensionar um PVC (`spec.resources.requests.storage`) com SC que permite expand.
- [ ] `subPath` num volumeMount.
