#!/bin/bash
#Need to run this script using sudo

# Install prerequisites
echo "Installing prerequisites..."
sudo tdnf install -y libusb-devel pciutils-devel

# Clone the Git repository
echo "Cloning the Git repository..."
git clone https://github.com/Mellanox/rshim-user-space.git

# Navigate to the repository directory
cd rshim-user-space

# Build the driver (replace with actual build commands)
echo "Building the driver..."
./bootstrap.sh
./configure
make

# Install the driver (replace with actual install commands)
echo "Installing the driver..."
make install

#Updating PATH
echo
PATH=$PATH:/usr/local/sbin

# Update rshim service file
echo
sed -i 's/usr\/sbin/usr\/local\/sbin/g' /etc/systemd/system/rshim.service

# Start rshim service
echo "Starting rshim service..."
systemctl start rshim

echo "Driver installation completed successfully."
