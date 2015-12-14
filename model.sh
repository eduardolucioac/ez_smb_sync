#!/bin/bash

# User name/password to authenticate on samba share!
NET_SHARE_USER = "user_name"
NET_SHARE_PSW = "user_pwd"

# "samba share" on remote machine!
NET_SHARE_REMOTE = "//IP_OR_NAME/FOLDER_A"

# Folder to mount the "share" above!
DIR_MOUNT_REMOTE = "/FOLDER_A/FOLDER_B"

# Enable or disable synchronization. You needn't to inform 
# "DIR_MOUNT_SYNC_REMOTE" and "DIR_MOUNT_SYNC_LOCAL" if "SYNC_ENABLED" 
# is equal to 0!
SYNC_ENABLED=1

# Remote (mounted) diretory to synchronize!
DIR_MOUNT_SYNC_REMOTE = "/FOLDER_A/FOLDER_B/FOLDER_C"

# Local diretory to synchronize!
DIR_MOUNT_SYNC_LOCAL = "/FOLDER_A/FOLDER_B/FOLDER_C"

. ./ez_smb_sync.sh
