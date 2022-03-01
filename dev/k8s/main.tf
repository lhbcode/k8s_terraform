provider "aws" {
  region     = var.region
}

data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket  = "terraform-lhb-apse2-tfstate"
    key     = "dev/vpc/terraform.tfstate"
    region  = "ap-southeast-2"
  }
}


locals {
  region            = var.lookup-region_abbr["${var.region}"]
  ami               = lookup(var.aws_amis, var.region)
  instance_type     = "t3.medium" #bastion instance type
  private_key_name  = "private"
  worker_ip = {
      one = {
      k8s_worker_ip = "${module.ec2_worker1.private_ip}"
      }
      two = {
      k8s_worker_ip = "${module.ec2_worker2.private_ip}"
      }
      three = {
      k8s_worker_ip = "${module.ec2_worker3.private_ip}"
      }
  }
}


#################################################################################
## Random string                                                               ##
#################################################################################

# for iam role and frontend deploy tags
resource "random_string" "random" {
  length  = 4
  special = false
}


#################################################################################
## Keypair                                                                     ##
#################################################################################
resource "tls_private_key" "this" {
  algorithm = "RSA"
  rsa_bits  = 4096

  provisioner "local-exec" {
    command = <<EOF
    rm ./${local.private_key_name}-key.pem
    echo '${self.private_key_pem}' > ./${local.private_key_name}-key.pem
    chmod 400 ${local.private_key_name}-key.pem
    EOF
  }
}

module "keypair" {
  source = "../../terraform/module/key"

  key_name   = "${var.project}-${var.environment}-${local.region}-key"
  public_key = tls_private_key.this.public_key_openssh
}


#################################################################################
## IAM                                                                         ##
#################################################################################
# for master
resource "aws_iam_role" "master_role" {
  name               = "${var.project}-${var.environment}-master-${random_string.random.id}"
  path               = "/"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
   tags = {
    Project    = "${var.project}"
  }
}


resource "aws_iam_role_policy_attachment" "this_1" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.master_role.name
}

resource "aws_iam_instance_profile" "master_role" {
  name = "${var.project}-${var.environment}--${local.region}-master-${random_string.random.id}"
  role = aws_iam_role.master_role.name
}
##############################################
# for worker
resource "aws_iam_role" "worker_role" {
  name               = "${var.project}-${var.environment}-worker-${random_string.random.id}"
  path               = "/"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
   tags = {
    Project    = "${var.project}"
  }
}


resource "aws_iam_role_policy_attachment" "this_2" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.worker_role.name
}

resource "aws_iam_instance_profile" "worker_role" {
  name = "${var.project}-${var.environment}-${local.region}-worker-${random_string.random.id}"
  role = aws_iam_role.worker_role.name
}

# security groups
module "security_group_k8s_ec2" {
  source = "../../terraform/module/security"

  name        = "${var.project}-${var.environment}-k8s-sg"
  description = "Security group for k8s usage with EC2 instance"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id

  ingress_cidr_blocks = ["${data.terraform_remote_state.vpc.outputs.vpc_cidr}"]
  ingress_rules       = ["ssh-tcp" ]
  egress_rules        = ["http-80-tcp","https-443-tcp","ssh-tcp"]
  computed_ingress_with_source_security_group_id = [
    {
      rule                     = "all-all"
      source_security_group_id = module.security_group_k8s_ec2.security_group_id
      description = "access k8s"
    },
  ]
  number_of_computed_ingress_with_source_security_group_id = 1


  computed_egress_with_source_security_group_id = [
    {
      rule                     = "all-all"
      source_security_group_id = module.security_group_k8s_ec2.security_group_id
      description = "out k8s"
    },
  ]
  number_of_computed_egress_with_source_security_group_id = 1
   ingress_with_cidr_blocks = [
    {
      from_port   = 30000
      to_port     = 32767
      protocol    = "tcp"
      description = "NodePort"
      cidr_blocks = "0.0.0.0/0"
    },
  ]
   tags = {
    Project    = "${var.project}"

  }
}

# security groups
module "security_group_bastion_ec2" {
  source = "../../terraform/module/security"

  name        = "${var.project}-${var.environment}-bastion-sg"
  description = "Security group for bastion usage with EC2 instance"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id

  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["ssh-tcp" ]
  egress_rules        = ["http-80-tcp","https-443-tcp","ssh-tcp"]
   tags = {
    Project    = "${var.project}"

  }
}

#################################################################################
## EC2                                                                         ##
#################################################################################
# for master
module "ec2_master" {
  source = "../../terraform/module/ec2"

