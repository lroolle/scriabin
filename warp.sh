#!/usr/bin/env bash

version='0.0.3'

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "[INFO] Installing jq..."
    if command -v apt &> /dev/null; then
        apt update && apt install -y jq
    elif command -v yum &> /dev/null; then
        yum install -y jq
    else
        echo "[ERROR] Package manager not supported. Please install jq manually."
        exit 1
    fi
fi

# Add default Tailscale IP ranges near the top of the file with other variables
WireGuard_Interface='wgcf'
WireGuard_ConfPath="/etc/wireguard/${WireGuard_Interface}.conf"

# Add Tailscale default ranges
Tailscale_IPv4_Range='100.64.0.0/10'
Tailscale_IPv6_Range='fd7a:115c:a1e0::/48'

Register_Teams_Account() {
    if [[ ${teams_mode} -eq 1 ]]; then
        log INFO "Registering Teams account..."
        wg_private_key="$(wg genkey)"
        wg_public_key="$(printf %s "${wg_private_key}" | wg pubkey)"
        reg="$(curl -s --header 'User-Agent: okhttp/3.12.1' \
            --header 'CF-Client-Version: a-6.16-2483' \
            --header 'Accept: application/json; charset=UTF-8' \
            --header 'Content-Type: application/json' \
            --header "CF-Access-Jwt-Assertion: ${teams_ephemeral_token}" \
            --request "POST" \
            --data '{"key":"'"${wg_public_key}"'","install_id":"","fcm_token":"","model":"","serial_number":"","locale":"en_US"}' \
            'https://api.cloudflareclient.com/v0a2483/reg')"

        if [ $? -ne 0 ] || [ -z "${reg}" ]; then
            log ERROR "Failed to register Teams account"
            exit 1
        fi

        # Extract required values from registration response
        wg_addresses_v4=$(echo "${reg}" | jq -r '.config.interface.addresses.v4')
        wg_addresses_v6=$(echo "${reg}" | jq -r '.config.interface.addresses.v6')
        wg_peer_pubkey=$(echo "${reg}" | jq -r '.config.peers[0].public_key')

        if [ "${wg_addresses_v4}" = "null" ] || [ "${wg_addresses_v6}" = "null" ] || [ "${wg_peer_pubkey}" = "null" ]; then
            log ERROR "Invalid registration response from Cloudflare"
            exit 1
        fi

        mkdir -p "${WGCF_ProfileDir}"

        # Create WGCF profile with Teams info
        cat >"${WGCF_ProfilePath}" <<-EOF
[Interface]
PrivateKey = ${wg_private_key}
Address = ${wg_addresses_v4}, ${wg_addresses_v6}
DNS = 1.1.1.1, 1.0.0.1, 2606:4700:4700::1111, 2606:4700:4700::1001

[Peer]
PublicKey = ${wg_peer_pubkey}
Endpoint = ${WireGuard_Peer_Endpoint_IPv4}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF
    fi
}

Generate_WGCF_Profile() {
    if [[ ${teams_mode} -eq 1 ]]; then
        Register_Teams_Account
    else
        while [[ ! -f ${WGCF_Profile} ]]; do
            Register_WARP_Account
            log INFO "WARP WireGuard profile (wgcf-profile.conf) generation in progress..."
            wgcf generate
        done
        Uninstall_wgcf
    fi
}

CF_Trace_URL='https://www.cloudflare.com/cdn-cgi/trace'
TestIPv4_1='1.1.1.1'
TestIPv4_2='1.0.0.1'
TestIPv6_1='2606:4700:4700::1111'
TestIPv6_2='2606:4700:4700::1001'

FontColor_Red="\033[31m"
FontColor_Red_Bold="\033[1;31m"
FontColor_Green="\033[32m"
FontColor_Green_Bold="\033[1;32m"
FontColor_Yellow="\033[33m"
FontColor_Yellow_Bold="\033[1;33m"
FontColor_Purple="\033[35m"
FontColor_Purple_Bold="\033[1;35m"
FontColor_Suffix="\033[0m"

# Initialize teams variables
teams_ephemeral_token=""
teams_mode=0

log() {
    local LEVEL="$1"
    local MSG="$2"
    case "${LEVEL}" in
    INFO)
        local LEVEL="[${FontColor_Green}${LEVEL}${FontColor_Suffix}]"
        local MSG="${LEVEL} ${MSG}"
        ;;
    WARN)
        local LEVEL="[${FontColor_Yellow}${LEVEL}${FontColor_Suffix}]"
        local MSG="${LEVEL} ${MSG}"
        ;;
    ERROR)
        local LEVEL="[${FontColor_Red}${LEVEL}${FontColor_Suffix}]"
        local MSG="${LEVEL} ${MSG}"
        ;;
    *) ;;
    esac
    echo -e "${MSG}"
}

if [[ $(uname -s) != Linux ]]; then
    log ERROR "This operating system is not supported."
    exit 1
fi

if [[ $(id -u) != 0 ]]; then
    log ERROR "This script must be run as root."
    exit 1
fi

if [[ -z $(command -v curl) ]]; then
    log ERROR "cURL is not installed."
    exit 1
fi

WGCF_Profile='wgcf-profile.conf'
WGCF_ProfileDir="/etc/warp"
WGCF_ProfilePath="${WGCF_ProfileDir}/${WGCF_Profile}"

WireGuard_Interface='wgcf'
WireGuard_ConfPath="/etc/wireguard/${WireGuard_Interface}.conf"

