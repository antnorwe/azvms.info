. "$PSScriptRoot\Common.ps1"

Connect-AzIfNeeded

$accessToken = Get-AzAccessToken -ResourceUrl "https://management.azure.com" -AsSecureString | Select-Object -ExpandProperty Token | ConvertFrom-SecureString -AsPlainText

$headers = @{
    "authorization" = "bearer $accessToken"
    "content-type"  = "application/json"
}

$subId = Get-AzContext | Select-Object -ExpandProperty Subscription

$uri = "https://management.azure.com/subscriptions/$subId/providers/Microsoft.Compute/skus?api-version=2021-07-01"

$disks = Invoke-RestMethodWithRetry -Uri $uri -Method GET -Headers $headers | Select-Object -ExpandProperty Value | Where-Object { $_.resourceType -eq "disks" }

$diskSkus = $disks | Select-Object Name, Tier, Size -unique

# Fetch every disk price in one bulk, paginated query instead of one HTTP call per (size,
# redundancy, meter) combination - contains() lets a single filter cover every disk tier
# (fixed-size Premium/Standard/StandardSSD plus the provisioned-unit PremiumV2/UltraSSD meters)
# without pulling in unrelated Storage products (Blob, Files, etc.). See GenerateVMResourceJson.ps1
# for why request count, not per-request speed, is what matters against this API's rate limit.
Write-Output "Fetching all disk retail prices..."
$allDiskPrices = Get-AllRetailPrices -Filter "serviceFamily eq 'Storage' and serviceName eq 'Storage' and (contains(productName,'Managed Disks') or contains(productName,'SSD v2') or contains(productName,'Ultra Disks'))"
Write-Output "Fetched $($allDiskPrices.Count) price rows; grouping by SKU/meter..."

$pricesBySkuMeter = @{}
foreach ($item in $allDiskPrices) {
    if ($item.productName -notmatch "Disks" -and $item.productName -notmatch "SSD v2") {
        continue
    }
    $key = "$($item.skuName)|$($item.meterName)"
    if (-not $pricesBySkuMeter.ContainsKey($key)) {
        $pricesBySkuMeter[$key] = New-Object System.Collections.Generic.List[object]
    }
    $pricesBySkuMeter[$key].Add($item)
}

