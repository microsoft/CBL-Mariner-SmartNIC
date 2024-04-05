# Installing rshim Interface in Azure Linux host 

Rshim driver provides an interface where the a Linux host can access Bluefield resources.
Rshim do not build nativelly in Azure Linux host, there are some prerequisites to be installed and update to $PATH.
Rshim provides bfb-install and rshim tools.

## Prerequisites
Get an Azure Linux host with a Bluefield 2/3 connected via PCIE.
Verify the card is connected via:
    ```bash
    lspci | grep Mellanox
    `````

## Steps

3. Install the required dependencies:
    ```bash
    sudo tdnf install pciutils-devel
    sudo tdnf install lubusb-devel
    `````

4. Download the rshim interface source code:
    ```bash
    git clone git@github.com:Mellanox/rshim-user-space.git
    ```

5. Change to the rshim directory:
    ```bash
    cd rshim
    ```

6. Configure the rshim interface:
    ```bash
    ./bootstrap
    sudo ./configure  --with-systemdsystemunitdir=/usr/lib/systemd/system
    ```

6. Build the rshim interface:
    ```bash
    sudo make
    ```

7. Install the rshim interface:
    ```bash
    sudo install
    ```

9. Update $PATH
    ```bash
    PATH=$PATH:/usr/local/sbin
    ```

9. Update rshim.service to search for the bin at /usr/local/sbin (need to simplify)
    ```bash
    vi /etc/systemd/system/rshim.service
    ```

9. Restart service 
    ```bash
    sudo systemctl start rshim
    ```

8. Verify the installation:
    ```bash
    rshim --version
    ```

    You should see the version information of the rshim interface if the installation was successful.

Congratulations! You have successfully installed the rshim interface in your Azure Linux host.
