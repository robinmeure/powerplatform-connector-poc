#requires -Version 7.1

throw @'
Environment creation through Microsoft.PowerApps.Administration.PowerShell is disabled here.
That legacy cmdlet does not expose the macroRegion request required by this tenant and can fail
after authentication. No login or environment-creation request was made. Use the Power Platform
admin center, or implement the documented environment-provisioning REST API only after verifying
the approved macroRegion value, permissions, operation completion, and resulting data location.
'@