$output = @{}
$diskSkus | Select-Object -ExpandProperty Size -Unique | foreach-object {
    $diskSize = $_

    $disks | Where-Object { $_.Size -eq $diskSize } | Group-Object name | foreach-object {
        $disk = $_.Group
        $diskName = $disk | Select-Object -ExpandProperty Name -First 1
        $diskType = $diskName.split('_')[0]

        Write-Output "Retrieving $diskName"

        $diskSpecs = if ($diskType -eq "PremiumV2" -or $diskType -eq "UltraSSD") {
            $disk | Select-Object -First 1 | foreach-object {
                New-Object PsObject -Property @{
                    "name"                      = "$($diskType)"
                    "tier"                      = "$diskType"
                    "redundancy"                = $(($_.name).split('_')[1])
                    "MaxSizeGiB"                = $_.capabilities | Where-Object name -eq "MaxSizeGiB" | Select-Object -ExpandProperty value
                    "MinSizeGiB"                = $_.capabilities | Where-Object name -eq "MinSizeGiB" | Select-Object -ExpandProperty value
                    "MaxIOpsReadWrite"          = $_.capabilities | Where-Object name -eq "MaxIOpsReadWrite" | Select-Object -ExpandProperty value
                    "MinIOpsReadWrite"          = $_.capabilities | Where-Object name -eq "MinIOpsReadWrite" | Select-Object -ExpandProperty value
                    "MaxBandwidthMBpsReadWrite" = $_.capabilities | Where-Object name -eq "MaxBandwidthMBpsReadWrite" | Select-Object -ExpandProperty value
                    "MinBandwidthMBpsReadWrite" = $_.capabilities | Where-Object name -eq "MinBandwidthMBpsReadWrite" | Select-Object -ExpandProperty value
                    "MaxValueOfMaxShares"       = $_.capabilities | Where-Object name -eq "MaxValueOfMaxShares" | Select-Object -ExpandProperty value
                    "MinIOSizeKiBps"            = $_.capabilities | Where-Object name -eq "MinIOSizeKiBps" | Select-Object -ExpandProperty value
                    "MaxIOSizeKiBps"            = $_.capabilities | Where-Object name -eq "MaxIOSizeKiBps" | Select-Object -ExpandProperty value
                    "MinIopsReadOnly"           = $_.capabilities | Where-Object name -eq "MinIopsReadOnly" | Select-Object -ExpandProperty value
                    "MaxIopsReadOnly"           = $_.capabilities | Where-Object name -eq "MaxIopsReadOnly" | Select-Object -ExpandProperty value
                    "MinBandwidthMBpsReadOnly"  = $_.capabilities | Where-Object name -eq "MinBandwidthMBpsReadOnly" | Select-Object -ExpandProperty value
                    "MaxBandwidthMBpsReadOnly"  = $_.capabilities | Where-Object name -eq "MaxBandwidthMBpsReadOnly" | Select-Object -ExpandProperty value
                    "MaxIopsPerGiBReadWrite"    = $_.capabilities | Where-Object name -eq "MaxIopsPerGiBReadWrite" | Select-Object -ExpandProperty value
                    "MaxIopsPerGiBReadOnly"     = $_.capabilities | Where-Object name -eq "MaxIopsPerGiBReadOnly" | Select-Object -ExpandProperty value
                    "MinIopsPerGiBReadWrite"    = $_.capabilities | Where-Object name -eq "MinIopsPerGiBReadWrite" | Select-Object -ExpandProperty value
                    "MinIopsPerGiBReadOnly"     = $_.capabilities | Where-Object name -eq "MinIopsPerGiBReadOnly" | Select-Object -ExpandProperty value
                    "BillingPartitionSizes"     = $_.capabilities | Where-Object name -eq "BillingPartitionSizes" | Select-Object -ExpandProperty value
                    "PlatformFaultDomainCount"  = $_.capabilities | Where-Object name -eq "PlatformFaultDomainCount" | Select-Object -ExpandProperty value
                }
            }
        }
        elseif ($diskType -eq "Premium" -or $diskType -eq "Standard") {
            $disk | Where-Object { $_.size -eq $diskSize } | Select-Object -First 1 | foreach-object {
                New-Object PsObject -Property @{
                    "name"                       = "$($diskSize)"
                    "tier"                       = "$diskType"
                    "redundancy"                 = $(($_.name).split('_')[1])
                    "MaxSizeGiB"                 = $_.capabilities | Where-Object name -eq "MaxSizeGiB" | Select-Object -ExpandProperty value
                    "MinSizeGiB"                 = $_.capabilities | Where-Object name -eq "MinSizeGiB" | Select-Object -ExpandProperty value
                    "MaxIOps"                    = $_.capabilities | Where-Object name -eq "MaxIOps" | Select-Object -ExpandProperty value
                    "MinIOps"                    = $_.capabilities | Where-Object name -eq "MinIOps" | Select-Object -ExpandProperty value
                    "MaxBandwidthMBps"           = $_.capabilities | Where-Object name -eq "MaxBandwidthMBps" | Select-Object -ExpandProperty value
                    "MinBandwidthMBps"           = $_.capabilities | Where-Object name -eq "MinBandwidthMBps" | Select-Object -ExpandProperty value
                    "MaxValueOfMaxShares"        = $_.capabilities | Where-Object name -eq "MaxValueOfMaxShares" | Select-Object -ExpandProperty value
                    "MaxBurstIops"               = $_.capabilities | Where-Object name -eq "MaxBurstIops" | Select-Object -ExpandProperty value
                    "MaxBurstBandwidthMBps"      = $_.capabilities | Where-Object name -eq "MaxBurstBandwidthMBps" | Select-Object -ExpandProperty value
                    "MaxBurstDurationInMin"      = $_.capabilities | Where-Object name -eq "MaxBurstDurationInMin" | Select-Object -ExpandProperty value
                    "BurstCreditBucketSizeInIO"  = $_.capabilities | Where-Object name -eq "BurstCreditBucketSizeInIO" | Select-Object -ExpandProperty value
                    "BurstCreditBucketSizeInGiB" = $_.capabilities | Where-Object name -eq "BurstCreditBucketSizeInGiB" | Select-Object -ExpandProperty value
                }
            }
        }
        elseif ($diskType -eq "StandardSSD") {
            $disk | Where-Object { $_.size -eq $diskSize } | Select-Object -First 1 | foreach-object {
                New-Object PsObject -Property @{
                    "name"                = "$($diskSize)"
                    "tier"                = "$diskType"
                    "redundancy"          = $(($_.name).split('_')[1])
                    "MaxSizeGiB"          = $_.capabilities | Where-Object name -eq "MaxSizeGiB" | Select-Object -ExpandProperty value
                    "MinSizeGiB"          = $_.capabilities | Where-Object name -eq "MinSizeGiB" | Select-Object -ExpandProperty value
                    "MaxIOps"             = $_.capabilities | Where-Object name -eq "MaxIOps" | Select-Object -ExpandProperty value
                    "MinIOps"             = $_.capabilities | Where-Object name -eq "MinIOps" | Select-Object -ExpandProperty value
                    "MaxBandwidthMBps"    = $_.capabilities | Where-Object name -eq "MaxBandwidthMBps" | Select-Object -ExpandProperty value
                    "MinBandwidthMBps"    = $_.capabilities | Where-Object name -eq "MinBandwidthMBps" | Select-Object -ExpandProperty value
                    "MaxValueOfMaxShares" = $_.capabilities | Where-Object name -eq "MaxValueOfMaxShares" | Select-Object -ExpandProperty value
                }
            }
        }

        switch ($diskType) {
            "PremiumV2" {
                $skuName = "Premium $($diskName.split('_')[1])"
                $meterName = @("Premium $($diskName.split('_')[1]) Provisioned Capacity", "Premium $($diskName.split('_')[1]) Provisioned IOPS", "Premium $($diskName.split('_')[1]) Provisioned Throughput (MBps)")
            }
            "UltraSSD" {
                $skuName = "Ultra $($diskName.split('_')[1])"
                $meterName = @("Ultra $($diskName.split('_')[1]) Provisioned Capacity", "Ultra $($diskName.split('_')[1]) Provisioned IOPS", "Ultra $($diskName.split('_')[1]) Provisioned Throughput (MBps)")
            }
            "Premium" {
                $skuName = "$($diskSize) $($diskName.split('_')[1])"
                $meterName = @("$($diskSize) $($diskName.split('_')[1]) Disk")
            }
            "Standard" {
                $skuName = "$($diskSize) $($diskName.split('_')[1])"
                $meterName = @("$($diskSize) $($diskName.split('_')[1]) Disk")
            }
            "StandardSSD" {
                $skuName = "$($diskSize) $($diskName.split('_')[1])"
                $meterName = @("$($diskSize) $($diskName.split('_')[1]) Disk")
            }
        }

        Write-Output "Collecting Price information for $skuName"
        $prices = $meterName | foreach-object {
            $key = "$skuName|$_"
            if ($pricesBySkuMeter.ContainsKey($key)) {
                $pricesBySkuMeter[$key]
            }
        }

        # One entry per (size, redundancy) combination - a size like "P10" has both LRS and ZRS
        # variants, each with its own specs/pricing, so this has to live inside the redundancy loop.
        $output | Add-Member -MemberType NoteProperty -Name "$($diskSize)_$(($diskName).split('_')[1])" -Value $(New-Object PsObject -Property @{
                "specs"  = $diskSpecs
                "prices" = $prices
            })
    }
}

Write-Output "Writing file to $PsScriptRoot\..\web\disks.json"
$output | ConvertTo-JSON -Depth 100 | Out-File -FilePath "$PsScriptRoot\..\web\disks.json"
