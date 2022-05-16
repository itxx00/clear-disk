#! /bin/bash
PATH=/sbin:/usr/local/bin:/usr/bin:/bin:.:$PATH
workdir=$(cd "$(dirname "$0")" && pwd)
logdir="$workdir/../log"
log_file_name="clear.log.$(date '+%Y%m')"
log_file="${workdir}/../log/$log_file_name"
cd "$workdir" || {
    echo "error: cannot cd into $workdir"
    exit 1
}
[ -d "$logdir" ] || mkdir "$logdir"
TMP_CONF="${workdir}/../log/tmp.conf"

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] : INFO : $* "
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] : INFO : $* " >>"$log_file"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] : ERROR: $*" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] : ERROR: $*" >>"$log_file"
}

load_config() {
    # read conf from clear.conf
    grep -Ev '^#|^$' "$workdir"/../conf/clear.conf > "$TMP_CONF"
    # add a newline at end of file only if it doesn't end with newline
    sed -i -e '$a\' "$TMP_CONF"
    return 0
}

get_params() {
    local filter_file
    local filter_file_tmp
    filter_file="${workdir}/../conf/filter.conf"
    filter_file_tmp="/tmp/.cleardisk.filter"
    Param=""
    Dir=""
    File=""
    Param=$(sed -n "${1}p" "$TMP_CONF" | awk '{print $2}')
    Dir=$(sed -n "${1}p" "$TMP_CONF" | awk '{print $3}')
    File=$(sed -n "${1}p" "$TMP_CONF" | awk '{print $4}')

    if ! echo "$Dir" | grep -q "/$"; then
        Dir="${Dir}/"
    fi

    # gen default filter conf
      cat > $filter_file_tmp <<EOF
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
    if [ -f "$filter_file" ]; then
        cat "$filter_file" >>$filter_file_tmp
    fi
    sort $filter_file_tmp | uniq | grep -v '^$' >${filter_file_tmp}.dat

    while read -r d; do
        if ! echo "$d" | grep -q "/$"; then
            d="${d}/"
        fi
        if [[ "$Dir" = "$d" ]]; then
            log_error "danger path '$Dir', will not clean"
            return 1
        fi
    done <${filter_file_tmp}.dat

    if echo "$File" | grep -q "/"; then
        log_error "danger file name '$File', will not clean"
        return 1
    fi
    return 0
}

get_limit() {
    limit_conf="${workdir}/../conf/limit.conf"
    LIMIT=""
    HARDLIMIT=""
    if [ -f "$limit_conf" ]; then
        LIMIT=$(grep -v "^#" "$limit_conf" | grep "^limit=" | head -n 1 | awk -F= '{print $2}' | awk '{print $1}')
        HARDLIMIT=$(grep -v "^#" "$limit_conf" | grep "^hardlimit=" | head -n 1 | awk -F= '{print $2}' | awk '{print $1}')
        if grep -v "^#" "$limit_conf" | grep -q "${1}="; then
            LIMIT=$(grep -v "^#" "$limit_conf" | grep "${1}=" | head -n 1 | awk -F= '{print $2}' | awk '{print $1}')
        fi
    fi

    if [[ "$LIMIT" = "" ]]; then
        log_info "set limit thres of mount point '$1' default to 70%"
        LIMIT=70
    else
        log_info "limit thres of mount point '$1' is ${LIMIT}%"
    fi
}

disk_exceeds_limit() {
    MSG=""
    for space in $(df -lhP -t ext2 -t ext3 -t ext4 -t xfs -t btrfs |sed '1d' |awk '{print $5$6}'); do
        used_percent=$(echo "$space" | awk -F% '{print $1}')
        mount_point=$(echo "$space" | awk -F% '{print $2}')
        get_limit "$mount_point"
        if [ "$used_percent" -gt $LIMIT ]; then
            MSG=$MSG"$mount_point used ${used_percent}%, more than ${LIMIT}%; "
        fi
    done

    if [[ "$MSG" = "" ]]; then
        return 1
    else
        return 0
    fi
}

