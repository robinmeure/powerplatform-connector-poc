# PowerShell script review research

## Runtime support

The script suite requires PowerShell 7.1 or later. `Invoke-WebRequest -SkipHttpErrorCheck` was introduced in PowerShell 7, while the repository also uses `SHA256.HashData` and `Convert.ToHexString`, which require .NET 5. PowerShell 7.1 is the first PowerShell release based on .NET 5. The shared [Common.ps1](../scripts/Common.ps1) enforces this floor when sourced, and standalone [New-CompatibleDefinition.ps1](../scripts/New-CompatibleDefinition.ps1) enforces it directly; the deployment guide recommends a currently supported LTS release.

Sources:

- [Invoke-WebRequest](https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/invoke-webrequest): documents `-SkipHttpErrorCheck` as introduced in PowerShell 7.
- [Convert.ToHexString](https://learn.microsoft.com/dotnet/api/system.convert.tohexstring) and [SHA256.HashData](https://learn.microsoft.com/dotnet/api/system.security.cryptography.sha256.hashdata): .NET 5 APIs used by the scripts.
- [PowerShell support lifecycle](https://learn.microsoft.com/powershell/scripting/install/powershell-support-lifecycle): current support status and lifecycle.

## Power Platform environment provisioning

The legacy [`New-AdminPowerAppEnvironment`](https://learn.microsoft.com/powershell/module/microsoft.powerapps.administration.powershell/new-adminpowerappenvironment) cmdlet exposes `LocationName` and optional `RegionName`, but no `macroRegion` parameter. Microsoft's [macro-region guidance](https://learn.microsoft.com/power-platform/admin/macro-regions) describes capacity-based placement within a selected residency boundary. The documented [environment-provisioning REST API](https://learn.microsoft.com/rest/api/power-platform/environmentmanagement/environment-provisioning/provision-new-environment) accepts `macroRegion` for a Dataverse environment.

The REST reference defines `macroRegion` as a string but doesn't enumerate accepted values or document an operation-status polling endpoint on the create operation page. The repository has not verified authentication, tenant permissions, accepted value, asynchronous completion handling, or a live deployment through this API. Consequently, `New-DemoEnvironment.ps1` now fails before authentication or creating resources rather than retrying the legacy cmdlet with an unsupported location.

## Dataverse URL validation

The script validates that the supplied URI is an absolute HTTPS organization root, has a public-cloud organization hostname, and has no user information, non-default port, path, query, or fragment. It also validates the organization URL returned in environment metadata and compares hosts before requesting a Dataverse token. `Uri.TryCreate` provides non-throwing parsing for the metadata value. The hostname pattern is based on Microsoft's documented organization and regional host examples; it's intentionally narrower than a general `.dynamics.com` suffix check so an API endpoint host such as `org.api.crm.dynamics.com` isn't accepted as the organization URL.

Sources:

- [Power Platform data-center regions](https://learn.microsoft.com/power-platform/admin/new-datacenter-regions): documents organization/Web API host patterns and regional hosts.
- [Uri.TryCreate](https://learn.microsoft.com/dotnet/api/system.uri.trycreate): returns whether a URI can be created without throwing.

This validation is intentionally for the public-cloud `.dynamics.com` deployments used by this repository; sovereign-cloud hostnames are not accepted.

## External CLI diagnostics

The Azure CLI and PAC wrappers capture `$LASTEXITCODE` immediately and report the tool, a non-sensitive command prefix, and the exit code. They don't echo argument values or raw diagnostics, since command arguments can contain URLs, request bodies, tokens, or other sensitive values. `Invoke-AzJson` also fails explicitly when a successful command returns no JSON.

Sources:

- [about_Automatic_Variables](https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_automatic_variables): documents `$LASTEXITCODE` for the most recent native program.
- [Azure CLI troubleshooting](https://learn.microsoft.com/cli/azure/use-azure-cli-successfully-troubleshooting): describes `--debug` diagnostics; don't copy debug output into shared logs without reviewing it for sensitive data.
