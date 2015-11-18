#!/usr/bin/env bash
#
# Description
# ===========
# This script does a blue-green deploy of an app to Bluemix. It assumes
# the user has already logged in. This script is written to be used by 
# a deploy stage running in an IBM Bluemix DevOps Services Build & Deploy pipeline.
#
# The script can do the following things:
# 1. Pushes the application
# 2. Set environment variables
# 3. Map Routes
# 4. Bind services
# 5. Start the application
# 6. Notify a Slack channel upon completion or when there is a failure
#
# Environment variables
# =====================
# This script processes environment variables to:
# 1. set envs for the application
# 2. add routes to the application
# 3. add services to the application
# 4. add arguments to the 'cf push' command
#
# There are other environment variables that need to be set, such as:
# 1. Slack web hook URL
# 2. Location of the manifest.yml file
# 3. Directory where to run 'cf push' from, the default is the top level directory
# 4. Root URL of the app if different from the default
#****************************************************************

#------------
# Functions
#------------


notify_slack () {
   MSG=${1-"Visit ${WIKI} for more information."}
   EMOJI=${2-:dash:}
   COLOR=${3-#ffd400}
   if [[ "$COLOR" == "$GREEN" ]]; then
      curl -X POST --data-urlencode "payload={\"icon_emoji\": \"${EMOJI}\",\"username\": \"JOB ${BUILD_NUMBER} - Project->${IDS_PROJECT_NAME}\", \"attachments\": [{\"title\": \"Stage -> ${IDS_STAGE_NAME} started by ${BUILD_USER_ID} \",  \"color\": \"${COLOR}\", \"text\": \"${MSG}\"}]}" ${SLACK_WEBHOOK_PATH}
   else 
      curl -X POST --data-urlencode "payload={\"icon_emoji\": \"${EMOJI}\",\"username\": \"JOB ${BUILD_NUMBER} - Project->${IDS_PROJECT_NAME}\", \"attachments\": [{\"title\": \"Stage -> ${IDS_STAGE_NAME} started by ${BUILD_USER_ID} \",  \"color\": \"${COLOR}\", \"text\": \"<!channel> ${MSG}\"}]}" ${SLACK_WEBHOOK_PATH}
   fi 
}
#-------------
# Variables
#-------------

BLUE_APP="${CF_APP}-blue"
GREEN_APP="${CF_APP}-green"
GREEN_APP_BACKUP="${CF_APP}-green-backup"

# emoji
FAILED=":x:"
PASSED=":white_check_mark:"

# colors
GREEN=good
YELLOW=warning
RED=danger

#-------------
# Main Steps
#
# Other environment variables, set in the ENVIRONMENT PROPERTIES of 
# the stage running this script. These are:
# SLACK_WEBHOOK_PATH
# CF_PUSH_ARGS
# MY_DOMAIN 
# MANIFEST_FILE
# APP_PUSH_DIR
# URL_PATH_PAGE
# ROUTES
# APP_ENVS
# SERVICES
#-------------

# Set defaults
DOMAIN=${MY_DOMAIN:-"mybluemix.net"}
MANIFEST_FILE=${MANIFEST_FILE:-manifest.yml}
PATH_PAGE=${URL_PATH_PAGE:-""}
CF_PUSH_ARGS=${PUSH_ARGS:-""}
PUSH_DIR=${APP_PUSH_DIR:-.}
WIKI="https://github.com/oneibmcloud/buildscripts"

# The SLACK_WEBHOOK_PATH environment variable is expected to be set to report status. 
# NOTE: Modify the script if a different mechanism for reporting status is used.
if [[ -z ${SLACK_WEBHOOK_PATH} ]]; then
   echo "Environment variable SLACK_WEBHOOK_PATH has not been set, set it to the URL of the Slack web hook integration."
   exit 1
fi

CF="cf"

set +e
#-------------
# (1) If the blue app exits, exit and ask the user to clean up before restarting.
#-------------
BLUE_ERR_MESSAGE="Found ${BLUE_APP} on Bluemix. Delete the application by running *cf delete ${BLUE_APP} -f* and rerun the deploy stage."  
$CF app ${BLUE_APP}
if [ $? -eq 0 ]; then
   notify_slack "${BLUE_ERR_MESSAGE}" ${FAILED} ${RED} && exit 1
fi

#-------------
# (2) Push a new version of the app.
#-------------
PUSH_ERR_MESSAGE="*cf push* failed. Open log, find the cause of the error, correct he problem and rerun the deploy stage."
cd ${PUSH_DIR}
$CF push ${BLUE_APP} -n ${BLUE_APP} ${CF_PUSH_ARGS} -d ${DOMAIN} -f ${MANIFEST_FILE} --no-start
if [ $? -ne 0 ]; then
   notify_slack "${PUSH_ERR_MESSAGE}" ${FAILED} ${RED} && exit 1
fi

echo "${BLUE_APP} deployed"
$CF apps | grep ${BLUE_APP}

#-------------
# (3) Set environment variables.
#-------------
SETENV_ERR_MESSAGE="*cf set-env* failed. Make sure the ENV value was set up and parsed correctly. Open the log, find the cause of the error, correct the problem and rerun the deploy stage."
if [[ -z "${APP_ENVS}" ]]; then
   echo "********** Application has no environment variables to set **********"
else 
   echo "********** Setting environment variables **********"
   IFS=', ' read -r -a array_envs <<< "${APP_ENVS}"
   for element in "${array_envs[@]}"; do
     echo " *** Element in array_envs is : $element ***"
     echo "Variable: $element ***** Value: ${!element}"
     $CF set-env ${BLUE_APP} ${element} "`eval echo ${!element}`"
     if [ $? -ne 0 ]; then
        notify_slack "${SETENV_ERR_MESSAGE}" ${FAILED} ${RED} && exit 1
     fi
   done
fi

#-------------
# (4) Start blue app.
#------------- 
BLUESTART_ERR_MESSAGE="*cf start* failed to start ${BLUE_APP}. Open the log, correct the problem, delete ${BLUE_APP} and restart the deploy."
$CF start ${BLUE_APP}
if [ $? -ne 0 ]; then
   notify_slack "${BLUESTART_ERR_MESSAGE}" ${FAILED} ${RED} && exit 1
fi

#-------------
# (5) Test blue app.
#-------------
URL_ERR_MESSAGE="*curl* failed to contact ${APPL_URL}, it returned ${CURL_EXIT}. Investigate the problem, delete ${BLUE_APP} and restart the deploy."
APP_URL="https://${BLUE_APP}.${DOMAIN}/${PATH_PAGE}"
for i in {1..3}; do
#    CURL_EXIT=`curl "$APP_URL" -s -k -w "%{http_code}" -X POST -H 'Content-Type: application/json' -d "$JSON" -o /dev/null`
    CURL_EXIT=`curl "$APP_URL" -w  %{http_code} -s -k -S -o /dev/null`
    if [[ '200' == "$CURL_EXIT" ]]; then
        echo "${APP_URL} notified successfully."
        break
    elif [[ $i == 3 ]]; then
        notify_slack "${URL_ERR_MESSAGE}" ${FAILED} ${RED} && exit 1
    else
        echo "${APP_URL} notification failed. Code $CURL_EXIT. Retrying..."
        sleep 2
    fi
done

#-------------
# (6) Route traffic to the new instance of the app by binding to the public host.
# Note: The old version is still taking traffic to avoid disruption in service.
#------------- 
MAPROUTE_ERR_MESSAGE="*cf map-route* failed, Investigate the problem, delete ${BLUE_APP} and restart the deploy."
$CF map-route ${BLUE_APP} ${DOMAIN} -n ${CF_APP}
if [ $? -ne 0 ]; then
   notify_slack "${MAPROUTE_ERR_MESSAGE}" ${FAILED} ${RED} && exit 1
fi

# Map additional routes
if [[ -z ${ROUTES} ]]; then
   echo "*********** No additional routes to map ***********"
else 
   echo "Mapping routes in order to balance traffic"
   IFS=',' read -a routesarray <<< "$ROUTES"
   for element in "${routesarrary[@]}"
   do
      if [[ $element == *":"* ]]; then
         IFS=':' read -a route <<< "$element"
         $CF map-route ${BLUE_APP} ${route[1]} -n ${route[0]}
      else
         $CF map-route ${BLUE_APP} $element
      fi
      if [ $? -ne 0 ]; then
         notify_slack "${MAPROUTE_ERR_MESSAGE}" ${FAILED} ${RED} && exit 1
      fi
   done
fi

echo "Public route bindings"
$CF routes | grep ' $CF_APP '
#-------------
# (7) Delete the temporary route that was used for testing, it is not longer needed.
#-------------
DELROUTE_ERR_MESSAGE="*cf delete-route* failed. Investigate the problem, delete ${BLUE_APP} and restart the deploy."
$CF unmap-route ${BLUE_APP} $DOMAIN -n ${BLUE_APP}
if [ $? -ne 0 ]; then
   echo "Test route isn't mapped and didn't have to be removed"
fi
$CF delete-route $DOMAIN -n ${BLUE_APP} -f
if [ $? -ne 0 ]; then
   notify_slack "${DELROUTE_ERR_MESSAGE}" 7 ${FAILED} ${RED} && exit 1
fi

#-------------
# 8) Rename green to green-backup, thus preserving previous version.
#-------------
DELGREEN_ERR_MESSAGE="*cf delete* ${GREEN_APP_BACKUP} failed. Investigate the problem, delete ${BLUE_APP} and restart the deploy."
$CF app ${GREEN_APP_BACKUP}
if [ $? -eq 0 ]; then
   echo "${GREEN_APP_BACKUP} exists, removing it before creating a new backup"
   $CF delete ${GREEN_APP_BACKUP} -f
   if [ $? -ne 0 ]; then
      notify_slack "${DELGREEN_ERR_MESSAGE}" ${FAILED} ${RED} && exit 1
   fi
fi

# This is neecessary if for some reason the Green app has been deleted or has 
# not been created yet, eg the first time this script runs
RENAME_ERR_MESSAGE="*cf rename* ${GREEN_APP} failed. Investigate the problem, delete ${BLUE_APP} and restart the deploy."
$CF app ${GREEN_APP}
if [ $? -eq 0 ]; then
   $CF rename ${GREEN_APP} ${GREEN_APP_BACKUP}
   if [ $? -ne 0 ]; then
      notify_slack "${RENAME_ERR_MESSAGE}" ${FAILED} ${RED}&& exit 1
   fi
fi

#-------------
# 9) Rename blue -> green
#-------------
BR_ERR_MESSAGE="*cf rename* ${BLUE_APP} failed. Investigate the problem, delete ${BLUE_APP} and restart the deploy."
$CF rename ${BLUE_APP} ${GREEN_APP}
if [ $? -ne 0 ]; then
   notify_slack "${BR_ERR_MESSAGE}" ${FAILED} ${RED} && exit 1
fi

#-------------
# 10) Stop backup app
#-------------
BACKUP_ERR_MESAGE="Steps to create a back up of the existing ${GREEN_APP} failed. Investigate the problem, delete ${BLUE_APP} and restart the deploy."
$CF map-route ${GREEN_APP_BACKUP} ${DOMAIN} -n ${GREEN_APP_BACKUP}
if [ $? -ne 0 ]; then
   notify_slack "${BACKUP_ERR_MESSAGE}" ${FAILED} ${RED} && exit 1
fi
$CF unmap-route ${GREEN_APP_BACKUP} ${DOMAIN} -n ${CF_APP}
if [ $? -ne 0 ]; then
   notify_slack "${BACKUP_ERR_MESSAGE}" ${FAILED} ${RED} && exit 1
fi
for i in {1..3}; do
   $CF stop ${GREEN_APP_BACKUP}
   if [ $? -eq 0 ]; then
      echo "${GREEN_APP_BACKUP} was stopped successfully, done!"
      break
   elif [ $i -eq 3 ]; then
      notify_slack "${BACKUP_ERR_MESSAGE}" ${FAILED} ${RED} && exit 1
   else
      echo "Retrying $i 'cf stop'..."
      sleep 2
   fi
done

#-------------
# 11) Post a successful message to Slack
#-------------
notify_slack "${GREEN_APP} deployed successfully!!!" ${PASSED} ${GREEN} 
set -e
