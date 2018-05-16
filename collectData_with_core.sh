#!/bin/bash
LOG_DIR=/var/tmp/cloudera_case_$(date +"%Y_%m_%d_%I_%M_%S_%p")
echo "Will be collecting logs under ${LOG_DIR}"

mkdir -p $LOG_DIR 2>/dev/null

# Open STDOUT as $LOG_FILE file for read and write.
exec 1<>${LOG_DIR}/LOG.out


# Redirect STDERR to STDOUT
exec 2>&1
tee ${LOG_DIR}/LOG.out &
tail -f ${LOG_DIR}/LOG.out > /dev/tty &

STACK_COLLECTION_INTERVAL=5
NUM_OF_STACKS=10

#Detecting Jstack path from NodeManagerProcess.
NM_PROC=$(ps -ef | grep "org.apache.hadoop.yarn.server.nodemanager.NodeManager"| grep -v grep | grep -v $$)
if [ "X$NM_PROC" == "X" ];
then
	#try to detect Jstack from the hdfs process
	JSTACK="$(ps -ef | egrep "^hdfs" | head -1  | awk '{print $8}' | awk -F\/ 'BEGIN{FS=OFS="/"}{$NF=""; NF--; print}')/jstack"	
else
	JSTACK="$(echo $NM_PROC | awk '{print $8}' | awk -F\/ 'BEGIN{FS=OFS="/"}{$NF=""; NF--; print}')/jstack"
fi


collectPandJstackImpalaDaemon()
{
        impala_pid=$1
	echo "Collecting pstack for Impala daemon $impala_pid "

	for i in $(seq 1 ${NUM_OF_STACKS} )
	do
		sudo -u impala pstack $impala_pid > ${LOG_DIR}/impalad_$(date +"%Y_%m_%d_%I_%M_%S_%p").pstack 2>&1
		sudo -u impala $JSTACK -m  $impala_pid > ${LOG_DIR}/impalad_$(date +"%Y_%m_%d_%I_%M_%S_%p").m.jstack 2>&1
                sudo -u impala $JSTACK $impala_pid > ${LOG_DIR}/impalad_$(date +"%Y_%m_%d_%I_%M_%S_%p").jstack 2>&1
		sleep $STACK_COLLECTION_INTERVAL
	done
}

collectTopOutput()
{
	echo "Collecting top output"
	top -bc -d1 -n5 > ${LOG_DIR}/$(hostname).top 2>&1 
}

collectlsof()
{
	echo "Collecting lsof"
	lsof > ${LOG_DIR}/$(hostname).lsof 2>&1
}

collectiostat()
{
	echo "Collecting iostat"
	iostat 1 5 > ${LOG_DIR}/$(hostname).iostat 2>&1
}

collectvmstat()
{
	echo "Collecting vmstat"
	vmstat  1 5 > ${LOG_DIR}/$(hostname).vmstat 2>&1
}

coreImpalaDaemon()
{
	impala_pid=$1
        echo "Collecting pstack for Impala daemon $impala_pid "

	gcore -o $LOG_DIR/core $impala_pid
        tpwd=`pwd`
        cd $LOG_DIR
        gtar -cvzf core.${impala_pid}.gtz core.$impala_pid
        rm -rf core.$impala_pid
        cd $tpwd
}

copyHdfsLogs()
{
        echo "Copying HDFS logs"

	gtar -cvzf $LOG_DIR/hadoop-hdfs.gtz /var/log/hadoop-hdfs 

}

copyImpalaDaemonLogs()
{
        echo "Copying Impala daemon logs"

        gtar -cvzf $LOG_DIR/impalad.gtz /var/log/impalad

}

collectSymbols()
{
	sudo -u impala gdb --batch attach $(pidof impalad) -ex "info shared" 2>/dev/null | sed '1,/Shared Object Library/d' | sed 's/\(.*\s\)\(\/.*\)/\2/' | grep \/ | tar -chvzf $LOG_DIR/impala_shared_lib_$(hostname).tar -T -	
}


impala_pid=$(pidof impalad)


collectTopOutput
collectlsof
collectiostat
collectvmstat

if [ "X$impala_pid" != "X" ];
then 
	collectSymbols
	collectPandJstackImpalaDaemon $impala_pid
	coreImpalaDaemon $impala_pid
	copyImpalaDaemonLogs
else
	echo "Impala process not detected on this host."
fi 

copyHdfsLogs

echo "Creating a .tgz of $LOG_DIR "
tar -czf ${LOG_DIR}_$(hostname).tgz $LOG_DIR


tail_pid=`ps | grep tail | grep -v grep | awk '{print $1}'`
kill $tail_pid


