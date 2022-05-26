#!/bin/bash
# Auther: Patrick Warren
# Date: 05/18/2021
# Description: First version of the script will successfully remove a multipath (SAN Storage) LUN
# from the server. Script built and tested in RHEL v8.
# This assumes device-mapper-multipath is installed when managing SAN LUNs.

# Create direcory if it does not exist.
DMCLI_DIR="/var/log/dmcli"
if [[ ! -d $DMCLI_DIR ]]
then
	mkdir $DMCLI_DIR
fi

############################################################
# Help                                                     #
############################################################
function Help()
{
	# Display Help
	echo "dmcli is used to add or remove a disk."
	echo
	echo "Usage: dmcli [-h][-a][-d disk]"
	echo
	echo "Where:"
	echo "	-h			Print this Help."
	echo "	-a			Add a new disk."
	echo "	-d disk			Remove a disk."
	echo
}

############################################################
# Add a disk                                               #
############################################################
function Add()
{
	# Save lsscsi info to file before bringing in a new disk
	echo "Saving lsscsi output to $DMCLI_DIR/lsscsi_pre-scan.txt"
	lsscsi -b > "$DMCLI_DIR/lsscsi_pre-scan.txt"

	# Add disks
	if [ -d "/sys/class/fc_host/" ]
	then
		echo "Fibre channel adapters found. Making OS aware of a new storage device."
		# Scan FC adapters if present
		for BUS in /sys/class/fc_host/host*/issue_lip; 
		do 
			echo 1 > /sys/class/fc_host/host${i}/issue_lip
		done
	fi
	
	# Scan for new disks
	echo "Scanning for new disks."
	for BUS in /sys/class/scsi_host/host*/scan
	do
		echo "- - -" >  ${BUS}
	done

	# Save lsscsi info to file before bringing in a new disk
	echo "Scanning complete"
	echo "Saving lsscsi output to $DMCLI_DIR/lsscsi_post-scan.txt"
	lsscsi -b > "$DMCLI_DIR/lsscsi_post-scan.txt"
	echo "Checking for new disks."
	echo "------------"
	diff "$DMCLI_DIR/lsscsi_post-scan.txt" "$DMCLI_DIR/lsscsi_pre-scan.txt" | grep dev > $DMCLI_DIR/lsscsi_new-disk.txt
	if [[ -s "$DMCLI_DIR/lsscsi_new-disk.txt" ]]
	then
		echo "New disk(s) found!" 
		cat "$DMCLI_DIR/lsscsi-new_disk.txt" | awk '{print $3}'
		echo "------------"
	else
		echo "No new disks. Disk size could have changed."
	fi
}