  name                    = "${var.project}-${var.environment}-${local.region}-master"
  ami                     = local.ami[0]
  instance_type           = local.instance_type
  key_name                = module.keypair.key_pair_key_name
  monitoring              = false

  vpc_security_group_ids  = [module.security_group_k8s_ec2.security_group_id]
  iam_instance_profile    = aws_iam_instance_profile.master_role.name
  subnet_id               = element(data.terraform_remote_state.vpc.outputs.pri_subnet_ids, 1)
  availability_zone       = element(data.terraform_remote_state.vpc.outputs.vpc_azs, 1)

  root_block_device = [
        {
          encrypted   = true
          volume_type = "gp3"
          throughput  = 200
          volume_size = 50
        }
  ]
   tags = {
    Project             = "${var.project}"
    "kubernetes.io/cluster/msa_maker" = "shared"
  }
}

# for worker1 
module "ec2_worker1" {
  source = "../../terraform/module/ec2"

  name                    = "${var.project}-${var.environment}-${local.region}-worker1"
  ami                     = local.ami[0]
  instance_type           = local.instance_type
  key_name                = module.keypair.key_pair_key_name
  monitoring              = false

  vpc_security_group_ids  = [module.security_group_k8s_ec2.security_group_id]
  iam_instance_profile    = aws_iam_instance_profile.worker_role.name
  subnet_id               = element(data.terraform_remote_state.vpc.outputs.pri_subnet_ids, 1)
  availability_zone       = element(data.terraform_remote_state.vpc.outputs.vpc_azs, 1)

  root_block_device = [
        {
          encrypted   = true
          volume_type = "gp3"
          throughput  = 200
          volume_size = 50
        }
  ]
   tags = {
    Project             = "${var.project}"
    "kubernetes.io/cluster/msa_maker" = "shared"
  }
}

# for worker2 
module "ec2_worker2" {
  source = "../../terraform/module/ec2"

  name                    = "${var.project}-${var.environment}-${local.region}-worker2"
  ami                     = local.ami[0]
  instance_type           = local.instance_type
  key_name                = module.keypair.key_pair_key_name
  monitoring              = false

  vpc_security_group_ids  = [module.security_group_k8s_ec2.security_group_id]
  iam_instance_profile    = aws_iam_instance_profile.worker_role.name
  subnet_id               = element(data.terraform_remote_state.vpc.outputs.pri_subnet_ids, 2)
  availability_zone       = element(data.terraform_remote_state.vpc.outputs.vpc_azs, 2)

  root_block_device = [
        {
          encrypted   = true
          volume_type = "gp3"
          throughput  = 200
          volume_size = 50
        }
  ]
   tags = {
    Project                           = "${var.project}"
    "kubernetes.io/cluster/test"      = "shared"
  }
}

# for worker3 
module "ec2_worker3" {
  source = "../../terraform/module/ec2"

  name                    = "${var.project}-${var.environment}-${local.region}-worker3"
  ami                     = local.ami[0]
  instance_type           = local.instance_type
  key_name                = module.keypair.key_pair_key_name
  monitoring              = false

  vpc_security_group_ids  = [module.security_group_k8s_ec2.security_group_id]
  iam_instance_profile    = aws_iam_instance_profile.worker_role.name
  subnet_id               = element(data.terraform_remote_state.vpc.outputs.pri_subnet_ids, 3)
  availability_zone       = element(data.terraform_remote_state.vpc.outputs.vpc_azs, 3)

  root_block_device = [
        {
          encrypted   = true
          volume_type = "gp3"
          throughput  = 200
          volume_size = 50
        }
  ]
   tags = {
    Project                           = "${var.project}"
    "kubernetes.io/cluster/test"      = "shared"
  }
}


# for bastion
module "ec2_bastion" {
  source = "../../terraform/module/ec2"

  name                    = "${var.project}-${var.environment}-${local.region}-bastion"
  ami                     = local.ami[0]
  instance_type           = local.instance_type
  key_name                = module.keypair.key_pair_key_name
  monitoring              = false

  vpc_security_group_ids  = [module.security_group_bastion_ec2.security_group_id]
  iam_instance_profile    = aws_iam_instance_profile.worker_role.name
  subnet_id               = element(data.terraform_remote_state.vpc.outputs.pub_subnet_ids, 1)
  availability_zone       = element(data.terraform_remote_state.vpc.outputs.vpc_azs, 1)

