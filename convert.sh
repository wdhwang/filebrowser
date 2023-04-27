#!/bin/bash
# Convert docker to Helm Chart

##################################################
### Define global variables
WORK_DIR=/work
BACK_DIR=/backup
DOCKER_DIR=1-docker-compose
K8S_DIR=2-k8s
HELM_DIR=3-helm
PACKAGE_DIR=4-package
LOG=process.log
FNAME=""
SERVICE=""
TARBALL=""
HARBOR_HOST=harbor.my
HARBOR_PORT=30003
HARBOR_USER=admin
HARBOR_PASS=admin
DEBUG=True

##################################################
### Create all directories
mkdir -p $WORK_DIR
mkdir -p $WORK_DIR/$DOCKER_DIR
mkdir -p $WORK_DIR/$K8S_DIR
mkdir -p $WORK_DIR/$HELM_DIR
mkdir -p $WORK_DIR/$PACKAGE_DIR

mkdir -p $BACK_DIR
mkdir -p $BACK_DIR/$DOCKER_DIR
mkdir -p $BACK_DIR/$K8S_DIR
mkdir -p $BACK_DIR/$HELM_DIR

##################################################
### Functions
function logMessage {
    DTIME=`date +%Y-%m-%d %H:%M:%S`
    echo "$DTIME:$1: $2" >> $WORK_DIR/$LOG
}

function exitTask {
    DTIME=`date +%Y-%m-%d %H:%M:%S`
    if [ ! "$1" = "-" ] ; then
        echo "$DTIME:$1: exit $2" >> $WORK_DIR/$LOG
        echo "" >> $WORK_DIR/$LOG
    fi
    exit $2
}

