#!/bin/bash
set -xe

# Download kubectl
curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl 
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Download kind
curl -Lo kind https://github.com/kubernetes-sigs/kind/releases/download/v0.4.0/kind-linux-amd64
chmod +x kind 
sudo mv kind /usr/local/bin/

# Create kind cluster
kind create cluster --config kubernetes-storage/cluster/cluster.yaml --wait 300s
export KUBECONFIG="$(kind get kubeconfig-path)"

# Clone CSI driver host path repo
git clone https://github.com/kubernetes-csi/csi-driver-host-path.git

# Okay, lets install it
csi-driver-host-path/deploy/kubernetes-1.15/deploy-hostpath.sh

# create infrastructure
kubectl apply -f kubernetes-storage/hw && sleep 10

# storage-pod should be ready
kubectl wait --for=condition=Ready pod storage-pod -n default --timeout=300s

# storage pvc should present
kubectl get pvc storage-pvc > /dev/null || exit 1

# storage-pod should use our pvc
kubectl describe pod storage-pod | grep storage-pvc > /dev/null || exit 1

# store super important data
kubectl exec storage-pod -- /bin/bash -c "echo kek lol i am eagle > /data/item" || exit 1

MD5FIRST=$(kubectl exec storage-pod -- /bin/bash -c "md5sum /data/item | cut -f 1 -d \" \"")

# let we do a snap now
cat <<EOF | kubectl apply -f -
apiVersion: snapshot.storage.k8s.io/v1alpha1
kind: VolumeSnapshot
metadata:
  name: storage-snapshot
spec:
  snapshotClassName: csi-hostpath-snapclass
  source:
    name: storage-pvc
    kind: PersistentVolumeClaim
EOF

# do a stupid backup of pod
kubectl get pod storage-pod -o yaml --export > backup.yml || exit 1

# now we will delete everything
kubectl delete pod storage-pod || exit 1
kubectl delete pvc storage-pvc || exit 1

# okay, time for black magic!
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: storage-pvc
spec:
  storageClassName: csi-hostpath-sc
  dataSource:
    name: storage-snapshot
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF

# rise and shine
kubectl apply -f backup.yml || exit 1

# storage-pod should be ready
kubectl wait --for=condition=Ready pod storage-pod -n default --timeout=300s

# get it again
MD5SECOND=$(kubectl exec storage-pod -- /bin/bash -c "md5sum /data/item | cut -f 1 -d \" \"")

if [ $MD5FIRST != $MD5SECOND ]; then
  echo "Whooops! Snaphot data not equals original v_v"; exit 1;
fi

exit 0

# Manual approve
# echo "All tests passed. Proceed with manual approve" 
# exit 1

