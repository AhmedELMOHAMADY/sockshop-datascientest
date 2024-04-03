// Création du VPC
resource "aws_vpc" "ci-sockshop-vpc" {
  cidr_block = "10.0.0.0/16"
}

// Création des sous-réseaux
resource "aws_subnet" "ci-sockshop-subnet-a" {
  vpc_id            = aws_vpc.ci-sockshop-vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-west-3a"
}

resource "aws_subnet" "ci-sockshop-subnet-b" {
  vpc_id            = aws_vpc.ci-sockshop-vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-west-3b"
}

// Création du groupe de sécurité pour le cluster EKS
resource "aws_security_group" "ci-sockshop-eks-security-group" {
  vpc_id = aws_vpc.ci-sockshop-vpc.id

  // Définissez vos règles d'entrée et de sortie comme avant
}

// Création du cluster EKS
resource "aws_eks_cluster" "ci-sockshop-eks-cluster" {
  name     = "ci-sockshop-eks-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = "1.29" // Version de Kubernetes EKS

  vpc_config {
    subnet_ids              = [aws_subnet.ci-sockshop-subnet-a.id, aws_subnet.ci-sockshop-subnet-b.id]
    security_group_ids      = [aws_security_group.ci-sockshop-eks-security-group.id]
    endpoint_private_access = true
    endpoint_public_access  = true
    // Autres configurations du VPC
  }
}

// Création du rôle IAM pour le cluster EKS
resource "aws_iam_role" "eks_cluster_role" {
  name = "eks-cluster-role"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "eks.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })

  // Ajoutez ici les autorisations nécessaires pour le cluster EKS
}

// Création du groupe de nœuds pour le cluster EKS
resource "aws_eks_node_group" "ci-sockshop-eks-node-group" {
  cluster_name    = aws_eks_cluster.ci-sockshop-eks-cluster.name
  node_group_name = "ci-sockshop-eks-node-group"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = [aws_subnet.ci-sockshop-subnet-a.id, aws_subnet.ci-sockshop-subnet-b.id]

  scaling_config {
    desired_size = 1
    max_size     = 1
    min_size     = 1
    // Autres configurations de mise à l'échelle
  }
}

// Création du rôle IAM pour les nœuds EKS
resource "aws_iam_role" "eks_node_role" {
  name = "eks-node-role"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [{
      "Effect" : "Allow",
      "Principal" : {
        "Service" : "ec2.amazonaws.com"
      },
      "Action" : "sts:AssumeRole"
    }]
  })

  // Ajoutez d'autres autorisations requises pour les nœuds du cluster EKS ici
}

// Création du sous-réseau public pour le NAT Gateway
resource "aws_subnet" "ci-sockshop-subnet-public" {
  vpc_id            = aws_vpc.ci-sockshop-vpc.id
  cidr_block        = "10.0.3.0/24"  // Choisissez un CIDR approprié pour votre sous-réseau public
  availability_zone = "eu-west-3a"   // Choisissez une zone de disponibilité appropriée
}

// Création d'une adresse IP élastique pour le NAT Gateway
resource "aws_eip" "ci-sockshop-nat-eip" {
  vpc      = true
}

// Création du NAT Gateway
resource "aws_nat_gateway" "ci-sockshop-nat-gateway" {
  allocation_id = aws_eip.ci-sockshop-nat-eip.id
  subnet_id     = aws_subnet.ci-sockshop-subnet-public.id
}

// Route table for private subnets
resource "aws_route_table" "private_subnet_route_table" {
  vpc_id = aws_vpc.ci-sockshop-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.ci-sockshop-nat-gateway.id
  }
}

// Associate private subnets with the private route table
resource "aws_route_table_association" "private_subnet_route_association" {
  subnet_id      = aws_subnet.ci-sockshop-subnet-a.id
  route_table_id = aws_route_table.private_subnet_route_table.id
}

resource "aws_route_table_association" "private_subnet_route_association_b" {
  subnet_id      = aws_subnet.ci-sockshop-subnet-b.id
  route_table_id = aws_route_table.private_subnet_route_table.id
}

// Déploiement des fichiers YAML de Kubernetes sur le cluster EKS
resource "null_resource" "apply_kubernetes_manifests" {
  depends_on = [aws_eks_cluster.ci-sockshop-eks-cluster, aws_eks_node_group.ci-sockshop-eks-node-group]

  provisioner "local-exec" {
    command = "kubectl apply -f deploy/kubernetes/manifests"
  }
}
