
This monitor is flexible and thus has a complex copnfiguration, this is the logic:

Healthy -> jobFailures <= MaxThreshold
Unhealthy -> jobFailures > MaxThreshold

JobFailures number of jobs with status that matches FailureCondition (default Failes|Suspended) in the LastNJobs executions

Other parameters:
MaxFailures is used to report the MaxThreshold parameters, don't know why I implemented it in this silly way but this is how it is

Parameters not used:
MaxFailures