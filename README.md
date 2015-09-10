ez_smb_sync - Synchronizing directories via network using samba or compatible networking protocol!
=============

<img border="0" alt="GrooVim Doc" src="http://imageshack.com/a/img829/4064/meg6.png" height="15%" width="15%">GrooVim Doc

What is ez_smb_sync?
-----

It's a shell script that uses "unison" for synchronizing directories via network using samba or compatible networking protocol. It's perfect for software development using virtualized environments (VMWare, VirtualBox...), enabling synchronizing them with local directory on your host. 
The synchronization occurs when you start or stop "ez_smb_sync" or if you type the "sync" command when "ez_smb_sync" is running.

How to use!
-----

 * Install "unison" (Debian based example)...

```
apt-get install unison
```

 * Make a copy of the file "model.sh" and give it a name to identify. Examples: "MyProject.sh", "MyClientName.sh" and so on...
    - I: This file must be in the same directory of "ez_smb_sync.sh" file;
    - II: For different targets use different copies of the file "model.sh". In that way you can have different settings for different targets easily;
    - III: The synchronization of directories is made bi-directionally.

 * Set the following attributes according to their descriptions in the "model.sh" copy:
    - NET_SHARE_REMOTE - Network path (Samba share);
    - DIR_MOUNT_SYNC_REMOTE - Directory where "ez_smb_sync" will mount the "NET_SHARE_REMOTE" network path;
    - DIR_MOUNT_SYNC_LOCAL - Directory which will be the local copy of "NET_SHARE_REMOTE" share.

```
# Note: Samba User! By Questor 
NET_SHARE_USER="username"
# Note: Samba Password! By Questor 
NET_SHARE_PSW="password"

# Note: "samba share" on remote machine! By Questor 
NET_SHARE_REMOTE="//IP_OR_NAME/DEV_REMOTE/PROJECT_NAME"

# Note: The folder to mount the "share" above! By Questor 
DIR_MOUNT_SYNC_REMOTE="/DEV_REMOTE/PROJECT_NAME"

# Note: Folder to synchronize the local copy! By Questor 
DIR_MOUNT_SYNC_LOCAL="/DEV_LOCAL/PROJECT_NAME"
```

 * Give execute permissions:

```
chmod a+x ez_smb_sync.sh
chmod a+x ModelCopy.sh
```

 * Open a terminal and run...

```
sh model_copy.sh
```

... and let the magic happen!

 * Commands - Type at the terminal while "MyProject.sh" ("ez_smb_sync.sh") is running:
    - quit - To exit;
    - sync - To start a synchronizing between "DIR_MOUNT_SYNC_REMOTE" and "DIR_MOUNT_SYNC_LOCAL" directories.

Contact
-----

groovimdoc@gmail.com

Brazil-DF

<img border="0" alt="GrooVim Doc" src="http://upload.wikimedia.org/wikipedia/commons/thumb/6/6d/Map_of_Brazil_with_flag.svg/180px-Map_of_Brazil_with_flag.svg.png" height="15%" width="15%">