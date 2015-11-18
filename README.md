## Blue Green Deploy
##### From IBM Bluemix DevOps Services to Bluemix

### Introduction

The ```blue-green-deploy.sh``` script deploys an application from a _Deploy Stage_, on a project created at IBM Bluemix DevOps Services (IDS), to Bluemix. It is assumed that the user has created a pipeline in IDS and is ready to deploy the application.

### Configuration
The script depends on environment variables having been set on the _Deploy Stage_. Some variables assume a default value if they have not been defined. See the script for more details.

These environment variables are:

|  Variable             |  Default Value  | Comment            |
|-----------------------|:--------------- |:-------------------|
| MANIFEST_FILE         | manifest.yml    | current directory  |
| MY_DOMAIN             |                 | Bluemix domain name     |
| SLACK_WEBHOOK_PATH    |                 | URL of Slack hook integration |
| APP_PUSH_DIR          | (top level dir) | directory from where to run ```cf push```|
| URL_PATH_PAGE         |  (blank)        | application's URL path page |

If environment variables and routes are defined for the application, they are defined as follows:

|  Variable      |  Value                              |
|----------------|:---------------|:-------------------|
| APP_EVNS       |ENV1,ENV2,ENV3... List of ENVs to be processed by the script, each ENV must be defined separately|
| ROUTES         |routes that should be mapped to the application. The value should take the from of  host1:domain1,host2:domain2,domain3 |
| SERVICES       |services that should be bound to the application, the value should take the form servicename1,servicename2                   |
| CF_PUSH_ARGS | a string of arguments to use when ```cf push``` is called                    |


NOTES: Processing the SERVICES has not been implemented but it can be done very similarly to ROUTES.

### Script Implementation

The main purpose of the script is to deploy an application as gracefully as possible from Green to Blue, minimizing the downtime. The script accomplishes this by manipulating the routes. After the script has deployed Blue and verified that is up and responding, there is going to be a very small period of time while the old and new versions of the applications are running simultaneously; as Blue migrates to Green and Green gets renamed to the backup version.

If the script fails at any point, the Blue instance most likely has been pushed already and needs to be deleted before re-running the script. 

### Future Improvement
There is room for improvment:

* The script creates a back up of the old application. A script could be written to roll back in the event that the new application doesn not perform as expected. 

* The messages posted to Slack could be formatted more nicely, in particular those reporting error messages, for example using syntax highlighting.
