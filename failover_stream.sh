#! /bin/sh
# Failover command for streaming replication.
# This script assumes that DB node 0 is primary, and 1 is standby.
#
# If standby goes down, do nothing. If primary goes down, create a
# trigger file so that standby takes over primary node.
#
# Arguments: $1: failed node id. $2: new master hostname. $3: path to
# trigger file.

# Edited by https://github.com/vitovitolo
#

PGPOOL_DIR='/etc/pgpool2/'
PGPOOL_HOME='/var/lib/postgresql/'
NODE_COUNT=`/usr/sbin/pcp_node_count 0 sql-pool 9898 user passwd 2> /dev/null`


failed_node=$1
new_master_hostname=$2
new_master_id=$3
trigger_file=$4

logger "$0 - ###############################################"
logger "$0 - FAILOVER STREAM SCRIPT "
logger "$0 - ###############################################"

#Search wich node is primary
old_master_id=`cat $PGPOOL_DIR/master_node_id`
#Check if master_node_id file have real info
CHECK_MASTER=`/usr/bin/psql  -p 5432 -U postgres -d template1 -tAc "select pg_is_in_recovery()" -h sql-node$old_master_id`
if [ "$CHECK_MASTER" == "t" ] ; then
    logger "$0 ERROR while getting master node id. Please, check manually if master node is running. Exiting.."
    exit 2
fi

logger "$0 - failed_node: "$failed_node
logger "$0 - new_master_hostname: "$new_master_hostname
logger "$0 - new_master_id: "$new_master_id
logger "$0 - old_master_id: "$old_master_id
logger "$0 - trigger_file: "$trigger_file


# Do nothing if standby goes down.
if [ "$failed_node" != "$old_master_id" ]
    then
    logger "$0 - Standby node failed: sql-node"$failed_node
    #Save failed node in a file for monitoring purpose
    /bin/echo "Standby node failed: sql-node"$failed_node > $PGPOOL_DIR/failed_node  2>&1 | logger -i
    exit 0;
# If Master node
else
    logger "$0 - Master node failed: sql-node"$failed_node
    #Save failed node in a file for monitoring purpose
    /bin/echo "Master node failed: sql-node"$failed_node > $PGPOOL_DIR/failed_node  2>&1 | logger -i
    # Create the trigger file to set read/write mode in new master backend
    /usr/bin/ssh -T -i $PGPOOL_HOME/.ssh/id_rsa postgres@$new_master_hostname "/bin/touch $trigger_file"  2>&1 | logger -i
    if [ $? -eq 0 ] ; then
        logger "$0 - trigger file sent successfully to "$new_master_hostname
    fi
    logger "$0 - Saving master node id to file $PGPOOL_DIR/master_node_id"
    rm $PGPOOL_DIR/master_node_id
    echo "$new_master_id" > $PGPOOL_DIR/master_node_id

    #Create new recovery.conf changing new_master hostname
    /bin/cat $PGPOOL_DIR/recovery.conf.template | /bin/sed s/NEW_MASTER_HOSTNAME/$new_master_hostname/ > $PGPOOL_DIR/recovery.conf  2>&1 | logger -i
    if [ $? -eq 0 ] ; then
        logger "$0 - New recovery.conf file created successfully"
    fi

#FOR MULTIPLE STANDBY SERVERS ENVIRONMENT
#  #Sends new master in all standby servers
#    #NODE_COUNT=`/usr/sbin/pcp_node_count 0 sql-pool 9898 admin shoei300!`
#    if [ $NODE_COUNT -gt -1 ]; then
#    #MAX_NODE=`expr $NODE_COUNT - 1`
#    #iterate between nodes of the pool
#       for node_id in `seq 0 $MAX_NODE`
#       do
#           #Send new recovery.conf file to all standby servers and reload postgresql
#           if [ $node_id != $new_master_id ] && [ $node_id != $failed_node ]
#	      then
#               /usr/bin/scp -i $PGPOOL_HOME/.ssh/id_rsa $PGPOOL_DIR/recovery.conf postgres@sql-node$node_id:$PGPOOL_HOME/9.1/main/  2>&1 | logger -i
#               if [ $? -eq 0 ] ; then
#        	  logger "$0 - recovery.conf file sent successfully in standby server sql-node"$node_id
#    	       fi
#	       /usr/bin/ssh -i $PGPOOL_HOME/.ssh/id_rsa postgres@sql-node$node_id '/etc/init.d/postgresql restart'  2>&1 | logger -i
#	       if [ $? -eq 0 ] ; then
#                  logger "$0 - Remote PostgreSQL restart successfully at standby server sql-node"$node_id
#    	       fi
#           fi
#       done
#    fi
#'
    #Cleanup
    rm $PGPOOL_DIR/recovery.conf  2>&1 | logger -i
    exit 0;
fi
