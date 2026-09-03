#!/bin/bash

# Real path of this script, with every symbolic link resolved. It matters when the
# script is called through a link in a "bin" folder, a common way of turning it into
# a regular terminal command: without resolving the link, the setups would be looked
# for beside the link instead of beside the script.
# [Ref(s).: https://stackoverflow.com/a/246128/3223785 ]
EZ_SMB_SYNC_PATH="$(readlink -f "$0" 2> /dev/null || echo "$0")"

# Absolute folder of this script, so that the setups are found no matter where it
# is called from.
EZ_SMB_SYNC_DIR="$(cd "$(dirname "$EZ_SMB_SYNC_PATH")" && pwd)"

# Folder holding the configuration profiles ("setups").
CONFIGS_DIR="$EZ_SMB_SYNC_DIR/configs"

# Name of the template, which is not a usable setup and is never listed.
CONFIG_MODEL_NAME="my_config_model"

# Seconds to wait for a host while checking whether it is up. Kept short so that
# listing many setups stays quick.
SETUP_PROBE_TIMEOUT=2

# Name the user actually typed. Through a link in a "bin" folder that is the
# command they know, which is what a message telling them how to come back should
# use -- not the real file name behind it.
INVOKED_AS="$(basename "$0")"

# Prefix of every log line. It becomes the setup name once one is chosen, so that
# several terminals running different setups can be told apart. Until then there is
# no setup to name, and the messages of the selection stage carry no prefix at all.
LOG_TAG="$(basename "$EZ_SMB_SYNC_PATH")"

# Guard against the sourcing line that older profiles carry on their last line,
# which loads this engine. Without it, loading such a profile would load this
# engine a second time, recursively.
if [ -n "$EZ_SMB_SYNC_LOADED" ]; then
    return 0 2> /dev/null || exit 0
fi
EZ_SMB_SYNC_LOADED=1

f_setup_value() {
    : 'Read one value out of a setup.

    The file is parsed instead of being loaded, so that listing the setups never
    runs the code of a configuration profile.

    Args:
        SETUP_FILE (str): Path of the configuration profile.
        FIELD_NAME (str): Name of the parameter to read.

    Returns:
        The value, on the standard output. Empty when the parameter is not there.'

    local SETUP_FILE="$1"
    local FIELD_NAME="$2"
    local FIELD_VALUE=""

    FIELD_VALUE="$(grep -m 1 "^[[:space:]]*${FIELD_NAME}=" "$SETUP_FILE" 2> /dev/null)"
    [ -n "$FIELD_VALUE" ] || return 0

    # Drop the variable name, the surrounding whitespace and the quotes.
    FIELD_VALUE="${FIELD_VALUE#*=}"
    FIELD_VALUE="${FIELD_VALUE#"${FIELD_VALUE%%[![:space:]]*}"}"
    FIELD_VALUE="${FIELD_VALUE%"${FIELD_VALUE##*[![:space:]]}"}"
    FIELD_VALUE="${FIELD_VALUE#[\'\"]}"
    FIELD_VALUE="${FIELD_VALUE%[\'\"]}"

    # A home written as "$HOME" or "~" is common enough to be worth resolving.
    # Nothing else is expanded: the value is data here, and running it to find
    # out what it says is exactly what parsing avoids.
    FIELD_VALUE="${FIELD_VALUE//\$\{HOME\}/$HOME}"
    FIELD_VALUE="${FIELD_VALUE//\$HOME/$HOME}"
    case "$FIELD_VALUE" in
        "~"|"~/"*) FIELD_VALUE="$HOME${FIELD_VALUE#\~}" ;;
    esac

    printf '%s\n' "$FIELD_VALUE"
}

