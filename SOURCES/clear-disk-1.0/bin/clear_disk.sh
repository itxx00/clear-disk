#! /bin/bash
PATH=/sbin:/usr/local/bin:/usr/bin:/bin:.:$PATH
workdir=$(cd $(dirname $0) && pwd)
logdir="$workdir/../log"
cd $workdir
[ -d $logdir ] || mkdir $logdir
TMP_CONF="${workdir}/../log/tmp.conf"

log_info() {
    local log_file="${workdir}/../log/clear_$(date +%Y%m).log"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] : INFO : $* "
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] : INFO : $* " >>$log_file
}

log_error() {
    local log_file="${workdir}/../log/clear_$(date +%Y%m).log"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] : ERROR: $*" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] : ERROR: $*" >>$log_file
}

load_config() {
    # read conf from clear.conf
    egrep -v '^#|^$' $workdir/../conf/clear.conf > $TMP_CONF
    # add a newline at end of file only if it doesn't end with newline
    sed -i -e '$a\' $TMP_CONF
    return 0
}

get_params() {
    filter_file="${workdir}/../conf/filter.conf"
    param=""
    dir=""
    file=""
    param=$(sed -n "${1}p" $TMP_CONF | awk '{print $2}')
    dir=$(sed -n "${1}p" $TMP_CONF | awk '{print $3}')
    file=$(sed -n "${1}p" $TMP_CONF | awk '{print $4}')

    echo $dir | grep -q "/$"
    if [ $? -ne 0 ]; then
        dir="${dir}/"
    fi
    
    # gen default filter conf
    if ! [ -f $filter_file ]; then
      cat > $filter_file <<EOF
/
/lib
/lib64
/usr/local
/usr/lib
/usr/lib64
/sbin
/bin
/usr/bin
/usr/sbin
/usr/local/bin
/usr/local/sbin
/dev
/proc
EOF
    fi

    for d in $(awk '{print $1}' $filter_file); do
        if [[ "$dir" = "$d" ]]; then
            log_error "danger path '$d', will not clean"
            return 1
        fi
    done

    echo "$file" | grep -q "/"
    if [ $? -eq 0 ]; then
        log_error "danger file name, contains '/'"
        return 1
    fi
    return 0
}

get_limit() {
    limit_conf="$(dirname ${workdir})/conf/limit.conf"
    if [ ! -f $limit_conf ]; then
        log_info "limit thres for mount point default to 70%"
        LIMIT=70
    else
        grep -v "#" $limit_conf | grep -q "${1}="
        if [ $? -eq 0 ]; then
            LIMIT=$(grep -v "#" $limit_conf | grep "${1}=" | head -n 1 | awk -F= '{print $2}')
        else
            LIMIT=$(grep -v "#" $limit_conf | grep "limit=" | head -n 1 | awk -F= '{print $2}')
        fi
    fi

    if [ "$LIMIT" = "" ]; then
        log_info "limit thres for mount point '$1' default to 70%"
        LIMIT=70
    else
        log_info "limit thres for mount point '$1' is ${LIMIT}%"
    fi
}

disk_exceeds_limit() {
    MSG=""
    for space in $(df -lhP | sed '1d' | egrep -v '^tmpfs|^devtmpfs' | awk '{print $5$6}'); do
        used_percent=$(echo $space | awk -F% '{print $1}')
        mount_point=$(echo $space | awk -F% '{print $2}')
        get_limit $mount_point
        if [ $used_percent -gt $LIMIT ]; then
            MSG=${MSG}"$mount_point used ${used_percent}%, more than ${LIMIT}%"
        fi
    done

    if [ "$MSG" = "" ]; then
        return 1
    else
        return 0
    fi
}

