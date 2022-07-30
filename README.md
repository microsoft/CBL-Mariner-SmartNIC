This is a combination of the following repos

CBL-Mariner https://github.com/microsoft/CBL-Mariner/ 
Mellanox/bfb-mariner https://github.com/Mellanox/bfb-mariner

## Build BFB

`$ sudo ./bfb-build`

You may need to run the following to configure qemu
`docker run --rm --privileged multiarch/qemu-user-static --reset -p yes`

## Flash BFB 

On the linux machine connected via USB to the bf2, 
If you do not have RSHIM installed:
 RSHIM package is available under: https://developer.nvidia.com/networking/doca
 https://www.mellanox.com/downloads/BlueField/RSHIM/rshim_2.0.6-3.ge329c69_amd64.deb


Deploy the image to BF2 device via the rshim interface (assuming rshim0).

`$ sudo bfb-install -r rshim0 -b your-bfb`

You can watch the process using a serial monitor like minicom on port /dev/rshim0/console

`$ sudo minicom`

Configure the Linux rshim network interface static IP address to 192.168.100.3/24 (basically 192.168.100.x).
The BF2 device is set to static IP 192.168.100.2.
If you are not using the BF2 management network interface, but rather the rshim network interface, you will need to configure your Linux machine as a gateway/router, so the device can use it for internet access.

Make sure ipv4 forward is enabled
 ```
 $ cat /proc/sys/net/ipv4/ip_forward
 1
 ```

NAT (MASQUERADE) is enabled on the external network interface, in this example eno1:
`$ sudo iptables -t nat -A POSTROUTING -o eno1 -j MASQUERADE`

Once the bfb is flashed, log in using minicom and the credentials 
user: mariner
pw: mariner

Some network configuration may be needed. Make the following changes:

```
$ sudo cat > /etc/resolv.conf << EOF
nameserver 127.0.0.53
EOF
```
```
$ sudo cat >  /etc/netplan/60-mlnx.yaml << EOF
network:
    ethernets:
        oob_net0:
            renderer: networkd
            dhcp4: true
        tmfifo_net0:
            renderer: networkd
            addresses:
            - 192.168.100.2/24
            dhcp4: false
            gateway4: 192.168.100.3
            nameservers:
               addresses: [10.50.10.50, 10.50.50.50]
               search: [corp.microsoft.com]
        enp3s0f0s0:
            renderer: networkd
            dhcp4: true
        enp3s0f1s0:
            renderer: networkd
            dhcp4: true
    version: 2
EOF
```
`$ sudo netplan apply`

Now you should be able to ssh using the rshim device
`$ ssh mariner@192.168.100.2`
