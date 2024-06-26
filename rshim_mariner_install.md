# Installing rshim Interface in Azure Linux host 

Rshim driver provides an interface where the a Linux host can access Bluefield resources.
Rshim do not build nativelly in Azure Linux host, there are some prerequisites to be installed and update to $PATH.
Rshim provides bfb-install and rshim tools.

## Prerequisites

Get an Azure Linux host with a Bluefield 2/3 connected via PCIE.
Verify the card is connected via

    lspci | grep Mell

    
## Steps

1. Install the required dependencies:
    ```bash
    tdnf install pciutils-devel lubusb-devel
    ```

2. Download the rshim interface source code:
    ```bash
    git clone git@github.com:Mellanox/rshim-user-space.git
    ```

3. Change to the rshim directory:
    ```bash
    cd rshim-user-space
    ```

4. Configure the rshim interface:
    ```bash
    ./bootstrap.sh
    ./configure
    ```

5. Build the rshim interface:
    ```bash
    sudo make
    ```

6. Install the rshim interface:
    ```bash
    sudo install
    ```

7. Update $PATH
    ```bash
    PATH=$PATH:/usr/local/sbin
    ```

8. Update rshim.service
    ```bash
    sed -i 's/usr\/sbin/usr\/local\/sbin/g' /etc/systemd/system/rshim.service
    ```

9. Restart service 
    ```bash
    sudo systemctl start rshim
    ```

10. Verify the installation:
    ```bash
    rshim --version
    ```

    You should see the version information of the rshim interface if the installation was successful.

Congratulations! You have successfully installed the rshim interface in your Azure Linux host.
