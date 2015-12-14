
KEEP_RUNNING=1

# Note: Obtêm o nome do script p/ identifica-lo quando há varios abertos! By Questor
SCRIPT_FN="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

# Note: Permite digitar um comando para sair do script! By Questor
script_quit() {
    count=0
    commandValue=''
    while [ ${KEEP_RUNNING} -eq 1 ] ; do
        if [ "$commandValue" = "quit" ]; then
            echo "--- [[ $SCRIPT_FN ]] Trying to quit! "

            # Note: Permite a sincronização de mudanças que ocorreram quando o script estava rodando! By Questor
            unison_excuter "final"

            # Note: Tenta desmontar o share caso tenha restado montado! By Questor
            unmount_share

            KEEP_RUNNING=0
            break
        fi
        if [ "$commandValue" = "sync" ]; then

            # Note: Permite a sincronização de mudanças que ocorreram quando o script estava rodando! By Questor
            unison_excuter "by command"
        fi
        read commandValue
    done
}

unison_excuter() {
    if [ ${SYNC_ENABLED} -eq 1 ] ; then
        EXECUTER=$1
        # Note: Só permite sincronização se o diretório do guest estiver efetivamente acessível! By Questor
        if [ "$(ls -A $DIR_MOUNT_SYNC_REMOTE)" ] && [ ${KEEP_RUNNING} -eq 1 ] ; then
            echo "--- [[ $SCRIPT_FN ]] ---------------------------------- Unison \"$EXECUTER\" execution! ---------------------------------- "
            # unison -auto -perms 0 -batch "$DIR_MOUNT_SYNC_LOCAL" "$DIR_MOUNT_SYNC_REMOTE"
            unison -auto -force newer -perms=0 -batch "$DIR_MOUNT_SYNC_LOCAL" "$DIR_MOUNT_SYNC_REMOTE"
            echo "--- [[ $SCRIPT_FN ]] ----------------------------------------------------------------------------------------------------- "
        fi
    fi
}

# Note: Desmonta o "samba share" do guest! By Questor
unmount_share() {
    if mountpoint -q "$DIR_MOUNT_REMOTE" ; then
        echo "--- [[ $SCRIPT_FN ]] Unmounting the network path! "
        sudo umount "$DIR_MOUNT_REMOTE"
    fi
}

# Note: Verifica se o share já está montado. Se não estiver o monta! By Questor
if ! mountpoint -q "$DIR_MOUNT_REMOTE" ; then
    echo "--- [[ $SCRIPT_FN ]] Trying to mount the network path! "

    # Note: A configuração abaixo é valida, também, com o Wine. Para não haver falhas com o Wine faz-se necessário o parâmetro "nounix"! By Questor
    sudo mount -t cifs -o noperm,username="$NET_SHARE_USER",password="$NET_SHARE_PSW",uid=1000,cache=none,auto,nounix "$NET_SHARE_REMOTE" "$DIR_MOUNT_REMOTE"
fi

# Note: Verifica se o share foi montado e inicia verificador de comando para "quit"! By Questor
# Note: "[ $? -eq 0 ]" verifica a saída de "mount" (último comando executado)! By Questor
if [ $? -eq 0 ] ; then

    if mountpoint -q "$DIR_MOUNT_REMOTE" ; then

        # Note: Permite a sincronização de mudanças que ocorreram quando o script estava desligado! By Questor
        unison_excuter "initial"
    fi

    echo " "
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! WARNING !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "--- [[ $SCRIPT_FN ]] To stop the script use the command \"quit\" and press Enter! "
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! WARNING !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo " "

    # Note: O "script_quit" tem que ser o último, pois caso contrário não apanha o comando do teclado! By Questor
    script_quit
else
    echo "--- [[ $SCRIPT_FN ]] Crap! The directory can not be mounted! :( "
fi

echo "--- [[ $SCRIPT_FN ]] Script ended! Thanks! :) "

# Note: Tentativa de garantir que nenhum processo reste! By Questor
KEEP_RUNNING=0
exit=0
