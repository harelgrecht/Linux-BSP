# Usage: ./reset_interface.sh eth0
interfaceName=$1

if [ -z "$interfaceName" ]; then
    echo "Please provide an interface name."
    exit 1
fi

echo "Resetting $interfaceName..."

# 1. Stop the DHCP client (adjust based on if you use udhcpc or dhcpcd)
sudo killall udhcpc 2>/dev/null

# 2. Flush addresses and routes
sudo ip addr flush dev $interfaceName
sudo ip route flush dev $interfaceName

# 3. Reset the interface link state
sudo ip link set $interfaceName down
sudo ip link set $interfaceName up

echo "Interface $interfaceName has been flushed."
