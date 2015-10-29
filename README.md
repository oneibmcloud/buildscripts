This project has build and deploy scripts intended to be used in the IBM Bluemix DevOps Services Build & Deploy pipelines. 

The blue-green deploy script consists of 10 steps. The following are instructions on how to recover in case of a
failure from each of the steps. Before you execute any of the 'cf' commands, you need to login onto Bluemix and be in
the space where the app is being deployed.

1) 
PROBLEM: Blue-app exists, the script fails. 
SOLUTION: Delte the blue-app by hand. On the command line, run 'cf delete <blue-app-name>'

2) 
PROBLEM: 'cf push' of blue app failed.
SOLUTION: Examine the deploy log to find the cause of the problem, before restarting the
          deploy, run: 'cf delete <blue-app-name>'

3)
PROBLEM: 'ct set-env' failed
SOLUTION:  TBD

4)
PROBLEM: 'cf start' failed.
SOLUTION: This indicates a problem either with Bluemix or with the app itself. Check the log for
details and clean the the blue-app as in problem 1).

5) 
PROBLEM: Application not responsding.
SOLUTION: Manually investigate why the application is not responsding. Use the browser to connect to the application
to see if the problem persists. Clean up and redeploy.

6)
PROBLEM: Adding additional routes failed.
SOLUTION: Check the log and investigate why the mapping additional routes failed. 

7)
PROBLEM: Deleting additional route from blue-app failed
SOLUTION: Verify that the additional route does not exist, remove it by hand if it does.

8)
PROBLEM: Deleting backup of green-app failed. 
SOLUTION: Clean up and restart the deploy.

9)
PROBLEM: Problems stopping the backup.
SOLUTION: Clean up and restart the deploy.

10)
DONE!
