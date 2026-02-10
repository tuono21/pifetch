#!/bin/bash
# pifetch.sh for ~2017+ raspberry Pi models - April 2021
# 2-18-2022 removed full path
# May 2025 bookworm updates, eeprom, neo and cpufetch
# cpufetch broken bookworm pi5
# 6-23-25 fix video mode check for 3 versions of OS
# add 32/64 bit kernel and userspace check
# add uptime
# 6-30-2025 add desktop info
# 2-5-2026 add cpu revision
# 2-10-26 fixed cpu/board revision and blue bars

bold=`tput smso`
boldoff=`tput rmso`
red=`tput setaf 1`
green=`tput setaf 2`
yellow=`tput setaf 3`
blue=`tput setaf 6`
default=`tput sgr0`
columns=`tput cols`

trim() {
	sed 's/^[ \t]*//;s/[ \t]*$//' | tr '\t' ' ' | tr -s "[:blank:]"
}

pad() {
	local spaces="                                                                               "
	local temp="$(cat)$spaces"
	local columns=`tput cols`
	if [ "$columns" -gt 100 ]; then
		columns=100
	fi	
	echo "${temp:0:$columns}${default}"
}

# Start setup
echo

if [ "`ps | tail -n 4 | sed -E '2,$d;s/.* (.*)//'`" = "sh" ]; then
   echo
   echo "*** Oops, the Bourne shell is not supported"
   echo
   exit 86
fi

# for command in bc neofetch cpufetch btop; do
for command in bc vcgencmd kmsprint; do
  which $command 2>&1 >/dev/null
  if (( $? != 0 )); then
    echo "WARNING: $command is not installed."
    echo "Installing $command"
    sudo apt-get -y install $command
    echo
    if  (( $? != 0 )); then
      echo "ERROR: $command could not be installed."
      echo
#      exit -2
    fi
  fi
done

command -v rpi-eeprom-update 2>&1>/dev/null
if [[ $? != 0 ]]; then
	echo "rpi-eeprom utils not installed, Installing..."
	sudo apt-get install rpi-eeprom
fi

#Begin
echo
echo -e "${bold}${blue}  S Y S T E M  D E T A I L S  F O R: $(whoami)@$(hostname)" | pad 
echo -en "$(cat /proc/cpuinfo | grep 'Model'| cut -f2 -d ":"|trim)"
echo -e " - Board $(cat /proc/cpuinfo | grep Revision|trim)"
echo -e "$(lscpu|grep "^Model name:"|tr -s " "|cut -d " " -f 3) $(lscpu|grep -v "NUMA"|grep "CPU(s):"|trim) - $(cat /proc/cpuinfo | grep -m 1 'revision'|trim) - $(lscpu | grep Stepping|trim)"
echo -e "Serial Number $(cat /proc/cpuinfo | grep 'Serial'| cut -f2 -d ":"|trim)${default}"
output=$(ip addr|grep "inet "|grep -v "scope host"|trim)
if [[ "$output" == "" ]]; then
  echo "${red} NO network interfaces are currently assigned an IP address ${default}"
else
  echo "$output"
fi
echo -n "${yellow}UPTIME: "
uptime
echo -n "${default}"

# Display temperatures
TEMPC=$(vcgencmd measure_temp|awk -F "=" '{print $2}')
TEMPf=$(echo -e "$TEMPC" | awk -F "\'" '{print $1}' 2>/dev/null)
TEMP2=$(echo "$TEMPf*1.8+32"|bc)
OVRTMP=85
ALRM=""
[[ `echo $TEMPC|cut -d. -f1` -gt ${OVRTMP:-70} ]] && ALRM="\n\t TOO HOT! \t TOO HOT! \t TOO HOT! "
TEMPB4OVER=$(echo "${OVRTMP:-70}-${TEMPf}"|bc -l)
echo -e "${bold}${blue}  S Y S T E M    T E M P E R A T U R E                  ${default}   `[[ -n $ALRM ]] || COLOR=green; setterm -foreground ${COLOR:-red}`${ALRM:-OK}"; setterm -foreground default
echo -e "The SoC (CPU/GPU) temperature is:`tput smso` ${TEMPf}°C or ${TEMP2}°F `tput rmso` `tput smso;setterm -foreground red`$ALRM`setterm -foreground default;tput rmso`"
[[ `echo $TEMPC|cut -d. -f1` -lt OVRTMP ]] && echo -e "This is below the ${OVRTMP:-70}°C HIGH-TEMP LIMIT by ${TEMPB4OVER}°C"
echo -e "${yellow}$(vcgencmd get_throttled)${default}\c" && echo -e "\tThrottling or undervoltage has occured when nonzero"