f_setup_host() {
    : 'Extract the host of a setup, out of its "NET_SHARE_REMOTE" value.

    Args:
        SETUP_FILE (str): Path of the configuration profile.

    Returns:
        The host name or IP, on the standard output. Empty when it cannot be
    determined.'

    local REMOTE_VALUE=""
    local HOST_VALUE=""

    REMOTE_VALUE="$(f_setup_value "$1" "NET_SHARE_REMOTE")"
    [ -n "$REMOTE_VALUE" ] || return 0

    # "//HOST/SHARE" -> "HOST".
    HOST_VALUE="${REMOTE_VALUE#//}"
    HOST_VALUE="${HOST_VALUE%%/*}"

    printf '%s\n' "$HOST_VALUE"
}

f_setup_is_mounted() {
    : 'Tell whether the share of a setup is already mounted.

    Args:
        SETUP_FILE (str): Path of the configuration profile.

    Returns:
        0 when the mount point of the setup is already a mount point, 1 otherwise.'

    local MOUNT_VALUE=""

    MOUNT_VALUE="$(f_setup_value "$1" "DIR_MOUNT_REMOTE")"
    [ -n "$MOUNT_VALUE" ] || return 1

    mountpoint -q "$MOUNT_VALUE" 2> /dev/null
}

f_host_is_up() {
    : 'Tell whether a host is answering on a Samba port.

    The SMB port itself is probed, not ICMP: a host that answers a ping but has no
    Samba service running is of no use here, and many hosts drop ICMP altogether.

    Args:
        HOST_VALUE (str): Host name or IP.

    Returns:
        0 when the host answers, 1 otherwise.'

    local HOST_VALUE="$1"
    local PORT_VALUE=""

    [ -n "$HOST_VALUE" ] || return 1

    # 445 is the modern SMB port, 139 the legacy NetBIOS one, still used by old
    # servers.
    for PORT_VALUE in 445 139; do
        if timeout "$SETUP_PROBE_TIMEOUT" bash -c \
                "exec 3<>/dev/tcp/$HOST_VALUE/$PORT_VALUE" 2> /dev/null; then
            return 0
        fi
    done

    return 1
}

