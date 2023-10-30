#  docker build -t bfb_runtime_mariner -f Dockerfile .
FROM --platform=linux/arm64 mcr.microsoft.com/cbl-mariner/base/core:2.0.20231004-arm64
ADD qemu-aarch64-static /usr/bin/

WORKDIR /root/workspace
ADD install.sh .
ADD create_bfb .
ADD rebuild_drivers /tmp

ENV RUN_FW_UPDATER=no

RUN yum install -y dnf-utils sed libtool
RUN yum-config-manager --nogpgcheck --add-repo https://linux.mellanox.com/public/repo/doca/2.2.0/mariner2.0/aarch64/
RUN sed -i -e "s/linux.mellanox.com_public_repo_doca_2.2.0_mariner2.0_aarch64_/doca/" /etc/yum.repos.d/linux.mellanox.com_public_repo_doca_2.2.0_mariner2.0_aarch64_.repo
RUN yum-config-manager --save --setopt=doca.sslverify=0 doca
RUN yum-config-manager --save --setopt=doca.gpgcheck=0 doca
RUN yum-config-manager --dump doca

RUN yum install -y wget kmod util-linux sudo net-utils netplan hostname openssh-server iproute which git selinux-policy-devel diffutils file procps-ng patch rpm-build kernel kernel-devel kernel-headers python3 python3-devel python3-libs python3-test python3-pyelftools efibootmgr efivar grub2 grub2-efi grub2-efi-unsigned shim-unsigned-aarch64 lvm2 popt-devel bc flex bison lm_sensors ninja-build meson cryptsetup pciutils-devel python3-sphinx python3-six kexec-tools jq dbus libgomp iana-etc libgomp-devel libgcc-devel libgcc-atomic libmpc binutils libsepol-devel iptables glibc-devel gcc tcl-devel automake libmnl autoconf tcl libnl3-devel openssl-devel libstdc++-devel binutils-devel libselinux-devel libnl3 libdb-devel make libmnl-devel iptables-devel lsof glibc numactl-devel ncurses-devel systemd-devel groff libgudev libgudev-devel lsb-release popt-devel pkg-config python3-twisted libpcap unbound python3-zope-interface graphviz less iputils tcpdump sysstat qemu-kvm libvirt libguestfs-tools libreswan ipmitool nvme-cli coreutils rsyslog

# Set python3.9 as a default
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.9 10

RUN /tmp/rebuild_drivers $(/bin/ls -1 /lib/modules/ | head -1)
RUN /usr/sbin/depmod -a $(/bin/ls -1 /lib/modules/ | head -1) || true

RUN yum install -y ibacm ibutils2 infiniband-diags infiniband-diags-compat libibumad libibverbs libibverbs-utils librdmacm librdmacm-utils libxpmem libxpmem-devel mft mft-oem mlnx-ethtool mlnx-fw-updater mlnx-iproute2 mlnx-libsnap mlx-regex mlxbf-bootctl mlxbf-bootimages mstflint ofed-scripts opensm opensm-devel opensm-libs opensm-static perftest rdma-core rdma-core-devel srp_daemon ucx ucx-cma ucx-devel ucx-ib ucx-knem ucx-rdmacm xpmem mlnx-tools mlnx-dpdk mlnx-dpdk-devel dpcp libvma libvma-utils python3-grpcio python3-protobuf rxp-compiler openvswitch openvswitch-devel python3-openvswitch openvswitch-ipsec mlxbf-bfscripts bf-release

RUN /bin/rm -f *rpm

CMD  /root/workspace/create_bfb -k $(/bin/ls -1 /lib/modules/ | head -1)
