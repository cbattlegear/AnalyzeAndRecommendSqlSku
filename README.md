# AnalyzeAndRecommendSqlSku
    
Quickly create recommendations for which SQL Azure Sku to run based on current SQL Server usage

## Description

This script wraps the process of collecting and analyzing database performance counters to recommend a SQL Azure SKU into a simple script.
Please capture at least 40 minutes worth of data for a valid recommendation.
Prerequisites:
- Please make sure you are running on PowerShell Version 5.1
- Please install the latest version of [Database Migration Assistant](https://aka.ms/get-dma)
- Please install the [Azure PowerShell Module](https://docs.microsoft.com/en-us/powershell/azure/install-az-ps?view=azps-1.8.0&preserve-view=true)
- Please go to https://aka.ms/dmaskuprereq for further information

## Example

To analyze for 40 minutes and get a recommendation
`.\AnalyzeAndRecommendSqlSku.ps1 -CollectionTimeInSeconds 2400 -ConnectionString "Server=myServerAddress;Initial Catalog=master;Trusted_Connection=True;"`