# Display voltages
echo -e "${bold}${blue}  S Y S T E M    V O L T A G E S" | pad
echo -e "Core:      \c"
echo -n $(vcgencmd measure_volts core|awk -F "=" '{print $2}')
echo -e "\t\tsdram Core: \c"
echo -n $(vcgencmd measure_volts sdram_c|awk -F "=" '{print $2}')
echo -e "\nsdram I/O: \c"
echo -n $(vcgencmd measure_volts sdram_i|awk -F "=" '{print $2}')
echo -e "\t\tsdram PHY:  \c"
echo -n $(vcgencmd measure_volts sdram_p|awk -F "=" '{print $2 ""}')
echo

# Display frequencies
echo -e "${bold}${blue}  R E A L T I M E   C L O C K    F R E Q U E N C I E S"|pad
for src in arm core h264 isp v3d uart pwm emmc pixel vec hdmi dpi ;do
  echo -e "$src\t $(echo "scale=0;$(vcgencmd measure_clock $src|cut -f2 -d "=") / 1000000"|bc -l) MHz"
done | pr --indent=0 -r -t -3 -e3
echo -e "${bold}${yellow} CONFIG ${boldoff} SDRAM  $(echo "$(vcgencmd get_config int|grep sdram_freq=|cut -f2 -d "=")") Mhz\c"
echo -e "   ARM  $(echo "$(vcgencmd get_config int|grep arm_freq=|cut -f2 -d "=")") Mhz\c"
echo -e "   CORE  $(echo "$(vcgencmd get_config int|grep core_freq=|cut -f2 -d "=")") Mhz\c"
echo -e "   GPU  $(echo "$(vcgencmd get_config int|grep gpu_freq=|cut -f2 -d "=")") Mhz${default}"

echo -e "${bold}${blue}  M E M O R Y   S I Z E"|pad
vcgencmd get_mem gpu
free -h

echo -e "${bold}${blue}  V I D E O   M O D E"|pad
if command -v kmsprint 2>&1 >/dev/null; then
	kmsprint|grep -iv plane
elif command -v tvservice 2>&1 >/dev/null; then
#old OS commands - still tvservice issues with specific video driver... expected?
#VC=$(lsmod|grep "^vc4"|wc -l)
#if [ "$VC" = "1" ]; then
	tvservice -s
	echo "${yellow}LCD: ${default}$(vcgencmd get_lcd_info)"
fi
if command -v xrandr 2>&1 >/dev/null; then
	echo -n "${yellow}X server: ${default}"
	xrandr|grep "connected\|disconnected\|Screen"
fi
echo "${yellow}Systemd default target at boot: ${default}$(systemctl get-default)"
echo "${yellow}Desktop running${default}"
session=$(loginctl|grep seat|tr -s ' '|cut -d " " -f 2) 
if [[ $session == "" ]]; then
	echo "${red}NONE and no local login${default}"
else
	loginctl show-session $session | grep -i "service\|desktop\|type"
fi
read -p "${blue} Press key for more ${default}" -n1 -s

echo
echo -e "${bold}${blue}  O T P   R E G I S T E R S"|pad
B="$(printf "%032s\n" $(echo "obase=2;ibase=16;$(A=$(vcgencmd otp_dump|grep 30:|cut -c 4-);echo ${A^^})"|bc)|tr ' ' '0')"
C="$(expr substr $B 7 1)"
if [ "$C" = "1" ]; then 
	echo "${red}Warranty bit 25 of register 30 is SET - warranty is VOIDED by using excessive overvoltage!${default}"
else
	echo "${green}Warranty bit 25 of register 30 is NOT set - high overvoltage has not been used or Pi4+${default}"
fi
D="$(printf "%032s\n" $(echo "obase=2;ibase=16;$(A=$(vcgencmd otp_dump|grep 17:|cut -c 4-);echo ${A^^})"|bc)|tr ' ' '0')"
E="$(expr substr $D 3 1)"
if [ "$E" = "1" ]; then
	echo "${green}USB host boot mode is ENABLED in bootmode register 17 bit 29${default}"
else
	echo "${yellow}USB host boot mode (3B,3B+,3A+,2B) is NOT enabled in bootmode register 17 bit 29${default}"
fi
E="$(expr substr $D 4 1)"
if [ "$E" = "1" ]; then
	echo "${green}USB device boot mode is ENABLED in bootmode register 17 bit 28${default}"
else
	echo "${yellow}USB device boot mode (Zero,3A+,CM) is NOT enabled in bootmode register 17 bit 28${default}"
fi

