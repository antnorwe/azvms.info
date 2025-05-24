$tenantID = Read-Host "Please enter your tenant ID to connect to"

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

$disks = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers | Select-Object -ExpandProperty Value | Where-Object { $_.resourceType -eq "disks" } 

$diskSkus = $disks | Select-Object Name, Tier, Size -unique

$output = @{}
$diskSkus | Select-Object -ExpandProperty Size -Unique | foreach-object {
    $diskSize = $_

    $disk = $disks | Where-Object { $_.Size -eq $diskSize }
    $diskName = $disk | Select-Object -ExpandProperty Name -First 1
    $diskType = $diskName.split('_')[0]

    $diskSpecs = if ($diskType -eq "PremiumV2" -or $diskType -eq "UltraSSD") {
        $disk | Select-Object -First 1 | foreach-object {
            New-Object PsObject -Property @{
                "name"                      = "$($diskType)"
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

    $skuName = "$($diskSize) $($diskName.split('_')[1])"

    $priceUri = "https://prices.azure.com/api/retail/prices?currencyCode='USD'&`$filter=serviceFamily eq 'Storage' and serviceName eq 'Storage' and skuName eq '$skuName'"
    $prices = Invoke-RestMethod -Method GET -Uri $priceUri

    $output | Add-Member -MemberType NoteProperty -Name "$($diskSize)_$(($diskName).split('_')[1])" -Value $(New-Object PsObject -Property @{
            "specs" = $diskSpecs
        })
}

$output | ConvertTo-JSON -Depth 100 | Out-File -FilePath "C:\Temp\disks.json"