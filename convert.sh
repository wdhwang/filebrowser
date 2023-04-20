#!/bin/bash
# Convert docker to Helm Chart

WORK_DIR=/work
DOCKER_DIR=1-docker-compose
K8S_DIR=2-k8s
HELM_DIR=3-helm
PACKAGE_DIR=4-package
LOG=process.log
SERVICE=""

### Create all directories
mkdir -p $WORK_DIR
mkdir -p $WORK_DIR/$DOCKER_DIR
mkdir -p $WORK_DIR/$K8S_DIR
mkdir -p $WORK_DIR/$HELM_DIR
mkdir -p $WORK_DIR/$PACKAGE_DIR

### Function
function logMessage {
    DTIME=`date +%Y-%m-%d-%H:%M:%S`
    LOGFILE=$WORK_DIR/$1/$LOG
    #echo "$DTIME: $2" >> $LOGFILE
    echo "$DTIME:$1: $2" >> $WORK_DIR/$LOG
}

function exitTask {
    DTIME=`date +%Y-%m-%d-%H:%M:%S`
    LOGFILE=$WORK_DIR/$1/$LOG
    #echo "$DTIME: exit $2" >> $LOGFILE
    echo "$DTIME:$1: exit $2" >> $WORK_DIR/$LOG
    echo "" >> $WORK_DIR/$LOG
}

### Check docker-compose.yaml
CURDIR=$WORK_DIR/$DOCKER_DIR
if [ ! "$(ls -A $CURDIR)" ]; then
    #logMessage $DOCKER_DIR "'$DOCKER_DIR' directory is Empty!"
    exitTask $DOCKER_DIR 1
fi
FNAME=""
for FN in "$CURDIR"/* ; do
    #echo $FN
    if [[ "$FN" = *"$LOG"* ]] ; then
        continue
    fi
    RES=`yq eval "(.services[] | key)" $FN 2>&1`
    if [ ! "$?" = "0" ] ; then
        logMessage $DOCKER_DIR "'$RES'"
        exitTask $DOCKER_DIR 1
    fi
    if [ ! "$RES" = "" ] ; then
        FNAME=$FN
	SERVICE=`echo $RES | awk '{FS=" "} {print $1}'`
        break
    fi
done
if [ "$FNAME" = "" ] ; then
    #logMessage $DOCKER_DIR "'$DOCKER_DIR' directory has no valid Docker Compose YAML file!"
    exitTask $DOCKER_DIR 1
else
    logMessage $DOCKER_DIR "Begin process '$FNAME'."
    logMessage $DOCKER_DIR "Use '$SERVICE' as service name."
fi

### Convert docker-compose.yaml to K8s resource files
CURDIR=$WORK_DIR/$K8S_DIR
logMessage $K8S_DIR "Create K8s resource files to '$K8S_DIR' directory."
RES=`kompose convert -f $FNAME --with-kompose-annotation=false --out $CURDIR 2>&1`
logMessage $K8S_DIR "'$RES'"
for FN in "$CURDIR"/* ; do
    #echo $FN
    if [[ "$FN" = *"networkpolicy"* ]] ; then
        sed -e 's,true,false,g' -i $FN
        logMessage $K8S_DIR "Change '$FN' configuration value from 'true' to 'false'."
        break
    fi
done

### Build Helm chart from K8s resource files
CURDIR=$WORK_DIR/$HELM_DIR
logMessage $HELM_DIR "Create helm chart files to '$HELM_DIR' directory."
RES=`awk 'FNR==1 && NR!=1  {print "---"}{print}' $WORK_DIR/$K8S_DIR/*.yaml | helmify $CURDIR/$SERVICE 2>&1`
logMessage $HELM_DIR "'$RES'"

### Package Helm Chart to package tarball
CURDIR=$WORK_DIR/$PACKAGE_DIR
logMessage $PACKAGE_DIR "Package helm chart files to '$PACKAGE_DIR' directory."
cd $CURDIR
if [ -d "$WORK_DIR/$HELM_DIR/$SERVICE" ] ; then
    RES=`helm package $WORK_DIR/$HELM_DIR/$SERVICE`
    logMessage $PACKAGE_DIR "'$RES'"
    exitTask $PACKAGE_DIR 0
else
    logMessage $PACKAGE_DIR "'$WORK_DIR/$HELM_DIR/$SERVICE' not existed!"
    exitTask $PACKAGE_DIR 1
fi

