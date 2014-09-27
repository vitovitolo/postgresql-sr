#!/bin/bash

# Author https://github.com/vitovitolo
# Script to deploy primary or standby node for pgpool II +  streaming replication in master/slave mode
# Requisites: postgresql 9.1 installed and running
#             permission to connect to primary node with user postgres without passwd
# Usage: $0 [primary/standby] [ip_bind_postgresql] [net_pool] [node_id] [master_hostname] [master_ip]

PG_HOME=/var/lib/postgresql/9.1/main/
PG_CONF=/etc/postgresql/9.1/main/

NODE_ROLE=$1
IP_BIND=$2
NET_POOL=$3
NODE_ID=$4
MASTER_HOST=$5
MASTER_IP=$6
HOSTNAME=`/bin/hostname`

#Check number of parameters
if [ -n $# ] && [ $# -lt 6 ] ; then
    echo "Wrong parameters!"
    echo "Usage: $0 [primary/standby] [ip_bind_postgresql] [net_pool] [node_id] [master_hostname] [master_ip]."
    exit 2
fi

#init checks
if ! [ -e postgresql.conf ] || ! [ -e basebackup.sh ] || ! [ -e pgpool_remote_start ] || ! [ -e recovery.conf ] ; then
    echo "Sorry, this script needs this files: 'postgresql.conf', 'basebackup.sh', 'pgpool_remote_start' and 'recovery.conf'  to continue."
    exit 2
fi

#check user root is running script
if [ `id | grep "uid\=0" | wc -l` -eq 0 ]
then
    echo "Sorry, this script can only run by root."
    exit 2
fi

# check postgres user are installed in the system
IS_PGUSER=`cat /etc/passwd | grep postgres | wc -l`
if [ $IS_PGUSER -gt 1 ] || [ $IS_PGUSER -lt 1 ] ; then
   echo "Error. User postgres does not exist. Exiting..."
   exit 2
fi

#check node_role parameter
if ! [ "$NODE_ROLE" == "primary" ] && ! [ "$NODE_ROLE" == "standby" ] ; then
    echo "Error. Node only could be 'primary' or 'standby'."
    echo "Usage: $0 [primary/standby] [ip_bind_postgresql] [net_pool] [node_id] [master_hostname] [master_ip]."
    exit 2
fi

#check ip format in 192.168.0.0/16
#IS_IP=`echo $IP_BIND | grep 192.168 | wc -l`
#if [ $IS_IP -lt 1 ] ; then
#   echo "Error. IP format is not in 192.168.0.0/16 range. Exiting..."
#   echo "Usage: $0 [primary/standby] [ip_bind_postgresql] [net_pool] [node_id] [master_hostname] [master_ip]."
#   exit 2
#fi

#check if postgres bind ip address
IS_BIND=`netstat -putan | grep 5432 | grep postgres  | grep $IP_BIND | wc -l`
if [ $IS_BIND -lt 1 ] ; then
   echo "Error. Postgres is not bind in $IP_BIND and port 54332. Exiting..."
   echo "Usage: $0 [primary/standby] [ip_bind_postgresql] [net_pool] [node_id] [master_hostname] [master_ip]."
   exit 2
fi

#check net_pool parameter
#IS_NET_VALID=`echo $NET_POOL | grep 192.168 | wc -l`
#if [ $IS_NET_VALID -lt 1 ] ; then
#   echo "Error. Net pool address $NET_POOL is not in valid range: 192.168.0.0/16 . Exiting..."
#   echo "Usage: $0 [primary/standby] [ip_bind_postgresql] [net_pool] [node_id] [master_hostname] [master_ip]."
#   exit 2
#fi

# check node id is not in use
#ping -c 1 sql-node$NODE_ID  &> /dev/null
#if [ $? -eq 0 ] ; then
#    echo "sql-node$NODE_ID is alive. Please, select other NODE ID. Exiting..."
#    exit 2
#fi

#check master host only deploying standby nodes
if  [ "$NODE_ROLE" == "standby" ] ; then
   IS_SLAVE=`psql -U postgres  -d template1 -h $MASTER_IP -tAc "select pg_is_in_recovery()" 2> /dev/null`
   if ! test -n $IS_SLAVE  ; then
       echo "Can´t connect to Master host ($MASTER_HOST) with user postgres and without passwd. Check $PG_CONF/pg_hba.conf in $MASTER_HOST. Exiting..."
       exit 2
   fi
   if [ '$IS_SLAVE' == 't' ] ; then
       echo "$MASTER_HOST is not a Master node. Exiting..."
       exit 2
   fi
fi


#Config postgresql
rm $PG_HOME/backup_in_progress
rm $PG_CONF/postgresql.conf
sed s/LISTEN_IP_ADDR/$IP_BIND/ postgresql.conf > $PG_CONF/postgresql.conf


#Set permission to allow connections from others nodes belonging to the pool
echo "host    all             all             $NET_POOL/24          trust" >> $PG_CONF/pg_hba.conf
echo "host    replication             postgres             $NET_POOL/24          trust" >> $PG_CONF/pg_hba.conf

#Set hostname in pool format
echo "$MASTER_IP  $MASTER_HOST"  >> /etc/hosts
echo "$IP_BIND  sql-node$NODE_ID  #$HOSTNAME"  >> /etc/hosts

#Copy online recovery scripts and set permissions
mv basebackup.sh $PG_HOME/basebackup.sh
chmod 755 $PG_HOME/basebackup.sh
chown postgres:postgres $PG_HOME/basebackup.sh
mv pgpool_remote_start $PG_HOME/pgpool_remote_start
chmod 755 $PG_HOME/pgpool_remote_start
chown postgres:postgres $PG_HOME/pgpool_remote_start

#Config standby config file: recovery.conf
if  [ "$NODE_ROLE" == "standby" ] ; then
  rm $PG_HOME/recovery.conf
  /bin/cat recovery.conf | /bin/sed s/NEW_MASTER_HOSTNAME/$MASTER_HOST/ > $PG_HOME/recovery.conf
  chmod 600 $PG_HOME/recovery.conf
  chown postgres:postgres $PG_HOME/recovery.conf
fi

#Restarting postgresql
/etc/init.d/postgresql restart

exit 0
