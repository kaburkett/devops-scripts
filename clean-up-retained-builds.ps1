# Azure Tenant ID
$tenantId = ""
# Azure Subscription ID
$subscriptionId = ""
# DevOps Repo ID
$repoId = ""
# DevOps Organisation Name
$organisation = ""
# DevOps Project Name
$project = ""
# (Optional) DevOps Branch Name
$branch = ""
# Number of days to retain builds for
$daysToRetain = 30
 
# Connect to Azure
# Test if alreday authenticated with Azure
if ([string]::IsNullOrEmpty($(Get-AzContext).Account)) {
    Connect-AzAccount -Tenant $tenantId -Subscription $subscriptionId
}
 
# Azure DevOps API resource id
$token = (Get-AzAccessToken -ResourceUrl "499b84ac-1321-427f-aa17-267ca6975798").Token
 
# Get bulds in Repo older than the $daysToRetain
if ($branch -ne "") {
    $branchParam = "&branchName=$($branch)"
}
$daysToRetain = - [Math]::Abs($daysToRetain)
$maxTime = (Get-Date).AddDays($daysToRetain).ToString("yyyy-MM-dd")
$url = "https://$($organisation).visualstudio.com/$($project)/_apis/build/builds?api-version=7.0&repositoryType=TfsGit&repositoryId=$($repoId)&maxTime=$($maxTime)$($branchParam)"
$header = @{
    'Authorization' = 'Bearer ' + $token
    'Content-Type'  = 'application/json'
}
$response = Invoke-RestMethod -Method Get -Uri $url -Headers $header
$builds = $response.PSObject.Properties.Item("value") | ForEach-Object { $_.Value } | ForEach-Object { $_.id } | ForEach-Object { $_.ToString() };
Write-Host "Builds: " $builds
 
## For Each Build
# Get and Delete Leases
Foreach ($buildId in $builds) {
    Write-Host "Processing BuildId: $($buildId)"
 
    # Get Leases
    $url = "https://$($organisation).visualstudio.com/$($project)/_apis/build/builds/$($buildId)/leases?api-version=7.0"
    $header = @{
        'Authorization' = 'Bearer ' + $token
        'Content-Type'  = 'application/json'
    }
    $response = Invoke-RestMethod -Method Get -Uri $url -Headers $header
    $leases = $response.PSObject.Properties.Item("value") | ForEach-Object { $_.Value } | ForEach-Object { $_.leaseId } | ForEach-Object { $_.ToString() };
    $leases = $leases -join ","
 
    # Delete leases
    if ($leases -ne "") {
        Write-Host "Deleting Lease(s): $($leases) for BuildId $($buildId)"
 
        $url = "https://$($organisation).visualstudio.com/$($project)/_apis/build/retention/leases/?api-version=7.0&ids=$($leases)"
        $header = @{
            'Authorization' = 'Bearer ' + $token
            'Content-Type'  = 'application/json'
        }
        $response = Invoke-RestMethod -Method Delete -Uri $url -Headers $header
    }
 
    # Delete Build
    Write-Host "Deleting Build: $($buildId)"
    $url = "https://$($organisation).visualstudio.com/$($project)/_apis/build/builds/$($buildId)?api-version=7.0"
    $header = @{
        'Authorization' = 'Bearer ' + $token
        'Content-Type'  = 'application/json'
    }
    $response = Invoke-RestMethod -Method Delete -Uri $url -Headers $header
}