delete_file() {
    delete_tmp_file="${workdir}/../log/delete.tmp"
    get_params $*
    if [ $? -ne 0 ]; then 
        /bin/rm $delete_tmp_file
        return 1
    fi
    
    cmd="mtime"
    echo "$param" | grep -q "h$"
    if [ $? -eq 0 ]; then
        cmd="mmin"
        param=$(echo "$param" | sed -e "s/h//g")
        param=$(( $param * 60 ))
    fi

    echo "$param" | grep -q "m$"
    if [ $? -eq 0 ]; then
        cmd="mmin"
        param=$(echo "$param" | sed -e "s/m//g")
    fi

    if ! ls -d $dir >/dev/null 2>&1; then
        return
    fi
    #log_info "delete $param $dir $file"
    find ${dir} -path "${dir}${file}" -type f -$cmd "+$param" -print >$delete_tmp_file
    if [ $? -ne 0 ]; then
        log_error "failed to find file"
        /bin/rm $delete_tmp_file
        return 1
    fi
    file_num=$(cat $delete_tmp_file | wc -l)
    if [[ $file_num -eq 0 ]]; then
        #log_info "no file to be deleted"
        /bin/rm $delete_tmp_file
        return 0
    else
        log_info "find out $file_num files to be deleted"
    fi
    for f2d in $(cat $delete_tmp_file); do
        $RM $f2d
        if [ $? -ne 0 ]; then
            log_error "Delete $dir$f2d failed"
        fi
        sleep .5
    done
    log_info "Delete $dir$file complete"
    /bin/rm $delete_tmp_file
    return 0
}

clear_file() {
    clear_tmp_file="${workdir}/../log/clear.tmp"
    get_params $*
    if [ $? -ne 0 ]; then
        /bin/rm $clear_tmp_file
        return 1
    fi
    if ! ls -d $dir >/dev/null 2>&1; then
        return
    fi
    #log_info "delete $param $dir $file"
    find $dir -maxdepth 1 -name "$file" -type f -size +${param}k > $clear_tmp_file
    if [ $? -ne 0 ]; then
        log_error "failed to find file"
        /bin/rm $clear_tmp_file
        return 1
    fi
    file_num=$(cat $clear_tmp_file | wc -l)
    if [[ $file_num -eq 0 ]]; then
        #log_info "no file to be cleared"
        /bin/rm $clear_tmp_file
        return 0
    else
        log_info "find out $file_num files to be cleared"
    fi
    for f2c in $(cat $clear_tmp_file); do
         [ -f "$f2c" ] || continue
         echo "" > $f2c
        if [ $? -ne 0 ]; then
            log_error "clear $dir$f2c failed"
        fi
    done

    log_info "Clear $dir$file complete"
    /bin/rm $clear_tmp_file
    return 0
}

free_space() {
    count=$(wc -l $TMP_CONF | awk '{print $1}')
    for (( i=1;i<=$count;i++ )); do
        opt=$(sed -n "${i}p" $TMP_CONF | awk '{print $1}')
        case $opt in
        delete) delete_file $i
        ;;
        clear) clear_file $i
        ;;
        *) log_error "bad rule:$(sed -n '${i}p' $TMP_CONF)"
        ;;
        esac
    done
}

case $1 in
    start)
    cat >/etc/cron.d/clear-disk <<EOF
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
SHELL=/bin/bash
*/20 * * * * root /usr/local/clear-disk/bin/clear_disk.sh force >/dev/null 2>&1
EOF
    exit
    ;;
    stop)
    /bin/rm -f /etc/cron.d/clear-disk    
    exit
    ;;
esac

# let's make it
RUN_LOCK="${workdir}/../log/run.lock"
if [ -f $RUN_LOCK ]; then
    retry_tmp="${workdir}/../log/retry_count.tmp"
    if [ ! -f $retry_tmp ]; then
        retry_count=0
    else
        retry_count=$(cat $retry_tmp)
    fi
    retry_count=$(( $retry_count + 1 ))
    if [ $retry_count -gt 3 ]; then
        rm -f $RUN_LOCK
        rm -f $retry_tmp
        killall -9 clear_disk.sh
        log_error "the last clean task was not exit normally, has been force stopped"
    else
        echo $retry_count > $retry_tmp
    fi
    log_error "clear_disk task already running"
    exit 1
else
    touch $RUN_LOCK
fi

RM="/bin/rm"
if [ -x /usr/bin/ionice ]; then
   RM="/usr/bin/ionice -n 7 /bin/rm"
fi

# clear file 
#sleep $(($RANDOM%20)).$(($RANDOM%50))
load_config
if disk_exceeds_limit; then
    log_info "${MSG} , clean task starting..."
    free_space
    if ! disk_exceeds_limit >/dev/null; then
        log_info "disk clean success"
    else
        log_info "disk clean finished, but ${MSG}"
    fi
    rm $TMP_CONF
elif [[ "$1" = "force" ]]; then
    log_info "force clean"
    free_space
else
    log_info "disk space used not exceeds thres."
fi

/bin/rm $RUN_LOCK
exit 0

