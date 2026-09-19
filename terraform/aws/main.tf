# Provisiona SÓ a infra (VPC, rede, security group, 3 EC2) — nada de Kubernetes.
# É o equivalente AWS do Vagrantfile: as Fases 2 a 6 do runbook continuam na mão.
# Runbook: ../../docs/k8s-lab/00b-aws-ec2.md

data "aws_availability_zones" "disponiveis" {
  state = "available"
}

# AMI oficial do Ubuntu 24.04 (parametro publico da Canonical no SSM — sempre a mais recente)
data "aws_ssm_parameter" "ubuntu_2404" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

locals {
  az = coalesce(var.availability_zone, data.aws_availability_zones.disponiveis.names[0])

  # Plano de IPs: espelha o do lab local (.10 control plane, .11/.12 workers).
  # A AWS reserva os 4 primeiros IPs e o ultimo de cada sub-rede — por isso comecamos no .10.
  workers = {
    for i in range(1, var.worker_count + 1) :
    "k8s-w${i}" => {
      instance_type = var.worker_instance_type
      private_ip    = cidrhost(var.subnet_cidr, 10 + i)
    }
  }

  nodes = merge({
    "k8s-cp" = {
      instance_type = var.control_plane_instance_type
      private_ip    = cidrhost(var.subnet_cidr, 10)
    }
  }, local.workers)

  hosts = { for nome, no in local.nodes : nome => no.private_ip }
}

# ---------------------------------------------------------------------------
# Rede: VPC dedicada, sub-rede publica com IGW (saida pra internet que as
# Fases 2/3 precisam pra baixar pacotes e imagens).
# ---------------------------------------------------------------------------

resource "aws_vpc" "lab" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = var.project }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id

  tags = { Name = var.project }
}

resource "aws_subnet" "lab" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = var.subnet_cidr
  availability_zone       = local.az
  map_public_ip_on_launch = true

  tags = { Name = "${var.project}-publica" }
}

resource "aws_route_table" "lab" {
  vpc_id = aws_vpc.lab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }

  tags = { Name = var.project }
}

resource "aws_route_table_association" "lab" {
  subnet_id      = aws_subnet.lab.id
  route_table_id = aws_route_table.lab.id
}

# ---------------------------------------------------------------------------
# Security Group — o firewall que o lab local nao tem.
# Perfil minimo: tudo liberado ENTRE os nos + SSH do seu IP.
# ---------------------------------------------------------------------------

resource "aws_security_group" "nodes" {
  name_prefix = "${var.project}-"
  description = "CKA/CKAD lab: trafego entre nos + SSH"
  vpc_id      = aws_vpc.lab.id

  tags = { Name = var.project }

  lifecycle {
    create_before_destroy = true
  }
}

# A regra indispensavel: apiserver (6443), etcd (2379-2380), kubelet (10250),
# NodePort e o encapsulamento do CNI (IPIP protocolo 4 / VXLAN 4789) de uma vez.
resource "aws_vpc_security_group_ingress_rule" "entre_nos" {
  security_group_id            = aws_security_group.nodes.id
  referenced_security_group_id = aws_security_group.nodes.id
  ip_protocol                  = "-1"
  description                  = "Todo trafego entre os nos do lab"
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.nodes.id
  cidr_ipv4         = var.allowed_ssh_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  description       = "SSH"
}

resource "aws_vpc_security_group_ingress_rule" "apiserver" {
  count = var.expose_apiserver ? 1 : 0

  security_group_id = aws_security_group.nodes.id
  cidr_ipv4         = var.allowed_ssh_cidr
  ip_protocol       = "tcp"
  from_port         = 6443
  to_port           = 6443
  description       = "kube-apiserver (kubectl de fora do cluster)"
}

resource "aws_vpc_security_group_ingress_rule" "nodeports" {
  count = var.expose_nodeports ? 1 : 0

  security_group_id = aws_security_group.nodes.id
  cidr_ipv4         = var.allowed_ssh_cidr
  ip_protocol       = "tcp"
  from_port         = 30000
  to_port           = 32767
  description       = "NodePort"
}

resource "aws_vpc_security_group_egress_rule" "saida" {
  security_group_id = aws_security_group.nodes.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Saida liberada (apt, imagens de container)"
}

# ---------------------------------------------------------------------------
# Acesso SSH
# ---------------------------------------------------------------------------

resource "aws_key_pair" "lab" {
  count = var.key_name == null ? 1 : 0

  key_name_prefix = "${var.project}-"
  public_key      = file(pathexpand(var.public_key_path))
}

# ---------------------------------------------------------------------------
# Os nos. Nada de Kubernetes aqui: o user_data so cuida de hostname e
# /etc/hosts (o C6 do runbook). containerd, kubeadm, init e join sao manuais.
# ---------------------------------------------------------------------------

resource "aws_instance" "node" {
  for_each = local.nodes

  ami                    = data.aws_ssm_parameter.ubuntu_2404.value
  instance_type          = each.value.instance_type
  subnet_id              = aws_subnet.lab.id
  private_ip             = each.value.private_ip
  vpc_security_group_ids = [aws_security_group.nodes.id]
  key_name               = var.key_name != null ? var.key_name : aws_key_pair.lab[0].key_name
  source_dest_check      = var.source_dest_check

  user_data = var.manage_hostnames ? templatefile("${path.module}/cloud-init.yaml.tftpl", {
    hostname = each.key
    hosts    = local.hosts
  }) : null

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  metadata_options {
    http_tokens = "required" # IMDSv2
  }

  tags = { Name = each.key }
}

resource "aws_eip" "control_plane" {
  count = var.allocate_eip ? 1 : 0

  instance = aws_instance.node["k8s-cp"].id
  domain   = "vpc"

  tags = { Name = "${var.project}-cp" }

  depends_on = [aws_internet_gateway.lab]
}
