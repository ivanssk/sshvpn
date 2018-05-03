export tpip=118.163.124.43
export homeip=220.132.209.119

function vpn()
{
	if [ $1 = "on" ]
	then
		if [ "$(sudo file /tmp/sshvpn | awk '{print $2}')" = socket ]; then
			echo vpn status is on
			return;
		fi

		serverIP=$2

		if [ "$serverIP" = "" ]; then
			PS3='Please enter your choice: '
			options=("$tpip" "192.168.0.50" "$homeip" "Quit")
			select opt in "${options[@]}"
			do
				case $opt in
					"$tpip" | "192.168.0.50")
						serverIP=$opt
						serverPort=22
						break;
						;;
					"$homeip")
						serverIP=$opt
						serverPort=80
						break;
						;;
					"Quit")
						echo "Bye"
						return
						;;
					*) echo invalid option;;
				esac
			done
		fi

		echo vpn connecting...

		default_gateway=`route -n get default | grep gateway | awk '{print \$2}'`
		inf=$(route -n get default | awk '/interface: /{print $2}')

		IFS=$'\n'

		for i in $(networksetup -listallhardwareports)
		do
			if [[ $i =~ ^Hardware ]]; then
				hardwareport=${i##*Hardware Port: }
			elif [[ $i =~ ^Device ]]; then
				device=${i##*Device: }

				if [ $device == $inf ]; then
					defaultdns=$(networksetup -getdnsservers "$hardwareport" | awk 1 ORS=' ')
					break
				fi
			fi
		done

		cat << EOF > /tmp/setupVPNRoute.sh

		for i in $defaultdns
		do
			if [ \$i != $default_gateway ]; then
				route add \$i $default_gateway
			fi
		done

		networksetup -setdnsservers "$hardwareport" 8.8.8.8 $defaultdns

		ifconfig tap0 20.0.0.2 netmask 255.255.255.0 broadcast 20.0.0.255
		route add $serverIP $default_gateway
		route change default 20.0.0.1

		echo VPN connected
EOF

		chmod a+x /tmp/setupVPNRoute.sh

		cat << EOF > /tmp/turn-VPN-on.sh
		ssh -o Tunnel=ethernet -w 0:0 -o Compression=yes -o CompressionLevel=6 -o ControlMaster=auto -o ControlPath=/tmp/sshvpn -o PermitLocalCommand=yes -o LocalCommand=/tmp/setupVPNRoute.sh $serverIP -p $serverPort "ifconfig tap0 20.0.0.1 netmask 255.255.255.0 up; iptables -t nat -A POSTROUTING -s 20.0.0.0/24 -o eth0 -j MASQUERADE"

		for i in $defaultdns
		do
			if [ \$i != $default_gateway ]; then
				route delete \$i
			fi
		done

		route delete $serverIP
		route add default $default_gateway
		networksetup -setdnsservers "$hardwareport" $defaultdns

		echo "VPN disconnected"
EOF

		cat << EOF > /tmp/turn-VPN-off.sh
		ssh -o ControlMaster=auto -o ControlPath=/tmp/sshvpn $serverIP iptables -t nat -D POSTROUTING -s 20.0.0.0/24 -o eth0 -j MASQUERADE
		ssh -o ControlMaster=auto -o ControlPath=/tmp/sshvpn -O exit $serverIP
EOF

		chmod a+x /tmp/turn-VPN-on.sh
		chmod a+x /tmp/turn-VPN-off.sh

		sudo sh /tmp/turn-VPN-on.sh &

	elif [ $1 = "off" ]
	then
		sudo /tmp/turn-VPN-off.sh
	elif [ $1 = "status" ]
	then
		if [ "$(sudo file /tmp/sshvpn | awk '{print $2}')" = socket ]; then
			echo vpn status is on
		else
			echo vpn status is off
		fi
	fi;
}
