#!/usr/bin/env bash
#
# Description
# ===========
# This script does a blue-green deploy of an app to Bluemix. It assumes
# the user has already logged in. This script is tailored to be used by 
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
#
# There are other environment variables that need to be set, such as:
# 1. Slack web hook URL
# 2. Location of the manifest.yml file
# 3. Directory where to run 'cf push' from, the default is the top level directory
# 4. Root URL of the app if different from the default
#****************************************************************

#############
# Functions
#############

notify_slack () {
   MSG=${1-"Visit ${WIKI} for more information."}
   STEP=${2-unknown}
   EMOJI=${3-:dash:}
   COLOR=${4-#ffd400}
   curl -X POST --data-urlencode "payload={\"icon_emoji\": \"${EMOJI}\",\"username\": \"JOB ${BUILD_NUMBER}\", \"attachments\": [{\"title\": \"Job ${BUILD_NUMBER} - Step ${STEP} \",  \"color\": \"${COLOR}\", \"text\": \"<!channel> ${MSG}\"}]}" ${SLACK_WEBHOOK_PATH}
}

#############
# Variables
#############

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

#############
# Main Steps
#
# Other environment variables, set in the ENVIRONMENT PROPERTIES of 
# the stage running this script. These are:
# SLACK_WEBHOOK_PATH
# MANIFEST_FILE
# APP_PUSH_DIR
# URL_PATH_PAGE
# ROUTES
# ENVS
# SERVICES
# MY_DOMAIN 
# FAILURE_RECOVERY_WIKI
#############

# Set defaults
DOMAIN=${MY_DOMAIN:-"mybluemix.net"}
PATH_PAGE=${URL_PATH_PAGE:-""}
PUSH_DIR=${APP_PUSH_DIR:-.}
WIKI=${FAILURE_RECOVERY_WIKI:-"https://github.com/oneibmcloud/buildscripts"}

# The location of the manifest needs to be set.
if [ -z ${MANIFEST_FILE} ]; then
   echo "Environment variable MANIFEST_FILE not set, set it to the path of the manifest file."
   exit 1
fi

# default generic message
ERR_MESSAGE="Visit ${WIKI} for instructions on how to recover from this failure."

CF="cf"

set +e
#############
# (1) If the blue app exits, exit and ask user to clean up before restarting.
#############
$CF app ${BLUE_APP}
if [ $? -eq 0 ]; then
   notify_slack "${ERR_MESSAGE}" 1 ${FAILED} ${RED} && exit 1
fi

#############
# (2) Push a new version of the app.
#############
cd ${PUSH_DIR}
$CF push ${BLUE_APP} -n ${BLUE_APP} -f ${MANIFEST_FILE} --no-start
if [ $? -ne 0 ]; then
   notify_slack "${ERR_MESSAGE}" 2 ${FAILED} ${RED} && exit 1
fi

echo "${BLUE_APP} deployed"
$CF apps | grep ${BLUE_APP}

#############
# (3) Set environment variables.
#############
if [ -z ${ENVS} ]; then
   echo "********** Application has no environment variables to set **********"
else 
   echo "********** Setting environment variables **********"
   IFS==',' read -a envvararray <<< "${ENVS}"
   for element in "${envvararray[@]}"
      do
        var="$(sed 's/:.*//' <<< "$element")"
        value="$(sed 's/^[^:]*://' <<< "$element")"
        echo "***** variable = ${var} and value = ${value} ******"
        $CF set-env ${BLUE_APP} ${var} "${value}"
   done
fi

#############
# (4) Start blue app.
#############
$CF start ${BLUE_APP}
if [ $? -ne 0 ]; then
   notify_slack "${ERR_MESSAGE}" 4 ${FAILED} ${RED} && exit 1
fi

#############
# (5) Test blue app.
#############
APP_URL="https://${BLUE_APP}.${DOMAIN}/${PATH_PAGE}"
for i in {1..3}; do
    CURL_EXIT=`curl "$APP_URL" -s -k -w "%{http_code}" -X POST -H 'Content-Type: application/json' -d "$JSON" -o /dev/null`
    if [ '200' == "$CURL_EXIT" ]; then
        echo "${APP_URL} notified successfully."
        break
    elif [ $i == 3 ]; then
        notify_slack "${ERR_MESSAGE}i" 5 ${FAILED} ${RED} && exit 1
    else
        echo "${APP_URL} notification failed. Code $CURL_EXIT. Retrying..."
        sleep 2
    fi
done

#############
# (6) Route traffic to the new instance of the app by binding to public host.
# Note: The old version is still taking traffic to avoid disruption in service.
#############
$CF map-route ${BLUE_APP} ${DOMAIN} -n ${CF_APP}
if [ $? -ne 0 ]; then
   notify_slack "${ERR_MESSAGE}" 6 ${FAILED} ${RED} && exit 1
fi

# Map additional routes
if [ -z ${ROUTES} ]; then
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
   done
fi

echo "Public route bindings"
$CF routes | grep ' $CF_APP '
#############
# (7) Delete the temporary route that was used for testing, it is not longer needed.
#############
$CF unmap-route ${BLUE_APP} $DOMAIN -n ${BLUE_APP}
if [ $? -ne 0 ]; then
   echo "Test route isn't mapped and didn't have to be removed"
fi
$CF delete-route $DOMAIN -n ${BLUE_APP} -f

#############
# 8) Rename green to green-backup, thus preserving previous version.
#############
$CF app ${GREEN_APP_BACKUP}
if [ $? -eq 0 ]; then
   echo "${GREEN_APP_BACKUP} exists, removing it before creating a new backup"
   $CF delete ${GREEN_APP_BACKUP} -f
   if [ $? -ne 0 ]; then
      notify_slack "${ERR_MESSAGE}" 8 ${FAILED} ${RED} && exit 1
   fi
fi

# This is neecessary if for some reason the Green app has been deleted or has 
# not been created year, eg the first time this script runs
$CF app ${GREEN_APP}
if [ $? -eq 0]; then
   $CF rename ${GREEN_APP} ${GREEN_APP_BACKUP}
   if [ $? -ne 0 ]; then
      notify_slack "${ERR_MESSAGE}" 8.1 ${FAILED} ${RED}&& exit 1
   fi
fi

#############
# 9) Rename blue -> green
#############
$CF rename ${BLUE_APP} ${GREEN_APP}
if [ $? -ne 0 ]; then
   notify_slack "${ERR_MESSAGE}" 9 ${FAILED} ${RED} && exit 1
fi

#############
# 10) Stop backup app
#############
$CF map-route ${GREEN_APP_BACKUP} ${DOMAIN} -n ${GREEN_APP_BACKUP}
if [ $? -ne 0 ]; then
   notify_slack "${ERR_MESSAGE}" 10.1 ${FAILED} ${RED} && exit 1
fi
$CF unmap-route ${GREEN_APP_BACKUP} ${DOMAIN} -n ${CF_APP}
if [ $? -ne 0 ]; then
   notify_slack "${ERR_MESSAGE}" 10.2 ${FAILED} ${RED} && exit 1
fi
for i in {1..3}; do
   $CF stop ${GREEN_APP_BACKUP}
   if [ $? -eq 0 ]; then
      echo "${GREEN_APP_BACKUP} was stopped successfully, done!"
      break
   elif [ $i -eq 3 ]; then
      notify_slack "${ERR_MESSAGE}" 10.3 ${FAILED} ${RED} && exit 1
   else
      echo "Retrying $i 'cf stop'..."
      sleep 2
   fi
done

#############
# 11) Post a successful message to Slack
#############
notify_slack "${GREEN_APP} deployed successfully!!!" 11 ${PASSED} ${GREEN} 
set -e