WireGuard_Interface_DNS_IPv4='8.8.8.8,8.8.4.4'
WireGuard_Interface_DNS_IPv6='2001:4860:4860::8888,2001:4860:4860::8844'
WireGuard_Interface_DNS_46="${WireGuard_Interface_DNS_IPv4},${WireGuard_Interface_DNS_IPv6}"
WireGuard_Interface_DNS_64="${WireGuard_Interface_DNS_IPv6},${WireGuard_Interface_DNS_IPv4}"
WireGuard_Interface_Rule_table='51888'
WireGuard_Interface_Rule_fwmark='51888'
WireGuard_Interface_MTU='1280'

WireGuard_Peer_Endpoint_IP4='162.159.192.1'
WireGuard_Peer_Endpoint_IP6='2606:4700:d0::a29f:c001'
WireGuard_Peer_Endpoint_IPv4="${WireGuard_Peer_Endpoint_IP4}:2408"
WireGuard_Peer_Endpoint_IPv6="[${WireGuard_Peer_Endpoint_IP6}]:2408"
WireGuard_Peer_Endpoint_Domain='engage.cloudflareclient.com:2408'
WireGuard_Peer_AllowedIPs_IPv4='0.0.0.0/0'
WireGuard_Peer_AllowedIPs_IPv6='::/0'
WireGuard_Peer_AllowedIPs_DualStack='0.0.0.0/0,::/0'

TestIPv4_1='1.0.0.1'
TestIPv4_2='9.9.9.9'
TestIPv6_1='2606:4700:4700::1001'
TestIPv6_2='2620:fe::fe'
CF_Trace_URL='https://www.cloudflare.com/cdn-cgi/trace'

Get_System_Info() {
    source /etc/os-release
    SysInfo_OS_CodeName="${VERSION_CODENAME}"
    SysInfo_OS_Name_lowercase="${ID}"
    SysInfo_OS_Name_Full="${PRETTY_NAME}"
    SysInfo_RelatedOS="${ID_LIKE}"
    SysInfo_Kernel="$(uname -r)"
    SysInfo_Kernel_Ver_major="$(uname -r | awk -F . '{print $1}')"
    SysInfo_Kernel_Ver_minor="$(uname -r | awk -F . '{print $2}')"
    SysInfo_Arch="$(uname -m)"
    SysInfo_Virt="$(systemd-detect-virt)"
    case ${SysInfo_RelatedOS} in
    *fedora* | *rhel*)
        SysInfo_OS_Ver_major="$(rpm -E '%{rhel}')"
        ;;
    *)
        SysInfo_OS_Ver_major="$(echo ${VERSION_ID} | cut -d. -f1)"
        ;;
    esac
}

Print_System_Info() {
    echo -e "
System Information
---------------------------------------------------
  Operating System: ${SysInfo_OS_Name_Full}
      Linux Kernel: ${SysInfo_Kernel}
      Architecture: ${SysInfo_Arch}
    Virtualization: ${SysInfo_Virt}
---------------------------------------------------
"
}

Install_Requirements_Debian() {
    if [[ ! $(command -v gpg) ]]; then
        apt update
        apt install gnupg -y
    fi
    if [[ ! $(apt list 2>/dev/null | grep apt-transport-https | grep installed) ]]; then
        apt update
        apt install apt-transport-https -y
    fi
}

Install_WARP_Client_Debian() {
    if [[ ${SysInfo_OS_Name_lowercase} = ubuntu ]]; then
        case ${SysInfo_OS_CodeName} in
        bionic | focal | jammy) ;;
        *)
            log ERROR "This operating system is not supported."
            exit 1
            ;;
        esac
    elif [[ ${SysInfo_OS_Name_lowercase} = debian ]]; then
        case ${SysInfo_OS_CodeName} in
        bookworm | buster | bullseye) ;;
        *)
            log ERROR "This operating system is not supported."
            exit 1
            ;;
        esac
    fi
    Install_Requirements_Debian
    curl https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ ${SysInfo_OS_CodeName} main" | tee /etc/apt/sources.list.d/cloudflare-client.list
    apt update
    apt install cloudflare-warp -y
}

Install_WARP_Client_CentOS() {
    if [[ ${SysInfo_OS_Ver_major} = 8 ]]; then
        rpm -ivh http://pkg.cloudflareclient.com/cloudflare-release-el8.rpm
        yum install cloudflare-warp -y
    else
        log ERROR "This operating system is not supported."
        exit 1
    fi
}

Check_WARP_Client() {
    WARP_Client_Status=$(systemctl is-active warp-svc)
    WARP_Client_SelfStart=$(systemctl is-enabled warp-svc 2>/dev/null)
}

Install_WARP_Client() {
    Print_System_Info
    log INFO "Installing Cloudflare WARP Client..."
    if [[ ${SysInfo_Arch} != x86_64 ]]; then
        log ERROR "This CPU architecture is not supported: ${SysInfo_Arch}"
        exit 1
    fi
    case ${SysInfo_OS_Name_lowercase} in
    *debian* | *ubuntu*)
        Install_WARP_Client_Debian
        ;;
    *centos* | *rhel*)
        Install_WARP_Client_CentOS
        ;;
    *)
        if [[ ${SysInfo_RelatedOS} = *rhel* || ${SysInfo_RelatedOS} = *fedora* ]]; then
            Install_WARP_Client_CentOS
        else
            log ERROR "This operating system is not supported."
            exit 1
        fi
        ;;
    esac
    Check_WARP_Client
    if [[ ${WARP_Client_Status} = active ]]; then
        log INFO "Cloudflare WARP Client installed successfully!"
    else
        log ERROR "warp-svc failure to run!"
        journalctl -u warp-svc --no-pager
        exit 1
    fi
}

