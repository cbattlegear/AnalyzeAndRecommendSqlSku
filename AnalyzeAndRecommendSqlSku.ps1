<#
.SYNOPSIS
    Quickly create recommendations for which SQL Azure Sku to run based on current SQL Server usage
.DESCRIPTION
    This script wraps the process of collecting and analyzing database performance counters to recommend a SQL Azure SKU into a simple script.
    Please capture at least 40 minutes worth of data for a valid recommendation.
    Prerequisites:
    - Please make sure you are running on PowerShell Version 5.1
    - Please install the latest version of Database Migration Assistant
    - Please install the Azure PowerShell Module
    - Please go to https://aka.ms/dmaskuprereq for further information

.EXAMPLE
    To analyze for 40 minutes and get a recommendation
    .\AnalyzeAndRecommendSqlSku.ps1 -CollectionTimeInSeconds 2400 -ConnectionString "Server=myServerAddress;Initial Catalog=master;Trusted_Connection=True;"
#>
param
(
    [Parameter(Mandatory=$true)][int]$CollectionTimeInSeconds,
    [Parameter(Mandatory=$true)][string]$ConnectionString
)

# Grabbed from SkuRecommendationDataCollectionScript, Added check for Instances and Custom Ports
# This is how we are getting the computer name instead of manually entering it
function ExtractServerNameFromConnectionStringForComputerName
{
    param
    (
        [Parameter(Mandatory=$true)][string]$DbConnectionString
    )

    $splitString = $DbConnectionString -split ';'

    foreach ($token in $splitString)
    {
        if ($token.StartsWith("Server=")) {
            #Remove slashes from Instance Names eg "\InstanceName"
            if($token.Contains("\")) {
                $server = ($token -split "\",-1,'SimpleMatch')[0]
            } else {
                $server = $token
            }
            #Remove commas for custom ports eg. ",1433"
            if($server.Contains(",")) {
                $server = ($token -split ",")[0]
            }
            #Remove "Server=" from beginning of connection string
            $server.Replace("Server=", "").Trim()
            #Remove : from custom protocols eg. "tcp:"
            if($server.Contains(":")) {
                $server = ($server -split ":")[1]
            }
            return $server
        }
    }
    return "";
}

# Basic prerequisite checks
$DMADirectory = "C:\Program Files\Microsoft Data Migration Assistant\"

If($PSVersionTable.PSVersion.Major -gt 5) {
    Write-Host "To collect machine information, the data collection script uses the Get-WmiObject cmdlet, which was deprecated in PowerShell 6. To run this script in PowerShell 6 or 7, you must replace the WMI cmdlets with the newer CIM cmdlets."
    Write-Host "Please go to https://aka.ms/dmaskuprereq for a list of prequisites."
    return
}

If(!(Test-Path -Path $DMADirectory -PathType Container)) {
    Write-Host "Please install the newest version of the Database Migration Assistant."
    Write-Host "Please go to https://aka.ms/dmaskuprereq for a list of prequisites."
    return
}

if(!(Get-Module -Name Az.Accounts -ListAvailable)) {
    Write-Host "Ensure that your computer has the Azure Powershell Module installed."
    Write-Host "Please go to https://aka.ms/dmaskuprereq for a list of prequisites."
    return
}

# Get the Computer Name from the Connection String (might not work with IPs, haven't tested yet)
$ComputerName = ExtractServerNameFromConnectionStringForComputerName $ConnectionString

if($ComputerName.Contains(".")) {
    Write-Host "It looks like you are using an IP Address or FQDN, this tool requires WMI access which is often only available on the local network."
    $choice = ""
    while ($choice -notmatch "[y|n]"){
        $choice = Read-Host "Are you sure you want to continue? (Y/N)"
    }
    if($choice -eq "n") {
        return
    }
}

# Create Our directories for our stats and recommendations in the same folder as the PowerShell script
New-Item -ItemType Directory -Force -Path "$PSScriptRoot\Counters\", "$PSScriptRoot\$ComputerName-RecommenderOutput\" | Out-Null

$SkuRecommenderScript = $DMADirectory + "SkuRecommendationDataCollectionScript.ps1"

# Run the Sku recommendation script provided with DMA
& $SkuRecommenderScript -ComputerName $ComputerName -OutputFilePath "$PSScriptRoot\Counters\$ComputerName-counters.csv" -CollectionTimeInSeconds $CollectionTimeInSeconds -DbConnectionString $ConnectionString

# We are assuming the script doesn't write anything if it fails (quick glance at the script says it doesn't)
If(!(Test-Path -Path "$PSScriptRoot\Counters\$ComputerName-counters.csv" -PathType Leaf)) {
    Write-Host "The SQL Server information capturing script failed to create an output, please see above for more troubleshooting information."    
    return
} else {
# Run the DMA command, this is really noisy on the CLI
    $DmaCmd = $DMADirectory + "DmaCmd.exe"
    & $DmaCmd /Action=SkuRecommendation /SkuRecommendationInputDataFilePath="$PSScriptRoot\Counters\$ComputerName-counters.csv" /SkuRecommendationTsvOutputResultsFilePath="$PSScriptRoot\$ComputerName-RecommenderOutput\$ComputerName-prices.tsv" /SkuRecommendationJsonOutputResultsFilePath="$PSScriptRoot\$ComputerName-RecommenderOutput\$ComputerName-prices.json" /SkuRecommendationOutputResultsFilePath="$PSScriptRoot\$ComputerName-RecommenderOutput\$ComputerName-prices.html" /SkuRecommendationPreventPriceRefresh=true
    Write-Host "Recommendations Complete!"
    Write-Host "View your recommendations at $PSScriptRoot\$ComputerName-RecommenderOutput\"
}