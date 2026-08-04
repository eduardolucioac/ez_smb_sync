#!/bin/bash

# Get the name of the script to identify it. Useful if there are several scripts
# running.
# [Ref(s).: https://stackoverflow.com/a/192337/3223785 ]
SCRIPT_FILENAME="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

function f_ask_support() {
    : 'Display a notice asking for a donation.'

    if [ -n "$I_SUPPORT_FREE_SOFTWARE_N_THIS_WORK" ] &&\
            [ "$I_SUPPORT_FREE_SOFTWARE_N_THIS_WORK" -eq 1 ]; then
        return
    fi

    echo " > ------------------- 
I'm just a regular everyday normal guy with bills and family.
This is an open-source project and will continue to be so forever.

Please consider to deposit a donation through PayPal 
( https://www.paypal.com/donate/?hosted_button_id=TANFQFHXMZDZE ).

Support free software and my work! S2
 < ------------------- "
}

f_config_error() {
    : 'Report a configuration problem and mark the configuration as unusable.

    Args:
        MESSAGE (str): Description of the problem.'

    echo "--- [[ $SCRIPT_FILENAME ]] CONFIG ERROR: $1"
    CONFIG_ERRORS=$((CONFIG_ERRORS + 1))
}

f_clean_path() {
    : 'Clean up a path informed in the configuration.

    Args:
        PATH_VALUE (str): Path to clean up.

    Returns:
        The cleaned up path, on the standard output.'

    local PATH_VALUE="$1"

    # Remove the surrounding whitespace, a common leftover of copying and pasting
    # paths into the configuration file.
    PATH_VALUE="${PATH_VALUE#"${PATH_VALUE%%[![:space:]]*}"}"
    PATH_VALUE="${PATH_VALUE%"${PATH_VALUE##*[![:space:]]}"}"

    # Remove the trailing slashes, keeping the root "/" untouched.
    while [ "${#PATH_VALUE}" -gt 1 ] && [ "${PATH_VALUE: -1}" == "/" ]; do
        PATH_VALUE="${PATH_VALUE%/}"
    done

    # NOTE: "printf" is used instead of "echo" so that a value starting with a dash
    # is not taken as an option.
    printf '%s\n' "$PATH_VALUE"
}

f_check_config() {
    : 'Validate and clean up the configuration parameters.

    Clean up what can be safely cleaned up (surrounding whitespace and trailing
    slashes of paths) and reject the values that would make "mount" or Unison fail in
    a way that is hard to diagnose. The user name, the domain and the password are
    never modified, since changing them would only turn an authentication failure
    into a confusing one.

    Returns:
        0 if the configuration is usable, 1 otherwise.'

    CONFIG_ERRORS=0

    # Apply the default values of the optional parameters.
    if [ -z "$SYNC_ENABLED" ]; then
        SYNC_ENABLED=0
    fi
    if [ -z "$ONE_WAY_SYNC_FROM_REMOTE" ]; then
        ONE_WAY_SYNC_FROM_REMOTE=1
    fi

    DIR_MOUNT_REMOTE="$(f_clean_path "$DIR_MOUNT_REMOTE")"
    DIR_MOUNT_SYNC_REMOTE="$(f_clean_path "$DIR_MOUNT_SYNC_REMOTE")"
    DIR_MOUNT_SYNC_LOCAL="$(f_clean_path "$DIR_MOUNT_SYNC_LOCAL")"
    NET_SHARE_REMOTE="$(f_clean_path "$NET_SHARE_REMOTE")"

    # These two are used in arithmetic tests, which abort the script with a syntax
    # error when the value is not a number.
    case "$SYNC_ENABLED" in
        0|1) ;;
        *) f_config_error "\"SYNC_ENABLED\" must be 0 or 1, got \"$SYNC_ENABLED\"." ;;
    esac
    case "$ONE_WAY_SYNC_FROM_REMOTE" in
        0|1) ;;
        *) f_config_error "\"ONE_WAY_SYNC_FROM_REMOTE\" must be 0 or 1, got"\