disk_exceeds_hardlimit() {
    MSG=""
    get_limit "/" >/dev/null
    if [[ -z "$HARDLIMIT" ]] || [[ "$HARDLIMIT" -lt 1 ]]; then
        return 1
    fi
    for space in $(df -lhP -t ext2 -t ext3 -t ext4 -t xfs -t btrfs |sed '1d' |awk '{print $5$6}'); do
        used_percent=$(echo "$space" | awk -F% '{print $1}')
        mount_point=$(echo "$space" | awk -F% '{print $2}')
        if [ "$used_percent" -gt "$HARDLIMIT" ]; then
            MSG=$MSG"$mount_point used ${used_percent}%, more than hardlimit ${HARDLIMIT}%; "
        fi
    done

    if [[ "$MSG" = "" ]]; then
        return 1
    else
        return 0
    fi
}

delete_file() {
    local param
    local cmd
    local step
    step=0
    [[ -n $2 ]] && step=$2
    delete_tmp_file="${workdir}/../log/delete.tmp"
    if ! get_params "$1"; then
        /bin/rm -f "$delete_tmp_file"
        return 1
    fi

    cmd="mtime"
    param=$(echo "$Param" | sed 's/[a-zA-Z]//g')
    if echo "$Param" | grep -Eq "[h|H]$"; then
        cmd="mmin"
        param=$((param * 60))
        step=$((step * 60))
        param=$((param - step))
    elif echo "$Param" | grep -Eq "[m|M]$"; then
        cmd="mmin"
        step=$((step * 30))
        param=$((param - step))
    else
        param=$((param - step))
    fi
    if [[ "$param" -le 1 ]]; then
        Deleteable=no
        return
    else
        Deleteable=yes
    fi

    if ! ls -d $Dir >/dev/null 2>&1; then
        log_info "$Dir not exists"
        return 1
    else
        log_info "$Dir exists"
    fi
    #log_info "delete $param $Dir $File"
    find ${Dir} -path "${Dir}${File}" -type f -$cmd "+$param" -print >"$delete_tmp_file"
    retval=$?
    if [ $retval -ne 0 ]; then
        log_error "failed to find file"
        /bin/rm "$delete_tmp_file"
        return 1
    fi
    file_num=$(wc -l <"$delete_tmp_file")
    if [[ $file_num -eq 0 ]]; then
        #log_info "no file to be deleted"
        /bin/rm "$delete_tmp_file"
        return 0
    else
        if [[ "$step" = 0 ]]; then
            log_info "find out $file_num files to be deleted"
        else
            log_info "find out $file_num more files of step $step to be deleted"
        fi
    fi
    while read -r f2d; do
        [ -f "$f2d" ] || continue
        $RM "$f2d"
        retval=$?
        if [ $retval -ne 0 ]; then
            log_error "Delete $Dir$f2d failed"
        fi
        sleep .5
    done <"$delete_tmp_file"
    log_info "Delete $Dir$File complete"
    /bin/rm "$delete_tmp_file"
    return 0
}

