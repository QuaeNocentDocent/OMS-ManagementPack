

#we must sstay with ADAL 2.x

$subscriptionId='13779b63-84d9-4e09-8c64-5cfa364dc563'  #Azure Benefits

$tenantId='prelabs.onmicrosoft.com'
#$resourceUri='https://management.azure.com/subscriptions/{0}' -f $subscriptionId
$resourceUri='https://management.azure.com/'
$authBaseAddress = 'https://login.microsoftonline.com/{0}/' -f $tenantId

  $authBaseAddress='https://login.windows.net/prelabs.onmicrosoft.com/'
 $resourcebaseAddress='https://management.azure.com/'

#authenticate
import-module .\QNDAdal

$context = Get-AdalAuthentication -resourceURI $resourceUri -authority $authBaseAddress

$authHeader=$context.CreateAuthorizationHeader()

#list activity logs
$uri='https://management.azure.com/subscriptions/{0}/providers/microsoft.insights/eventtypes/management/values?api-version=2015-04-01&$filter=eventTimestamp ge ''2017-12-08T20:00:00Z''' -f $subscriptionId
$body=$null
$nextLink=$null
$results = invoke-QNDAzureRestRequest -uri ($uri) -httpVerb GET -authToken ($authHeader) -nextLink $nextLink -data $body -TimeoutSeconds 300 -Verbose

#list all alerts rules per subscription

#1 get all the reosurce groups *** NOT NEEDED we can go subs leve

$uri='https://management.azure.com/subscriptions/{0}/resourcegroups?api-version=2017-05-10' -f $subscriptionId
$body=$null
$nextLink=$null
$results = invoke-QNDAzureRestRequest -uri ($uri) -httpVerb GET -authToken ($authHeader) -nextLink $nextLink -data $body -TimeoutSeconds 300 -Verbose

$AlertsRules=@{}

foreach($rg in $results.Values) {
  #std alerts
    $uri = 'https://management.azure.com/{0}/providers/microsoft.insights/alertrules?api-version=2016-03-01' -f $rg.id
    $rules = invoke-QNDAzureRestRequest -uri ($uri) -httpVerb GET -authToken ($authHeader) -nextLink $nextLink -data $body -TimeoutSeconds 300 
    if ($rules.GotValue) {
        $rules.Values
    }
    $uri = 'https://management.azure.com/{0}/providers/microsoft.insights/metricAlerts?api-version=2017-09-01-preview' -f $rg.id
    $rules = invoke-QNDAzureRestRequest -uri ($uri) -httpVerb GET -authToken ($authHeader) -nextLink $nextLink -data $body -TimeoutSeconds 300 
    if ($rules.GotValue) {
        $rules.Values
    }
}

#activityLogAlerts can be queired by subscription
$body=$null
$nextLink=$null
$uri='https://management.azure.com/subscriptions/{0}/providers/microsoft.insights/activityLogAlerts?api-version=2017-04-01' -f $subscriptionId
$alRules = invoke-QNDAzureRestRequest -uri ($uri) -httpVerb GET -authToken ($authHeader) -nextLink $nextLink -data $body -TimeoutSeconds 300 -Verbose

{"value":[{"id":"/subscriptions/13779b63-84d9-4e09-8c64-5cfa364dc563/resourceGroups/Monitor/providers/microsoft.insights/activityLogAlerts/AL Alert 1","type":"Microsoft.Insights/ActivityLogAlerts","name":"AL Alert 1","location":"Global","kind":null,"tags":{},"properties":{"scopes":["/subscriptions/13779b63-84d9-4e09-8c64-5cfa364dc563"],"condition":{"allOf":[{"field":"category","equals":"ServiceHealth","containsAny":null}]},"actions":{"actionGroups":[{"actionGroupId":"/subscriptions/13779b63-84d9-4e09-8c64-5cfa364dc563/resourceGroups/Monitor/providers/microsoft.insights/actionGroups/Action%20Group%201","webhookProperties":{}}]},"enabled":true,"description":"AL Alert 11"},"identity":null}]}

$uri = 'https://management.azure.com/subscriptions/{0}/providers/microsoft.insights/alertrules?api-version=2016-03-01' -f $subscriptionId
$rules = invoke-QNDAzureRestRequest -uri ($uri) -httpVerb GET -authToken ($authHeader) -nextLink $nextLink -data $body -TimeoutSeconds 300 -Verbose

$uri = 'https://management.azure.com/subscriptions/{0}/providers/microsoft.insights/metricAlerts?api-version=2017-09-01-preview' -f $subscriptionId
$nrtRules = invoke-QNDAzureRestRequest -uri ($uri) -httpVerb GET -authToken ($authHeader) -nextLink $nextLink -data $body -TimeoutSeconds 300 -Verbose

