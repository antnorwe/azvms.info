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
function Invoke-RestMethodWithRetry {
    param(
        [Parameter(Mandatory)] [string] $Uri,
        [string] $Method = 'GET',
        [hashtable] $Headers,
        [int] $MaxRetries = 8,
        [int] $InitialDelaySeconds = 5
    )

    for ($attempt = 1; $true; $attempt++) {
        try {
            if ($Headers) {
                return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers
            }
            return Invoke-RestMethod -Method $Method -Uri $Uri
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
