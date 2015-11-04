## Blue Green Deploy
##### From IBM Bluemix DevOps Services to Bluemix

### Introduction

The ```blue-green-deploy.sh``` script deploys an application from a _Deploy Stage_ on IBM Bluemix DevOps Services (IDS) to Bluemix. It is assumed that the user has created a pipeline in IDS and is ready to deploy the application.

### Configuration
The script depends on some environment variables having been set. In some cases, if they have not been set, a default is used. 
These are:

|  Variable             |  Default Value  | Comment            |
|-----------------------|:--------------- |:-------------------|
| MANIFEST_FILE         | manifest.yml    | current directory  |
| MY_DOMAIN             |                 | Bluemix domain name     |
| SLACK_WEBHOOK_PATH    |                 | URL of Slack hook integration |
| APP_PUSH_DIR          | (top level dir) | directory from where to run ```cf push```|
| URL_PATH_PAGE         |                 | application's URL path page |

If set, the script also processes variables intended to be set for the application.

|  Variable      |  Value                              |
|----------------|:---------------|:-------------------|
| ENVS           |application environment variables to be set, the value should be name1:value1,name2:value2 |
| ROUTES         |routes that should be mapped to the application. The value should take the from of  host1:domain1,host2:domain2,domain3 |
| SERVICES       |services that should be bound to the application, the value should take the form servicename1,servicename2                   |
| CF_PUSH_ARGS | a string of arguments to use when ```cf push``` is called                    |