  root_block_device = [
        {
          encrypted   = true
          volume_type = "gp3"
          throughput  = 200
          volume_size = 30
        }
  ]
   tags = {
    Project                           = "${var.project}"
  }
}


# for harbor
module "ec2_harbor" {
  source = "../../terraform/module/ec2"

  name                    = "${var.project}-${var.environment}-${local.region}-harbor"
  ami                     = local.ami[0]
  instance_type           = local.instance_type
  key_name                = module.keypair.key_pair_key_name
  monitoring              = false

  vpc_security_group_ids  = [module.security_group_bastion_ec2.security_group_id]
  iam_instance_profile    = aws_iam_instance_profile.worker_role.name
  subnet_id               = element(data.terraform_remote_state.vpc.outputs.pub_subnet_ids, 1)
  availability_zone       = element(data.terraform_remote_state.vpc.outputs.vpc_azs, 1)

  root_block_device = [
        {
          encrypted   = true
          volume_type = "gp3"
          throughput  = 200
          volume_size = 30
        }
  ]
   tags = {
    Project                           = "${var.project}"
  }
}


resource "null_resource" "connect_private" {
  connection {
    bastion_host = "${module.ec2_bastion.public_ip}"
    host         = "${module.ec2_master.private_ip}"
    user         = "ubuntu"
    private_key  = file("./private-key.pem")
  }
  provisioner "remote-exec" {
    script = "./master_script.sh"
  }
  provisioner "file" {
    source      = "./private-key.pem"
    destination = "/tmp/private-key.pem"
  }
  provisioner "remote-exec" {
   inline = [
     "sudo apt-get install -y sshpass",
     "chmod 400 /tmp/private-key.pem",
     "sshpass scp -i /tmp/private-key.pem  -o StrictHostKeyChecking=no /tmp/join.yml ubuntu@${module.ec2_worker1.private_ip}:/tmp",
     "sshpass scp -i /tmp/private-key.pem  -o StrictHostKeyChecking=no /tmp/join.yml ubuntu@${module.ec2_worker2.private_ip}:/tmp",
     "sshpass scp -i /tmp/private-key.pem  -o StrictHostKeyChecking=no /tmp/join.yml ubuntu@${module.ec2_worker3.private_ip}:/tmp",
   ]
  }
}

###### 
# for worker2
resource "null_resource" "install" {
  depends_on = [
    null_resource.connect_private,
  ]

  for_each = local.worker_ip
  connection {
    bastion_host = "${module.ec2_bastion.public_ip}"
    host         = each.value.k8s_worker_ip
    user         = "ubuntu"
    private_key  = file("./private-key.pem")
  }
  provisioner "remote-exec" {
    script = "./worker_script.sh"
  }
}

##

resource "null_resource" "anisble" {
  provisioner "local-exec" {
    command = <<EOF
    cat << EOT > ../../ansible/inventory/hosts
    [bastion] 
    ${module.ec2_bastion.public_ip} 
    [master] 
    ${module.ec2_master.private_ip} 
    [worker] 
    ${module.ec2_worker1.private_ip}
    ${module.ec2_worker2.private_ip}
    ${module.ec2_worker3.private_ip} 
    [all:vars] 
    ansible_user=ubuntu 
    ansible_ssh_private_key_file=${local.private_key_name}-key.pem 
    ansible_ssh_common_args='-F ssh.cfg -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand=\"ssh -F ssh.cfg -W %h:%p -q bastion\"'
EOT
    EOF
  }
  # create ssh.config
  provisioner "local-exec" {
    command = <<EOF
      cat << EOT > ssh.cfg
Host *
    Port 22
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    ServerAliveInterval 60
    ServerAliveCountMax 30

Host bastion
    HostName ${module.ec2_bastion.public_ip}
    StrictHostKeyChecking no
    User ubuntu
    IdentityFile ${local.private_key_name}-key.pem
EOT
    EOF
  }
  # for bastion tunneling
  provisioner "local-exec" {
    command = <<EOF
    scp -F ssh.cfg ${local.private_key_name}-key.pem bastion:~/.ssh/id_rsa
    ansible bastion -m command -a "ssh -o StrictHostKeyChecking=no localhost -fN -L 0.0.0.0:22:${module.ec2_master.private_ip}:22" -i ../../ansible/inventory/hosts
    EOF
  }
  # run ../ansible
  provisioner "local-exec" {
    command = <<EOF
    ansible-playbook -i ../../ansible/inventory/hosts -l master ../../ansible/main.yaml
    
    EOF
  }
   depends_on = [
    null_resource.install,
    null_resource.connect_private,
  ]
}

