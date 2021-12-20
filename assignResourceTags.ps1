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
    $resourceGroupName     = "d-pod-rg",

    [string]
    $masterResourceTagFile = "https://raw.githubusercontent.com/tfitzmac/resource-capabilities/master/tag-support.csv",

    [string]
    $resourceMapFileName  = "c:\users\jgange\Projects\PowerShell\ManageAzureResourceTags\resourceTypeMapping.csv"
)

$resourceList      = [System.Collections.ArrayList]@()
$tempFile          = $ENV:USERPROFILE,"tempFile.csv" -join "\"
$resourceObjectMap = [ordered]@{}

#$objectTypes = [ordered]@{}

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
    # $list = (Get-AzResource -ResourceGroupName $resourceGroupName).Name
    # $list | ForEach-Object { Get-AzResource -Name $_ -ExpandProperties | Select-Object -Property * }
    (Get-AzResource -ResourceGroupName $resourceGroupName).Name | ForEach-Object { Get-AzResource -Name $_ -ExpandProperties | Select-Object -Property * }
    
}

function assignTags($resource)
{  

    $tags = [ordered]@{
        "Name"         = $resource.Name
        "Project"      = $projectName
        "Environment"  = $environment
        "ObjectType"   = $resourceObjectMap[($resource.ResourceType, $resource.kind -join "/")]   
        "Owner"        = $projectOwner
        "Contact"      = $primaryContact
        "Region"       = $resource.Location
        "Department"   = $department
        "Created By"   = $createdBy
        "ResourceType" = $resource.ResourceType
        "Creation Date" = $resource.Properties.creationDate
    }

    $tags.GetEnumerator() | Format-Table -HideTableHeaders | out-file -FilePath "c:\users\jgange\Projects\PowerShell\ManageAzureResourceTags\taglist.txt" -Append
    
    <#
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
   #>
}

Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"  # This suppresses the breaking change warnings

$null = Connect-AzAccount -WarningAction Ignore

getResourceTypeMappings $resourceMapFileName

$resourceTypes = (generateTaggableResourceList $masterResourceTagFile).resourceType

$resourceList  = returnResourceList $subscriptionName $resourceGroupName

$resourceList | Where-Object { $_.ResourceType -in $resourceTypes } | ForEach-Object { assignTags $_ }