" \"$ONE_WAY_SYNC_FROM_REMOTE\"." ;;
    esac

    # A comma ends the current option of "mount", so a credential containing one
    # would be silently truncated. A line break would corrupt the option list too.
    local FIELD_NAME=""
    for FIELD_NAME in NET_SHARE_DOMAIN NET_SHARE_USER NET_SHARE_PSW; do
        case "${!FIELD_NAME}" in
            *,*) f_config_error "\"$FIELD_NAME\" cannot contain a comma, it is the"\
" option separator of \"mount\"." ;;
        esac
        case "${!FIELD_NAME}" in
            *$'\n'*) f_config_error "\"$FIELD_NAME\" cannot contain a line break." ;;
        esac
    done

    if [ -z "$NET_SHARE_USER" ]; then
        f_config_error "\"NET_SHARE_USER\" is required."
    fi

    if [ -z "$NET_SHARE_REMOTE" ]; then
        f_config_error "\"NET_SHARE_REMOTE\" is required."
    else
        case "$NET_SHARE_REMOTE" in
            //?*/?*) ;;
            *) f_config_error "\"NET_SHARE_REMOTE\" (\"$NET_SHARE_REMOTE\") must be"\
" in the \"//IP_OR_NAME/SHARE_NAME\" form." ;;
        esac
    fi

    if [ -z "$DIR_MOUNT_REMOTE" ]; then
        f_config_error "\"DIR_MOUNT_REMOTE\" is required."
    elif [ ! -d "$DIR_MOUNT_REMOTE" ]; then
        f_config_error "\"DIR_MOUNT_REMOTE\" (\"$DIR_MOUNT_REMOTE\") is not an"\
" existing directory."
    fi

    # "mount.cifs" usually lives in a "sbin" folder, which is not always in the PATH
    # of a regular user, so the usual locations are checked as well.
    if ! command -v mount.cifs > /dev/null 2>&1 &&\
            [ ! -x /sbin/mount.cifs ] && [ ! -x /usr/sbin/mount.cifs ]; then
        f_config_error "\"mount.cifs\" was not found. Install the \"cifs-utils\""\
" package."
    fi

    if [ "$SYNC_ENABLED" == "1" ]; then
        if ! command -v unison > /dev/null 2>&1 ; then
            f_config_error "\"unison\" was not found, but \"SYNC_ENABLED\" is 1."
        fi

        if [ -z "$DIR_MOUNT_SYNC_LOCAL" ]; then
            f_config_error "\"DIR_MOUNT_SYNC_LOCAL\" is required when"\
" \"SYNC_ENABLED\" is 1."
        elif [ ! -d "$DIR_MOUNT_SYNC_LOCAL" ]; then
            f_config_error "\"DIR_MOUNT_SYNC_LOCAL\" (\"$DIR_MOUNT_SYNC_LOCAL\") is"\
" not an existing directory."
        fi

        # The remote folder to synchronize has to be part of the share, otherwise it
        # would not receive anything from the remote machine.
        if [ -n "$DIR_MOUNT_SYNC_REMOTE" ] &&\
                [ "$DIR_MOUNT_SYNC_REMOTE" != "$DIR_MOUNT_REMOTE" ] &&\
                [ -n "${DIR_MOUNT_SYNC_REMOTE##"$DIR_MOUNT_REMOTE"/*}" ]; then
            f_config_error "\"DIR_MOUNT_SYNC_REMOTE\""\
" (\"$DIR_MOUNT_SYNC_REMOTE\") must be \"DIR_MOUNT_REMOTE\""\
" (\"$DIR_MOUNT_REMOTE\") or a folder inside it."
        fi

        # Synchronizing the share with a folder inside the share itself would make
        # Unison fight against its own changes.
        if [ -n "$DIR_MOUNT_SYNC_LOCAL" ] && [ -n "$DIR_MOUNT_REMOTE" ] &&\
                { [ "$DIR_MOUNT_SYNC_LOCAL" == "$DIR_MOUNT_REMOTE" ] ||\
                [ -z "${DIR_MOUNT_SYNC_LOCAL##"$DIR_MOUNT_REMOTE"/*}" ]; }; then
            f_config_error "\"DIR_MOUNT_SYNC_LOCAL\" (\"$DIR_MOUNT_SYNC_LOCAL\")"\
" cannot be \"DIR_MOUNT_REMOTE\" (\"$DIR_MOUNT_REMOTE\") or a folder inside it."
        fi
    fi

    if [ ${CONFIG_ERRORS} -gt 0 ]; then
        return 1
    fi

    return 0
}

