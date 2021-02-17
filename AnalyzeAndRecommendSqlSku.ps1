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
            $server = $server.Replace("Server=", "").Trim()
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
    Write-Warning "To collect machine information, the data collection script uses the Get-WmiObject cmdlet, which was deprecated in PowerShell 6. To run this script in PowerShell 6 or 7, you must replace the WMI cmdlets with the newer CIM cmdlets."
    Write-Warning "Please go to https://aka.ms/dmaskuprereq for a list of prequisites."
    return
}

If(!(Test-Path -Path $DMADirectory -PathType Container)) {
    Write-Warning "Please install the newest version of the Database Migration Assistant."
    Write-Warning "Please go to https://aka.ms/dmaskuprereq for a list of prequisites."
    return
}

if(!(Get-Module -Name Az.Accounts -ListAvailable)) {
    Write-Warning "Ensure that your computer has the Azure Powershell Module installed."
    Write-Warning "Please go to https://aka.ms/dmaskuprereq for a list of prequisites."
    return
}

# Get the Computer Name from the Connection String (might not work with IPs, haven't tested yet)
$ComputerName = ExtractServerNameFromConnectionStringForComputerName $ConnectionString

try {
    Get-CimInstance win32_bios -ComputerName $ComputerName -ErrorAction Stop | Out-Null
} catch {
    Write-Warning "Cannot access WMI objects on the computer $ComputerName, see the error below for more information."
    Write-Error $Error[0]
    return
}

