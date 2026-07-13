# Fase 1 — VMs e rede (IP estático via netplan)

**Objetivo:** com as 3 VMs já criadas pelo `vagrant up`, dar a cada uma um IP
estático fixo na rede do `K8sLabSwitch`, garantir resolução de nomes entre os nós
e validar conectividade (entre nós, gateway, internet e DNS).

**Rodar em:** `k8s-cp`, `k8s-w1`, `k8s-w2` (os mesmos passos, mudando só o IP e o
hostname de cada um).

**Pré-requisito:** [Fase 0](00-preparacao-host-vms.md) concluída — as 3 VMs
`running` e acessíveis via `vagrant ssh`. Todos os passos abaixo são **dentro**
da VM (entre com `vagrant ssh <nome>`).

> **Por que IP estático?** O ICS entrega IPs por DHCP, mas eles podem mudar num
> reboot. O control plane publica seu endereço no certificado do apiserver e nos
> manifests; se o IP dos nós dançar, o cluster quebra. Fixar IP é pré-requisito.

📖 **Doc liberada na prova:**
[kubeadm — antes de começar (hostname/MAC/product_uuid únicos)](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#before-you-begin)
· [Portas e protocolos](https://kubernetes.io/docs/reference/networking/ports-and-protocols/)

> O `netplan`/IP estático em si é config de SO (não tem página no `kubernetes.io`).
> O que o exame cobra aqui são os **requisitos de nó**: hostname único, portas
> abertas e conectividade entre os nós.

---

## Passo 1 — descobrir a interface da rede do lab

Dentro da VM:

```bash
ip -brief address        # lista interfaces e IPs de forma compacta
ip route | grep default  # mostra por qual interface sai o default gateway
```

- Procure a interface com um IP **`192.168.137.x`** — é a placa na rede do lab
  (`K8sLabSwitch` no Windows / rede `k8slab` do libvirt no Linux), que pegou IP por
  DHCP. Costuma ser `eth0`/`enp*`.
- **Anote o nome exato dessa interface** — você vai usá-lo no netplan. Se houver
  mais de uma NIC, é a que tem o IP `192.168.137.x` e/ou a do `default via
  192.168.137.1`.

> ⚠️ Não altere a interface que o Vagrant usa para SSH — mudar a placa errada pode
> te trancar pra fora da VM. No **Windows** (switch interno único) costuma ser a
> mesma `eth0`. No **Linux** (vagrant-libvirt) há uma NIC de gerência separada pro
> SSH; configure a que está em `192.168.137.x` e deixe a de SSH quieta.

**Resultado (interface identificada por VM):**

| VM | Interface | IP atual (DHCP) |
|----|-----------|-----------------|
| k8s-cp | | |
| k8s-w1 | | |
| k8s-w2 | | |

---

## Passo 2 — escrever o netplan estático

O Ubuntu 24.04 usa **netplan**. Crie um arquivo dedicado (não edite o do
cloud-init) — troque `eth0` pelo nome real e o endereço conforme o
[plano de IPs](README.md#plano-de-ips).

```bash
sudo tee /etc/netplan/99-k8s-static.yaml >/dev/null <<'EOF'
network:
  version: 2
  ethernets:
    eth0:                       # <-- nome REAL da interface (Passo 1)
      dhcp4: false
      addresses:
        - 192.168.137.10/24     # <-- IP DESTE nó (.10 cp / .11 w1 / .12 w2)
      routes:
        - to: default
          via: 192.168.137.1    # gateway (ICS no Windows / libvirt no Linux)
      nameservers:
        addresses: [192.168.137.1, 1.1.1.1]
EOF

sudo chmod 600 /etc/netplan/99-k8s-static.yaml   # netplan exige perm restrita no 24.04
```

Explicação campo a campo:
- `dhcp4: false` — desliga o DHCP nessa interface; o IP passa a ser manual.
- `addresses` — o IP estático **com a máscara** (`/24` = 255.255.255.0).
- `routes → default via 192.168.137.1` — rota padrão apontando pro gateway ICS
  (é assim que a VM chega na internet, via NAT do Windows).
- `nameservers` — DNS. `192.168.137.1` (o ICS resolve) + `1.1.1.1` de reserva.
- `chmod 600` — sem isso o `netplan` reclama de "permissions too open".

Aplicar e conferir:

```bash
sudo netplan generate      # valida a sintaxe do YAML (erra alto se estiver torto)
sudo netplan apply         # aplica a config
ip -brief address          # confirma o IP novo na interface
```

> Se você aplicar via `vagrant ssh` e o IP da interface de SSH mudar, a sessão
> pode congelar — é esperado. Reentre com `vagrant ssh` (o Vagrant reencontra a
> VM). Em caso de erro, `sudo netplan apply` de novo ou reboot.

**Resultado (`k8s-cp` — repita o bloco pra w1/w2):**

```text
# cole aqui a saída de: ip -brief address  e  ip route
```

---

## Passo 3 — impedir o cloud-init de sobrescrever o netplan

As boxes Vagrant/Ubuntu usam cloud-init, que **regenera** o netplan no boot e pode
apagar sua config estática. Desative a parte de rede do cloud-init:

```bash
sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg >/dev/null <<'EOF'
network: {config: disabled}
EOF
```

- Isso diz ao cloud-init "não mexa na rede" — seu `99-k8s-static.yaml` vira a
  fonte da verdade e sobrevive a reboots.

---

## Passo 4 — hostname e /etc/hosts

Nome consistente por nó (rode o certo em cada VM):

```bash
sudo hostnamectl set-hostname k8s-cp     # k8s-w1 / k8s-w2 nos workers
exec bash                                 # recarrega o prompt com o novo hostname
```

Resolução estática entre os nós — **nos 3** — pra eles se acharem por nome:

```bash
sudo tee -a /etc/hosts >/dev/null <<'EOF'

# --- k8s lab ---
192.168.137.10 k8s-cp
192.168.137.11 k8s-w1
192.168.137.12 k8s-w2
EOF
```

- `hostnamectl set-hostname` — define o nome do nó (é o que aparece em
  `kubectl get nodes`).
- Entradas em `/etc/hosts` — dispensam DNS interno pro cluster: qualquer nó
  resolve `k8s-cp`, `k8s-w1`, `k8s-w2` direto pelo IP.

---

## Passo 5 — validar conectividade

```bash
ping -c2 192.168.137.1     # gateway / host Windows (ICS)
ping -c2 k8s-cp            # outro nó por nome (testa /etc/hosts)
ping -c2 1.1.1.1           # internet por IP (testa NAT/rota)
ping -c2 github.com        # internet por nome (testa DNS)
```

Todos os 4 têm que responder. Se o de **nome** (github.com) falhar mas o de
**IP** (1.1.1.1) funcionar → problema de DNS (revise `nameservers` no netplan).
Se nem o IP externo responde → problema de rota/NAT (revise `routes` e o ICS).

**Resultado:**

| Teste | k8s-cp | k8s-w1 | k8s-w2 |
|-------|--------|--------|--------|
| ping gateway (.1) | | | |
| ping entre nós | | | |
| ping 1.1.1.1 | | | |
| ping DNS (nome) | | | |

---

## Checklist de saída da Fase 1

- [ ] As 3 VMs com IP estático `.10 / .11 / .12` (confirmado em `ip -brief address`)
- [ ] cloud-init de rede desativado nos 3
- [ ] hostname correto nos 3 + `/etc/hosts` com os 3 nós
- [ ] ping OK: gateway, entre nós, internet por IP, internet por nome

➡️ Próxima: [Fase 2 — preparação dos nós](02-preparacao-nos.md).

---

## Notas / gotchas desta fase

- _(anote aqui o que aparecer — ex.: nome de interface diferente de eth0, warning
  de permissão do netplan, cloud-init voltando após reboot, etc.)_