############################################################
# Delete a disk                                            #
############################################################
function Delete()
{

	local lun_id="$1"

	# Check if disk exists
	DISKEXISTS=$(fdisk -l | grep -e /dev/$lun_id -e /dev/mapper/$lun_id| wc -l)
	if [ $DISKEXISTS = 0 ]
	then
		echo "Disk $lun_id does not exist. Exiting."
		exit 0
	else
		echo "Disk $lun_id exists!"
		echo
		if [[ $lun_id = s* ]]
		then
			lsscsi | grep $lun_id > $DMCLI_DIR/$lun_id.txt
		elif [[ $lun_id = m* ]]
		then
			multipath -ll $lun_id | grep ready | sed 's/^.//' | awk '{print $2}' > $DMCLI_DIR/$lun_id.txt;
		fi
	fi

	# Display selected LUN
	echo "Target device: $lun_id." >> $DMCLI_DIR/$lun_id.txt
	echo >> $DMCLI_DIR/$lun_id.txt

	# If the disk does not exist, stop the script
	CHECK_EMPTY=$(cat $DMCLI_DIR/$lun_id.txt | wc -l)
	if [ $CHECK_EMPTY = 0 ]
	then
		echo "Disk does not exist or error occurred from multipath output." >> $DMCLI_DIR/$lun_id.txt
		exit 0
	fi

	# Find any phyiscal volume or mount point
	CHECKPVS=$(pvs | grep $lun_id | grep -v "/var/spool/mail/root" | wc -l)
	CHECKDF=$(df -h | grep $lun_id | wc -l)
	if [ $CHECKPVS = 0 ] && [ $CHECKDF = 0 ]
	then
		echo "Disk not used and ready for removal."
	else
		# Display any mount points
		CHECKMOUNT=$(df -h | grep $lun_id | wc -l)
		if [[ $CHECKMOUNT = 0 ]]
		then
			echo "No mount points being used by $lun_id at this time!"
			echo
		else
			echo "Mount points:"
			df -hT | grep $lun_id | grep -v "/var/spool/mail/root"
			echo
		fi

		# Display Physical Volumes
		echo "Physical volume attributes:" 
		pvs |  head -1 && pvs | grep $lun_id | grep -v "/var/spool/mail/root"
		echo

		# Check if any open files are using the disk
		CHECKLSOF=$(lsof | grep $lun_id | wc -l)
		if [[ $CHECKLSOF = 0 ]]
		then
			echo "No open files using $lun_id."
			echo
		else
			echo "Open files using $lun_id	;"
			lsof | grep $lun_id
			echo
		exit 0
		fi

		echo "Disk in use. Make sure these are complete:"
		echo "	1) Unmount filesystems using the physical volume."
		echo "	2) Reduce the physical volume from the volume group."
		echo "	3) Run pvremove on the physical volume."
		echo
	fi

	while true;
	do
		disk_type=$(cat $DMCLI_DIR/$lun_id.txt | awk '{print $4}')
		
		#Confirm disk type
		if [[ $disk_type = "VRAID" ]]
		then
			# Confirm removal
			while true; 
			do
				echo "If there is a phsical volume created on the disk, it will be restored when you bring the disk back in. Run pvremove to completely remove it."
				read -p "Ready to flush and remove multipath device $lun_id? (y/n): " yes_no
				case $yes_no in
					[yY]|[yY][eE][sS] ) 
						echo "Flushing device $lun_id" 
						echo "multipath -f $lun_id"
						echo
						echo "Flushing buffers." 
						echo "blockdev --flushbufs $lun_id"
						echo
						echo "Removing each path to the device."
						for path in `cat /$DMCLI_DIR/$lun_id`
						do
							echo 1 > /sys/class/scsi_device/$path/device/delete
							echo "Path $path has been removed."
						done
						echo
						echo "Please confirm the disk has been removed by viewing lsscsi, lsblk, fdisk, or multipath."
						break;;
					[nN]|[nN][oO] ) 
						echo "Not removing device $lun_id...Exiting"
						exit 0;;
					* ) 
						echo "Invalid response."
						;;
				esac
			done
				
		elif [[ $disk_type = "Virtual" ]]
		then			
			#Confrim Removal
			while true;
			do
				echo "If there is a phsical volume created on the disk, it will be restored when you bring the disk back in. Run pvremove to completely remove it." 
				read -p "Ready to remove virtual disk device $lun_id? (y/n): " yes_no
				case $yes_no in
					[yY]|[yY][eE][sS] ) 
						echo "Deleting device $lun_id" >> $DMCLI_DIR/$lun_id.txt; 
						echo 1 > /sys/block/$lun_id/device/delete; 
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
		h) # display Help
			Help;
			exit;;
		a) # Scan the bus to add a disk
			Add;
			exit;;
		d) # Delete a disk
			disk_arg="$OPTARG";
			Delete "$disk_arg";
			exit;;
		\?) # Invalid option
			echo "Error: Invalid option"
			echo
			Help;
			exit 1;;
		:) # Option requires argument
			echo "Option -$OPTARG requires an argument." >&2
			echo
			Help
			exit 1;;
   esac
done

# Remove arguments associated with options
shift $((OPTIND-1))

# Print help for missing flag
Help