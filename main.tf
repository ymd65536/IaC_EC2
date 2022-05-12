terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.21.0"
    }
  }
}

variable "aws_region" {
  default = "ap-northeast-1"
}
variable "aws_profile" {
  default = "User"
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

## VPC領域の作成
resource "aws_vpc" "JupyterVpc" {
  cidr_block           = "10.0.0.0/24"
  instance_tenancy     = "default"
  enable_dns_support   = "true"
  enable_dns_hostnames = "true"
  tags = {
    Name = "JupyterNoteBook"
  }
}

## パブリックサブネットの作成
resource "aws_subnet" "PublicSubnetJupyter" {
  vpc_id            = aws_vpc.JupyterVpc.id
  cidr_block        = "10.0.0.0/26"
  availability_zone = "ap-northeast-1a"

  tags = {
    Name = "PublicSubnetJupyter"
  }
}

## インターネットゲートウェイの設定
resource "aws_internet_gateway" "IGW" {
  vpc_id = aws_vpc.JupyterVpc.id
}

##ルートテーブルの追加(0.0.0.0/0)
resource "aws_route_table" "PublicRoute" {
  vpc_id = aws_vpc.JupyterVpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.IGW.id
  }
}

##ルートテーブルの追加(1a)
resource "aws_route_table_association" "PublicRouteJupyter" {
  subnet_id      = aws_subnet.PublicSubnetJupyter.id
  route_table_id = aws_route_table.PublicRoute.id
}

## Jupter用セキュリティグループの設定
resource "aws_security_group" "JupyterSec" {
  name        = "JupyterWeb"
  description = "JupyterEnv"
  vpc_id      = aws_vpc.JupyterVpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "PublicSecJupyter"
  }
}

## AMIを自動で取得
data "aws_ssm_parameter" "amzn2_ami" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

resource "aws_instance" "JupyterInstance" {
  ami               = data.aws_ssm_parameter.amzn2_ami.value
  instance_type     = "t2.micro"
  availability_zone = "ap-northeast-1a"
  key_name          = aws_key_pair.key_pair.id
  private_ip        = "10.0.0.10"

  disable_api_termination = false
  vpc_security_group_ids  = [aws_security_group.JupyterSec.id]
  subnet_id               = aws_subnet.PublicSubnetJupyter.id

  root_block_device {
    volume_type = "gp2"
    volume_size = 8
  }

  tags = {
    Name = "JupyterServer"
  }
}

resource "aws_eip" "JupyterInstanceIP" {
  instance = aws_instance.JupyterInstance.id
  vpc      = true
}

## EC2 key pairの作成
variable "key_name" {
  description = "keypair name"
  default     = "JupyterInstance"
}

## キーファイル
## 生成場所のPATH指定をしたければ、ここを変更するとよい。
locals {
  public_key_file  = "./.ssh/id_rsa.pub"
  private_key_file = "./.ssh/id_rsa"
}

## キーペアを作る
resource "tls_private_key" "keygen" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

## 秘密鍵ファイルを作る
resource "local_file" "private_key_pem" {
  filename        = local.private_key_file
  content         = tls_private_key.keygen.private_key_pem
  file_permission = "0600"
}

## sshのキー設定
resource "local_file" "public_key_openssh" {
  filename        = local.public_key_file
  content         = tls_private_key.keygen.public_key_openssh
  file_permission = "0600"
}

## キー名
output "key_name" {
  value = var.key_name
}

## 秘密鍵ファイルPATH（このファイルを利用してサーバへアクセスする。）
output "private_key_file" {
  value = local.private_key_file
}

## 秘密鍵内容
output "private_key_pem" {
  value     = tls_private_key.keygen.private_key_pem
  sensitive = true
}

## 公開鍵ファイルPATH
output "public_key_file" {
  value = local.public_key_file
}

## 公開鍵内容（サーバの~/.ssh/authorized_keysに登録して利用する。）
output "public_key_openssh" {
  value = tls_private_key.keygen.public_key_openssh
}

## EC2にキーペアを登録
resource "aws_key_pair" "key_pair" {
  key_name   = var.key_name
  public_key = tls_private_key.keygen.public_key_openssh
}