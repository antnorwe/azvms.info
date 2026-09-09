# Shared helpers for the data-generation scripts in this folder. Dot-source this file:
#   . "$PSScriptRoot\Common.ps1"

function Connect-AzIfNeeded {
    # Reuses an existing Az context (e.g. set up by `azure/login` in CI) if there is one,
    # otherwise falls back to an interactive login for local/manual runs.
    if (-not (Get-AzContext)) {
        Connect-AzAccount
    }
}

# The Retail Prices API (and, occasionally, ARM) rate-limits with a 429 when called this often -
# especially from shared CI runner IPs. Retry with backoff, honouring Retry-After when the API sends one.
# Pass -ResponseHeaders ([ref]$var) to also capture the response headers (used by Get-AllRetailPrices
# below to read the API's own x-ms-ratelimit-* headers for proactive throttling).
function Invoke-RestMethodWithRetry {
    param(
        [Parameter(Mandatory)] [string] $Uri,
        [string] $Method = 'GET',
        [hashtable] $Headers,
        [int] $MaxRetries = 8,
        [int] $InitialDelaySeconds = 5,
        [ref] $ResponseHeaders
    )

    for ($attempt = 1; $true; $attempt++) {
        try {
            $respHeaders = $null
            if ($Headers) {
                $result = Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -ResponseHeadersVariable respHeaders
            }
            else {
                $result = Invoke-RestMethod -Method $Method -Uri $Uri -ResponseHeadersVariable respHeaders
            }
            if ($ResponseHeaders) {
                $ResponseHeaders.Value = $respHeaders
            }
            return $result
        }
        catch {
            $response = $_.Exception.Response
            $statusCode = if ($response) { [int]$response.StatusCode } else { $null }

            if ($statusCode -ne 429 -or $attempt -ge $MaxRetries) {
                throw
            }

            $retryAfter = $response.Headers.RetryAfter
            $delaySeconds = if ($retryAfter -and $retryAfter.Delta) {
                [math]::Ceiling($retryAfter.Delta.Value.TotalSeconds)
            }
            else {
                $InitialDelaySeconds * [math]::Pow(2, $attempt - 1)
            }

            Write-Warning "Rate limited (429) calling $Uri - waiting $delaySeconds seconds before retry $attempt/$MaxRetries"
            Start-Sleep -Seconds $delaySeconds
        }
    }
}

# Fetches every page of a Retail Prices API query for the given $filter, following NextPageLink.
# The API caps pages at 1000 items and rate-limits aggressively; it reports its own quota via
# x-ms-ratelimit-remaining-retailPrices-requests / x-ms-ratelimit-retailPrices-retry-after response
# headers, so this throttles proactively against those instead of guessing at a fixed delay -
# Invoke-RestMethodWithRetry's 429 handling remains as a fallback for whatever this doesn't catch
# (e.g. quota shared with unrelated traffic on the same CI runner IP).
function Get-AllRetailPrices {
    param(
        [Parameter(Mandatory)] [string] $Filter
    )

    $items = New-Object System.Collections.Generic.List[object]
    # The API's $skip-based pagination can return the boundary row twice across two pages -
    # confirmed directly against the live API (same meterId/armRegionName/type/skuName repeated
    # at a page boundary). meterId alone isn't a safe dedup key (it's shared across type variants
    # like Consumption/DevTestConsumption/Reservation for the same underlying meter), so key on
    # the full row identity instead - this only drops rows that are identical in every field that
    # matters, never a legitimately distinct one.
    $seenKeys = New-Object System.Collections.Generic.HashSet[string]
    $encodedFilter = [uri]::EscapeDataString($Filter)
    $uri = "https://prices.azure.com/api/retail/prices?currencyCode='USD'&`$filter=$encodedFilter"
    $page = 0

    while ($uri) {
        $page++
        $respHeaders = $null
        $results = Invoke-RestMethodWithRetry -Uri $uri -ResponseHeaders ([ref]$respHeaders)

        foreach ($item in $results.Items) {
            $key = "$($item.armRegionName)|$($item.type)|$($item.skuName)|$($item.reservationTerm)|$($item.meterId)"
            if ($seenKeys.Add($key)) {
                $items.Add($item)
            }
        }
        # Write-Host, not Write-Output: this function returns $items via the pipeline, and
        # Write-Output inside a function feeds that same pipeline - it would otherwise get
        # spliced into the returned collection alongside the actual price objects.
        Write-Host "  ...page $page, $($items.Count) unique price rows so far"

        $uri = $results.NextPageLink

        if ($uri) {
            $remaining = $null
            $retryAfter = 60
            if ($respHeaders -and $respHeaders['x-ms-ratelimit-remaining-retailPrices-requests']) {
                $remaining = [int]$respHeaders['x-ms-ratelimit-remaining-retailPrices-requests'][0]
            }
            if ($respHeaders -and $respHeaders['x-ms-ratelimit-retailPrices-retry-after']) {
                $retryAfter = [int]$respHeaders['x-ms-ratelimit-retailPrices-retry-after'][0]
            }

            if ($remaining -ne $null -and $remaining -le 1) {
                Write-Host "  ...rate-limit quota nearly exhausted ($remaining remaining) - waiting ${retryAfter}s before next page"
                Start-Sleep -Seconds $retryAfter
            }
        }
    }

    return $items
}
