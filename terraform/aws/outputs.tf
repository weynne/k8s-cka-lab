output "nodes" {
  description = "Nome, IP privado (usado pelo cluster) e IP publico (usado por voce) de cada no."
  value = {
    for nome, no in aws_instance.node : nome => {
      instance_id = no.id
      privado     = no.private_ip
      publico     = nome == "k8s-cp" && var.allocate_eip ? aws_eip.control_plane[0].public_ip : no.public_ip
    }
  }
}

output "control_plane_privado" {
  description = "Vai em --apiserver-advertise-address na Fase 4."
  value       = aws_instance.node["k8s-cp"].private_ip
}

output "control_plane_publico" {
  description = "Para SSH e, se expose_apiserver = true, para --apiserver-cert-extra-sans."
  value       = var.allocate_eip ? aws_eip.control_plane[0].public_ip : aws_instance.node["k8s-cp"].public_ip
}

output "ssh" {
  description = "Comandos de SSH prontos (usuario da AMI Ubuntu = ubuntu)."
  value = {
    for nome, no in aws_instance.node : nome =>
    "ssh ubuntu@${nome == "k8s-cp" && var.allocate_eip ? aws_eip.control_plane[0].public_ip : no.public_ip}"
  }
}

output "instance_ids" {
  description = "Para parar/religar o lab: aws ec2 stop-instances --instance-ids <estes>"
  value       = [for no in aws_instance.node : no.id]
}

output "proximo_passo" {
  description = "Onde continuar no runbook."
  value       = <<-EOT
    Infra pronta. Kubernetes continua na mao:

      1. ssh ubuntu@${var.allocate_eip ? aws_eip.control_plane[0].public_ip : aws_instance.node["k8s-cp"].public_ip}
      2. Valide a rede (C do runbook): ping entre nos por nome, curl https://pkgs.k8s.io
      3. Fase 2 -> docs/k8s-lab/02-preparacao-nos.md   (containerd, swap, sysctl)
      4. Fase 3 -> docs/k8s-lab/03-instalacao-kube-tools.md
      5. Fase 4 -> sudo kubeadm init \
                     --apiserver-advertise-address=${aws_instance.node["k8s-cp"].private_ip} \
                     --pod-network-cidr=10.244.0.0/16 \
                     --cri-socket=unix:///run/containerd/containerd.sock${var.expose_apiserver ? " \\\n                     --apiserver-cert-extra-sans=${var.allocate_eip ? aws_eip.control_plane[0].public_ip : aws_instance.node["k8s-cp"].public_ip}" : ""}
      6. Fases 5 e 6 -> CNI e join dos workers

    Ao parar de estudar (para a cobranca de compute):
      aws ec2 stop-instances --region ${var.region} --instance-ids ${join(" ", [for no in aws_instance.node : no.id])}
  EOT
}
