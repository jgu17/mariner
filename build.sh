#!/bin/bash
set -ex

kubectl -f ./vm.yaml delete || true
# kubectl delete pvc mariner-vm-disk || true

toolkit_image="quay.io/port/mariner-toolkit"
builder_image="quay.io/port/mariner-builder"
kubevirt_image="quay.io/port/mariner-kubevirt"
docker build -t "${toolkit_image}" -f ./Dockerfile.toolkit --target "CBL-Mariner-tools" .
toolkit_dir="$(mktemp -d)"
docker run -it --rm --privileged --volume "${toolkit_dir}:/CBL-Mariner/out:rw" "${toolkit_image}"
ls -lah ${toolkit_dir}
mv -v ${toolkit_dir}/toolkit-*.tar.gz ./toolkit.tar.gz


docker build -t "${builder_image}" -f ./Dockerfile.toolkit --target "CBL-Mariner-builder" .
image_work_dir="$(mktemp -d)"
image_dir="$(mktemp -d)"
image_target="demo_vhd"
docker run -it --rm --privileged --volume "${image_work_dir}:/opt/mariner/build:rw" --volume "${image_dir}:/opt/mariner/out:rw" -v /dev:/dev:rw -e "image_target=${image_target}" "${builder_image}"

ls -lah "${image_dir}/images/${image_target}"
if [ -f ${image_dir}/images/${image_target}/*.tar.gz ]; then
    echo "filesystem tar found"
    docker import ${image_dir}/images/${image_target}/*.tar.gz quay.io/port/mariner-distroless
    echo "docker run -it --rm quay.io/port/mariner-distroless"
elif [ -f ${image_dir}/images/${image_target}/*.vhd ]; then
    echo "vm imagefound"
    sudo qemu-img convert -f vpc -O qcow2 \
    "$(ls ${image_dir}/images/${image_target}/*.vhd | head -1 )" \
    "${image_dir}/images/${image_target}/kubevirt.qcow"

    kubectl -f ./vm.yaml delete || true
    # kubectl delete pvc mariner-vm-disk || true

    # kubectl port-forward -n cdi service/cdi-uploadproxy 8443:443 &
    # sleep 2
    # kubectl virt image-upload --pvc-name=mariner-vm-disk --pvc-size=64Gi --storage-class=rook-ceph-ec-block --image-path="${image_dir}/images/${image_target}/kubevirt.qcow" --uploadproxy-url=https://127.0.0.1:8443 --insecure

    image_work_dir="$(mktemp -d)"
    sudo qemu-nbd --connect=/dev/nbd0 ${image_dir}/images/${image_target}/kubevirt.qcow
    sudo fdisk /dev/nbd0 -l
    sudo mount /dev/nbd0p2 ${image_work_dir}

    sudo sh -c "ls -lah ${image_work_dir}/boot/initrd.img-*.cm1"
    sudo sh -c "ls -lah ${image_work_dir}/boot/vmlinuz-*.cm1"

    image_build_dir="$(mktemp -d)"
    cp -v ${image_dir}/images/${image_target}/kubevirt.qcow ${image_build_dir}/mariner.img
    sudo sh -cx "cp -v ${image_work_dir}/boot/initrd.img-*.cm1 ${image_build_dir}/initrd"
    sudo sh -cx "cp -v ${image_work_dir}/boot/vmlinuz-*.cm1 ${image_build_dir}/vmlinuz"


    sudo docker build -t "${kubevirt_image}" -f ./Dockerfile.kubevirt  ${image_build_dir}
    docker push quay.io/port/mariner-kubevirt:latest

    sudo umount ${image_work_dir}

    sudo rm -rfv  ${image_build_dir} ${image_work_dir}

    sudo qemu-nbd --disconnect /dev/nbd0

    kubectl -f ./vm.yaml apply
    kubectl -f ./vm.yaml describe

    tee /dev/stdout <<'EOF'
kubectl virt console $(kubectl get vmi -l kubevirt.io/vm=vm-mariner -o name | awk -F '/' '{ print $NF }')
EOF

fi

