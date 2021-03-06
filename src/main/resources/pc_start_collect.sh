 #!/bin/bash
function HELP {
  echo -e \\n"Help documentation for ${SCRIPT}."\\n
  echo -e "Basic usage:$SCRIPT file.ext"\\n
  echo "Command line switches are optional. The following switches are recognized."
  echo "-f  Frequency in seconds. Default is 4."
  echo "-o  Output directory. Default is ./target."
  echo "-c  Copy this path into conf dir. Default is empty."
  echo -e "-h  --Displays this help message. No further functions are performed."\\n
  echo -e "Example: $SCRIPT -f 1 -c /opt/conf java_pid"\\n
  exit 1
}

function killBackgroundProcesses {
    echo Kill previous processes
    for f in ${DATA_COLLECTION_DIR}/*.pid; do
        echo PID file to kill:$f
        cat $f | xargs kill
    done
}

function cleanCollection {
    echo Preparing output dirs
    rm -Rf ${DATA_COLLECTION_DIR}
}

function prepareCollectionOutputDirs {
    echo Preparing output dirs
    mkdir -p ${CONF_COLLECTION_DIR}
    mkdir -p ${META_COLLECTION_DIR}
    mkdir -p ${JAVA_COLLECTION_DIR}
    mkdir -p ${SYS_COLLECTION_DIR}
    mkdir -p ${SIP_COLLECTION_DIR}
}

function collectConfUsed {
    if [[ -z ${CONF_DIR} ]]; then
        echo Collect conf disabled
    else
        echo Collect conf from ${CONF_DIR}
        cp -a ${CONF_DIR} ${CONF_COLLECTION_DIR}
    fi
}
function collectJavaProcessInfo {
    echo Collect Java Process Info

    set > ${META_COLLECTION_DIR}/envVars.txt  
   
    ps -f -p ${JAVA_PID} >${META_COLLECTION_DIR}\jvmoptions.txt

    $JAVA_HOME/bin/java $JAVA_OPTS -cp $CLASSPATH org.restcomm.perfcorder.collector.VMInfoPrinter ${JAVA_PID} > ${META_COLLECTION_DIR}/jvmdump.txt

    lsof -p ${JAVA_PID} | grep ".jar" > ${META_COLLECTION_DIR}/jarList.txt

    echo $JAVA_PID > ${META_COLLECTION_DIR}/java.pid
}

function startSystemMeasCollection {
    echo Starting System Collection over process ${JAVA_PID}

    iostat -x -d ${MEAS_INTERVAL_SECONDS} | grep -v 'Device' > ${SYS_COLLECTION_DIR}/iostat.txt &
    echo $! > ${DATA_COLLECTION_DIR}/iostat.pid

    netstat -s ${MEAS_INTERVAL_SECONDS} > ${SYS_COLLECTION_DIR}/netstat.txt &
    echo $! > ${DATA_COLLECTION_DIR}/netstat.pid
}
function startJavaMeasCollection {
    echo Starting Java Collection over process ${JAVA_PID}

    jstat -gccause -t ${JAVA_PID} ${MEAS_INTERVAL_SECONDS}s > ${JAVA_COLLECTION_DIR}/jstat.txt &
    echo $! > ${DATA_COLLECTION_DIR}/jstat.pid

    $JAVA_HOME/bin/java $JAVA_OPTS -cp $CLASSPATH org.restcomm.perfcorder.collector.JVMStatApp -d ${MEAS_INTERVAL_SECONDS} ${JAVA_PID} > ${JAVA_COLLECTION_DIR}/jvmtop.txt &
    echo $! > ${DATA_COLLECTION_DIR}/jvmstat.pid

    $JAVA_HOME/bin/java $JAVA_OPTS -cp $CLASSPATH org.restcomm.perfcorder.collector.GCPausePrinter -d ${MEAS_INTERVAL_SECONDS} ${JAVA_PID} > ${JAVA_COLLECTION_DIR}/jgcstat.txt &
    echo $! > ${DATA_COLLECTION_DIR}/jgcstat.pid
}
function startNetworkCapture {
    if [[ -z ${PC_NETWORK_CAPTURE} ]]; then
        echo Network capture disabled
    else 
        echo Network capture enabled
        tshark  -w ${SYS_COLLECTION_DIR}/net.pcap -F pcapng &
        echo $! > DATA_COLLECTION_DIR/tshark.pid
    fi
}

function startCollection {
    echo Starting collection
    killBackgroundProcesses
    cleanCollection
    prepareCollectionOutputDirs
    collectConfUsed
    collectJavaProcessInfo

    startTimestamp=$(date +%s)
    echo $startTimestamp > ${META_COLLECTION_DIR}/startTimestamp

    startSystemMeasCollection
    startJavaMeasCollection
    startNetworkCapture
}

#Set Script Name variable
SCRIPT=`basename ${BASH_SOURCE[0]}`

OUTPUT_DIR=./target
MEAS_INTERVAL_SECONDS=4
CONF_DIR=
EXTERNAL_FILES=

#Check the number of arguments. If none are passed, print help and exit.
NUMARGS=$#
echo -e \\n"Number of arguments: $NUMARGS"
if [ $NUMARGS -eq 0 ]; then
  HELP
fi

while getopts "f:c:o:e:h" opt; do
  case $opt in
    f)
      MEAS_INTERVAL_SECONDS=${OPTARG}
      ;;
    c)
      CONF_DIR=${OPTARG}
      ;;
    o)
      OUTPUT_DIR=${OPTARG}
      ;;
    h)
      HELP
      ;;
    \?)
      HELP
      ;;
  esac
done
shift $((OPTIND-1))

# HANDLE CORRECT NUMBER OF MASS OPTIONS
if [ $# -ne 1 ]; then
  HELP
  exit 1
fi

JAVA_PID=$1
echo Process monitored $JAVA_PID

TOOLSJAR="$JAVA_HOME/lib/tools.jar"
if [ ! -f "$TOOLSJAR" ] ; then
        echo "$JAVA_HOME seems to be no JDK!" >&2
        exit 1
fi
DIR=$( cd $(dirname $0) ; pwd -P )
#maven filtering has to replace the version var during build
CLASSPATH="$DIR/sipp-report-${project.version}-with-dependencies.jar:$TOOLSJAR"
echo CLASSPATH:${CLASSPATH}

DATA_COLLECTION_DIR=${OUTPUT_DIR}/data
META_COLLECTION_DIR=${DATA_COLLECTION_DIR}/meta
CONF_COLLECTION_DIR=${DATA_COLLECTION_DIR}/conf
PERIODIC_COLLECTION_DIR=${DATA_COLLECTION_DIR}/periodic
JAVA_COLLECTION_DIR=${PERIODIC_COLLECTION_DIR}/java
SYS_COLLECTION_DIR=${PERIODIC_COLLECTION_DIR}/sys
SIP_COLLECTION_DIR=${PERIODIC_COLLECTION_DIR}/sip
    
ANALYSIS_GENERATION_DIR=${OUTPUT_DIR}/analysis
GRAPHS_DIR=${ANALYSIS_GENERATION_DIR}/graphs
STATS_DIR=${ANALYSIS_GENERATION_DIR}/stats

startCollection