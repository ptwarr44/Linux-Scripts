#!/bin/bash
# Auther: Patrick Warren
# Date: 05/18/2021
# Description: First version of the script will successfully remove a multipath (SAN Storage) LUN
# from the server. Script built and tested in RHEL v8.
# This assumes device-mapper-multipath is installed.
############################################################
# Help                                                     #
############################################################
function Help()
{
	# Display Help
	echo "dmcli is used to add or remove a disk."
	echo
	echo "Usage: dmcli [--help][--add][--delete dev]"
	echo
	echo "Where:"
	echo "	-h|--help			Print this Help."
	echo "	-a|--add			Add a new disk."
	echo "	-d|--delete dev			Remove a disk."
	echo
}

############################################################
# Add a disk                                               #
############################################################
function Add()
{
	# Scan the bus
	echo "Scanning for new disks."
	echo
	# Add disks
	if [ -d "/sys/class/fc_host/" ]
	then
		# Scan FC adapters if present
		for BUS in /sys/class/fc_host/host*/issue_lip; 
		do 
			echo 1 > /sys/class/fc_host/host${i}/issue_lip
		done
	fi
	
	# Scan for new disks
	for BUS in /sys/class/scsi_host/host*/scan
	do
		echo "- - -" >  ${BUS}
	done
}

############################################################
# Delete a disk                                            #
############################################################
function Delete()
{

	local lun_id="$1"

	# Check if disk exists
	DISKEXISTS=$(fdisk -l | grep $lun_id | wc -l)
	if [ $DISKEXISTS = 0 ]
	then
		echo "Disk $lun_id does not exist. Exiting."
		exit 0
	else
		echo "Disk $lun_id exists!"
		echo
		if [[ $lun_id = s* ]]
		then
			lsscsi | grep $lun_id > /tmp/"$lun_id".txt
		elif [[ $lun_id = m* ]]
		then
			multipath -ll $lun_id | grep ready | sed 's/^.//' | awk '{print $2}' > /tmp/"$lun_id".txt;
		fi
	fi

	# Display selected LUN
	echo "Target device: $lun_id." >> /tmp/"$lun_id".txt
	echo
	echo >> /tmp/"$lun_id".txt

	# If the disk does not exist, stop the script
	CHECK_EMPTY=$(cat /tmp/"$lun_id".txt | wc -l)
	if [ $CHECK_EMPTY = 0 ]
	then
		echo "Disk does not exist or error occurred from multipath output." >> /tmp/"$lun_id".txt
		exit 0
	fi

	CHECKPVS=$(pvs | grep $lun_id | grep -v "/var/spool/mail/root" | wc -l)
	CHECKDF=$(df -h | grep $lun_id | wc -l)
	if [ $CHECKPVS = 0 ] && [ $CHECKDF = 0 ]
	then
		echo "Disk not used and ready for removal."
	else
		echo
		echo "Disk in use. Make sure these are complete:"
		echo "	1) Unmount filesystems using the physical volume."
		echo "	2) Reduce the physical volume from the volume group."
		echo "	3) Run pvremove on the physical volume."
		echo
		echo "Processes using $lun_id"
		lsof | grep $lun_id
		echo
		exit 0
	fi

	while true;
	do
		disk_type=$(cat /tmp/"$lun_id".txt | awk '{print $4}')
		
		#Confirm disk type
		if [[ $disk_type = "VRAID" ]]
		then
			# Redirect device information to /tmp
			echo "Device type is VRAID for disk $lun_id";
			echo "" >> /tmp/"$lun_id".txt;
			
			# Confirm removal
			while true; 
			do
				read -p "Ready to flush and remove multipath device $lun_id? (y/n): " yes_no
				
				case $yes_no in
					[yY]|[yY][eE][sS] ) 
						echo "Flushing device $lun_id" >> /tmp/"$lun_id".txt; 
						echo "multipath -f $lun_id"  >> /tmp/"$lun_id".txt; 
						echo "Flushing buffers." >> /tmp/"$lun_id".txt; 
						echo "blockdev --flushbufs $lun_id"  >> /tmp/"$lun_id".txt;
						break;;
					[nN]|[nN][oO] ) 
						echo "Not removing device $lun_id...Exiting";
						exit 0;;
					* ) 
						echo "Invalid response."
						;;
				esac
			done
				
		elif [[ $disk_type = "Virtual" ]]
		then
			# Redirect device information to /tmp
			echo "Device type is Virtual for disk $lun_id";
			echo "" >> /tmp/"$lun_id".txt;
			
			#Confrim Removal
			while true;
			do
				read -p "Ready to remove virtual disk device $lun_id? (y/n): " yes_no
				case $yes_no in
					[yY]|[yY][eE][sS] ) 
						echo "Deleting device $lun_id" >> /tmp/"$lun_id".txt; 
						echo echo 1 > /sys/block/$lun_id/device/delete; 
						exit 0;;
					[nN]|[nN][oO] ) 
						echo "Not removing device $lun_id...Exiting";
						exit 1;;
					* ) 
						echo "Invalid response."
						;;
				esac
			done		
		fi
	done
}
#############################################################
#############################################################
# Main program                                              #
#############################################################
#############################################################
#############################################################
# Print help for dmcli                                      #
#############################################################
no_arg=
# Get the options
while getopts ":had:" option; do
   case $option in
		h|--help) # display Help
			Help
			exit;;
		a|--add) # Scan the bus to add a disk
			Add
			exit;;
		d|--delete) # Delete a disk
			disk_arg="$OPTARG"
			Delete "$disk_arg"
			exit;;
		\?) # Invalid option
			echo "Error: Invalid option"
			Help
			exit 1;;
		:) # Option requires argument
			echo "Option -$OPTARG requires an argument." >&2
			exit 1;;
   esac
done

# Remove arguments associated with options
shift $((OPTIND-1))