Uninstall_WARP_Client() {
    log INFO "Uninstalling Cloudflare WARP Client..."
    case ${SysInfo_OS_Name_lowercase} in
    *debian* | *ubuntu*)
        apt purge cloudflare-warp -y
        rm -f /etc/apt/sources.list.d/cloudflare-client.list /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
        ;;
    *centos* | *rhel*)
        yum remove cloudflare-warp -y
        ;;
    *)
        if [[ ${SysInfo_RelatedOS} = *rhel* || ${SysInfo_RelatedOS} = *fedora* ]]; then
            yum remove cloudflare-warp -y
        else
            log ERROR "This operating system is not supported."
            exit 1
        fi
        ;;
    esac
}

Restart_WARP_Client() {
    log INFO "Restarting Cloudflare WARP Client..."
    systemctl restart warp-svc
    Check_WARP_Client
    if [[ ${WARP_Client_Status} = active ]]; then
        log INFO "Cloudflare WARP Client has been restarted."
    else
        log ERROR "Cloudflare WARP Client failure to run!"
        journalctl -u warp-svc --no-pager
        exit 1
    fi
}

Init_WARP_Client() {
    Check_WARP_Client
    if [[ ${WARP_Client_SelfStart} != enabled || ${WARP_Client_Status} != active ]]; then
        Install_WARP_Client
    fi
    if ! warp-cli registration show >/dev/null 2>&1; then
        log INFO "Registering WARP client..."
        warp-cli registration new
    fi
}

Connect_WARP() {
    log INFO "Connecting to WARP..."
    warp-cli connect
}

Disconnect_WARP() {
    log INFO "Disconnecting from WARP..."
    warp-cli disconnect
}

Set_WARP_Mode_Proxy() {
    log INFO "Setting up WARP Proxy Mode..."
    warp-cli mode proxy
}

Enable_WARP_Client_Proxy() {
    Init_WARP_Client
    Set_WARP_Mode_Proxy
    Connect_WARP
    Print_WARP_Client_Status
}

Get_WARP_Proxy_Port() {
    WARP_Proxy_Port=$(warp-cli settings list 2>/dev/null | grep 'Proxy Port' | awk '{print $NF}')
    if [[ -z "${WARP_Proxy_Port}" ]]; then
        WARP_Proxy_Port='40000' # Default port if not found
    fi
}

Print_Delimiter() {
    printf '=%.0s' $(seq $(tput cols))
    echo
}

Install_wgcf() {
    curl -fsSL git.io/wgcf.sh | bash
}

Uninstall_wgcf() {
    rm -f /usr/local/bin/wgcf
}

Register_WARP_Account() {
    while [[ ! -f wgcf-account.toml ]]; do
        Install_wgcf
        log INFO "Cloudflare WARP Account registration in progress..."
        yes | wgcf register
        sleep 5
    done
}

Backup_WGCF_Profile() {
    mkdir -p ${WGCF_ProfileDir}
    mv -f wgcf* ${WGCF_ProfileDir}
}

Read_WGCF_Profile() {
    WireGuard_Interface_PrivateKey=$(cat ${WGCF_ProfilePath} | grep ^PrivateKey | cut -d= -f2- | awk '$1=$1')
    WireGuard_Interface_Address=$(cat ${WGCF_ProfilePath} | grep ^Address | cut -d= -f2- | awk '$1=$1' | sed ":a;N;s/\n/,/g;ta")
    WireGuard_Peer_PublicKey=$(cat ${WGCF_ProfilePath} | grep ^PublicKey | cut -d= -f2- | awk '$1=$1')
    WireGuard_Interface_Address_IPv4=$(echo ${WireGuard_Interface_Address} | cut -d, -f1 | cut -d'/' -f1)
    WireGuard_Interface_Address_IPv6=$(echo ${WireGuard_Interface_Address} | cut -d, -f2 | cut -d'/' -f1)
}

Load_WGCF_Profile() {
    if [[ -f ${WGCF_Profile} ]]; then
        Backup_WGCF_Profile
        Read_WGCF_Profile
    elif [[ -f ${WGCF_ProfilePath} ]]; then
        Read_WGCF_Profile
    else
        Generate_WGCF_Profile
        Backup_WGCF_Profile
        Read_WGCF_Profile
    fi
}