"value": [
    {
      "location": "global",
      "type": "Microsoft.Insights/metricAlerts",
      "name": "NRT Alert 1",
      "id": "/subscriptions/13779b63-84d9-4e09-8c64-5cfa364dc563/resourceGroups/preAzureSDK1/providers/microsoft.insights/metricAlerts/NRT%20Alert%201",
      "tags": {},
      "properties": {
        "description": "NRT Alert 1",
        "severity": 3,
        "enabled": true,
        "scopes": [
          "/subscriptions/13779b63-84d9-4e09-8c64-5cfa364dc563/resourceGroups/preAzureSdk1/providers/Microsoft.Compute/virtualMachines/preAzureSDK1"
        ],
        "evaluationFrequency": "PT1M",
        "windowSize": "PT5M",
        "templateType": 8,
        "templateSpecificParameters": {},
        "criteriaSchemaId": "SingleResourceMultipleMetricCriteria",
        "criteria": {
          "allOf": [
            {
              "name": "Metric1",
              "metricName": "Percentage CPU",
              "dimensions": [],
              "operator": "GreaterThan",
              "threshold": 10.0,
              "timeAggregation": "Maximum"
            }
          ]
        },
        "actions": [
          {
            "actionGroupId": "/subscriptions/13779b63-84d9-4e09-8c64-5cfa364dc563/resourcegroups/monitor/providers/microsoft.insights/actiongroups/action%20group%201",
            "webHookProperties": {}
          }
        ],
        "currentStatus": {
          "value": "Healthy",
          "timestamp": "2017-12-30T15:43:22.7806106Z"
        }
      }
    }
  ]


$uri='https://management.azure.com/subscriptions/13779b63-84d9-4e09-8c64-5cfa364dc563/resourceGroups/Monitor/providers/microsoft.insights/activityLogAlerts/AL Alert 1?api-version=2017-04-01'

$incidents = invoke-QNDAzureRestRequest -uri ($uri) -httpVerb GET -authToken ($authHeader) -nextLink $nextLink -data $body -TimeoutSeconds 300 -Verbose

$uri='https://management.azure.com/subscriptions/ec2b2ab8-ba74-41a0-bf54-39cc0716f414/resourceGroups/OaaSCSHRWRPZB6GXQVDR3MZN4LZ2ID5KGAHA3HNK26JFKSEGZK7HOMRALQ-West-Europe/providers/Microsoft.Automation/automationAccounts/PreLabsAutoWE'
$command='/runbooks?api-version=2015-10-31'

$command='/runbooks/ASR-HybridAutomation/?api-version=2015-10-31'
$runbooks = invoke-QNDAzureRestRequest -uri ($uri+$command) -httpVerb GET -authToken ($connection) -nextLink $nextLink -data $body -TimeoutSeconds 300 -Verbose


#list all alerts incident per rule

GET https://management.azure.com/subscriptions/b67f7fec-69fc-4974-9099-a26bd6ffeda3/resourcegroups/Rac46PostSwapRG/providers/microsoft.insights/alertrules/myRuleName/incidents?api-version=2016-03-01

listDigestedEvents: "{0}/subscriptions/{1}/providers/microsoft.insights/eventtypes/management/digestEvents",
                listEvents: "{0}/subscriptions/{1}/providers/microsoft.insights/eventtypes/management/values",
                listEventCategories: "{0}/providers/Microsoft.Insights/eventCategories?api-version={1}",
                listEventsWithTimeFilter: "/subscriptions/{0}/providers/microsoft.insights/eventtypes/management/values?api-version=2017-03-01-preview&$filter=eventTimeStamp ge '{1}' and eventTimeStamp le '{2}'",
                listEventsWithResourceIdFilter: "/subscriptions/{0}/providers/microsoft.insights/eventtypes/management/values?api-version=2017-03-01-preview&$filter=categories eq 'Alert' and eventTimeStamp ge '{1}' and resourceId eq '{2}'",
                createActivityLogAlert: "{0}/subscriptions/{1}/resourceGroups/{2}/providers/microsoft.insights/activityLogAlerts/{3}?api-version={4}"
            },


            insightsController: {
              getMetricDefinition: "{0}/insights/api/Insights/GetMetricDefinition",
              getMetricHistory: "{0}/insights/api/Insights/GetMetricHistory",
              getMetricHistoryCollection: "{0}/insights/api/Insights/GetMetricHistoryCollection",
              listMetricDefinitions: "{0}/insights/api/Insights/ListMetricDefinitions",
              queryActions: "{0}/insights/api/Insights/QueryActions",
              queryActionsCount: "{0}/insights/api/Insights/QueryActionsCount",
              queryActionsDownload: "{0}/insights/api/Insights/QueryActionsDownload"
          },
          serviceNotifications: {
              getNotifications: "{0}/subscriptions/{1}/providers/microsoft.insights/notifications",
              getActionGroup: "{0}/subscriptions/{1}/resourceGroups/{2}/providers/microsoft.insights/actionGroups/{3}?api-version={4}",
              listActionGroupsBySub: "{0}/subscriptions/{1}/providers/microsoft.insights/actionGroups?api-version={2}"
          }
          relativeUrls: {
            createActionGroup: "/subscriptions/{0}/resourceGroups/{1}/providers/microsoft.insights/actionGroups/{2}",
            listEvents: "/subscriptions/{0}/providers/microsoft.insights/eventtypes/management/values",
            listResourceGroups: "/subscriptions/{0}/resourcegroups?api-version={1}",
            getNotifications: "/subscriptions/{0}/providers/microsoft.insights/notifications",
            getAlertsInSubscription: "/subscriptions/{0}/providers/microsoft.insights/activityLogAlerts?api-version={1}",
            getSupportTickets: "/subscriptions/{0}/providers/microsoft.support/supportTickets/?api-version={1}",
            getVmInstanceView: "/{0}/?$expand=instanceView&api-version={1}"
        }

        PROD: "https://portal.azure.com",
        MS: "https://ms.portal.azure.com",
        PREVIEW: "https://preview.portal.azure.com",
        RC: "https://rc.portal.azure.com"
    };