f_select_setup() {
    : 'List the reachable setups and let the user choose one.

    Returns:
        The path of the chosen configuration profile, on the standard output.
        1 when there is nothing to choose from or the choice is invalid, 2 when
    the answer was to leave.'

    local SETUP_FILE=""
    local SETUP_NAME=""
    local HOST_VALUE=""
    local MARK_VALUE=""
    local CHOICE_VALUE=""
    local INDEX_VALUE=0
    local SETUP_PATHS=()
    local SETUP_LABELS=()

    if [ ! -d "$CONFIGS_DIR" ]; then
        echo "The \"$CONFIGS_DIR\" folder does not exist." >&2
        return 1
    fi

    for SETUP_FILE in "$CONFIGS_DIR"/*.bash; do
        [ -f "$SETUP_FILE" ] || continue

        SETUP_NAME="$(basename "$SETUP_FILE" .bash)"

        # The template is not a setup.
        [ "$SETUP_NAME" == "$CONFIG_MODEL_NAME" ] && continue

        HOST_VALUE="$(f_setup_host "$SETUP_FILE")"

        # An already mounted share is listed whatever its host is doing: it may
        # well have gone away underneath, and reattaching is how the mount gets
        # synced and taken down properly. An unmounted one is only worth offering
        # when there is something at the other end to mount from.
        MARK_VALUE=""
        if f_setup_is_mounted "$SETUP_FILE"; then
            MARK_VALUE="[reattach]"
        else
            f_host_is_up "$HOST_VALUE" || continue
        fi

        SETUP_PATHS+=("$SETUP_FILE")
        # A space is kept between the fields, so that a name longer than its
        # column pushes the rest along instead of running into it.
        SETUP_LABELS+=("$(printf '%-29s %-18s %s' "$SETUP_NAME" "$HOST_VALUE" "$MARK_VALUE")")
    done

    if [ ${#SETUP_PATHS[@]} -eq 0 ]; then
        echo "No setup available (none with a host answering on Samba, none"\
" mounted)." >&2
        echo "Looked in \"$CONFIGS_DIR\"." >&2
        return 1
    fi

    echo "Available setups (host answering on Samba, or already mounted):" >&2
    for INDEX_VALUE in "${!SETUP_PATHS[@]}"; do
        printf '  %2d) %s\n' "$((INDEX_VALUE + 1))" "${SETUP_LABELS[$INDEX_VALUE]}" >&2
    done

    read -r -p "number or 0/quit: " CHOICE_VALUE

    # Leaving without picking anything is a normal way out, not a mistake, so it
    # gets its own status for the caller to tell the two apart.
    case "$CHOICE_VALUE" in
        0|"quit") return 2 ;;
    esac

    case "$CHOICE_VALUE" in
        ''|*[!0-9]*)
            echo "Invalid choice." >&2
            return 1
            ;;
    esac
    if [ "$CHOICE_VALUE" -lt 1 ] || [ "$CHOICE_VALUE" -gt ${#SETUP_PATHS[@]} ]; then
        echo "Invalid choice." >&2
        return 1
    fi

    printf '%s\n' "${SETUP_PATHS[$((CHOICE_VALUE - 1))]}"
}

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

    echo "--- [[ $LOG_TAG ]] CONFIG ERROR: $1"
    CONFIG_ERRORS=$((CONFIG_ERRORS + 1))
}

f_default_to() {
    : 'Apply a default to a parameter that was left empty.

    Args:
        FIELD_NAME (str): Name of the parameter.
        DEFAULT_VALUE (str): What to use when it is empty.'

    [ -n "${!1}" ] || printf -v "$1" '%s' "$2"
}

f_must_be_boolean() {
    : 'Reject a parameter that is neither 0 nor 1.

    These end up in arithmetic tests, which abort the script with a syntax error
    when the value is not a number, so they are worth catching early.

    Args:
        FIELD_NAME (str): Name of the parameter.'

    case "${!1}" in
        0|1) ;;
        *) f_config_error "\"$1\" must be 0 or 1, got \"${!1}\"." ;;
    esac
}

f_must_be_set() {
    : 'Reject a parameter that is required and empty.

    Args:
        FIELD_NAME (str): Name of the parameter.
        WHEN_VALUE (Optional[str]): What makes it required, when it is not always.

    Returns:
        0 when it is there, 1 otherwise, so that a further check can be chained
    onto it and not fire on an empty value.'

    if [ -z "${!1}" ]; then
        f_config_error "\"$1\" is required${2:-}."
        return 1
    fi

    return 0
}

f_must_be_dir() {
    : 'Reject a parameter that does not point at an existing directory.

    Args:
        FIELD_NAME (str): Name of the parameter.

    Returns:
        0 when it is a directory, 1 otherwise.'

    [ -n "${!1}" ] || return 1

    if [ ! -d "${!1}" ]; then
        f_config_error "\"$1\" (\"${!1}\") is not an existing directory."
        return 1
    fi

    return 0
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
    f_default_to SYNC_ENABLED 0
    f_default_to ONE_WAY_SYNC_FROM_REMOTE 1
    f_default_to AUTO_DETACH 0

    DIR_MOUNT_REMOTE="$(f_clean_path "$DIR_MOUNT_REMOTE")"
    DIR_MOUNT_SYNC_REMOTE="$(f_clean_path "$DIR_MOUNT_SYNC_REMOTE")"
    DIR_MOUNT_SYNC_LOCAL="$(f_clean_path "$DIR_MOUNT_SYNC_LOCAL")"
    NET_SHARE_REMOTE="$(f_clean_path "$NET_SHARE_REMOTE")"

    # These two are used in arithmetic tests, which abort the script with a syntax
    # error when the value is not a number.
    f_must_be_boolean SYNC_ENABLED
    f_must_be_boolean ONE_WAY_SYNC_FROM_REMOTE
    f_must_be_boolean AUTO_DETACH

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

    f_must_be_set NET_SHARE_USER

    if f_must_be_set NET_SHARE_REMOTE; then
        case "$NET_SHARE_REMOTE" in
            //?*/?*) ;;
            *) f_config_error "\"NET_SHARE_REMOTE\" (\"$NET_SHARE_REMOTE\") must be"\