f_provide_prompt() {
    : 'Provide an interactive prompt.'

    local COMMAND_VALUE=""
    while :; do
        case "$COMMAND_VALUE" in
            "quit")
                echo "--- [[ $SCRIPT_FILENAME ]] Trying to quit! "
                f_run_unison "final"

                # Try unmounting the share if it is still mounted.
                f_unmount_share

                break
                ;;
            "sync")
                f_run_unison "by command"
                ;;
            "owsfr")
                f_run_unison "by command" "owsfr"
                ;;
            "owsfl")
                f_run_unison "by command" "owsfl"
                ;;
            "help")
                    echo "--- [[ $SCRIPT_FILENAME ]]
 INSTRUCTIONS:
  . sync - Synchronize according to the \"ONE_WAY_SYNC_FROM_REMOTE\" parameter.
  . owsfr - Force a one way sync (mirroring, CAUTION!) from remote.
  . owsfl - Force a one way sync (mirroring, CAUTION!) from local.
  . quit - Good bye."
                ;;
            *)
                if [ -n "$COMMAND_VALUE" ]; then
                    echo "--- [[ $SCRIPT_FILENAME ]] Unknown command \"$COMMAND_VALUE\"! Use \"help\" for instructions."
                fi
                ;;
        esac

        # NOTE: On end-of-file (Ctrl+D, or stdin not interactive) "read" fails and
        # clears the variable. Without treating that failure, the empty value would
        # fall into the "*)" branch, which stays silent for empty input, and the loop
        # would spin forever at full CPU without ever running the final sync and the
        # unmount. Turning end-of-file into a "quit" makes it take the regular exit
        # path. The "-r" prevents backslashes in the input from being interpreted.
        read -r COMMAND_VALUE || COMMAND_VALUE="quit"
    done
}

f_run_unison() {
    : 'Run Unison.

    Run Unison if conditions exist.

    Args:
        EXECUTION_CONTEXT (str): Message indicating the execution context.
        SYNC_MODE_FROM_CMD (Optional[str]): owsfr - Force a one way sync (mirroring)
    from remote, owsfl - Force a one way sync (mirroring) from local. If not specified,
    the default sync mode is defined by the "ONE_WAY_SYNC_FROM_REMOTE" configuration
    parameter.'

    if [ -z "$SYNC_ENABLED" ] ; then
        SYNC_ENABLED=0
    fi

    if [ ${SYNC_ENABLED} -eq 1 ] ; then
        local EXECUTION_CONTEXT=$1
        local SYNC_MODE_FROM_CMD=$2

        if [ -z "$ONE_WAY_SYNC_FROM_REMOTE" ] ; then
            ONE_WAY_SYNC_FROM_REMOTE=1
        fi

        # Fall back to the mount point itself when no specific sub folder was
        # informed, otherwise use the informed one.
        local DIR_MOUNT_SYNC_REMOTE_NOW="$DIR_MOUNT_SYNC_REMOTE"
        if [ -z "$DIR_MOUNT_SYNC_REMOTE_NOW" ]; then
            DIR_MOUNT_SYNC_REMOTE_NOW="$DIR_MOUNT_REMOTE"
        fi

        # NOTE: The command 'ls -A "/some/path"' is used to list the contents of a
        # directory. The "-A" option stands for "almost all". It lists all files
        # and directories in the specified directory except for the special entries
        # "." (current directory) and ".." (parent directory). In other words, it
        # shows all the regular files and subdirectories within the specified directory
        # without listing the special entries. This way, it only allows synchronization
        # if the source directory is effectively mounted and accessible. It also
        # avoids accidents if the directory is empty for some reason.
        if ( mountpoint -q "$DIR_MOUNT_REMOTE" ) &&\
                [ -n "$(ls -A "$DIR_MOUNT_SYNC_REMOTE_NOW")" ] ; then
            echo "--- [[ $SCRIPT_FILENAME ]] ---------------------------------- "\
"Unison \"$EXECUTION_CONTEXT\" execution! ---------------------------------- "

            # NOTE: The command is built as an array so that every path is passed to
            # Unison as a single argument. Building it as a string and running it
            # through "bash -c" would break on paths containing spaces or quotes.
            local UNISON_CMD=(unison -auto -batch -perms 0 "$DIR_MOUNT_SYNC_REMOTE_NOW"\
 "$DIR_MOUNT_SYNC_LOCAL")
            # [Ref(s).: https://askubuntu.com/a/111131/134723 ]

            if [ "$SYNC_MODE_FROM_CMD" == "owsfl" ]; then

                UNISON_CMD+=(-force "$DIR_MOUNT_SYNC_LOCAL")
                # [Ref(s).: https://stackoverflow.com/a/54732719/3223785 ]

                echo "--- [[ $SCRIPT_FILENAME ]] One way sync from local (command)."
            elif [ "$SYNC_MODE_FROM_CMD" == "owsfr" ]; then
                UNISON_CMD+=(-force "$DIR_MOUNT_SYNC_REMOTE_NOW")
                echo "--- [[ $SCRIPT_FILENAME ]] One way sync from remote (command)."
            elif [ ${ONE_WAY_SYNC_FROM_REMOTE} -eq 1 ]; then
                UNISON_CMD+=(-force "$DIR_MOUNT_SYNC_REMOTE_NOW")
                echo "--- [[ $SCRIPT_FILENAME ]] One way sync from remote enabled."
            fi

            "${UNISON_CMD[@]}"
            echo "--- [[ $SCRIPT_FILENAME ]] -----------------------------------"\
"------------------------------------------------------------------ "
        fi

    else
        echo "--- [[ $SCRIPT_FILENAME ]] Sync disabled."
    fi
}

