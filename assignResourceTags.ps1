param (

    [string]
    $projectName           = "Peak on Demand",
    
    [string]
    $environment           = "Development",

    [string]
    $projectOwner          = "andy.melichar@ascentgl.com",

    [string]
    $primaryContact        = "andy.melichar@ascentgl.com",

    [string]
    $department            = "SRE",
    
    [string]
    $createdBy             = "SRE",

    [string]
    $subscriptionName      = "Pod-Dev",

    [string]
    $resourceGroupName     = "MC_d-pod-rg_d-pod-aks_eastus2",

    [string]
    $masterResourceTagFile = "https://raw.githubusercontent.com/tfitzmac/resource-capabilities/master/tag-support.csv",

    [string]
    $scriptPath            = ($env:USERPROFILE,"Projects\PowerShell\ManageAzureResourceTags" -join "\"),

    [string]
    $logFilePath           = ($scriptPath, "ManageAzureResourceTags.log" -join "\"),

    [string]
    $resourceMapFileName   = ($scriptPath, "resourceTypeMapping.csv" -join "\"),

    [string]
    $debugMode             = "False",

    [string]
    $transcriptFile        = ($subscriptionName,$resourceGroupName,"Transcript.txt" -join "_")

)

$resourceList      = [System.Collections.ArrayList]@()
$tempFile          = $scriptPath,"tempFile.csv" -join "\"                        # file which holds the master list of taggable Azure resources
$resourceObjectMap = [ordered]@{}

function getResourceTypeMappings([string] $resourceMapFileName)
{
    Import-Csv $resourceMapFileName | ForEach-Object {
        $resourceObjectMap.Add($_.resourceType,$_.objectType)
    }
}
function generateTaggableResourceList([string] $masterResourceTagFile)
{
    Invoke-WebRequest -Uri $masterResourceTagFile -OutFile $tempFile
    Import-Csv $tempFile | Where-Object { $_.supportsTags -eq 'TRUE' } | Select-Object -Property @{name='resourceType';e={$_.providerName, $_.resourceType -join "/"}}
}
function returnResourceList ([string] $subscriptionName, [string]$resourceGroupName)
{
    $null = Set-AzContext -Subscription $subscriptionName
    (Get-AzResource -ResourceGroupName $resourceGroupName).Name | ForEach-Object { Get-AzResource -Name $_ -ExpandProperties | Select-Object -Property * }
    
}
function processError()
{
    $errorEntry = ("Exception: " + $Error[0].Exception), ("Category Info: " + $Error[0].CategoryInfo), ("Location: " + $Error[0].InvocationInfo.PositionMessage), ("Fully Qualified Error ID: " + $Error[0].FullyQualifiedErrorId) -join "\`n`n"
    createLogEntry $errorEntry $logFilePath "Error"
    Stop-Transcript
    Exit 1
}
function createLogEntry([string] $logEntry, [string]$logFilePath, [string]$entryType)
{
    (Get-Date -Format "MM/dd/yyyy HH:mm K"),$entryType,$logEntry -join "**" | Out-File $logFilePath -Append
}

function assignTags($resource)
{  

    if ($resource.Properties.creationDate) { $creationDate = $resource.Properties.creationDate }
    if ($resource.Properties.createdDate) { $creationDate = $resource.Properties.createdDate }
    if (!($creationDate)) { $creationDate = 'n/a'}

    $tags = [ordered]@{
        "Name"         =  $resource.Name
        "Project"      =  $projectName
        "Environment"  =  $environment
        "ObjectType"   =  $resourceObjectMap[($resource.ResourceType, $resource.kind -join "/")]   
        "Owner"        =  $projectOwner
        "Contact"      =  $primaryContact
        "Region"       =  $resource.Location
        "Department"   =  $department
        "Created By"   =  $createdBy
        "ResourceType" =  $resource.ResourceType
        "Creation Date" = $creationDate
    }

    if (!($tags["ObjectType"])) {
        Write-Host "Object Type is missing, $($resource.ResourceType), $($resource.kind)"
        processError
    }

    if ($debugMode -eq "True") {

        $tags.GetEnumerator() | Format-Table -HideTableHeaders | out-file -FilePath ($scriptPath, "taglist.txt" -join "\") -Append

        try {
            Write-Host "Adding tags"
            $tags.Keys | ForEach-Object {
                
                New-AzTag -Name $_ -Value $tags[$_] -WhatIf
            }
        }
        catch {
            Write-Host "Failed to created tags. $tags"
            processError
        }
    }
    else
    {
        # Try to add tags to it
        try {
            Write-Host "Adding tags"
            New-AzTag -ResourceId $resource.ResourceId -Tag $tags
        }
        catch {
            Write-Host "Failed to add tags to resource."
            processError
        }
    }

}

Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"  # This suppresses the breaking change warnings

$null = Connect-AzAccount -WarningAction Ignore                     # Suppress the output from the Azure connection

Start-Transcript -Path ($scriptPath, $transcriptFile -join "\")

Write-host "Grab a copy of the master list of taggable resources and store it locally."

getResourceTypeMappings $resourceMapFileName

Write-host "Filter the list to include only the resource types which support tags."

$resourceTypes = (generateTaggableResourceList $masterResourceTagFile).resourceType

Write-host "Get the list of resources included in the $subscriptionName subscription and the $resourceGroupName resource group."

$resourceList  = returnResourceList $subscriptionName $resourceGroupName

Write-Host "Filter the list to include the resources which support tags and apply tags."

$resourceList | Where-Object { $_.ResourceType -in $resourceTypes } | ForEach-Object { assignTags $_ }

Stop-Transcript