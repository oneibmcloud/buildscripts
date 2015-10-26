#!/usr/bin/env bash
#
# Description
# ===========
# This script does a blue-green deployment of an app to Bluemix. It assumes
# the user has already logged in. This is done on behalf of the user when running on
# IBM Bluemix DevOps Services Build & Deploy pipelines. 
#
# The script can do the following things:
# . Pushes the application
# . Set environment variables
# . Map Routes
# . Bind services
# . Start the application
# . Notify a Slack channel upon completion
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
# 1. Location of the manifest.yml file
#****************************************************************

#############
# Functions 
#############

notify_slack () {
   curl -X POST --data-urlencode "payload={ \"attachments\": [{\"title\": \"Job ${BUILD_NUMBER} - Deployment of ${GREEN_APP} failed. \",  \"color\": \"danger\", \"text\": \"<!channel> ${MESSAGE}\"}]}" ${SLACK_WEBHOOK_PATH}
}

#############
# Variables
#############

BLUE_APP="${CF_APP}-blue"
GREEN_APP="${CF_APP}-green"
GREEN_APP_BACKUP="${CF_APP}-green-backup"
#DOMAIN="oneibmcloud.com"
DOMAIN="mybluemix.net"

#############
# Main Steps
#############

set +e

#############
# (1) If the blue exits, exit and ask user to clean up before restarting.
#############
cf app ${BLUE_APP}
BLUE_APP_EXISTS=$?
if [ $BLUE_APP_EXISTS -eq 0 ]; then
   MESSAGE="${BLUE_APP} exits, delete the app manually and restart the deploy. To clean up, on the command line run- cf delete ${BLUE_APP}"
   notify_slack && exit 1
fi

#############
# (2) Push a new version of the app
#############
BLUE_APP_PUSH=$?
if [ $BLUE_APP_PUSH -ne 0 ]; then
   MESSAGE="Deployment of $BLUE_APP failed"
   notify_slack && exit 1
fi

echo "${BLUE_APP} deployed"
cf apps | grep ${BLUE_APP}

#############
# (3) Set environment variables
#############
cf set-env ${BLUE_APP} SENDGRID_APIKEY ${SENDGRID_APIKEY}

#############
# (4) Start blue app
#############
cf start ${BLUE_APP}
START_BLUE_APP=$?
if [ $START_BLUE_APP -ne 0 ]; then
   MESSAGE="${BLUE_APP} failed to start, check manually and perform any clean up necessary"
   notify_slack && exit 1
fi

#############
# (5) Test blue app
#############
APP_URL="https://${BLUE_APP}.${DOMAIN}"
for i in {1..3}; do
    CURL_EXIT=`curl "$APP_URL" -s -k -w "%{http_code}" -X POST -H 'Content-Type: application/json' -d "$JSON" -o /dev/null`
    if [ '200' == "$CURL_EXIT" ]; then
        echo "${APP_URL} notified successfully."
        break
    elif [ $i == 3 ]; then
        MESSAGE="${APP_URL} notification failed. Code $CURL_EXIT."
        notify_slack 
        exit 1
    else
        echo "${APP_URL} notification failed. Code $CURL_EXIT. Retrying..."
        sleep 2
    fi
done

#############
# (6) Map traffic to the new version of the app by binding to public host
# Note: The old version is still taking traffic to avoid disruption in 
# service
#############
cf map-route ${BLUE_APP} ${DOMAIN} -n ${CF_APP}
MAPROUTE_BLUE=$?
if [ $MAPROUTE_BLUE -ne 0 ]; then 
   MESSAGE="Failed to create the public route ${CF_APP}."
   notify_slack && exit 1
fi

echo "Public route bindings"
cf routes | grep ' $CF_APP '

#############
# (7) Delete the temporary route that was used for testing since
# it is not longer needed.
#############
cf unmap-route ${BLUE_APP} $DOMAIN -n ${BLUE_APP}
if [ $? -ne 0 ]; then
   echo "Test route isn't mapped and didn't have to be removed"
fi
cf delete-route $DOMAIN -n ${BLUE_APP} -f

#############
# 8) rename green green-backup
#############
cf app ${GREEN_APP_BACKUP}
if [ $? -eq 0 ]; then
   echo "${GREEN_APP_BACKUP} exists, removing it before creating a new backup"
   cf delete ${GREEN_APP_BACKUP} -f
   if [ $? -ne 0 ]; then
      MESSAGE="Removing ${GREEN_APP_BACKUP} failed, manually recover from this failure."
      notify_slack && exit 1
   fi
fi

cf rename ${GREEN_APP} ${GREEN_APP_BACKUP}
if [ $? -ne 0 ]; then
   MESSAGE="Creating backup of previously deployed app failed, manually recover from this failure."
   notify_slack && exit 1
fi

#############
# 9) Rename blue -> green
#############
cf rename ${BLUE_APP} ${GREEN_APP}
if [ $? -ne 0 ]; then
   MESSAGE="Failed to rename ${BLUE_APP} to ${GREEN_APP}, manually recover from this failure."
   notify_slack && exit 1
fi

#############
# 10) Stop backup app
#############
cf stop ${GREEN_APP_BACKUP}
if [ $? -ne 0 ]; then
   MESSAGE="Manually stop ${GREEN_APP_BACKUP}"
   notify_slack && exit 1
fi
set -e
