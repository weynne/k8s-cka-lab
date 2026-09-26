# Fase 0 — Preparação do host e subida das VMs

**Objetivo:** deixar o host pronto (hypervisor + rede + Vagrant) e subir as 3 VMs
com `vagrant up`, antes de qualquer coisa de Kubernetes.

Esta é a **única fase que muda conforme o SO do host** — da Fase 1 em diante tudo
roda **dentro** dos guests Ubuntu, idêntico. Escolha seu caminho:

- **[Caminho A — host Windows (Hyper-V)](#caminho-a--host-windows-hyper-v)**
- **[Caminho B — host Linux (KVM/libvirt)](#caminho-b--host-linux-kvmlibvirt)**
- **[Caminho C — nós na AWS (EC2)](00b-aws-ec2.md)** → arquivo à parte; use **só
  se você já tem um lab AWS** (ou uma conta nova com créditos do free tier). Não
  tem? Fique no A ou B — o lab local ensina a mesma coisa de graça.

**Meta comum (Caminhos A/B):** 3 VMs Ubuntu 24.04 (`k8s-cp`, `k8s-w1`, `k8s-w2`)
na rede **`192.168.137.0/24`** (gateway `.1`), acessíveis via `vagrant ssh`.

> **Por que os dois hosts usam `192.168.137.0/24`?** No Windows essa faixa é
> **imposta** pelo ICS (não dá pra mudar). No Linux ela é uma **escolha
> proposital**: ao reusar a mesma sub-rede, o plano de IPs e as **Fases 1–6 ficam
> idênticas independente do SO do host** — ninguém precisa remapear endereço
> nenhum. (No Linux você poderia usar qualquer outra `/24`; só teria que ajustar
> os `.137.x` no runbook inteiro.)

> **💾 Pouca RAM livre no host?** As VMs **reservam** a RAM enquanto ligadas
> (~8 GB os três: CP 4 + 2×2). Você não precisa das 3 sempre: um cluster de
> **2 nós** (`k8s-cp` + `k8s-w1`, ~6 GB) já cobre quase tudo da CKA — só perde a
> demo de "pod em nós diferentes"; suba o `k8s-w2` só pra cenário multi-worker.
> Use **`vagrant halt`** pra liberar a RAM ao parar de estudar (`vagrant up`
> retoma). Se rodar WSL2 junto, limite-o no `.wslconfig` (ex.: `memory=4GB`) pra
> não competir. Não corte o CP — 4 GB nele é o que evita OOM; ajuste pelo
> **número de VMs ligadas**.

---

## Caminho A — host Windows (Hyper-V)

**Rodar em:** host **Windows 11 Pro** (PowerShell **como Administrador** — o
provider `hyperv` do Vagrant e o Hyper-V exigem elevação).

🔧 **Referência de montagem (não abre na prova):**
[Vagrant — Hyper-V provider](https://developer.hashicorp.com/vagrant/docs/providers/hyperv)
· [Hyper-V no Windows](https://learn.microsoft.com/windows-server/virtualization/hyper-v/hyper-v-technology-overview)
· [Internet Connection Sharing (ICS)](https://learn.microsoft.com/windows-hardware/drivers/mobilebroadband/internet-connection-sharing)

### A1 — habilitar o Hyper-V (uma vez)

```powershell
# Estado atual
Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All

# Habilitar (reinicia o Windows ao final)
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All
```

- Hyper-V é o hypervisor tipo-1 do Windows; é o que o Vagrant (provider `hyperv`)
  usa pra criar as VMs. Requer Windows 11 **Pro/Enterprise** (o Home não tem).

### A2 — Virtual Switch interno `K8sLabSwitch` (uma vez)

```powershell
Get-VMSwitch                                           # já existe?
New-VMSwitch -Name "K8sLabSwitch" -SwitchType Internal # criar (só se não existir)
```

- **Interno** = as VMs falam entre si e com o host, mas **não** têm saída direta
  pra internet. A saída vem do ICS (A3), que faz NAT por cima desse switch.
- Ao criar, surge o adaptador `vEthernet (K8sLabSwitch)` — a "perna" do host nessa
  rede. O ICS vai colocar esse adaptador em `192.168.137.1`.

### A3 — ICS: compartilhar a internet com o `K8sLabSwitch` (uma vez)

Pela GUI (mais confiável que script): `ncpa.cpl` → botão direito no **adaptador de
internet** (Wi-Fi/Ethernet que já navega) → **Propriedades** → aba
**Compartilhamento** → marque *"Permitir que outros usuários da rede se conectem
pela conexão à Internet deste computador"* → em "Conexão de rede doméstica",
escolha **vEthernet (K8sLabSwitch)**.

- O ICS liga NAT + DHCP + DNS-forwarder para a rede interna. Ele **fixa** a faixa
  em `192.168.137.0/24` com o host em `192.168.137.1` (gateway). É daí que sai
  todo o [plano de IPs](README.md#plano-de-ips).

> ⚠️ Gotchas do ICS:
> - A faixa `192.168.137.x` é **fixa** e não configurável pela GUI.
> - Após reboot do Windows, o ICS às vezes precisa ser reativado (ou o serviço
>   *"Shared Access / Compartilhamento de Conexão"* iniciado). Se as VMs perderem
>   internet, comece a investigar por aqui.
> - Só **um** adaptador pode compartilhar por vez.

Validação:
```powershell
Get-NetIPAddress -InterfaceAlias "vEthernet (K8sLabSwitch)" -AddressFamily IPv4
# esperado: 192.168.137.1
```

### A4 — Vagrant + provider Hyper-V

```powershell
vagrant --version        # confirma o Vagrant instalado
```

- O provider `hyperv` já vem embutido no Vagrant (não precisa de plugin).
- O Vagrant usa **SMB** para a pasta sincronizada; ele vai pedir **usuário/senha
  do Windows** no `vagrant up`. É esperado.

### A5 — o Vagrantfile (referência das VMs)

Só cria **VM + rede + SO** (nada de Kubernetes):

```ruby
Vagrant.configure("2") do |config|
  config.vm.box = "generic/ubuntu2404"

  nodes = {
    "k8s-cp" => { cpus: 2, mem: 4096 },   # control plane: 2 vCPU exigidos; 4 GB p/ folga (mín. preflight é 1700 MB)
    "k8s-w1" => { cpus: 2, mem: 2048 },   # workers: 1 vCPU já basta (join não checa CPU); 2 roda mais liso
    "k8s-w2" => { cpus: 2, mem: 2048 },
  }

  nodes.each do |name, spec|
    config.vm.define name do |node|
      node.vm.hostname = name
      node.vm.provider "hyperv" do |hv|
        hv.vmname    = name
        hv.cpus      = spec[:cpus]
        hv.memory    = spec[:mem]
        hv.maxmemory = spec[:mem]         # desliga dynamic memory (ver nota)
      end
    end
  end
end
```

- **Sizing:** o mínimo do kubeadm é **2 vCPU + ≥ 1700 MB só no control plane**
  (preflight `NumCPU`/`Mem`). Os **workers não têm esse mínimo** — funcionam com
  **1 vCPU** (o `kubeadm join` não checa CPU); deixei 2 porque num host com CPU
  sobrando roda mais liso. Sizing deste lab: **CP 4 GB + workers 2 GB** (total
  ~8 GB) — 4 GB no CP absorve os picos de apiserver/upgrade/etcd sem OOM; num host
  apertado dá pra baixar pra 3 GB.
- **`maxmemory` = memory:** sem memória dinâmica, o kubelet não vê a RAM oscilando
  e evita decisões estranhas de eviction.
- O switch (`K8sLabSwitch`) costuma ser escolhido no prompt do `vagrant up`.

### A6 — subir as VMs

Na pasta do Vagrantfile, PowerShell **como Administrador**:

```powershell
vagrant up --provider=hyperv     # cria e liga as 3 VMs (1ª vez baixa a box)
# se perguntar o Virtual Switch, escolha: K8sLabSwitch
# se pedir credenciais SMB, informe usuário/senha do Windows
```

➡️ Pule para **[Validação](#validação-comum-aos-dois-caminhos)**.

---

## Caminho B — host Linux (KVM/libvirt)

**Rodar em:** host **Linux** (usuário com sudo). Não precisa de ICS nem de switch
manual — a rede NAT do libvirt faz esse papel.

🔧 **Referência de montagem (não abre na prova):**
[vagrant-libvirt](https://vagrant-libvirt.github.io/vagrant-libvirt/)
· [libvirt/KVM no Ubuntu](https://ubuntu.com/server/docs/virtualization-libvirt)

### B1 — verificar suporte + instalar KVM/libvirt/Vagrant

```bash
egrep -c '(vmx|svm)' /proc/cpuinfo     # > 0 = CPU suporta virtualização (VT-x/AMD-V)

# Ubuntu/Debian:
sudo apt update
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients virtinst vagrant
sudo usermod -aG libvirt,kvm "$USER"   # relogue depois pra valer
# Fedora/RHEL: sudo dnf install -y @virtualization vagrant

vagrant plugin install vagrant-libvirt
```

- **KVM/QEMU** = hypervisor no próprio kernel (o análogo nativo do Hyper-V).
- **libvirt** = camada de gerência (`virsh`, `virt-manager`).
- **vagrant-libvirt** = provider que deixa o Vagrant falar com o libvirt.

### B2 — rede NAT do libvirt em `192.168.137.0/24`

Aqui está o "de propósito": criamos uma rede libvirt na **mesma faixa do Windows**,
pra o resto do runbook valer sem mudar nada.

```bash
cat > k8slab-net.xml <<'EOF'
<network>
  <name>k8slab</name>
  <forward mode='nat'/>
  <bridge name='virbr-k8s' stp='on' delay='0'/>
  <ip address='192.168.137.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.137.100' end='192.168.137.200'/>
    </dhcp>
  </ip>
</network>
EOF

virsh net-define k8slab-net.xml
virsh net-start k8slab
virsh net-autostart k8slab
virsh net-list --all            # k8slab deve ficar active + autostart
```

- `forward mode='nat'` — NAT pra internet (o papel que o ICS faz no Windows).
- `ip address='192.168.137.1'` — gateway, **mesmo endereço** do host ICS no
  Windows → plano de IPs e Fases 1–6 valem sem alteração.
- `range .100–.200` — pool DHCP inicial; **não colide** com os estáticos
  `.10–.12` que a Fase 1 vai fixar.

### B3 — o Vagrantfile (referência das VMs)

Mesmo box do Windows, só muda o provider e a rede:

```ruby
Vagrant.configure("2") do |config|
  config.vm.box = "generic/ubuntu2404"

  nodes = {
    "k8s-cp" => { cpus: 2, mem: 4096 },   # control plane: 2 vCPU exigidos; 4 GB p/ folga (mín. preflight é 1700 MB)
    "k8s-w1" => { cpus: 2, mem: 2048 },   # workers: 1 vCPU já basta (join não checa CPU); 2 roda mais liso
    "k8s-w2" => { cpus: 2, mem: 2048 },
  }

  nodes.each do |name, spec|
    config.vm.define name do |node|
      node.vm.hostname = name
      # anexa a VM à rede libvirt 'k8slab' (192.168.137.0/24);
      # o IP estático é fixado na Fase 1 (igual ao Windows)
      node.vm.network :private_network,
        libvirt__network_name: "k8slab",
        type: "dhcp"
      node.vm.provider :libvirt do |lv|
        lv.cpus   = spec[:cpus]
        lv.memory = spec[:mem]
      end
    end
  end
end
```

- O box `generic/ubuntu2404` tem imagem tanto pra hyperv quanto pra libvirt.
- A VM pega um IP `.137.x` por DHCP e você fixa o estático na Fase 1 — mesmo fluxo
  do Windows.
- O vagrant-libvirt cria uma **rede de gerência separada** pro SSH, então a VM terá
  2 NICs (a de SSH + a `k8slab`). Na Fase 1 você configura a que está em
  `192.168.137.x`.

> A sintaxe de rede do vagrant-libvirt varia entre versões. Se der ruído no
> `vagrant up`, confira a doc do plugin (link acima); o essencial é: box +
> cpus/mem + anexar à rede `k8slab`.

### B4 — subir as VMs

```bash
vagrant up --provider=libvirt    # cria e liga as 3 VMs (1ª vez baixa a box)
```

- Sem prompt de switch nem de credenciais SMB — a rede `k8slab` já dá NAT/DHCP.

➡️ Continue em **[Validação](#validação-comum-aos-dois-caminhos)**.

---

## Validação (comum aos dois caminhos)

```bash
vagrant status            # k8s-cp / k8s-w1 / k8s-w2 devem estar 'running'
vagrant ssh k8s-cp        # abre shell dentro da VM
# dentro da VM:
ping -c2 192.168.137.1    # gateway responde? (ICS no Windows / libvirt no Linux)
```

- `vagrant status` — estado de cada VM do Vagrantfile.
- `vagrant ssh <nome>` — entra na VM. É por aqui que você faz as fases 1+.

## Resultado

```text
# cole: vagrant status (as 3 'running')  e  o ping ao gateway 192.168.137.1
```

## Checklist de saída da Fase 0

- [ ] Host preparado — **Windows:** Hyper-V + `K8sLabSwitch` + ICS · **Linux:**
      KVM/libvirt + rede `k8slab`
- [ ] Rede `192.168.137.0/24` com gateway `.1` ativo
- [ ] `vagrant up` OK; `vagrant status` mostra as 3 `running`
- [ ] `vagrant ssh` funciona nas 3

➡️ Próxima: [Fase 1 — VMs e rede (IP estático)](01-vms-e-rede.md).

## Notas / gotchas

- _(anote aqui — ex.: ICS caindo após reboot (Windows); grupo `libvirt`/`kvm`
  exigindo relogin (Linux); sintaxe de rede do vagrant-libvirt; box demorando;
  memória dinâmica do Hyper-V; etc.)_