" in the \"//IP_OR_NAME/SHARE_NAME\" form." ;;
        esac
    fi

    f_must_be_set DIR_MOUNT_REMOTE && f_must_be_dir DIR_MOUNT_REMOTE

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

        f_must_be_set DIR_MOUNT_SYNC_LOCAL " when \"SYNC_ENABLED\" is 1" &&\
            f_must_be_dir DIR_MOUNT_SYNC_LOCAL

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
    : 'Provide an interactive prompt.

    Each option answers to a number and to a name: "1" and "sync" do the same
    thing. The number is there to be read off the line the prompt prints, without
    having to remember anything; the name is there for the hand that already
    knows it.'

    local COMMAND_VALUE=""
    while :; do
        case "$COMMAND_VALUE" in
            "1"|"sync")
                f_run_unison "by command"
                ;;
            "2"|"owsfr")
                f_run_unison "by command" "owsfr"
                ;;
            "3"|"owsfl")
                f_run_unison "by command" "owsfl"
                ;;
            "4"|"detach")
                # Leaving the share mounted is the point of this one: the work
                # carries on outside, and this setup shows up in the list marked
                # as mounted, ready to be picked again.
                echo "--- [[ $LOG_TAG ]] Detaching, the share stays mounted! "
                f_run_unison "final"

                echo "--- [[ $LOG_TAG ]] Still mounted on"\
" \"$DIR_MOUNT_REMOTE\". Come back to it by picking it from the list, or with"\
" \"$INVOKED_AS $LOG_TAG\"."

                break
                ;;
            "5"|"quit")
                echo "--- [[ $LOG_TAG ]] Trying to quit! "
                f_run_unison "final"

                # Try unmounting the share if it is still mounted.
                f_unmount_share

                break
                ;;
            "6"|"help")
                    echo "--- [[ $LOG_TAG ]]
 INSTRUCTIONS (by number or by name, they do the same):
  1/sync - Synchronize according to the \"ONE_WAY_SYNC_FROM_REMOTE\" parameter.
  2/owsfr - Force a one way sync (mirroring, CAUTION!) from remote.
  3/owsfl - Force a one way sync (mirroring, CAUTION!) from local.
  4/detach - Sync one last time and leave, KEEPING the share mounted. It shows
      up in the list marked \"[reattach]\" for you to pick up later.
  5/quit - Sync one last time, unmount the share and leave. Good bye.
  6/help - This list."
                ;;
            *)
                if [ -n "$COMMAND_VALUE" ]; then
                    echo "--- [[ $LOG_TAG ]] Unknown option \"$COMMAND_VALUE\"!"\
" Use 6/help for details."
                fi
                ;;
        esac

        # NOTE: On end-of-file (Ctrl+D, or stdin not interactive) "read" fails and
        # clears the variable. Without treating that failure, the empty value would
        # fall into the "*)" branch, which stays silent for empty input, and the loop
        # would spin forever at full CPU without ever running the final sync and the
        # unmount. Turning end-of-file into a "5" makes it take the regular exit
        # path. The "-r" prevents backslashes in the input from being interpreted.
        read -r COMMAND_VALUE || COMMAND_VALUE="5"
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
            echo "--- [[ $LOG_TAG ]] ---------------------------------- "\
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

                echo "--- [[ $LOG_TAG ]] One way sync from local (command)."
            elif [ "$SYNC_MODE_FROM_CMD" == "owsfr" ]; then
                UNISON_CMD+=(-force "$DIR_MOUNT_SYNC_REMOTE_NOW")
                echo "--- [[ $LOG_TAG ]] One way sync from remote (command)."
            elif [ ${ONE_WAY_SYNC_FROM_REMOTE} -eq 1 ]; then
                UNISON_CMD+=(-force "$DIR_MOUNT_SYNC_REMOTE_NOW")
                echo "--- [[ $LOG_TAG ]] One way sync from remote enabled."
            fi

            "${UNISON_CMD[@]}"
            echo "--- [[ $LOG_TAG ]] -----------------------------------"\
