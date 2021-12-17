param (

    [string]
    $projectName           = "Peak on Demand",
    
    [string]
    $environment           = "Production",

    [string]
    $projectOwner          = "andy.melichar@ascentgl.com",

    [string]
    $primaryContact        = "andy.melichar@ascentgl.com",

    [string]
    $department            = "SRE",
    
    [string]
    $createdBy             = "SRE",

    [string]
    $subscriptionName      = 'Pod-Dev',

    [string]
    $resourceGroupName     = 'd-pod-rg',

    [string]
    $masterResourceTagFile = "https://raw.githubusercontent.com/tfitzmac/resource-capabilities/master/tag-support.csv",

    [string]
    $resourceMapFileName  = "c:\users\jgange\Projects\PowerShell\ManageAzureResourceTags\AZResourceList.csv"
)

$resourceList = [System.Collections.ArrayList]@()
$tempFile = $ENV:USERPROFILE,"tempFile.csv" -join "\"

$objectTypes = [ordered]@{}

function getResourceTypeMappings([string] $resourceMapFileName)
{
    Import-Csv $resourceMapFileName

}
function generateTaggableResourceList([string] $masterResourceTagFile)
{
    Invoke-WebRequest -Uri $masterResourceTagFile -OutFile $tempFile
    Import-Csv $tempFile | Where-Object { $_.supportsTags -eq 'TRUE' } | Select-Object -Property @{name='resourceType';e={$_.providerName, $_.resourceType -join "/"}}
}
function returnResourceList ([string] $subscriptionName, [string]$resourceGroupName)
{
    $null = Set-AzContext -Subscription $subscriptionName
    Get-AzResource -ResourceGroupName $resourceGroupName

}

function assignTags($resource)
{  

    #check if the resource supports tags
    $resource

    # Write-Host "Getting ready to tag Resource with Id $resource.$resourceId.Value"

    # get resource type from calling get-AzResource
    $tags = [ordered]@{
        "Project"      = $projectName
        "Environment"  = $environment
        "ObjectType"   = $objectType     
        "Owner"        = $projectOwner
        "Contact"      = $primaryContact
        "Region"       = $resource.Location
        "Department"   = $department
        "Created By"   = $createdBy
        "ResourceType" = $resource.ResourceType
    }
    
    $tags
    exit 0

    if ($debugMode -eq "True") {
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
        # Make sure the resource exists
        try {
            if ($type -eq 'Resource Group') { $resource = Get-AzResourceGroup -Id $resourceId -ErrorAction Stop }
            else { $resource = Get-AzResource -ResourceId $resourceId -ErrorAction Stop }
        }
        catch
        {
            Write-Host "Failed to look up resource."
            processError
        }

        # Try to add tags to it
        try {
            Write-Host "Adding tags"
            New-AzTag -ResourceId $resourceId -Tag $tags
        }
        catch {
            Write-Host "Failed to add tags to resource."
            processError
        }
    }

}

Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"  # This suppresses the breaking change warnings

# $null = Connect-AzAccount -WarningAction Ignore

# Set-AzContext -Subscription $subscriptionName

$resourceTypes = (generateTaggableResourceList $masterResourceTagFile).resourceType

$resourceList = returnResourceList $subscriptionName $resourceGroupName

$resourceList | Where-Object { $_.ResourceType -in $resourceTypes } | Select-Object -Property Name,ResourceType

exit 0

$resourceList | ForEach-Object { assignTags $_ }
