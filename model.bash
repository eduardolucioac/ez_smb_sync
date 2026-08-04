#!/bin/bash

# EZ_SMB_SYNC - Configuration profile model.
#
# HOW TO USE THIS FILE:
#  1. Make a copy of this file and give it a name to identify the target. Examples:
# "my_project.bash", "my_client_name.bash" and so on. Use one copy per target, that
# way you keep different settings for different targets easily.
#  2. The copy must be in the SAME directory of the "ez_smb_sync.bash" file.
#  3. Fill in the parameters of the configuration block below.
#  4. Give it execute permission (e.g. "chmod u+x my_project.bash").
#  5. Run it from its own directory (e.g. "./my_project.bash").
#
# REQUIREMENTS:
#  . "unison", which performs the synchronization (Debian based example:
# "apt-get install unison");
#  . "cifs-utils", which allows mounting the samba share (Debian based example:
# "apt-get install cifs-utils");
#  . "sudo" rights, used to mount and to unmount the share. You may be asked for
# your password when the script starts and when it ends.
#
# SYNTAX WARNING:
#  There must be NO spaces around the "=" sign. In Bash "VAR = value" is not an
# assignment, it is an attempt to run a command named "VAR".
#
# SECURITY WARNING:
#  This file holds the share password in plain text. Keep it out of version control
# (the provided ".gitignore" already does that) and restrict its permissions with
# "chmod 600 my_project.bash".
#
# CONFIGURATION CHECK:
#  The parameters below are validated when the script starts. Surrounding spaces and
# trailing slashes of the paths are cleaned up automatically, and anything that would
# fail in a confusing way later on is reported right away, before mounting anything.

# > -----------------------------------------
# EZ_SMB_SYNC CONFIGURATION

# Domain name, if necessary. Leave it empty when the share does not require one.
# (Optional)
NET_SHARE_DOMAIN=''

# Remote share user name.
# (Required)
NET_SHARE_USER='user_name'

# Remote share password. It cannot contain a comma or a line break, because they
# would corrupt the option list of "mount". The script refuses to start in that case.
# (Required)
NET_SHARE_PSW='user_pwd'

# Local folder path to mount the remote share. It must already exist and it should be
# empty, since its content becomes hidden while the share is mounted over it.
# (Required)
DIR_MOUNT_REMOTE='/FOLDER_A/FOLDER_B'

# Remote share path, in the "//IP_OR_NAME/SHARE_NAME" form.
# (Required)
NET_SHARE_REMOTE='//IP_OR_NAME/FOLDER_A'

# Enables synchronization of the remote folder to a local folder. Set it to 0 to only
# mount the share, without synchronizing anything. In that case you needn't to inform
# "DIR_MOUNT_SYNC_REMOTE" and "DIR_MOUNT_SYNC_LOCAL".
# (Optional, Default 0)
SYNC_ENABLED=1

# Folder with the mounted remote share that you want to sync locally. It must be
# "DIR_MOUNT_REMOTE" itself or a folder inside it. Use it when you want to sync only
# a sub folder of the share.
# (Optional, Assumes "DIR_MOUNT_REMOTE" value if not informed and "SYNC_ENABLED=1")
DIR_MOUNT_SYNC_REMOTE=''

# Local folder for synchronization. It must already exist.
# (Required if "SYNC_ENABLED=1")
DIR_MOUNT_SYNC_LOCAL='/FOLDER_A/FOLDER_B/FOLDER_C'

# Synchronizes in one-way mode from the folder with the mounted remote share.
# CAUTION: A one way sync is a mirroring, so files that exist ONLY in the local folder
# are DELETED to make it identical to the remote one. Set it to 0 to synchronize in
# both directions, keeping what exists on each side.
# (Optional, Default 1)
ONE_WAY_SYNC_FROM_REMOTE=1

# < -----------------------------------------

# COMMANDS AVAILABLE WHILE THIS SCRIPT IS RUNNING:
#  . sync - Synchronize according to the "ONE_WAY_SYNC_FROM_REMOTE" parameter above;
#  . owsfr - Force a one way sync (mirroring, CAUTION!) from remote;
#  . owsfl - Force a one way sync (mirroring, CAUTION!) from local;
#  . help - Show the commands above;
#  . quit - Run a final synchronization, unmount the share and exit. Pressing Ctrl+D
# has the same effect.
#
# A synchronization also happens automatically when the script starts and when it
# ends, so changes made while it was running are never lost.

# I'm just a regular everyday normal guy with bills and family.
# This is an open-source project and will continue to be so forever.
# Please consider to deposit a donation through PayPal
# ( https://www.paypal.com/donate/?hosted_button_id=TANFQFHXMZDZE ).
# Support free software and my work! :)
# Set it to 1 to hide the donation notice when the script starts.
I_SUPPORT_FREE_SOFTWARE_N_THIS_WORK=0

# ez-smb-sync "inverted ©" BSD-3-Clause
# Eduardo Lúcio Amorim Costa
# Brazil-DF
# https://www.linkedin.com/in/eduardo-software-livre/

# This line runs "ez_smb_sync.bash". DO NOT REMOVE IT!
. ./ez_smb_sync.bash
