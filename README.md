## Blue Green Deploy
##### From IBM Bluemix DevOps Services to Bluemix

### Introduction

The ```blue-green-deploy.sh``` script deploys an application from a _Deploy Stage_ on IBM Bluemix DevOps Services (IDS) to Bluemix. It is assumed that the user has created a pipeline in IDS and is ready to deploy the application.

### Configuration
The script depends on some environment variables having been set. In some cases, if they have not been set, a default is used. 
These are:

|  Variable             |  Default Value  | Comment            |
|-----------------------|:---------------:|-------------------:|
| MANIFEST_FILE         | manifest.yml    | current directory  |
| MY_DOMAIN             |                 | Bluemix domain name     |
| SLACK_WEBHOOK_PATH    |                 | URL of Slack hook integration |
| APP_PUSH_DIR          | (top level dir) | directory from where to run ```cf push```|
| URL_PATH_PAGE         |                 | application's URL page page |

There are other environment variables used to passed variable information for the application. These are:

* **ENVS**: application environment variables to be set, the value should be NAME1:VALUE1,NAME1:VALUE2
* **ROUTES**: routes that should be mapped to the application. The value should take the from of host1:domain1,host2:domain2,domain3
* **SERVICES**: TBD
* **CF_PUSH_ARGS**:TBD
