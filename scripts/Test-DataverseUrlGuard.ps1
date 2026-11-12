$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Dataverse.ps1"

Assert-DataverseOrganizationUrl -EnvironmentUrl ([Uri]'https://org.crm.dynamics.com/')

$invalidUrls = @(
    'http://org.crm.dynamics.com/'
    'https://org.crm.dynamics.com/api/data/v9.2'
    'https://org.crm.dynamics.com/?tenant=unexpected'
    'https://org.crm.dynamics.com/#unexpected'
    'https://user@org.crm.dynamics.com/'
    'https://org.crm.dynamics.com:444/'
    'https://org.api.crm.dynamics.com/'
    'https://org.crm.dynamics.com.example.net/'
)
foreach ($url in $invalidUrls) {
    $rejected = $false
    try { Assert-DataverseOrganizationUrl -EnvironmentUrl ([Uri]$url) }
    catch {
        if ($_.Exception.Message -notlike 'Expected an HTTPS Dataverse organization root URL*') { throw }
        $rejected = $true
    }
    if (-not $rejected) { throw "Regression: invalid Dataverse URL was accepted: $url" }
}

Write-Output 'PASS: accepted the organization root and rejected unsafe or malformed URL components.'
