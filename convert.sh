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
    DTIME=`date +%Y-%m-%d-%H:%M:%S`
    echo "$DTIME:$1: $2" >> $WORK_DIR/$LOG
}

function exitTask {
    DTIME=`date +%Y-%m-%d-%H:%M:%S`
    if [ ! "$1" = "-" ] ; then
        echo "$DTIME:$1: exit $2" >> $WORK_DIR/$LOG
        echo "" >> $WORK_DIR/$LOG
    fi
    exit $2
}

# Convert docker-compose.yaml to K8s resource files
function procDocker2K8s {
    CURDIR=$WORK_DIR/$K8S_DIR
    logMessage "procDocker2K8s" "Create K8s resource files to '$K8S_DIR' directory."
    RES=`kompose convert -f $FNAME --with-kompose-annotation=false --out $CURDIR 2>&1`
    logMessage "procDocker2K8s" "'$RES'"
    for FN in "$CURDIR"/* ; do
        #echo $FN
        if [[ "$FN" = *"networkpolicy"* ]] ; then
            sed -e 's,true,false,g' -i $FN
            logMessage "procDocker2K8s" "Change '$FN' configuration value from 'true' to 'false'."
            break
        fi
    done
}

# Build Helm chart from K8s resource files
function procK8s2Helm {
    CURDIR=$WORK_DIR/$HELM_DIR
    logMessage "procK8s2Helm" "Create helm chart files to '$HELM_DIR/$SERVICE' directory."
    RES=`awk 'FNR==1 && NR!=1  {print "---"}{print}' $WORK_DIR/$K8S_DIR/*.yaml | helmify $CURDIR/$SERVICE 2>&1`
    if [ ! "$RES" = "" ] ; then
        logMessage "procK8s2Helm" "'$RES'"
    fi
}

# Package Helm Chart to package tarball
function procHelm2Tarball {
    CURDIR=$WORK_DIR/$PACKAGE_DIR
    logMessage "procHelm2Tarball" "Package helm chart files to '$PACKAGE_DIR' directory."
    cd $CURDIR
    if [ -d "$WORK_DIR/$HELM_DIR/$SERVICE" ] ; then
        RES=`helm package $WORK_DIR/$HELM_DIR/$SERVICE 2>&1`
        if [ ! "$RES" = "" ] ; then
            logMessage "procHelm2Tarball" "'$RES'"
            TARBALL=`echo $RES | awk 'BEGIN {FS=":"} {print $2}'`
	fi
    else
        logMessage "procHelm2Tarball" "'$WORK_DIR/$HELM_DIR/$SERVICE' not existed!"
        exitTask "procHelm2Tarball" 1
    fi
}

# Upoad tarball to Harbor
function uploadTarball {
    logMessage "uploadTarball" "Upoad tarball '$TARBALL' to Harbor."
    RES=`curl -s --insecure -X POST "https://$HARBOR_HOST:$HARBOR_PORT/api/chartrepo/library/charts" -u "$HARBOR_USER:$HARBOR_PASS" -H "Content-Type: multipart/form-data" -H "accept: application/json" -F "chart=@${TARBALL};type=application/x-compressed-tar"`
    logMessage "uploadTarball" "'$RES'"
}

##################################################
### Check docker-compose.yaml
function checkDockerCompose {
    CURDIR=$WORK_DIR/$DOCKER_DIR
    BAKDIR=$BACK_DIR/$DOCKER_DIR

    # Check '$DOCKER_DIR' directory is Empty or not
    if [ ! "$(ls -A $CURDIR)" ]; then
        #logMessage "checkDockerCompose" "'$DOCKER_DIR' directory is Empty!"
        exitTask "-" 1
    fi

    # '$DOCKER_DIR' directory is not empty, and find valid YAML file
    for FN in "$CURDIR"/* ; do
        #echo $FN
        if [[ "$FN" = *"$LOG"* ]] ; then
            continue
        fi
        RES=`yq eval "(.services[] | key)" $FN 2>&1`
        if [ ! "$?" = "0" ] ; then
            logMessage "checkDockerCompose" "'$RES'"
            exitTask "-" 1
        fi
        if [ ! "$RES" = "" ] ; then
            FNAME=$FN
            SERVICE=`echo $RES | awk 'BEGIN {FS=" "} {print $1}'`
            break
        fi
    done
    if [ "$FNAME" = "" ] ; then
        #logMessage "checkDockerCompose" "'$DOCKER_DIR' directory has no valid Docker Compose YAML file!"
        exitTask "-" 1
    fi

    # Check the work YAML and backup YAML is the same one or not
    RES=`diff -r $CURDIR $BAKDIR`
    if [ ! "$RES" = "" ] ; then
        logMessage "checkDockerCompose" "Begin process '$FNAME'."
        logMessage "checkDockerCompose" "Use '$SERVICE' as service name."

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
        exitTask "Process End." 0
    fi
}

### Check K8s YAML files
function checkK8sResource {
    CURDIR=$WORK_DIR/$K8S_DIR
    BAKDIR=$BACK_DIR/$K8S_DIR

    # Check the work K8s resources and backup K8s resources are the same one or not
    RES=`diff -r $CURDIR $BAKDIR`
    if [ ! "$RES" = "" ] ; then
        logMessage "checkK8sResource" "Begin process K8s resource files."

        # Convert process
        procK8s2Helm
        procHelm2Tarball
        uploadTarball

        rm -r -f $BACK_DIR/$K8S_DIR
        rm -r -f $BACK_DIR/$HELM_DIR
        cp -p -a $WORK_DIR/$K8S_DIR $BACK_DIR
        cp -p -a $WORK_DIR/$HELM_DIR $BACK_DIR
        exitTask "Process End." 0
    fi
}

### Check Helm Chart files
function checkHelmChart {
    CURDIR=$WORK_DIR/$HELM_DIR
    BAKDIR=$BACK_DIR/$HELM_DIR

    # Check the work Helm charts and backup Helm charts are the same one or not
    RES=`diff -r $CURDIR $BAKDIR`
    if [ ! "$RES" = "" ] ; then
        logMessage "checkHelmChart" "Begin process K8s resource files."

        # Convert process
        procHelm2Tarball
        uploadTarball

        rm -r -f $BACK_DIR/$HELM_DIR
        cp -p -a $WORK_DIR/$HELM_DIR $BACK_DIR
        exitTask "Process End." 0
    fi
}

##################################################
### Main Process
checkDockerCompose
checkK8sResource
checkHelmChart

