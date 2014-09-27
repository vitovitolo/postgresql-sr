#!/bin/sh
# Author https://github.com/vitovitolo

BASENAME=`/usr/bin/basename $0`
PSQL=/usr/bin/psql
SSH="/usr/bin/ssh -i /var/lib/postgresql/.ssh/id_rsa"
SCP="/usr/bin/scp  -i /var/lib/postgresql/.ssh/id_rsa"
LOGGER="/usr/bin/logger -i -p local0.info -t "$BASENAME
RSYNC="/usr/bin/rsync --verbose --progress --archive --compress "
ID=`/usr/bin/id -un`
CRM_CLEANUP="/usr/sbin/crm resource cleanup msPostgresql"
E_USER=postgres
#This should be virtual master ip in cluster config
MASTER_NODE=`hostname`

EXPECTED_ARGS=1
# $1 = Hostname of a recovery target node.

PG_HOME=/var/lib/postgresql/9.1/main
if [ $# -ne $EXPECTED_ARGS  ] ; then
   echo "Please, use with correct parameters."
   echo "Usage: $0 NODE_TO_RECOVER"
   echo "Excample: $0  balaitus "
   exit 2
fi
if [ "$ID" != "root" ] ; then
   echo "This scripts only runs under root privileges. Exiting.."
   exit 2
fi
SRC_DATA=/var/lib/postgresql/9.1/main
DST_HOST=$1
DST_DATA=/var/lib/postgresql/9.1/main

export RSYNC_RSH="ssh -i /var/lib/postgresql/.ssh/id_rsa"

$LOGGER "#####################################################"
$LOGGER "     ONLINE RECOVERY SCRIPT (HA CLUSTER VERSION) 2.0 "
$LOGGER "#####################################################"
$LOGGER " - local data directory: "$SRC_DATA
$LOGGER " - destinattion hostname: "$DST_HOST
$LOGGER " - remote data directory: "$DST_DATA

#ONLY FOR CLUSTER VERSION
#$LOGGER "Creating lock file to stop cluster actions (start/stop postgresql) on destination node during recovery. And stop postgresql on node to recover."
#$SSH $E_USER@$DST_HOST "[ ! -f $DST_DATA/tmp/PGSQL.lock ] && touch $DST_DATA/tmp/PGSQL.lock && service postgresql stop"
$LOGGER "Stopping postgresql on node to recover."
su - $E_USER -c "$SSH $E_USER@$DST_HOST 'service postgresql stop'"

$LOGGER "Cleaning /pg_xlog/ directory  on target node: $DST_HOST."
su - $E_USER -c "$SSH $E_USER@$DST_HOST 'rm -R $DST_DATA/pg_xlog/*'"

$LOGGER "Creating file recovery.conf"
echo  "restore_command = '$SCP $MASTER_NODE:$PG_HOME/archive/%f %p' \n standby_mode = 'on' \n primary_conninfo = 'host=$MASTER_NODE user=postgres port=5432 sslmode=disable' \n trigger_file = '/tmp/trigger_file0'" > $SRC_DATA/recovery.conf

$LOGGER "Create switch file to START archiving WAL files"
su - $E_USER -c "touch $SRC_DATA/backup_in_progress"

$LOGGER "Executing pg_start_backup"
su - $E_USER -c "$PSQL -d postgres -c \"select pg_start_backup('online-recovery')\""

$LOGGER "Rsyncing directory base"
su - $E_USER -c "$RSYNC $SRC_DATA/base/* $DST_HOST:$DST_DATA/base/"
$LOGGER "Rsyncing directory global"
su - $E_USER -c "$RSYNC $SRC_DATA/global/ $DST_HOST:$DST_DATA/global/"
$LOGGER "Rsyncing directory pg_clog"
su - $E_USER -c "$RSYNC $SRC_DATA/pg_clog/ $DST_HOST:$DST_DATA/pg_clog/"
$LOGGER "Rsyncing directory pg_notify"
su - $E_USER -c "$RSYNC $SRC_DATA/pg_notify/ $DST_HOST:$DST_DATA/pg_notify/"
$LOGGER "Rsyncing directory pg_serial"
su - $E_USER -c "$RSYNC $SRC_DATA/pg_serial/ $DST_HOST:$DST_DATA/pg_serial/"
$LOGGER "Rsyncing directory pg_multixact"
su - $E_USER -c "$RSYNC $SRC_DATA/pg_multixact/ $DST_HOST:$DST_DATA/pg_multixact/"
$LOGGER "Rsyncing directory pg_stat_tmp"
su - $E_USER -c "$RSYNC $SRC_DATA/pg_stat_tmp/ $DST_HOST:$DST_DATA/pg_stat_tmp/"
$LOGGER "Rsyncing directory pg_subtrans"
su - $E_USER -c "$RSYNC $SRC_DATA/pg_subtrans/ $DST_HOST:$DST_DATA/pg_subtrans/"
$LOGGER "Rsyncing directory pg_tblspc"
su - $E_USER -c "$RSYNC $SRC_DATA/pg_tblspc/ $DST_HOST:$DST_DATA/pg_tblspc/"
$LOGGER "Rsyncing directory pg_twophase"
su - $E_USER -c "$RSYNC $SRC_DATA/pg_twophase/ $DST_HOST:$DST_DATA/pg_twophase/"
#$LOGGER "Rsyncing directory pg_xlog"
#su - $E_USER -c "$RSYNC $SRC_DATA/pg_xlog/ $DST_HOST:$DST_DATA/pg_xlog/"
$LOGGER "Rsyncing $BASENAME script"
su - $E_USER -c "$RSYNC $SRC_DATA/$BASENAME $DST_HOST:$DST_DATA/"
$LOGGER "Rsyncing file recovery.conf"
su - $E_USER -c "$RSYNC $SRC_DATA/recovery.conf $DST_HOST:$DST_DATA/"

$LOGGER "Executing pg_stop_backup"
su - $E_USER -c "$PSQL -d postgres -c 'select pg_stop_backup()'"

$LOGGER "Remove switch file to STOP archiving WAL files"
su - $E_USER -c "rm $SRC_DATA/backup_in_progress"

#$LOGGER "Rsyncing directory archive"
#su - $E_USER -c "$RSYNC $SRC_DATA/archive/ $DST_HOST:$DST_DATA/archive/"

$LOGGER "Deleting recovery.conf from master node"
su - $E_USER -c "rm -f $SRC_DATA/recovery.conf"

#ONLY FOR CLUSTER VERSION
#$LOGGER "Removing cluster lock file (ha cluster purpose)"
#$SSH $E_USER@$DST_HOST "rm $DST_DATA/tmp/PGSQL.lock"

#ONLY FOR CLUSTER VERSION
#$LOGGER "Refresh cluster node on crm: "$DST_HOST
#$CRM_CLEANUP $DST_HOST

$LOGGER "Starting node recovered: "$DST_HOST
su - $E_USER -c "$SSH $DST_HOST 'service postgresql start'"

$LOGGER "Cleanup /archive/ directory on this server "
su - $E_USER -c "rm $SRC_DATA/archive/*"

#ONLY FOR CLUSTER VERSION
#$LOGGER "   Check pgsql log on remote node to ensure recovery and cluster state (crm_mon -A)"

$LOGGER "###############################################"
$LOGGER "         - ONLINE RECOVERY - FINISHED          "
$LOGGER "###############################################"

exit 0