"------------------------------------------------------------------ "
        fi

    else
        echo "--- [[ $LOG_TAG ]] Sync disabled."
    fi
}

f_unmount_share() {
    : 'Unmount the Samba share.

    Unmount the Samba share if conditions exist. When the regular forced unmount
    fails, which usually means something is still using the share, offer a lazy
    unmount ("-l") after warning about what it implies.'

    ( mountpoint -q "$DIR_MOUNT_REMOTE" ) || return 0

    echo "--- [[ $LOG_TAG ]] Unmounting the network path! "
    if sudo umount -f "$DIR_MOUNT_REMOTE"; then
        return 0
    fi

    echo "--- [[ $LOG_TAG ]] The share could not be unmounted. It is busy: something"\
" is still using \"$DIR_MOUNT_REMOTE\"."

    # Point at the culprits when possible, so that the decision below is an informed
    # one instead of a guess.
    if command -v fuser > /dev/null 2>&1; then
        echo "--- [[ $LOG_TAG ]] What is holding it:"
        fuser -vm "$DIR_MOUNT_REMOTE" 2>&1 | sed 's/^/    /'
    else
        echo "--- [[ $LOG_TAG ]] Install \"psmisc\" to see what is holding it"\
" (\"fuser -vm\")."
    fi

    echo "
--- [[ $LOG_TAG ]]

 !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! WARNING !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
 Close whatever still depends on this share BEFORE forcing it. A terminal sitting
 inside the folder, an editor with an open file, a running build -- any of them
 keeps the share busy.

 A lazy unmount (\"umount -l\") detaches the folder right away and only releases
 it once nothing uses it any more. Whatever is still writing at that moment may
 never reach the server, so DATA CAN BE LOST.
 !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! WARNING !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
"

    local ANSWER_VALUE=""
    read -r -p "Force the unmount anyway? [y/N]: " ANSWER_VALUE || ANSWER_VALUE=""

    case "$ANSWER_VALUE" in
        [yY]|[yY][eE][sS])
            echo "--- [[ $LOG_TAG ]] Forcing a lazy unmount! "
            if sudo umount -l "$DIR_MOUNT_REMOTE"; then
                echo "--- [[ $LOG_TAG ]] Detached. It is released once nothing uses"\
" it any more."
            else
                echo "--- [[ $LOG_TAG ]] Even the lazy unmount failed. Unmount it by"\
" hand later: \"sudo umount -l $DIR_MOUNT_REMOTE\"."
            fi
            ;;
        *)
            echo "--- [[ $LOG_TAG ]] Left mounted, as requested. Unmount it when you"\
" are done: \"sudo umount $DIR_MOUNT_REMOTE\"."
            ;;
    esac
}