clear_file() {
    local param
    local step
    step=0
    [[ -n $2 ]] && step=$2
    clear_tmp_file="${workdir}/../log/clear.tmp"
    if ! get_params "$1"; then
        /bin/rm "$clear_tmp_file"
        return 1
    fi
    param=$((Param - step))
    if [[ "$param" -le 1 ]]; then
        Cleanable=no
        return
    else
        Cleanable=yes
    fi
    if ! ls -d $Dir >/dev/null 2>&1; then
        log_info "$Dir not exists"
        return 1
    else
        log_info "$Dir exists"
    fi
    #log_info "delete $param $Dir $File"
    find $Dir -maxdepth 1 -name "$File" -type f -size +"${param}"k > "$clear_tmp_file"
    retval=$?
    if [ $retval -ne 0 ]; then
        log_error "failed to find file"
        /bin/rm "$clear_tmp_file"
        return 1
    fi
    file_num=$(wc -l <"$clear_tmp_file")
    if [[ $file_num -eq 0 ]]; then
        #log_info "no file to be cleared"
        /bin/rm "$clear_tmp_file"
        return 0
    else
        if [[ "$step" = 0 ]]; then
            log_info "find out $file_num files to be cleared"
        else
            log_info "find out $file_num more files of step $step to be cleared"
        fi
    fi
    while read -r f2c; do
        [ -f "$f2c" ] || continue
        echo "" > "$f2c"
        retval=$?
        if [ $retval -ne 0 ]; then
            log_error "clear $Dir$f2c failed"
        fi
    done <"$clear_tmp_file"

    log_info "Clear $Dir$File complete"
    /bin/rm "$clear_tmp_file"
    return 0
}

free_space() {
    count=$(wc -l <"$TMP_CONF")
    for (( i=1;i<=count;i++ )); do
        opt=$(sed -n "${i}p" "$TMP_CONF" | awk '{print $1}')
        case $opt in
            delete)
                delete_file $i
                ;;
            clear)
                clear_file $i
                ;;
            *)
                bad_rule=$(sed -n "${i}p" "$TMP_CONF")
                log_error "bad rule: $bad_rule"
                ;;
        esac
    done
}

free_space_hard() {
    count=$(wc -l <"$TMP_CONF")
    delete_step=1
    clear_step=102400
    Cleanable="no"
    Deleteable="no"
    while disk_exceeds_hardlimit; do
        log_info "${MSG} , ds=$delete_step, cs=$clear_step, clean task starting..."
        for (( i=1;i<=count;i++ )); do
            opt=$(sed -n "${i}p" "$TMP_CONF" | awk '{print $1}')
            case $opt in
                delete)
                    delete_file $i $delete_step
                    ;;
                clear)
                    clear_file $i $clear_step
                    ;;
                *)
                    bad_rule=$(sed -n "${i}p" "$TMP_CONF")
                    log_error "bad rule: $bad_rule"
                    ;;
            esac
        done
        delete_step=$((delete_step+1))
        clear_step=$((clear_step+102400))
        if [[ "$Cleanable" = no ]] && [[ "$Deleteable" = no ]]; then
            log_info "nothing can be cleaned, quit."
            return 1
        fi
    done
}

case $1 in
    start)
        cat >/etc/cron.d/clear-disk <<EOF
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
SHELL=/bin/bash
*/20 * * * * root /usr/local/clear-disk/bin/clear_disk.sh >/dev/null 2>&1
30 01 * * 1 root /usr/local/clear-disk/bin/clear_disk.sh force >/dev/null 2>&1
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
if [ -f "$RUN_LOCK" ]; then
    retry_tmp="${workdir}/../log/retry_count.tmp"
    if ! [ -f "$retry_tmp" ]; then
        retry_count=0
    else
        retry_count=$(cat "$retry_tmp")
    fi
    retry_count=$((retry_count + 1))
    if [ $retry_count -gt 3 ]; then
        rm -f "$RUN_LOCK"
        rm -f "$retry_tmp"
        killall -9 clear_disk.sh
        log_error "the last clean task was not exit normally, has been force stopped"
    else
        echo $retry_count > "$retry_tmp"
    fi
    log_error "clear_disk task already running"
    exit 1
fi
touch "$RUN_LOCK"

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
else
    log_info "no disk exceeds limit, quit."
fi
if disk_exceeds_hardlimit; then
    log_info "${MSG} , trying hard to clean more files ..."
    free_space_hard
fi
if [[ "$1" = "force" ]]; then
    log_info "force clean"
    free_space
fi

/bin/rm "$TMP_CONF"
/bin/rm "$RUN_LOCK"
exit 0