if($ComputerName.Contains(".") -and !($ComputerName.StartsWith("10.") -or $ComputerName.StartsWith("172.16.") -or $ComputerName.StartsWith("192.168."))) {
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
# This is from the RecommendationExplainer.htm file, just have them separated out for readability.
    $recommenderhtml = @'
<html>
    <head>
        <title>Database Recommendation Information</title>
        <style>
            body {
                font-family: "Helvetica Neue",Helvetica,Arial,sans-serif;
                font-size: 14px;
                line-height: 1.42857143;
                color: #333;
                background-color: #fff;
            }

            #sqldbrecommendations {
                display: flex;
                flex-direction:row;
                flex-wrap:wrap;
            }

            .column {
                flex: 50%;
            }

            .recommended {
                background-color: khaki;   
            }

            .label {
                font-weight: bold;
            }

            .reasons {
                margin-left: 1.5em;
            }

            .prediction {
                margin: 1em 0;
            }
        </style>
    </head>
    <body>
        <div id='sqldb'>
            <h2>SQL DB Recommendations</h2>
            <div id='sqldbrecommendations'></div>
        </div>
        <div id='sqlmi'>
            <h2>SQL MI Recommendations</h2>
            <div id='sqlmirecommendations'></div>
        </div>
        <script>
            /* SQL DB Types */
            sqlskutypemapping = {
                DTU_STANDARD_TIER: 'DTU Model, Standard',
                DTU_PREMIUM_TIER: 'DTU Model, Premium',
                VCORE_GENERAL_PURPOSE: 'vCore Model, General Purpose, Gen 4',
                VCORE_GENERAL_PURPOSE_GEN5: 'vCore Model, General Purpose, Gen 5',
                VCORE_BUSINESS_CRITICAL: 'vCore Model, Business Critical, Gen 4',
                VCORE_BUSINESS_CRITICAL_GEN5: 'vCore Model, Business Critical, Gen 5',
                GENERAL_PURPOSE_GEN_5_MI: 'General Purpose Managed Instance',
                BUSINESS_CRITICAL_GEN_5_MI: 'Business Critical Managed Instance'
            };

            let reader = new FileReader();
            sqldbinput = JSON.parse('|SQLDBJSON|');
            sqlmiinput = JSON.parse('|SQLMIJSON|');
            
            currentsection = 'sqldbrecommendations';
            var sqldb = {};
            sqldbinput.Predictions.forEach(restructureSqlDbInput);
            Object.keys(sqldb).forEach(outputSqlDbs);

            currentsection = 'sqlmirecommendations';
            var sqlmi = {};
            sqlmiinput.Predictions.forEach(restructureSqlDbInput);
            Object.keys(sqlmi).forEach(outputSqlDbs);

            function restructureSqlDbInput(input, index) {
                /* Check for database name if exists, add object to array, if not create array, then add object */
                let hold = (({IsTierRecommended, PredictionTier, PredictedSku, PricePerMonth, TierExclusionReasons}) => ({IsTierRecommended, PredictionTier, PredictedSku, PricePerMonth, TierExclusionReasons}))(input);
                if(input.DatabaseName === undefined) {
                    if(sqlmi[input.DatabaseNames] === undefined) {
                        sqlmi[input.DatabaseNames] = [];
                    }
                        sqlmi[input.DatabaseNames].push(hold);
                } else {
                    if(sqldb[input.DatabaseName] === undefined) {
                        sqldb[input.DatabaseName] = [];
                    }
                        sqldb[input.DatabaseName].push(hold);
                }
            }

            function outputSqlDbs(dbinfo) {
                if(currentsection == 'sqldbrecommendations') {
                    var recommended = sqldb[dbinfo].filter(db => db.IsTierRecommended);
                    var notrecommended = sqldb[dbinfo].filter(db => !(db.IsTierRecommended));
                } else {
                    var recommended = sqlmi[dbinfo].filter(db => db.IsTierRecommended);
                    var notrecommended = sqlmi[dbinfo].filter(db => !(db.IsTierRecommended));
                }
                output = `<div class='column'><h3>${dbinfo}</h3>
                    <div class='recommended'><h4>Recommended SKU</h4>`;
                    for(i = 0; i < recommended.length; i++) {
                        output += `<div class='prediction'>`;
                        output += `<div><span class='label'>Predicted Tier:</span> ${sqlskutypemapping[recommended[i].PredictionTier]}</div>
                                    <div><span class='label'>Predicted Sku:</span> ${recommended[i].PredictedSku}</div>
                                    <div><span class='label'>Estimated Monthly Price:</span> ${'$' + recommended[i].PricePerMonth.toFixed(2)}</div>`;
                        output += `<hr /></div>`;
                    }
                output += `</div>
                <div class='notrecommended'><h4>Not Recommended SKUs</h4>`;
                    for(i = 0; i < notrecommended.length; i++) {
                        output += `<div class='prediction'>`;
                        output += `<div><span class='label'>Predicted Tier:</span> ${sqlskutypemapping[notrecommended[i].PredictionTier]}</div>
                                    <div><span class='label'>Predicted Sku:</span> ${notrecommended[i].PredictedSku}</div>
                                    <div><span class='label'>Estimated Monthly Price:</span> ${'$' + notrecommended[i].PricePerMonth.toFixed(2)}</div>`;
                        if(notrecommended[i].TierExclusionReasons.length > 0) {
                            output += `<div class='reasons'><p class='label'>Reasons this tier wasn't selected</p>
                                <ul>`;
                            for(j = 0; j < notrecommended[i].TierExclusionReasons.length; j++) {
                                output += `<li>${notrecommended[i].TierExclusionReasons[j].RuleDescription}</li>`;
                            }
                            output += '</ul></div>';
                        }
                        output += `<hr /></div>`;
                    }
                output += `</div>
                </div>`;
                document.getElementById(currentsection).innerHTML += output;
            }            
        </script>
    </body>
</html>
'@
    $sqldbjson = Get-Content "$PSScriptRoot\$ComputerName-RecommenderOutput\$ComputerName-prices_SQL_DB.json";
    $sqlmijson = Get-Content "$PSScriptRoot\$ComputerName-RecommenderOutput\$ComputerName-prices_SQL_MI.json";

    $recommenderhtml = $recommenderhtml.Replace("|SQLDBJSON|", $sqldbjson);
    $recommenderhtml = $recommenderhtml.Replace("|SQLMIJSON|", $sqlmijson);

    $recommenderhtml | Out-File "$PSScriptRoot\$ComputerName-RecommenderOutput\RecommendationExplainer.htm";

    Write-Host "Recommendations Complete!"
    Write-Host "View your recommendations at $PSScriptRoot\$ComputerName-RecommenderOutput\"
}