variable "region" {
  description = "Regiao da AWS. us-east-1 e a mais barata; sa-east-1 (SP) tem menos latencia e custa mais."
  type        = string
  default     = "us-east-1"
}

variable "availability_zone" {
  description = "AZ da sub-rede. Deixe null para usar a primeira da regiao. As 3 instancias ficam na MESMA AZ (trafego entre AZ e cobrado)."
  type        = string
  default     = null
}

variable "project" {
  description = "Prefixo de nome/tag dos recursos."
  type        = string
  default     = "k8s-lab"
}

variable "vpc_cidr" {
  description = "CIDR da VPC do lab. NAO pode se sobrepor ao pod CIDR (10.244.0.0/16) nem ao service CIDR (10.96.0.0/12)."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = tonumber(split("/", var.vpc_cidr)[1]) >= 16
    error_message = "Use um prefixo /16 ou menor (um 10.0.0.0/8 engloba o pod e o service CIDR do lab)."
  }

  validation {
    condition     = !startswith(var.vpc_cidr, "10.244.") && !startswith(var.vpc_cidr, "10.96.")
    error_message = "Essa faixa colide com o pod CIDR (10.244.0.0/16) ou o service CIDR (10.96.0.0/12) do runbook."
  }
}

variable "subnet_cidr" {
  description = "CIDR da sub-rede publica. Os nos recebem IP privado fixo .10 (cp), .11 (w1), .12 (w2) dentro dela."
  type        = string
  default     = "10.0.1.0/24"
}

variable "worker_count" {
  description = "Quantos workers subir. 1 economiza ~2 GB e ~US$0,02/h e ja cobre quase tudo; 2 libera cenario multi-worker."
  type        = number
  default     = 2

  validation {
    condition     = var.worker_count >= 1 && var.worker_count <= 3
    error_message = "Use entre 1 e 3 workers."
  }
}

variable "control_plane_instance_type" {
  description = "O kubeadm exige >= 2 vCPU e >= 1700 MB no control plane."
  type        = string
  default     = "t3.medium"
}

variable "worker_instance_type" {
  description = "Workers nao tem minimo de CPU no join, mas 1 GB (t3.micro) sofre. t3.small = 2 vCPU / 2 GB."
  type        = string
  default     = "t3.small"
}

variable "root_volume_size" {
  description = "GB de EBS gp3 por no. Com 8 GB voce bate em DiskPressure baixando imagens."
  type        = number
  default     = 20
}

variable "allowed_ssh_cidr" {
  description = "CIDR liberado no SSH (22). Use \"<SEU_IP>/32\" (curl -s https://checkip.amazonaws.com). Sem default de proposito: e uma decisao sua."
  type        = string

  validation {
    condition     = can(cidrhost(var.allowed_ssh_cidr, 0))
    error_message = "Informe um CIDR valido, ex.: 203.0.113.4/32."
  }
}

variable "expose_apiserver" {
  description = "Libera a 6443 para allowed_ssh_cidr. Necessario para rodar kubectl da sua maquina/WSL. Nunca exponha para 0.0.0.0/0."
  type        = bool
  default     = false
}

variable "expose_nodeports" {
  description = "Libera 30000-32767 para allowed_ssh_cidr (testar NodePort no navegador). De dentro do no o teste funciona sem isso."
  type        = bool
  default     = false
}

variable "allocate_eip" {
  description = "Elastic IP no control plane: o IP publico para de mudar a cada stop/start (essencial se voce usa kubectl de fora). Cobra ~US$3,6/mes, inclusive com a instancia parada."
  type        = bool
  default     = false
}

variable "source_dest_check" {
  description = "Deixe true (default) usando CNI com encapsulamento (IPIP/VXLAN). Só ponha false para testar Calico em modo roteado."
  type        = bool
  default     = true
}

variable "public_key_path" {
  description = "Chave publica SSH a instalar nos nos. Deixe null e informe key_name para reusar uma key pair que ja existe na AWS."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "key_name" {
  description = "Nome de uma key pair JA existente na AWS. Se informado, public_key_path e ignorado."
  type        = string
  default     = null
}

variable "manage_hostnames" {
  description = "user_data que define hostname (k8s-cp/k8s-w1/...) e popula /etc/hosts — o equivalente ao C6 do runbook. Ponha false para fazer na mao."
  type        = bool
  default     = true
}
