#/bin/bash! 

sudo apt-get update 
sudo apt-get install 


# apt가 HTTPS로 리포지터리를 사용하는 것을 허용하기 위한 패키지 설치
sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common gnupg2

# 도커 공식 GPG 키 추가:
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key --keyring /etc/apt/trusted.gpg.d/docker.gpg add -

# 도커 apt 리포지터리 추가:
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

# 도커 CE 설치
sudo apt-get update && sudo apt-get install -y containerd.io=1.2.13-2 docker-ce=5:19.03.11~3-0~ubuntu-$(lsb_release -cs) docker-ce-cli=5:19.03.11~3-0~ubuntu-$(lsb_release -cs)

## /etc/docker 생성
sudo mkdir /etc/docker

# 도커 데몬 설정
cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

# /etc/systemd/system/docker.service.d 생성
sudo mkdir -p /etc/systemd/system/docker.service.d

# 도커 재시작 & 부팅시 실행 설정 (systemd)
sudo systemctl daemon-reload
sudo systemctl restart docker
sudo systemctl enable docker

## 
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
br_netfilter
EOF

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sudo sysctl --system

##

sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl
sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl




# hostname 변경

region=`curl http://169.254.169.254/latest/meta-data/placement/region`
hostname_ip=`curl http://169.254.169.254/latest/meta-data/local-hostname`
ip=`curl http://169.254.169.254/latest/meta-data/local-ipv4`
sudo hostnamectl set-hostname "$hostname_ip.$region.compute.internal"

kube_version=`kubelet --version | awk '{print $2}'`

cat > /tmp/config.yml <<EOF
apiVersion: kubeadm.k8s.io/v1beta2
kind: InitConfiguration
nodeRegistration:
  kubeletExtraArgs:
    cloud-provider: "aws"
---
apiVersion: kubeadm.k8s.io/v1beta2
kind: ClusterConfiguration
kubernetesVersion: $kube_version
apiServer:
  extraArgs:
    cloud-provider: "aws"
controllerManager:
  extraArgs:
    cloud-provider: "aws"
EOF


sudo kubeadm init --config /tmp/config.yml | tee /tmp/output


mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

weave_count=0
while [ $weave_count -eq 0 ];
do
weave_count=`kubectl get pod -n kube-system | grep weave | wc -l`
  if [ $weave_count -eq 0 ] ; then
        kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')"
  fi
done


hash=`cat /tmp/output | grep sha256 | awk '{print $2}'`
token=`cat /tmp/output | grep 'kubeadm join' | awk '{print $5}'`

cat > /tmp/join.yml <<EOF
apiVersion: kubeadm.k8s.io/v1beta2
kind: JoinConfiguration
discovery:
  bootstrapToken:
    token: $token # 위 마스터 노드에서 발급 받은 토큰 
    apiServerEndpoint: "$ip:6443"
    caCertHashes: # 위 마스터 노드에서 발급 받은 해쉬 값 
      - "$hash"
nodeRegistration:
  name:  test # 노드 Private dns address
  kubeletExtraArgs:
    cloud-provider: aws
EOF

