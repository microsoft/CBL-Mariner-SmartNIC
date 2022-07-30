#  docker build -t bfb_runtime_mariner -f Dockerfile .
FROM --platform=linux/arm64 mcr.microsoft.com/cbl-mariner/base/core:2.0.20220426-arm64
ADD qemu-aarch64-static /usr/bin/

WORKDIR /root/workspace
ADD install.sh .
ADD create_bfb .
ADD setpriv /usr/bin/
ADD rebuild_drivers /tmp

ENV RUN_FW_UPDATER=no

RUN yum install -y dnf-utils sed libtool
RUN yum-config-manager --nogpgcheck --add-repo https://linux.mellanox.com/public/repo/doca/1.3.0/mariner2.0/aarch64/
RUN sed -i -e "s/linux.mellanox.com_public_repo_doca_1.3.0_mariner2.0_aarch64_/doca/" /etc/yum.repos.d/linux.mellanox.com_public_repo_doca_1.3.0_mariner2.0_aarch64_.repo
RUN yum-config-manager --save --setopt=doca.sslverify=0 doca
RUN yum-config-manager --save --setopt=doca.gpgcheck=0 doca
RUN yum-config-manager --dump doca

RUN for app in wget kmod util-linux netplan openssh-server iproute which git selinux-policy-devel diffutils file procps-ng patch rpm-build kernel kernel-devel kernel-headers python-netifaces libreswan python3-devel python3-idle python3-test python3-tkinter python3-Cython efibootmgr efivar grub2 grub2-efi grub2-efi-unsigned shim-unsigned-aarch64 device-mapper-persistent-data lvm2 acpid perf popt-devel bc flex bison edac-utils lm_sensors lm_sensors-sensord re2c ninja-build meson cryptsetup rasdaemon pciutils-devel watchdog python3-sphinx python3-six kexec-tools jq dbus libgomp iana-etc libgomp-devel libgcc-devel libgcc-atomic libmpc binutils iptables glibc-devel gcc tcl-devel automake libmnl autoconf tcl libnl3-devel openssl-devel libstdc++-devel binutils-devel libnl3 libdb-devel make libmnl-devel iptables-devel lsof desktop-file-utils doxygen cmake cmake3 libcap-ng-devel systemd-devel ncurses-devel net-tools sudo libpcap libnuma unbound vim; do yum install -y $app || true ;done

# Set python3.9 as a default
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.9 10
# RUN update-alternatives --install /usr/bin/python python /usr/bin/python2.7 10

RUN /tmp/rebuild_drivers $(/bin/ls -1 /lib/modules/ | head -1)
RUN /usr/sbin/depmod -a $(/bin/ls -1 /lib/modules/ | head -1) || true

RUN yum install -y ibacm ibutils2 infiniband-diags infiniband-diags-compat libibumad libibverbs libibverbs-utils librdmacm librdmacm-utils libxpmem libxpmem-devel mft mft-oem mlnx-ethtool mlnx-fw-updater mlnx-iproute2 mlnx-libsnap mlx-regex mlxbf-bootctl mlxbf-bootimages mstflint ofed-scripts opensm opensm-devel opensm-libs opensm-static perftest rdma-core rdma-core-devel srp_daemon ucx ucx-cma ucx-devel ucx-ib ucx-knem ucx-rdmacm xpmem mlnx-tools mlnx-dpdk mlnx-dpdk-devel dpcp libvma libvma-utils python3-grpcio python3-protobuf rxp-compiler

# RUN wget --no-check-certificate --no-verbose $(repoquery --nogpgcheck --location mlnx-ofa_kernel)
# RUN wget --no-check-certificate --no-verbose $(repoquery --nogpgcheck --location mlnx-ofa_kernel-devel)
# RUN wget --no-check-certificate --no-verbose $(repoquery --nogpgcheck --location mlnx-ofa_kernel-modules)
# RUN wget --no-check-certificate --no-verbose $(repoquery --nogpgcheck --location mlnx-ofa_kernel-source)
# RUN rpm -iv --nodeps mlnx-ofa_kernel*rpm

RUN wget --no-check-certificate --no-verbose $(repoquery --nogpgcheck --location libreswan)
RUN rpm -Uv --nodeps *libreswan*rpm
RUN wget --no-check-certificate --no-verbose $(repoquery --nogpgcheck --location openvswitch)
RUN wget --no-check-certificate --no-verbose $(repoquery --nogpgcheck --location openvswitch-devel)
RUN wget --no-check-certificate --no-verbose $(repoquery --nogpgcheck --location python3-openvswitch)
RUN wget --no-check-certificate --no-verbose $(repoquery --nogpgcheck --location openvswitch-ipsec)
RUN rpm -Uv --nodeps *openvswitch*rpm

RUN wget --no-check-certificate --no-verbose $(repoquery --nogpgcheck --location mlxbf-bfscripts)
RUN rpm -iv --nodeps mlxbf-bfscripts*rpm

RUN wget --no-check-certificate --no-verbose $(repoquery --nogpgcheck --location bf-release)
RUN rpm -iv --nodeps bf-release*rpm

RUN /bin/rm -f *rpm

CMD  /root/workspace/create_bfb -k $(/bin/ls -1 /lib/modules/ | head -1)
