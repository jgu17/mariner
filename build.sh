#!/bin/bash
set -ex

kubectl -f ./vm.yaml delete || true
kubectl delete pvc mariner-vm-disk || true

toolkit_image="quay.io/port/mariner-toolkit"
builder_image="quay.io/port/mariner-builder"
docker build -t "${toolkit_image}" -f ./Dockerfile.toolkit --target "CBL-Mariner-tools" .
toolkit_dir="$(mktemp -d)"
docker run -it --rm --privileged --volume "${toolkit_dir}:/CBL-Mariner/out:rw" "${toolkit_image}"
ls -lah ${toolkit_dir}
mv -v ${toolkit_dir}/toolkit-*.tar.gz ./toolkit.tar.gz


docker build -t "${builder_image}" -f ./Dockerfile.toolkit --target "CBL-Mariner-builder" .
image_work_dir="$(mktemp -d)"
image_dir="$(mktemp -d)"
docker run --rm --privileged --volume "${image_work_dir}:/opt/mariner/build:rw" --volume "${image_dir}:/opt/mariner/out:rw" -v /dev:/dev:rw "${builder_image}"
ls -lah ${image_dir}
ls -lah ${image_dir}/images/demo_vhd


sudo qemu-img convert -f vpc -O qcow2 \
    "$(ls ${image_dir}/images/demo_vhd/*.vhd | head -1 )" \
    "${image_dir}/images/demo_vhd/kubevirt.qcow"

# kubectl port-forward -n cdi service/cdi-uploadproxy 8443:443 &
# sleep 2
kubectl virt image-upload --pvc-name=mariner-vm-disk --pvc-size=64Gi --storage-class=rook-ceph-ec-block --image-path="${image_dir}/images/demo_vhd/kubevirt.qcow" --uploadproxy-url=https://127.0.0.1:8443 --insecure

kubectl -f ./vm.yaml apply
kubectl -f ./vm.yaml describe

