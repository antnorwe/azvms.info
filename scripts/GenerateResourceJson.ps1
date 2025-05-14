$tenantID = Read-Host "Please enter your tenant ID to connect to"
#fbd4347a-3682-41ac-8e52-8a2cbf8dd0dc

if ($(Get-AzContext | Select-Object -ExpandProperty Tenant | Select-Object -ExpandProperty Id) -ne $tenantID) {
    Connect-AzAccount -Tenant $tenantID
}

$accessToken = Get-AzAccessToken -ResourceUrl "https://management.azure.com" -AsSecureString | Select-Object -ExpandProperty Token | ConvertFrom-SecureString -AsPlainText

$headers = @{
    "authorization" = "bearer $accessToken"
    "content-type"  = "application/json"
}

$subId = Get-AzContext | Select-Object -ExpandProperty Subscription

$uri = "https://management.azure.com/subscriptions/$subId/providers/Microsoft.Compute/skus?api-version=2021-07-01"

$virtualMachines = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers | Select-Object -ExpandProperty Value | Where-Object { $_.resourceType -eq "virtualMachines" } 

$vmSkus = $virtualMachines | Select-Object Name, Tier, Size -unique

$output = @{}
$vmSkus | Select-Object -ExpandProperty Size -Unique | foreach-object {
    $vmSize = $_
    $vm = $virtualMachines | Where-Object { $_.size -eq $vmSize }
    Write-Output "Retrieving $($vm | Select-Object -ExpandProperty name -First 1)"

    $vmSpecs = $vm | Select-Object -First 1 | foreach-object {
        New-Object PsObject -Property @{
            "name"                    = $_.size
            "cpu"                     = $_.capabilities | Where-Object name -eq "vCPUs" | Select-Object -ExpandProperty value
            "cpu_type"                = $_.capabilities | Where-Object name -eq "CpuArchitectureType" | Select-Object -ExpandProperty value
            "ram"                     = $_.capabilities | Where-Object name -eq "MemoryGB" | Select-Object -ExpandProperty value
            "gpu_number"              = $_.capabilities | Where-Object name -eq "GPUs" | Select-Object -ExpandProperty value
            "gpu"                     = ""
            "premium_storage"         = [int]$([bool]$($_.capabilities | Where-Object name -eq "PremiumIO" | Select-Object -ExpandProperty value))
            "premium_storage_caching" = ""
            "live_migration"          = [int]$([bool]$($_.capabilities | Where-Object name -eq "MemoryPreservingMaintenanceSupported" | Select-Object -ExpandProperty value))
            "vm_generation"           = $_.capabilities | Where-Object name -eq "HyperVGenerations" | Select-Object -ExpandProperty value
            "local_disk"              = $($($_.capabilities | Where-Object name -eq "MaxResourceVolumeMB" | Select-Object -ExpandProperty value) / 1024)
            "max_data_disk"           = $_.capabilities | Where-Object name -eq "MaxDataDiskCount" | Select-Object -ExpandProperty value
            "iops"                    = "$($_.capabilities | Where-Object name -eq "UncachedDiskIOPS" | Select-Object -ExpandProperty value)/$([math]::ceiling($($($_.capabilities | Where-Object name -eq "UncachedDiskBytesPerSecond" | Select-Object -ExpandProperty value)/(1024*1024) * 8)))"
            "max_nics"                = $_.capabilities | Where-Object name -eq "MaxNetworkInterfaces" | Select-Object -ExpandProperty value
            "expected_network_mbps"   = ""
        }
    }

    $vmDescription = $vm | Select-Object -First 1 | foreach-object {
        "$($vmSize): $($_.capabilities | Where-Object name -eq "vCPUs" | Select-Object -ExpandProperty value) Cores, $($_.capabilities | Where-Object name -eq "MemoryGB" | Select-Object -ExpandProperty value) GB RAM, $($($($_.capabilities | Where-Object name -eq "MaxResourceVolumeMB" | Select-Object -ExpandProperty value) / 1024)) GB Temporary storage"
    }

    $priceUri = "https://prices.azure.com/api/retail/prices?currencyCode='USD'&`$filter=armSkuName eq '$($vm | Select-Object -expandProperty name -First 1)' and serviceFamily eq 'Compute' and serviceName eq 'Virtual Machines'"
    $prices = Invoke-RestMethod -Method GET -Uri $priceUri

    $linux = $prices.items | Where-Object { $_.productName -notmatch "Win" -and $_.productName -notmatch "Cloud" }
    $windows = $prices.items | Where-Object { $_.productName -match "Win" -and $_.productName -notmatch "Cloud" }

    $linondemand = @{}
    $linondemandLP = @{}
    $linondemandSpot = @{}
    $winondemand = @{}
    $winondemandLP = @{}
    $winondemandSpot = @{}
    
    $3yr = @{}
    $1yr = @{}

    $linux | Where-Object { $_.type -eq "Consumption" } | foreach-object {
        if ($_.skuName -match "Low Priority"){
            $linondemandLP | Add-Member -MemberType NoteProperty -Name $($_.armRegionName) -Value $(New-Object PsObject -Property @{
                "value" = $_.retailPrice
            })
        }
        elseif ($_.skuName -match "Spot") {
            $linondemandSpot | Add-Member -MemberType NoteProperty -Name $($_.armRegionName) -Value $(New-Object PsObject -Property @{
                "value" = $_.retailPrice
            })
        }
        else {
            $linondemand | Add-Member -MemberType NoteProperty -Name $($_.armRegionName) -Value $(New-Object PsObject -Property @{
                "value" = $_.retailPrice
            })
        }
    }

    $linux | Where-Object { $_.reservationTerm -eq "1 Year" } | foreach-object {
        $1yr | Add-Member -MemberType NoteProperty -Name $_.armRegionName -Value $(New-Object PsObject -Property @{
                "value" = $($_.retailPrice) / (365 * 24)
            })
    }

    $linux | Where-Object { $_.reservationTerm -eq "3 Year" } | foreach-object {
        $3yr | Add-Member -MemberType NoteProperty -Name $_.armRegionName -Value $(New-Object PsObject -Property @{
                "value" = $($_.retailPrice) / ((3 * 365) * 24)
            })
    }

    $windows | Where-Object { $_.type -eq "Consumption" } | foreach-object {
        if ($_.skuName -match "Low Priority"){
            $winondemandLP | Add-Member -MemberType NoteProperty -Name $($_.armRegionName) -Value $(New-Object PsObject -Property @{
                "value" = $_.retailPrice
            })
        }
        elseif ($_.skuName -match "Spot") {
            $winondemandSpot | Add-Member -MemberType NoteProperty -Name $($_.armRegionName) -Value $(New-Object PsObject -Property @{
                "value" = $_.retailPrice
            })
        }
        else {
            $winondemand | Add-Member -MemberType NoteProperty -Name $($_.armRegionName) -Value $(New-Object PsObject -Property @{
                "value" = $_.retailPrice
            })
        }
    }

    $output | Add-Member -MemberType NoteProperty -Name $vmSize -Value $(New-Object PsObject -Property @{
            "description" = $vmDescription
            "spec"        = $vmSpecs
            "standard"    = New-Object PsObject -Property @{
                "linux"   = New-Object PsObject -Property @{
                    "ondemand" = $linondemand | ConvertTo-JSON | ConvertFrom-JSON
                    "1yr"      = $1yr | ConvertTo-JSON | ConvertFrom-JSON
                    "3yr"      = $3yr | ConvertTo-JSON | ConvertFrom-JSON
                }
                "windows" = New-Object PsObject -Property @{
                    "ondemand" = $winondemand | ConvertTo-JSON | ConvertFrom-JSON
                }
            }
            "lowpriority"    = New-Object PsObject -Property @{
                "linux"   = New-Object PsObject -Property @{
                    "ondemand" = $linondemandLP | ConvertTo-JSON | ConvertFrom-JSON
                }
                "windows" = New-Object PsObject -Property @{
                    "ondemand" = $winondemandLP | ConvertTo-JSON | ConvertFrom-JSON
                }
            }
        }
        )
    }

    Write-Output "Writing file to $PsScriptRoot\..\web\azure.json"
$output | ConvertTo-JSON -Depth 100 | Out-File -FilePath "$PsScriptRoot\..\web\azure.json"