Install_WireGuardTools_Debian() {
    case ${SysInfo_OS_Ver_major} in
    10)
        if [[ -z $(grep "^deb.*buster-backports.*main" /etc/apt/sources.list{,.d/*}) ]]; then
            echo "deb http://deb.debian.org/debian buster-backports main" | tee /etc/apt/sources.list.d/backports.list
        fi
        ;;
    *)
        if [[ ${SysInfo_OS_Ver_major} -lt 10 ]]; then
            log ERROR "This operating system is not supported."
            exit 1
        fi
        ;;
    esac
    apt update
    apt install iproute2 openresolv -y
    apt install wireguard-tools --no-install-recommends -y
}

Install_WireGuardTools_Ubuntu() {
    apt update
    apt install iproute2 openresolv -y
    apt install wireguard-tools --no-install-recommends -y
}

Install_WireGuardTools_CentOS() {
    yum install epel-release -y || yum install https://dl.fedoraproject.org/pub/epel/epel-release-latest-${SysInfo_OS_Ver_major}.noarch.rpm -y
    yum install iproute iptables wireguard-tools -y
}

Install_WireGuardTools_Fedora() {
    dnf install iproute iptables wireguard-tools -y
}

Install_WireGuardTools_Arch() {
    pacman -Sy iproute2 openresolv wireguard-tools --noconfirm
}

Install_WireGuardTools() {
    log INFO "Installing wireguard-tools..."
    case ${SysInfo_OS_Name_lowercase} in
    *debian*)
        Install_WireGuardTools_Debian
        ;;
    *ubuntu*)
        Install_WireGuardTools_Ubuntu
        ;;
    *centos* | *rhel*)
        Install_WireGuardTools_CentOS
        ;;
    *fedora*)
        Install_WireGuardTools_Fedora
        ;;
    *arch*)
        Install_WireGuardTools_Arch
        ;;
    *)
        if [[ ${SysInfo_RelatedOS} = *rhel* || ${SysInfo_RelatedOS} = *fedora* ]]; then
            Install_WireGuardTools_CentOS
        else
            log ERROR "This operating system is not supported."
            exit 1
        fi
        ;;
    esac
}

Install_WireGuardGo() {
    case ${SysInfo_Virt} in
    openvz | lxc*)
        curl -fsSL git.io/wireguard-go.sh | bash
        ;;
    *)
        if [[ ${SysInfo_Kernel_Ver_major} -lt 5 || ${SysInfo_Kernel_Ver_minor} -lt 6 ]]; then
            curl -fsSL git.io/wireguard-go.sh | bash
        fi
        ;;
    esac
}

Check_WireGuard() {
    WireGuard_Status=$(systemctl is-active wg-quick@${WireGuard_Interface})
    WireGuard_SelfStart=$(systemctl is-enabled wg-quick@${WireGuard_Interface} 2>/dev/null)
}

Install_WireGuard() {
    Print_System_Info
    Check_WireGuard
    if [[ ${WireGuard_SelfStart} != enabled || ${WireGuard_Status} != active ]]; then
        Install_WireGuardTools
        Install_WireGuardGo
    else
        log INFO "WireGuard is installed and running."
    fi
}

Start_WireGuard() {
    Check_WARP_Client
    log INFO "Starting WireGuard..."
    if [[ ${WARP_Client_Status} = active ]]; then
        systemctl stop warp-svc
        systemctl enable wg-quick@${WireGuard_Interface} --now
        systemctl start warp-svc
    else
        systemctl enable wg-quick@${WireGuard_Interface} --now
    fi
    Check_WireGuard
    if [[ ${WireGuard_Status} = active ]]; then
        log INFO "WireGuard is running."
    else
        log ERROR "WireGuard failure to run!"
        journalctl -u wg-quick@${WireGuard_Interface} --no-pager
        exit 1
    fi
}

Restart_WireGuard() {
    Check_WARP_Client
    log INFO "Restarting WireGuard..."
    if [[ ${WARP_Client_Status} = active ]]; then
        systemctl stop warp-svc
        systemctl restart wg-quick@${WireGuard_Interface}
        systemctl start warp-svc
    else
        systemctl restart wg-quick@${WireGuard_Interface}
    fi
    Check_WireGuard
    if [[ ${WireGuard_Status} = active ]]; then
        log INFO "WireGuard has been restarted."
    else
        log ERROR "WireGuard failure to run!"
        journalctl -u wg-quick@${WireGuard_Interface} --no-pager
        exit 1
    fi
}

Enable_IPv6_Support() {
    if [[ $(sysctl -a | grep 'disable_ipv6.*=.*1') || $(cat /etc/sysctl.{conf,d/*} | grep 'disable_ipv6.*=.*1') ]]; then
        sed -i '/disable_ipv6/d' /etc/sysctl.{conf,d/*}
        echo 'net.ipv6.conf.all.disable_ipv6 = 0' >/etc/sysctl.d/ipv6.conf
        sysctl -w net.ipv6.conf.all.disable_ipv6=0
    fi
}

Enable_WireGuard() {
    Enable_IPv6_Support
    Check_WireGuard
    if [[ ${WireGuard_SelfStart} = enabled ]]; then
        Restart_WireGuard
    else
        Start_WireGuard
    fi
}

Stop_WireGuard() {
    Check_WARP_Client
    if [[ ${WireGuard_Status} = active ]]; then
        log INFO "Stoping WireGuard..."
        if [[ ${WARP_Client_Status} = active ]]; then
            systemctl stop warp-svc
            systemctl stop wg-quick@${WireGuard_Interface}
            systemctl start warp-svc
        else
            systemctl stop wg-quick@${WireGuard_Interface}
        fi
        Check_WireGuard
        if [[ ${WireGuard_Status} != active ]]; then
            log INFO "WireGuard has been stopped."
        else
            log ERROR "WireGuard stop failure!"
        fi
    else
        log INFO "WireGuard is stopped."
    fi
}

Disable_WireGuard() {
    Check_WARP_Client
    Check_WireGuard
    if [[ ${WireGuard_SelfStart} = enabled || ${WireGuard_Status} = active ]]; then
        log INFO "Disabling WireGuard..."
        if [[ ${WARP_Client_Status} = active ]]; then
            systemctl stop warp-svc
            systemctl disable wg-quick@${WireGuard_Interface} --now
            systemctl start warp-svc
        else
            systemctl disable wg-quick@${WireGuard_Interface} --now
        fi
        Check_WireGuard
        if [[ ${WireGuard_SelfStart} != enabled && ${WireGuard_Status} != active ]]; then
            log INFO "WireGuard has been disabled."
        else
            log ERROR "WireGuard disable failure!"
        fi
    else
        log INFO "WireGuard is disabled."
    fi
}

Print_WireGuard_Log() {
    journalctl -u wg-quick@${WireGuard_Interface} -f
}

Check_Network_Status_IPv4() {
    if ping -c1 -W1 ${TestIPv4_1} >/dev/null 2>&1 || ping -c1 -W1 ${TestIPv4_2} >/dev/null 2>&1; then
        IPv4Status='on'
    else
        IPv4Status='off'
    fi
}

Check_Network_Status_IPv6() {
    if ping6 -c1 -W1 ${TestIPv6_1} >/dev/null 2>&1 || ping6 -c1 -W1 ${TestIPv6_2} >/dev/null 2>&1; then
        IPv6Status='on'
    else
        IPv6Status='off'
    fi
}

Check_Network_Status() {
    Disable_WireGuard
    Check_Network_Status_IPv4
    Check_Network_Status_IPv6
}

Check_IPv4_addr() {
    IPv4_addr=$(
        ip route get ${TestIPv4_1} 2>/dev/null | grep -oP 'src \K\S+' ||
            ip route get ${TestIPv4_2} 2>/dev/null | grep -oP 'src \K\S+'
    )
}

Check_IPv6_addr() {
    IPv6_addr=$(
        ip route get ${TestIPv6_1} 2>/dev/null | grep -oP 'src \K\S+' ||
            ip route get ${TestIPv6_2} 2>/dev/null | grep -oP 'src \K\S+'
    )
}

Get_IP_addr() {
    Check_Network_Status
    if [[ ${IPv4Status} = on ]]; then
        log INFO "Getting the network interface IPv4 address..."
        Check_IPv4_addr
        if [[ ${IPv4_addr} ]]; then
            log INFO "IPv4 Address: ${IPv4_addr}"
        else
            log WARN "Network interface IPv4 address not obtained."
        fi
    fi
    if [[ ${IPv6Status} = on ]]; then
        log INFO "Getting the network interface IPv6 address..."
        Check_IPv6_addr
        if [[ ${IPv6_addr} ]]; then
            log INFO "IPv6 Address: ${IPv6_addr}"
        else
            log WARN "Network interface IPv6 address not obtained."
        fi
    fi
}

Get_WireGuard_Interface_MTU() {
    log INFO "Getting the best MTU value for WireGuard..."
    MTU_Preset=1500
    MTU_Increment=10
    if [[ ${IPv4Status} = off && ${IPv6Status} = on ]]; then
        CMD_ping='ping6'
        MTU_TestIP_1="${TestIPv6_1}"
        MTU_TestIP_2="${TestIPv6_2}"
    else
        CMD_ping='ping'
        MTU_TestIP_1="${TestIPv4_1}"
        MTU_TestIP_2="${TestIPv4_2}"
    fi
    while true; do
        if ${CMD_ping} -c1 -W1 -s$((${MTU_Preset} - 28)) -Mdo ${MTU_TestIP_1} >/dev/null 2>&1 || ${CMD_ping} -c1 -W1 -s$((${MTU_Preset} - 28)) -Mdo ${MTU_TestIP_2} >/dev/null 2>&1; then
            MTU_Increment=1
            MTU_Preset=$((${MTU_Preset} + ${MTU_Increment}))
        else
            MTU_Preset=$((${MTU_Preset} - ${MTU_Increment}))
            if [[ ${MTU_Increment} = 1 ]]; then
                break
            fi
        fi
        if [[ ${MTU_Preset} -le 1360 ]]; then
            log WARN "MTU is set to the lowest value."
            MTU_Preset='1360'
            break
        fi
    done
    WireGuard_Interface_MTU=$((${MTU_Preset} - 80))
    log INFO "WireGuard MTU: ${WireGuard_Interface_MTU}"
}

Generate_WireGuardProfile_Interface() {
    Get_WireGuard_Interface_MTU
    log INFO "WireGuard profile (${WireGuard_ConfPath}) generation in progress..."
    cat <<EOF >${WireGuard_ConfPath}
[Interface]
PrivateKey = ${WireGuard_Interface_PrivateKey}
Address = ${WireGuard_Interface_Address}
DNS = ${WireGuard_Interface_DNS}
MTU = ${WireGuard_Interface_MTU}
EOF

    # Add Tailscale exclusion rules if tailscale_dev is set
    if [[ -n "${tailscale_dev}" ]]; then
        Generate_WireGuardProfile_Interface_Rule_Tailscale
    fi
}

Generate_WireGuardProfile_Interface_Rule_TableOff() {
    cat <<EOF >>${WireGuard_ConfPath}
Table = off
EOF
}

Generate_WireGuardProfile_Interface_Rule_IPv4_nonGlobal() {
    cat <<EOF >>${WireGuard_ConfPath}
PostUP = ip -4 route add default dev ${WireGuard_Interface} table ${WireGuard_Interface_Rule_table}
PostUP = ip -4 rule add from ${WireGuard_Interface_Address_IPv4} lookup ${WireGuard_Interface_Rule_table}
PostDown = ip -4 rule delete from ${WireGuard_Interface_Address_IPv4} lookup ${WireGuard_Interface_Rule_table}
PostUP = ip -4 rule add fwmark ${WireGuard_Interface_Rule_fwmark} lookup ${WireGuard_Interface_Rule_table}
PostDown = ip -4 rule delete fwmark ${WireGuard_Interface_Rule_fwmark} lookup ${WireGuard_Interface_Rule_table}
PostUP = ip -4 rule add table main suppress_prefixlength 0
PostDown = ip -4 rule delete table main suppress_prefixlength 0
EOF
}

Generate_WireGuardProfile_Interface_Rule_IPv6_nonGlobal() {
    cat <<EOF >>${WireGuard_ConfPath}
PostUP = ip -6 route add default dev ${WireGuard_Interface} table ${WireGuard_Interface_Rule_table}
PostUP = ip -6 rule add from ${WireGuard_Interface_Address_IPv6} lookup ${WireGuard_Interface_Rule_table}
PostDown = ip -6 rule delete from ${WireGuard_Interface_Address_IPv6} lookup ${WireGuard_Interface_Rule_table}
PostUP = ip -6 rule add fwmark ${WireGuard_Interface_Rule_fwmark} lookup ${WireGuard_Interface_Rule_table}
PostDown = ip -6 rule delete fwmark ${WireGuard_Interface_Rule_fwmark} lookup ${WireGuard_Interface_Rule_table}
PostUP = ip -6 rule add table main suppress_prefixlength 0
PostDown = ip -6 rule delete table main suppress_prefixlength 0
EOF
}

Generate_WireGuardProfile_Interface_Rule_DualStack_nonGlobal() {
    Generate_WireGuardProfile_Interface_Rule_TableOff
    Generate_WireGuardProfile_Interface_Rule_IPv4_nonGlobal
    Generate_WireGuardProfile_Interface_Rule_IPv6_nonGlobal
}

Generate_WireGuardProfile_Interface_Rule_IPv4_Global_srcIP() {
    cat <<EOF >>${WireGuard_ConfPath}
PostUp = ip -4 rule add from ${IPv4_addr} lookup main prio 18
PostDown = ip -4 rule delete from ${IPv4_addr} lookup main prio 18
EOF
}

Generate_WireGuardProfile_Interface_Rule_IPv6_Global_srcIP() {
    cat <<EOF >>${WireGuard_ConfPath}
PostUp = ip -6 rule add from ${IPv6_addr} lookup main prio 18
PostDown = ip -6 rule delete from ${IPv6_addr} lookup main prio 18
EOF
}

Generate_WireGuardProfile_Peer() {
    cat <<EOF >>${WireGuard_ConfPath}

[Peer]
PublicKey = ${WireGuard_Peer_PublicKey}
AllowedIPs = ${WireGuard_Peer_AllowedIPs}
Endpoint = ${WireGuard_Peer_Endpoint}
EOF
}

Generate_WireGuardProfile_Interface_Rule_Tailscale() {
    if [[ -n "${tailscale_dev}" ]]; then
        cat <<EOF >>${WireGuard_ConfPath}
PostUp = ip -4 route add ${Tailscale_IPv4_Range} dev ${tailscale_dev} || true
PostUp = ip -6 route add ${Tailscale_IPv6_Range} dev ${tailscale_dev} || true
PostDown = ip -4 route del ${Tailscale_IPv4_Range} dev ${tailscale_dev} || true
PostDown = ip -6 route del ${Tailscale_IPv6_Range} dev ${tailscale_dev} || true
EOF
    fi
}

Check_WARP_Client_Status() {
    Check_WARP_Client
    case ${WARP_Client_Status} in
    active)
        WARP_Client_Status_en="${FontColor_Green}Running${FontColor_Suffix}"
        ;;
    *)
        WARP_Client_Status_en="${FontColor_Red}Stopped${FontColor_Suffix}"
        ;;
    esac
}

Check_WARP_Proxy_Status() {
    Check_WARP_Client
    if [[ ${WARP_Client_Status} = active ]]; then
        Get_WARP_Proxy_Port
        if warp-cli status | grep -q "Mode: Proxy"; then
            WARP_Proxy_Status="on"
        else
            WARP_Proxy_Status=""
        fi
    else
        unset WARP_Proxy_Status
    fi
    case ${WARP_Proxy_Status} in
    on)
        WARP_Proxy_Status_en="${FontColor_Green}${WARP_Proxy_Port}${FontColor_Suffix}"
        ;;
    plus)
        WARP_Proxy_Status_en="${FontColor_Green}${WARP_Proxy_Port}(WARP+)${FontColor_Suffix}"
        ;;
    *)
        WARP_Proxy_Status_en="${FontColor_Red}Off${FontColor_Suffix}"
        ;;
    esac
}

Check_WireGuard_Status() {
    Check_WireGuard
    case ${WireGuard_Status} in
    active)
        WireGuard_Status_en="${FontColor_Green}Running${FontColor_Suffix}"
        ;;
    *)
        WireGuard_Status_en="${FontColor_Red}Stopped${FontColor_Suffix}"
        ;;
    esac
}

Check_WARP_WireGuard_Status() {
    Check_Network_Status_IPv4
    if [[ ${IPv4Status} = on ]]; then
        WARP_IPv4_Status=$(curl -s4 ${CF_Trace_URL} --connect-timeout 2 | grep warp | cut -d= -f2)
    else
        unset WARP_IPv4_Status
    fi
    case ${WARP_IPv4_Status} in
    on)
        WARP_IPv4_Status_en="${FontColor_Green}WARP${FontColor_Suffix}"
        ;;
    plus)
        WARP_IPv4_Status_en="${FontColor_Green}WARP+${FontColor_Suffix}"
        ;;
    off)
        WARP_IPv4_Status_en="Normal"
        ;;
    *)
        Check_Network_Status_IPv4
        if [[ ${IPv4Status} = on ]]; then
            WARP_IPv4_Status_en="Normal"
        else
            WARP_IPv4_Status_en="${FontColor_Red}Unconnected${FontColor_Suffix}"
        fi
        ;;
    esac
    Check_Network_Status_IPv6
    if [[ ${IPv6Status} = on ]]; then
        WARP_IPv6_Status=$(curl -s6 ${CF_Trace_URL} --connect-timeout 2 | grep warp | cut -d= -f2)
    else
        unset WARP_IPv6_Status
    fi
    case ${WARP_IPv6_Status} in
    on)
        WARP_IPv6_Status_en="${FontColor_Green}WARP${FontColor_Suffix}"
        ;;
    plus)
        WARP_IPv6_Status_en="${FontColor_Green}WARP+${FontColor_Suffix}"
        ;;
    off)
        WARP_IPv6_Status_en="Normal"
        ;;
    *)
        Check_Network_Status_IPv6
        if [[ ${IPv6Status} = on ]]; then
            WARP_IPv6_Status_en="Normal"
        else
            WARP_IPv6_Status_en="${FontColor_Red}Unconnected${FontColor_Suffix}"
        fi
        ;;
    esac
    if [[ ${IPv4Status} = off && ${IPv6Status} = off ]]; then
        log ERROR "Cloudflare WARP network anomaly, WireGuard tunnel established failed."
        Disable_WireGuard
        exit 1
    fi
}

Check_ALL_Status() {
    Check_WARP_Client_Status
    Check_WARP_Proxy_Status
    Check_WireGuard_Status
    Check_WARP_WireGuard_Status
}

Print_WARP_Client_Status() {
    log INFO "Status check in progress..."
    sleep 3
    Check_WARP_Client_Status
    Check_WARP_Proxy_Status
    echo -e "
 ----------------------------
 WARP Client\t: ${WARP_Client_Status_en}
 SOCKS5 Port\t: ${WARP_Proxy_Status_en}
 ----------------------------
"
    log INFO "Done."
}

Print_WARP_WireGuard_Status() {
    log INFO "Status check in progress..."
    Check_WireGuard_Status
    Check_WARP_WireGuard_Status
    echo -e "
 ----------------------------
 WireGuard\t: ${WireGuard_Status_en}
 IPv4 Network\t: ${WARP_IPv4_Status_en}
 IPv6 Network\t: ${WARP_IPv6_Status_en}
 ----------------------------
"
    log INFO "Done."
}

Print_ALL_Status() {
    log INFO "Status check in progress..."
    Check_ALL_Status
    echo -e "
 ----------------------------
 WARP Client\t: ${WARP_Client_Status_en}
 SOCKS5 Port\t: ${WARP_Proxy_Status_en}
 ----------------------------
 WireGuard\t: ${WireGuard_Status_en}
 IPv4 Network\t: ${WARP_IPv4_Status_en}
 IPv6 Network\t: ${WARP_IPv6_Status_en}
 ----------------------------"

    # Add WARP status information
    echo -e "\nNetwork Information:"
    echo "IPv4: $(curl -s4 ${CF_Trace_URL} 2>/dev/null | grep -E '^ip=' | cut -d= -f2 || echo 'Not available')"
    echo "IPv6: $(curl -s6 ${CF_Trace_URL} 2>/dev/null | grep -E '^ip=' | cut -d= -f2 || echo 'Not available')"
    echo "WARP: $(curl -s4 ${CF_Trace_URL} 2>/dev/null | grep -E '^warp=' | cut -d= -f2 || echo 'Not available')"
}

View_WireGuard_Profile() {
    Print_Delimiter
    cat ${WireGuard_ConfPath}
    Print_Delimiter
}

Check_WireGuard_Peer_Endpoint() {
    if ping -c1 -W1 ${WireGuard_Peer_Endpoint_IP4} >/dev/null 2>&1; then
        WireGuard_Peer_Endpoint="${WireGuard_Peer_Endpoint_IPv4}"
    elif ping6 -c1 -W1 ${WireGuard_Peer_Endpoint_IP6} >/dev/null 2>&1; then
        WireGuard_Peer_Endpoint="${WireGuard_Peer_Endpoint_IPv6}"
    else
        WireGuard_Peer_Endpoint="${WireGuard_Peer_Endpoint_Domain}"
    fi
}

Set_WARP_IPv4() {
    Install_WireGuard
    Get_IP_addr
    Load_WGCF_Profile
    if [[ ${IPv4Status} = off && ${IPv6Status} = on ]]; then
        WireGuard_Interface_DNS="${WireGuard_Interface_DNS_64}"
    else
        WireGuard_Interface_DNS="${WireGuard_Interface_DNS_46}"
    fi
    WireGuard_Peer_AllowedIPs="${WireGuard_Peer_AllowedIPs_IPv4}"
    Check_WireGuard_Peer_Endpoint
    Generate_WireGuardProfile_Interface
    if [[ -n ${IPv4_addr} ]]; then
        Generate_WireGuardProfile_Interface_Rule_IPv4_Global_srcIP
    fi
    Generate_WireGuardProfile_Peer
    View_WireGuard_Profile
    Enable_WireGuard
    Print_WARP_WireGuard_Status
}

Set_WARP_IPv6() {
    Install_WireGuard
    Get_IP_addr
    Load_WGCF_Profile
    if [[ ${IPv4Status} = off && ${IPv6Status} = on ]]; then
        WireGuard_Interface_DNS="${WireGuard_Interface_DNS_64}"
    else
        WireGuard_Interface_DNS="${WireGuard_Interface_DNS_46}"
    fi
    WireGuard_Peer_AllowedIPs="${WireGuard_Peer_AllowedIPs_IPv6}"
    Check_WireGuard_Peer_Endpoint
    Generate_WireGuardProfile_Interface
    if [[ -n ${IPv6_addr} ]]; then
        Generate_WireGuardProfile_Interface_Rule_IPv6_Global_srcIP
    fi
    Generate_WireGuardProfile_Peer
    View_WireGuard_Profile
    Enable_WireGuard
    Print_WARP_WireGuard_Status
}

Set_WARP_DualStack() {
    Install_WireGuard
    Get_IP_addr
    Load_WGCF_Profile
    WireGuard_Interface_DNS="${WireGuard_Interface_DNS_46}"
    WireGuard_Peer_AllowedIPs="${WireGuard_Peer_AllowedIPs_DualStack}"
    Check_WireGuard_Peer_Endpoint
    Generate_WireGuardProfile_Interface
    if [[ -n ${IPv4_addr} ]]; then
        Generate_WireGuardProfile_Interface_Rule_IPv4_Global_srcIP
    fi
    if [[ -n ${IPv6_addr} ]]; then
        Generate_WireGuardProfile_Interface_Rule_IPv6_Global_srcIP
    fi
    Generate_WireGuardProfile_Peer
    View_WireGuard_Profile
    Enable_WireGuard
    Print_WARP_WireGuard_Status
}

Set_WARP_DualStack_nonGlobal() {
    Install_WireGuard
    Get_IP_addr
    Load_WGCF_Profile
    WireGuard_Interface_DNS="${WireGuard_Interface_DNS_46}"
    WireGuard_Peer_AllowedIPs="${WireGuard_Peer_AllowedIPs_DualStack}"
    Check_WireGuard_Peer_Endpoint
    Generate_WireGuardProfile_Interface
    Generate_WireGuardProfile_Interface_Rule_DualStack_nonGlobal
    Generate_WireGuardProfile_Peer
    View_WireGuard_Profile
    Enable_WireGuard
    Print_WARP_WireGuard_Status
}

Print_Usage() {
    echo -e "
Cloudflare WARP Installer [${version}]

USAGE:
    bash <(curl -fsSL 1lm.dev/warp.sh) [SUBCOMMAND]

SUBCOMMANDS:
    install         Install Cloudflare WARP Official Linux Client
    uninstall       Uninstall Cloudflare WARP Official Linux Client
    restart         Restart Cloudflare WARP Official Linux Client
    proxy           Enable WARP Client Proxy Mode (default SOCKS5 port: 40000)
    unproxy         Disable WARP Client Proxy Mode
    wg              Install WireGuard and related components
    wg4             Configuration WARP IPv4 Global Network (with WireGuard)
    wg6             Configuration WARP IPv6 Global Network (with WireGuard)
    wgd             Configuration WARP Dual Stack Global Network (with WireGuard)
    wgx             Configuration WARP Non-Global Network (with WireGuard)
    rwg             Restart WARP WireGuard service
    dwg             Disable WARP WireGuard service
    status          Prints status information
    version         Prints version information
    help            Prints this message
    -t TOKEN        Teams JWT token for Cloudflare Teams enrollment
    --ts-dev DEV    Tailscale device name (e.g. tailscale0) to exclude Tailscale networks
    --ts-ipv4 CIDR  Tailscale IPv4 range to exclude (default: 100.64.0.0/10)
    --ts-ipv6 CIDR  Tailscale IPv6 range to exclude (default: fd7a:115c:a1e0::/48)

Regarding Teams enrollment:
    1. Visit https://<teams id>.cloudflareaccess.com/warp
    2. Authenticate yourself as you would with the official client
    3. Check the source code of the page for the JWT token or use the following code in the Web Console (Ctrl+Shift+K):
        console.log(document.querySelector(\"meta[http-equiv='refresh']\").content.split(\"=\")[2])
    4. Pass the output as the value for the parameter -t. Example:
        ${0} -t eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.....

Examples:
    # Use default Tailscale ranges
    ${0} wgd --ts-dev tailscale0

    # Specify custom Tailscale ranges
    ${0} wgd --ts-dev tailscale0 --ts-ipv4 100.64.0.0/10 --ts-ipv6 fd7a:115c:a1e0::/48
"
}

if [ $# -ge 1 ]; then
    Get_System_Info

    # Initialize variables
    teams_mode=0
    teams_ephemeral_token=""
    command=""
    tailscale_dev=""

    # Process all arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            -t)
                if [ -z "$2" ]; then
                    log ERROR "Option -t requires an argument."
                    Print_Usage
                    exit 1
                fi
                teams_ephemeral_token="$2"
                teams_mode=1
                shift 2
                ;;
            --ts-dev)
                if [ -z "$2" ]; then
                    log ERROR "Option --ts-dev requires an argument."
                    Print_Usage
                    exit 1
                fi
                tailscale_dev="$2"
                shift 2
                ;;
            --ts-ipv4)
                if [ -z "$2" ]; then
                    log ERROR "Option --ts-ipv4 requires an argument."
                    Print_Usage
                    exit 1
                fi
                Tailscale_IPv4_Range="$2"
                shift 2
                ;;
            --ts-ipv6)
                if [ -z "$2" ]; then
                    log ERROR "Option --ts-ipv6 requires an argument."
                    Print_Usage
                    exit 1
                fi
                Tailscale_IPv6_Range="$2"
                shift 2
                ;;
            install|uninstall|restart|proxy|socks5|s5|unproxy|unsocks5|uns5|wg|wg4|4|wg6|6|wgd|d|wgx|x|rwg|dwg|status|help|version)
                command="$1"
                shift
                ;;
            *)
                log ERROR "Invalid Parameters: $*"
                Print_Usage
                exit 1
                ;;
        esac
    done

    # Execute the command if one was provided
    case ${command} in
    install)
        Install_WARP_Client
        ;;
    uninstall)
        Uninstall_WARP_Client
        ;;
    restart)
        Restart_WARP_Client
        ;;
    proxy | socks5 | s5)
        Enable_WARP_Client_Proxy
        ;;
    unproxy | unsocks5 | uns5)
        Disconnect_WARP
        ;;
    wg)
        Install_WireGuard
        ;;
    wg4 | 4)
        Set_WARP_IPv4
        ;;
    wg6 | 6)
        Set_WARP_IPv6
        ;;
    wgd | d)
        Set_WARP_DualStack
        ;;
    wgx | x)
        Set_WARP_DualStack_nonGlobal
        ;;
    rwg)
        Restart_WireGuard
        ;;
    dwg)
        Disable_WireGuard
        ;;
    status)
        Print_ALL_Status
        ;;
    help)
        Print_Usage
        ;;
    version)
        echo "${version}"
        ;;
    "")
        if [ ${teams_mode} -eq 1 ]; then
            # If only -t was provided without a command, default to installing the client
            Install_WARP_Client
        else
            Print_Usage
        fi
        ;;
    *)
        log ERROR "Invalid Parameters: $command"
        Print_Usage
        exit 1
        ;;
    esac
else
    Print_Usage
fi