f_unmount_share() {
    : 'Unmount the Samba share.

    Unmount the Samba share if conditions exist.'

    if ( mountpoint -q "$DIR_MOUNT_REMOTE" ) ; then
        echo "--- [[ $SCRIPT_FILENAME ]] Unmounting the network path! "
        sudo umount -f "$DIR_MOUNT_REMOTE"
    fi
}

# Check the configuration before touching anything.
if ! f_check_config ; then
    echo "--- [[ $SCRIPT_FILENAME ]] Fix the configuration above and try again! :("
    exit 1
fi

# Mount the Samba share if conditions exist.
if ( ! mountpoint -q "$DIR_MOUNT_REMOTE" ) ; then
    echo "--- [[ $SCRIPT_FILENAME ]] Trying to mount the network path! "
    # NOTE: The options below are handed to "mount" as one single argument, so they
    # must NOT be wrapped in shell quotes. Values that would corrupt this list were
    # already rejected by "f_check_config".
    MOUNT_OPTIONS=""
    if [ -n "$NET_SHARE_DOMAIN" ]; then
        MOUNT_OPTIONS+="domain=$NET_SHARE_DOMAIN,"
    fi
    MOUNT_OPTIONS+="username=$NET_SHARE_USER,"
    if [ -n "$NET_SHARE_PSW" ]; then
        MOUNT_OPTIONS+="password=$NET_SHARE_PSW,"
    fi

    # The "nounix" parameter improves compatibility with applications like Wine.
    MOUNT_OPTIONS+="uid=$(id -u),gid=$(id -g),cache=none,nounix,auto"
# [Ref(s).: https://unix.stackexchange.com/a/503573/61742 ,
# https://unix.stackexchange.com/a/68081/61742 ]

    sudo mount -t cifs -o "$MOUNT_OPTIONS" "$NET_SHARE_REMOTE" "$DIR_MOUNT_REMOTE"
else
    echo "--- [[ $SCRIPT_FILENAME ]] Hey! The remote directory is already mounted! ;)"
fi

# Starts the script's interactive prompt and control scheme if conditions exist.
if ( mountpoint -q "$DIR_MOUNT_REMOTE" ) ; then
    f_ask_support
    f_run_unison "initial"
    echo "
--- [[ $SCRIPT_FILENAME ]]

 !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! WARNING !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
            To stop the script type \"quit\" command and press Enter!
 !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! WARNING !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

 Type \"help\" for options.
"
    f_provide_prompt
else
    echo "--- [[ $SCRIPT_FILENAME ]] Crap! The directory can not be mounted! :("
fi

echo "--- [[ $SCRIPT_FILENAME ]] Script ended! Thanks! :) [<o>] Brazil-DF"

exit 0
