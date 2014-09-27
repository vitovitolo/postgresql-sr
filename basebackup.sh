#!/bin/sh

PSQL=/usr/bin/psql
SCP="/usr/bin/scp  -i /var/lib/postgresql/.ssh/id_rsa" 
SSH="/usr/bin/ssh -i /var/lib/postgresql/.ssh/id_rsa"
LOGGER="/usr/bin/logger -i -p local0.info -t pgpool" 
RSYNC="/usr/bin/rsync --archive --delete --quiet --compress " 
BASENAME=`/usr/bin/basename $0`
HOSTNAME=`/bin/hostname`
MASTER_NODE=`cat /etc/hosts | grep $HOSTNAME | grep sql-node | awk ' {print $2}'`
ID=`/usr/bin/id -un`

# $1 = Database cluster path of a master node.
# $2 = Hostname of a recovery target node.
# $3 = Database cluster path of a recovery target node.

PG_HOME=/var/lib/postgresql/9.1/main
SRC_DATA=$1
DST_HOST=$2
DST_DATA=$3

export RSYNC_RSH="ssh -i /var/lib/postgresql/.ssh/id_rsa" 

$LOGGER "###############################################"
$LOGGER "     BASE BACKUP - ONLINE RECOVERY SCRIPT "
$LOGGER "###############################################"
$LOGGER " - data directory: "$SRC_DATA
$LOGGER " - destinattion hostname: "$DST_HOST
$LOGGER " - destination directory: "$DST_DATA

$LOGGER "Stopping node to recovery: "$DST_HOST

$SSH $DST_HOST "service postgresql stop"

$LOGGER "Executing $BASENAME as user $ID" 

$LOGGER "Executing pg_start_backup" 
$PSQL -d postgres -c "select pg_start_backup('pgpool-recovery')" 

$LOGGER "Creating file recovery.conf" 
echo  "restore_command = 'cp $PG_HOME/archive/%f %p' \n standby_mode = 'on' \n primary_conninfo = 'host=$MASTER_NODE user=postgres port=5432' \n trigger_file = '/tmp/trigger_file0'" >> $SRC_DATA/recovery.conf

$LOGGER "Rsyncing directory base" 
$RSYNC $SRC_DATA/base/ $DST_HOST:$DST_DATA/base/
$LOGGER "Rsyncing directory global" 
$RSYNC $SRC_DATA/global/ $DST_HOST:$DST_DATA/global/
$LOGGER "Rsyncing directory pg_clog" 
$RSYNC $SRC_DATA/pg_clog/ $DST_HOST:$DST_DATA/pg_clog/
$LOGGER "Rsyncing directory pg_multixact" 
$RSYNC $SRC_DATA/pg_multixact/ $DST_HOST:$DST_DATA/pg_multixact/
$LOGGER "Rsyncing directory pg_subtrans" 
$RSYNC $SRC_DATA/pg_subtrans/ $DST_HOST:$DST_DATA/pg_subtrans/
$LOGGER "Rsyncing directory pg_tblspc" 
$RSYNC $SRC_DATA/pg_tblspc/ $DST_HOST:$DST_DATA/pg_tblspc/
$LOGGER "Rsyncing directory pg_twophase" 
$RSYNC $SRC_DATA/pg_twophase/ $DST_HOST:$DST_DATA/pg_twophase/
$LOGGER "Rsyncing directory pg_xlog" 
$RSYNC $SRC_DATA/pg_xlog/ $DST_HOST:$DST_DATA/pg_xlog/
$LOGGER "Rsyncing file recovery.conf" 
$RSYNC $SRC_DATA/recovery.conf $DST_HOST:$DST_DATA/
$RSYNC $SRC_DATA/basebackup.sh $DST_HOST:$DST_DATA/
$RSYNC $SRC_DATA/pgpool_remote_start $DST_HOST:$DST_DATA/

$LOGGER "Deleting recovery.conf temp file.."
rm $SRC_DATA/recovery.conf

$LOGGER "Executing pg_stop_backup" 
$PSQL -d postgres -c 'select pg_stop_backup()'

$LOGGER "###############################################"
$LOGGER "         - BASE BACKUP - FINISHED "
$LOGGER "###############################################"

exit 0