echo -e "${bold}${blue}  S O F T W A R E   V E R S I O N S - FW and kernel loaded from files in /boot partition"|pad
echo -e "${yellow}Videocore Firmware:${default} \c"
echo -n $(vcgencmd version| grep -E 'version|:')
echo -e "\n${yellow}Kernel:${default} $(uname -mrv)"
echo -e "${yellow}OS:${default} \c";cat /etc/*release|grep PRETTY|cut -d "=" -f 2|tr -d '"'
kern=$(uname -m)
userspace=$(getconf LONG_BIT)
if [[ $kern = "aarch64" ]]; then
	kern="64"
else 
	kern="32"
fi
echo "${yellow}The Linux kernel is $kern bit and the OS userspace is $userspace bit"

echo -e "${bold}${blue}  D R I V E   F E A T U R E S"|pad
rootfspart=$(findmnt | grep "^/" | tr -s " " | cut -d " " -f 2)
if [[ $rootfspart = "/dev/sda2" ]]; then
  echo "The rootfs partition is on a ${green}USB${default} device - UASP supported when driver listed as uas${yellow}"
  lsusb -t|grep -E --color=never 'uas|usb-storage' 
  if [[ $(lsblk -D|grep sda2|tr -s " "|cut -d " " -f 4) = "0B" ]]; then
	echo "${red}TRIM is NOT supported on this device - may be controller rather than drive or old firmware${default}"
  else
	echo "${green}TRIM is SUPPORTED on this device${default}" 
  fi
  if [[ $(echo "$(($(sudo fdisk -o device,start -l /dev/sda|grep sda2|tr -s " "|cut -d " " -f 2)%2048))") = 0 ]]; then
	echo "${green}The start sector of the rootfs partition is ALIGNED to a 1MB boundary${default}"
  else
	echo "${red}The start sector of the rootfs partition is NOT ALIGNED to a 1MB boundary${default}"
  fi
  sudo fdisk -l /dev/sda|grep --color=never size
elif [[ $rootfspart = "/dev/mmcblk0p2" ]]; then
  echo "The rootfs partition is running on an ${green}SD Card${default}"
  if [[ $(lsblk -D|grep mmcblk0p2|tr -s " "|cut -d " " -f 4) = "0B" ]]; then
	echo "${red}TRIM is NOT supported on this device - unusual, cheap or old card?${default}"
  else
	echo "${green}TRIM is SUPPORTED on this device${default}"
  fi
  if [[ $(echo "$(($(sudo fdisk -o device,start -l /dev/mmcblk0|grep mmcblk0p2|tr -s " "|cut -d " " -f 2)%2048))") = 0 ]]; then
	echo "${green}The start sector of the rootfs partition is ALIGNED to a 1MB boundary${default}"
  else
	echo "${red}The start sector of the rootfs partition is NOT ALIGNED to a 1MB boundary${default}"
  fi
  sudo fdisk -l /dev/mmcblk0|grep --color=never size
else echo "The rootfs partition is on an ${green}NVME${default} or other device" ;
fi
echo -n "${yellow}USB quirk running (for flaky USB to SATA adapters i.e. JMS578) - "
if output=$(cat /sys/module/usb_storage/parameters/quirks) && [ -z "$output" ]; then
  echo "${green}NONE${default}"
else
  echo "${red}$output${default}"
fi

echo -e "${bold}${blue}  M O U N T E D  P A R T I T I O N S"|pad
df -Th|grep -v "tmp"

#32bit broked pi zero 2w
echo -e "${bold}${blue}  E E P R O M   V E R S I O N S"|pad
output=$(sudo rpi-eeprom-update)
output2=$(echo "$output"|grep -i skipping)
if [[ "$output2" == "" ]]; then
  echo "$output"
  echo "VL805 supports onboard USB3 controller"
else
  echo "No EEPROM found - pre-Pi4 board"
fi
output3=$(rpi-eeprom-config)
output4=$(echo "$output3"|grep -i boot_order)
if [[ "$output4" == "BOOT_ORDER=0xf41" ]]; then
  echo "${green}Custom setting saved but it's the DEFAULT boot order 0xf41 - tries SD, USB-MSD, then RESTART${default}"
elif [[ "$output4" != "" ]]; then
  echo "${yellow}R to L - 1-SD, 2-NET, 3-RPI, 4-USB-MSD, 6-NVME, 7-HTTP, f-RESTART"
  echo "Non-Default $output4"
elif [[ "$output2" != "" ]]; then
  echo "${green}DEFAULT boot order 0xf41 in effect - no custom setting - tries SD, USB-MSD, then RESTART${default}"
fi

#read -p "${blue} Press key for more ${default}" -n1 -s
#echo
echo -e "${bold}${blue}  P C I / U S B   D E V I C E S"|pad
lspci
lsusb

#read -p "${blue} Press key for neofetch ${default}" -n1 -s
#neofetch
#read -p "${blue} Press key for cpufetch ${default}" -n1 -s
#cpufetch
#read -p "${blue} Press key for btop ${default}" -n1 -s
#btop
echo