##################################################
# Convert docker-compose.yaml to K8s resource files
function procDocker2K8s {
    CURDIR=$WORK_DIR/$K8S_DIR
    TASKNM=procDocker2K8s
    logMessage "$TASKNM" "Create K8s resource files to '$K8S_DIR' directory."
    RES=`kompose convert -f $FNAME --with-kompose-annotation=false --out $CURDIR 2>&1`
    logMessage "$TASKNM" "'$RES'"
    for FN in "$CURDIR"/* ; do
        if [ "$DEBUG" = True ] ; then
            logMessage "$TASKNM" "Find[$FN]"
        fi
        if [[ "$FN" = *"networkpolicy"* ]] ; then
            sed -e 's,true,false,g' -i $FN
            logMessage "$TASKNM" "Change '$FN' configuration value from 'true' to 'false'."
            break
        fi
    done
}

# Build Helm chart from K8s resource files
function procK8s2Helm {
    CURDIR=$WORK_DIR/$HELM_DIR
    TASKNM=procK8s2Helm
    logMessage "$TASKNM" "Create helm chart files to '$HELM_DIR/$SERVICE' directory."
    RES=`awk 'FNR==1 && NR!=1  {print "---"}{print}' $WORK_DIR/$K8S_DIR/*.yaml | helmify $CURDIR/$SERVICE 2>&1`
    if [ ! "$RES" = "" ] ; then
        logMessage "$TASKNM" "'$RES'"
    fi
}

# Package Helm Chart to package tarball
function procHelm2Tarball {
    CURDIR=$WORK_DIR/$PACKAGE_DIR
    TASKNM=procHelm2Tarball
    logMessage "$TASKNM" "Package helm chart files to '$PACKAGE_DIR' directory."
    cd $CURDIR
    if [ -d "$WORK_DIR/$HELM_DIR/$SERVICE" ] ; then
        RES=`helm package $WORK_DIR/$HELM_DIR/$SERVICE 2>&1`
        if [ ! "$RES" = "" ] ; then
            logMessage "$TASKNM" "'$RES'"
            TARBALL=`echo $RES | tr -d '[:blank:]' |  awk 'BEGIN {FS=":"} {print $2}'`
	    if [ "$DEBUG" = True ] ; then
                logMessage "$TASKNM" "tarball file '$TARBALL'"
	    fi
	fi
    else
        logMessage "$TASKNM" "'$WORK_DIR/$HELM_DIR/$SERVICE' not existed!"
        exitTask "$TASKNM" 1
    fi
}

# Upoad tarball to Harbor
function uploadTarball {
    TASKNM=uploadTarball
    logMessage "$TASKNM" "Upoad tarball '$TARBALL' to Harbor."
    if [ -f "$TARBALL" ]; then
        RES=`curl -s --insecure -X POST "https://$HARBOR_HOST:$HARBOR_PORT/api/chartrepo/library/charts" -u "$HARBOR_USER:$HARBOR_PASS" -H "Content-Type: multipart/form-data" -H "accept: application/json" -F "chart=@${TARBALL};type=application/x-compressed-tar"`
        logMessage "$TASKNM" "'$RES'"
    else
        logMessage "$TASKNM" "'$TARBALL' not existed!"
        exitTask "$TASKNM" 1
    fi
}

##################################################
### Check docker-compose.yaml
function checkDockerCompose {
    CURDIR=$WORK_DIR/$DOCKER_DIR
    BAKDIR=$BACK_DIR/$DOCKER_DIR
    TASKNM=checkDockerCompose

    # Check '$DOCKER_DIR' directory is Empty or not
    if [ ! "$(ls -A $CURDIR)" ]; then
	if [ "$DEBUG" = True ] ; then
            logMessage "$TASKNM" "'$DOCKER_DIR' directory is Empty!"
	fi
        exitTask "-" 1
    fi

    # '$DOCKER_DIR' directory is not empty, and find valid YAML file
    for FN in "$CURDIR"/* ; do
        if [ "$DEBUG" = True ] ; then
            logMessage "$TASKNM" "Find[$FN]"
        fi
        if [[ "$FN" = *"$LOG"* ]] ; then
            continue
        fi
        RES=`yq eval "(.services[] | key)" $FN 2>&1`
        if [ ! "$?" = "0" ] ; then
            logMessage "$TASKNM" "'$RES'"
            exitTask "-" 1
        fi
        if [ ! "$RES" = "" ] ; then
            FNAME=$FN
            SERVICE=`echo $RES | awk 'BEGIN {FS=" "} {print $1}'`
            break
        fi
    done
    if [ "$FNAME" = "" ] ; then
	if [ "$DEBUG" = True ] ; then
            logMessage "$TASKNM" "'$DOCKER_DIR' directory has no valid Docker Compose YAML file!"
	fi
        exitTask "-" 1
    fi

    # Check the work YAML and backup YAML is the same one or not
    RES=`diff -r $CURDIR $BAKDIR`
    if [ ! "$RES" = "" ] ; then
        logMessage "$TASKNM" "Begin process '$FNAME'."
        logMessage "$TASKNM" "Use '$SERVICE' as service name."

        # Convert process
        procDocker2K8s
        procK8s2Helm
        procHelm2Tarball
        uploadTarball

        rm -r -f $BACK_DIR/$DOCKER_DIR
        rm -r -f $BACK_DIR/$K8S_DIR
        rm -r -f $BACK_DIR/$HELM_DIR
        cp -p -a $WORK_DIR/$DOCKER_DIR $BACK_DIR
        cp -p -a $WORK_DIR/$K8S_DIR $BACK_DIR
        cp -p -a $WORK_DIR/$HELM_DIR $BACK_DIR
	if [ "$DEBUG" = True ] ; then
            logMessage "$TASKNM" "cp -p -a $WORK_DIR/$DOCKER_DIR $BACK_DIR"
            logMessage "$TASKNM" "cp -p -a $WORK_DIR/$K8s_DIR $BACK_DIR"
            logMessage "$TASKNM" "cp -p -a $WORK_DIR/$HELM_DIR $BACK_DIR"
        fi
        exitTask "Process End." 0
    fi
    if [ "$DEBUG" = True ] ; then
        logMessage "$TASKNM" "The work YAML and backup YAML is the same one, skip processing."
    fi
}

### Check K8s YAML files
function checkK8sResource {
    CURDIR=$WORK_DIR/$K8S_DIR
    BAKDIR=$BACK_DIR/$K8S_DIR
    TASKNM=checkK8sResource

    # Check the work K8s resources and backup K8s resources are the same one or not
    RES=`diff -r $CURDIR $BAKDIR`
    if [ ! "$RES" = "" ] ; then
        logMessage "$TASKNM" "Begin process K8s resource files."

        # Convert process
        procK8s2Helm
        procHelm2Tarball
        uploadTarball

        rm -r -f $BACK_DIR/$K8S_DIR
        rm -r -f $BACK_DIR/$HELM_DIR
        cp -p -a $WORK_DIR/$K8S_DIR $BACK_DIR
        cp -p -a $WORK_DIR/$HELM_DIR $BACK_DIR
	if [ "$DEBUG" = True ] ; then
            logMessage "$TASKNM" "cp -p -a $WORK_DIR/$K8s_DIR $BACK_DIR"
            logMessage "$TASKNM" "cp -p -a $WORK_DIR/$HELM_DIR $BACK_DIR"
	fi
        exitTask "Process End." 0
    fi
    if [ "$DEBUG" = True ] ; then
        logMessage "$TASKNM" "The work K8s resources and backup K8s resources are the same, skip processing."
    fi
}

### Check Helm Chart files
function checkHelmChart {
    CURDIR=$WORK_DIR/$HELM_DIR
    BAKDIR=$BACK_DIR/$HELM_DIR
    TASKNM=checkHelmChart

    # Check the work Helm charts and backup Helm charts are the same one or not
    RES=`diff -r $CURDIR $BAKDIR`
    if [ ! "$RES" = "" ] ; then
        logMessage "$TASKNM" "Begin process K8s resource files."

        # Convert process
        procHelm2Tarball
        uploadTarball

        rm -r -f $BACK_DIR/$HELM_DIR
        cp -p -a $WORK_DIR/$HELM_DIR $BACK_DIR
	if [ "$DEBUG" = True ] ; then
            logMessage "$TASKNM" "cp -p -a $WORK_DIR/$HELM_DIR $BACK_DIR"
	fi
        exitTask "Process End." 0
    fi
    if [ "$DEBUG" = True ] ; then
        logMessage "$TASKNM" "the work Helm charts and backup Helm charts are the same, skip processing."
    fi
}

##################################################
### Main Process
if [ "$DEBUG" = True ] ; then
    logMessage "Main" "Begin."
fi
checkDockerCompose
checkK8sResource
checkHelmChart
if [ "$DEBUG" = True ] ; then
    logMessage "Main" "End."
    exitTask "Main" 0
fi

