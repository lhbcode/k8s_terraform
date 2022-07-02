# k8s_terraform

Ansible + Terraform 혼합 버전 입니다. 

EC2 기반의 K8s Cluster가 생성 됩니다. 

생성되는 terraform-state 파일은 DynamoDB에 저장 됩니다.

각각의 AWS 리소스 단위별(디렉토리)로 구분 했습니다

1. init.tf를 먼저 구성 합니다.

2. AWS 인프라 생성 흐름에 따라 테라폼을 구성 합니다.