# When this file is executed directly it drives everything: it lists the setups,
# asks which one to use and loads it. When it is loaded by an older profile, which
# carries a sourcing line on its last line, the variables are already in place and
# there is nothing to choose.
# [Ref(s).: https://stackoverflow.com/a/2684300/3223785 ]
if [ "${BASH_SOURCE[0]}" == "$0" ]; then
    if [ -n "${1:-}" ]; then
        # Naming a setup goes straight to it, past the filters of the list. That
        # is the way back to a share the list will not show any more: one left
        # mounted on purpose, after the unmount was declined, still needs a run to
        # sync it and to unmount it properly.
        if [ -f "$1" ]; then
            SETUP_PATH="$1"
        elif [ -f "$CONFIGS_DIR/$1.bash" ]; then
            SETUP_PATH="$CONFIGS_DIR/$1.bash"
        else
            echo "There is no setup called \"$1\" in \"$CONFIGS_DIR\"." >&2
            echo "What is there:" >&2
            for SETUP_FILE in "$CONFIGS_DIR"/*.bash; do
                [ -f "$SETUP_FILE" ] || continue
                SETUP_NAME="$(basename "$SETUP_FILE" .bash)"
                [ "$SETUP_NAME" == "$CONFIG_MODEL_NAME" ] && continue
                echo "  $SETUP_NAME" >&2
            done
            exit 1
        fi
    else
        SETUP_PATH="$(f_select_setup)"
        SELECT_STATUS=$?
        if [ ${SELECT_STATUS} -eq 2 ]; then
            # Asked to leave. Nothing was mounted, so there is nothing to undo.
            exit 0
        elif [ ${SELECT_STATUS} -ne 0 ]; then
            exit 1
        fi
    fi

    LOG_TAG="$(basename "$SETUP_PATH" .bash)"
    echo "--- [[ $LOG_TAG ]] Setup loaded. "

    # NOTE: The profile only assigns variables, so loading it has no side effect.
    # The guard at the top of this file keeps an older profile, which still carries
    # the sourcing line, from loading this engine all over again.
    # shellcheck source=/dev/null
    . "$SETUP_PATH"
fi

# Check the configuration before touching anything.
if ! f_check_config ; then
    echo "--- [[ $LOG_TAG ]] Fix the configuration above and try again! :("
    exit 1
fi

# Whether the share was already there when this run started. It decides whether
# AUTO_DETACH applies: leaving at once makes sense for a run that mounted the
# share and has nothing else to do, but not for one that was asked to reattach to
# a share already up -- that was asked for on purpose, and the prompt is the point
# of it.
WAS_MOUNTED=0
( mountpoint -q "$DIR_MOUNT_REMOTE" ) && WAS_MOUNTED=1

# Mount the Samba share if conditions exist.
if ( ! mountpoint -q "$DIR_MOUNT_REMOTE" ) ; then
    echo "--- [[ $LOG_TAG ]] Trying to mount the network path! "
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
    echo "--- [[ $LOG_TAG ]] Hey! The remote directory is already mounted! ;)"
fi

# Starts the script's interactive prompt and control scheme if conditions exist.
if ( mountpoint -q "$DIR_MOUNT_REMOTE" ) ; then
    f_ask_support
    f_run_unison "initial"

    if [ ${AUTO_DETACH} -eq 1 ] && [ ${WAS_MOUNTED} -eq 0 ]; then
        # Mount, sync, and get out of the way. The prompt is the whole point of
        # the script for interactive use, but it is in the way when all you want
        # is the share in place -- from a login script, or before a session of
        # work that happens entirely outside here.
        echo "--- [[ $LOG_TAG ]] Auto detach: mounted and leaving, the share"\
" stays up! "
        echo "--- [[ $LOG_TAG ]] Mounted on \"$DIR_MOUNT_REMOTE\". Come back to"\
" it by picking it from the list, or with \"$INVOKED_AS $LOG_TAG\"."
    else
        echo "
--- [[ $LOG_TAG ]]

 !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! WARNING !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
            To stop the script type \"5/quit\" and press Enter!
 !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! WARNING !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

 1/sync, 2/owsfr, 3/owsfl, 4/detach, 5/quit, or 6/help for details.
"
        f_provide_prompt
    fi
else
    echo "--- [[ $LOG_TAG ]] Crap! The directory can not be mounted! :("
fi

echo "--- [[ $LOG_TAG ]] Script ended! Thanks! :) [<o>] Brazil-DF"

exit 0
