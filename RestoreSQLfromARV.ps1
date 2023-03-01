<#
.SYNOPSIS
    Restores a SQL backup stored in Azure Recovery Services vault to the filesystem on that same machine.
 
.DESCRIPTION
    This runbook demonstrates how to find the most recent full backup for a particular database
    and restore it to a SQL VM that has been registered with the vault.
 
    It has a dependency on Az.Accounts and Az.RecoveryServices powershell modules. These
    modules must be imported into the Automation account prior to execution.
 
.PARAMETER VaultName
    String name of the Azure Recovery Services Vault
 
.PARAMETER ResGroup
    String name of the Resource Group within which the vault resides
 
.PARAMETER SourceBackupServerFQDN
    String FQDN name of the server from which the SQL backup was taken, such as agtestnode1.jintech.com
 
.PARAMETER SourceAzureMachineName
    Case sensitive. What SourceBackupServerFQDN machine is named in Azure portal.
 
.PARAMETER BkupToRestore
    The String name of the backup item to restore
 
    For a default instance, the format is typically "sqldatabase;mssqlserver;<databasename>"
 
    Use Get-AzRecoveryServicesBackupItem in this manner to retrieve the list of possible items to restore for this parameter:
        $vault = Get-AzRecoveryServicesVault -ResourceGroupName "PureEnergy" -Name "TreyVault"
        Get-AzRecoveryServicesBackupItem -BackupManagementType AzureWorkload -WorkloadType MSSQL -VaultId $vault.ID
 
.PARAMETER RestoreDestinationFilePath
    Declare what filepath you want to restore the backup to on the source SQL instance.
 
.EXAMPLE
 
.NOTES
    AUTHOR: Trey Troegel
    LASTEDIT: Feb 03, 2023
    MODIFIED: Kyle Burkett
    v1.1 
     - Changed from restore to sql instance to restore to filesystem
     - changed target param to filesystem path
     - removed a param

#>

param
(
    [Parameter(Mandatory=$true)]
    [String] $VaultName,

    [Parameter(Mandatory=$true)]
    [String] $ResGroup,

    [Parameter(Mandatory=$true)]
    [String] $SourceBackupServerFQDN,

    [Parameter(Mandatory=$true)]
    [String] $SourceAzureMachineName,

    [Parameter(Mandatory=$true)]
    [String] $BkupToRestore,

    [Parameter(Mandatory=$true)]
    [String] $RestoreDestinationFilePath

)

# Ensures you do not inherit an AzContext in your runbook
# Disable-AzContextAutosave –Scope Process

Write-Output -Verbose ""
Write-Output -Verbose "------------------------ Authentication ------------------------"
Write-Output -Verbose "Logging into Azure ..."


# Connect to Azure with system-assigned managed identity
$AzureContext = (Connect-AzAccount -Identity).context

# Set and store context
$AzureContext = Set-AzContext -SubscriptionName $AzureContext.Subscription -DefaultProfile $AzureContext   

Write-Output -Verbose ""
Write-Output -Verbose "Finding Azure Recovery Vault..."
$vault = Get-AzRecoveryServicesVault -ResourceGroupName $ResGroup -Name $VaultName

<#
Use Get-AzRecoveryServicesBackupItem in the manner to below to find the exact "-Name" parameter of the database to be restored. This will also give you the sometimes elusive Container name that is used in other commands.
 
    $vault = Get-AzRecoveryServicesVault -ResourceGroupName "MyResGroup" -Name "MyVault"
    Get-AzRecoveryServicesBackupItem -BackupManagementType AzureWorkload -WorkloadType MSSQL -VaultId $vault.ID
 
#>

Write-Output -Verbose ""
Write-Output -Verbose "------------------Finding a backup to be restored------------------"
Write-Output -Verbose "Finding backup items from $($SourceBackupServerFQDN)"
Write-Output -Verbose ""
# There can be multiple database backups with the same name, but from different source servers registered in with vault. A common scenario would be the SQL system databases (master, msdb etc.).
# Therefore, we need to filter Get-AzRecoveryServicesBackupItem by $SourceBackupServerFQDN in order to target the correct backup.
$bkpItem = Get-AzRecoveryServicesBackupItem -BackupManagementType AzureWorkload -WorkloadType MSSQL -Name $BkupToRestore -VaultId $vault.ID | Where-Object ServerName -eq $SourceBackupServerFQDN  | Where-Object {$_.Name.EndsWith(";$BkupToRestore")}

$startDate = (Get-Date).AddDays(-14).ToUniversalTime()
$endDate = (Get-Date).ToUniversalTime()
$RecPointList = Get-AzRecoveryServicesBackupRecoveryPoint -Item $bkpItem -VaultId $vault.ID -StartDate $startdate -EndDate $endDate

# Next, narrow down the list of recovery points to the most recent Full backup by sorting the list Descending and taking the top 1 record
$RecPoint = $RecPointList | Where-Object RecoveryPointType -eq "Full" | Sort-Object -Descending -Property RecoveryPointTime | Select-Object -First 1

<#
This is the definition of the VM Container to which the 'restore as files' process will apply. 
#>
$TargetVM = Get-AzRecoveryServicesBackupContainer -ContainerType AzureVMAppContainer -VaultId $Vault.Id | Where-Object {$_.Name.EndsWith(";$SourceAzureMachineName") -and $_.HealthStatus -eq 'Healthy'}

<#
Generates config file with all the needed markers to do a file recovery method to a VM.
#>
$InstanceWithFullConfig = Get-AzRecoveryServicesBackupWorkloadRecoveryConfig -RecoveryPoint $RecPoint -TargetContainer $TargetVM -RestoreAsFiles -VaultId $vault.ID -FilePath $RestoreDestinationFilePath

Write-Output -Verbose ""
Write-Output -Verbose "------------------Restoring------------------"
Write-Output -Verbose "Restoring $($BkupToRestore) to $($RestoreDestinationFilePath)"
Write-Output -Verbose ""
# This is the command that actually performs the restore.
Restore-AzRecoveryServicesBackupItem -WLRecoveryConfig $InstanceWithFullConfig -VaultId $vault.ID