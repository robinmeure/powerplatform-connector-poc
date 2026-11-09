# Deploy and operate the demo

## Prerequisites

Use an explicitly approved subscription, tenant, Azure region and two isolated Power Platform Developer environments in the approved geography. Developer entitlement must already exist; never substitute paid environment types without approval.

Tooling: .NET 10 SDK, Azure CLI with Bicep, PAC CLI, and the official `Microsoft.PowerApps.Administration.PowerShell` module for environment administration. Authenticate Azure and PAC to the same tenant. The administration module may require interactive sign-in.

Bootstrap requires permission to create/maintain the three demo Entra apps, create service principals, grant delegated admin consent and assign the backend application role to APIM. Azure Contributor-style management permissions do not imply those Graph permissions. Do not grant broad tenant permissions to ordinary deployment agents merely to make bootstrap work.

Validate infrastructure and obtain cost approval before deploying. APIM Developer and App Service B1 are paid, nonproduction demo choices. Region advertising and general quotas do not guarantee provisioning eligibility: run provider-level ARM validation for the actual selected SKU.

## Azure

```powershell
.\scripts\Deploy-Azure.ps1 `
  -SubscriptionId <approved-subscription-guid> `
  -TenantId <approved-tenant-guid> `
  -Location <approved-azure-region> `
  -ResourceGroup <isolated-demo-resource-group> `
  -PublisherName 'Contoso Connector PoC' `
  -PublisherEmail <publisher-email>

.\scripts\Test-LiveBoundary.ps1
.\scripts\Export-Connector.ps1
```

Deployment creates single-tenant frontend/connector/backend applications without client secrets, grants `Demo.Read` delegated consent, creates APIM and the backend, grants APIM `Demo.Invoke`, resolves its actual client ID, deploys application code and imports APIM's API/policy.

The deploy script refuses to reuse a resource group without the demo ownership tag or an application without its demo tag. Preserve existing identities/solutions; do not delete and recreate a connector to apply an update.

Generated identifiers, artifacts and redacted evidence live under ignored `out\`. Do not publish its contents wholesale: inspect each intended artifact. Subscription keys and tokens stay in memory and must never be printed, committed or copied into evidence.

## Power Platform

Verify the actual returned location, environment IDs and organization URLs before adding components. Macro-region selection is not equivalent to an exact geography; observed PAC `eu-efta` placement selected Switzerland. The initially unapproved empty demo environment was deleted only after explicit approval and live content checks.

**Provisioning limitation:** PAC rejects `--region europe`, and the official administration cmdlet used by `New-DemoEnvironment.ps1` returns `MacroRegionRequired` for `-LocationName europe`. The authenticated admin center offers only macro-geographies with capacity-based system placement, not an exact Europe selector. The script is not a verified workaround.

For this demo the user subsequently explicitly approved **European Union & EFTA, including Switzerland**. The two Developer environments were then created through the admin center with Dataverse, without paid fallback or enabling Managed Environments. Build landed in Switzerland North; the managed-solution target in Switzerland West. "Managed target" describes the imported solution, not the environment's licensing setting. Actual IDs, URLs, geography and readiness are recorded in ignored `out\environments.local.json`. Supply `-ExpectedLocation switzerland` to the authoring, import and update scripts for these environments; their default remains `europe` and no location is silently substituted.

Run `Initialize-Solutions.ps1` against the approved Build environment after exporting connector files. Configure OAuth Managed identity on the connector's Security tab. Register its issuer/subject as a federated credential on the single-tenant connector client app; register the connector's actual redirect URI too.

The Security UI save removed the additional `api_key` parameter in the live test, even though its header policy survived. After configuring Managed identity, run `Restore-ConnectorSubscriptionParameter.ps1` against Build: it downloads persisted properties, restores only the required key parameter from the separate overlay, and verifies OAuth metadata is unchanged. Do not reapply the initial OAuth overlay, which would reset federation. Verify the parameter again after any later Security UI save, before exporting or creating Connections.

Export the connector solution as managed and import it into the approved target. Configure target-specific federation, then create a target-local delegated Connection with the Product subscription key. Sign-in is an explicit interactive step; development teams do not need the OAuth client secret.

Build the consumer flow in its separate solution with a Connection Reference, export managed and supply deployment settings that bind the reference to the existing target Connection. Create settings with `pac solution create-settings`. Never place a subscription key or bearer token in these settings.

Before declaring the proof successful, run the real flow, apply a compatible managed connector update and run the same flow again. Record observed run status and stable identifiers; do not replace this with a direct HTTP call or unit test.

Use `Update-ConnectorDefinition.ps1` for the update, not a bare `pac connector update --api-definition-file`: the live PAC version cleared request policies when properties were omitted. The script downloads the connector's persisted properties, supplies them unchanged with the new definition, and compares authentication/parameter/policy metadata before bumping the managed solution version. The baseline uses initial corrected version `1.0.0.1`; the compatible update uses `1.0.1.0`. Backend version need not change for a connector contract/documentation update.

### Observed PAC update failure and repair

With PAC `2.12.2+ga6b1ffa`, this command preserved OAuth/key parameters but persisted `policyTemplateInstances=[]`:

```powershell
pac connector update --environment $BuildUrl --connector-id $ConnectorId `
  --api-definition-file .\out\connector-update\apiDefinition.json
```

The post-update guard compared persisted `connectionparameters`, `connectionparametersets` and `policytemplateinstances` before allowing a solution version bump. It rejected the lost policy before managed promotion. This matters: an update without the header injection policy cannot send the APIM Product key even if the Connection still appears Connected.

The repaired sequence downloads **existing Managed identity properties**, not the initial auth overlay, and supplies those properties unchanged:

```powershell
.\scripts\New-CompatibleDefinition.ps1 -InputPath .\connector\apiDefinition.json `
  -OutputPath .\out\connector-update\apiDefinition.json

.\scripts\Update-ConnectorDefinition.ps1 @BuildParameters -ConnectorId $ConnectorId `
  -ApiDefinitionPath .\out\connector-update\apiDefinition.json -SolutionVersion 1.0.1.0
```

`$BuildParameters` contains the explicitly approved `TenantId`, `SubscriptionId`, `EnvironmentId`, `EnvironmentUrl` and `ExpectedLocation`. The update helper executes:

```powershell
pac connector download --environment $BuildUrl --connector-id $ConnectorId `
  --outputDirectory .\out\update-preserved
pac connector update --environment $BuildUrl --connector-id $ConnectorId `
  --api-definition-file .\out\connector-update\apiDefinition.json `
  --api-properties-file .\out\update-preserved\apiProperties.json
```

`.\scripts\Test-ConnectorUpdateGuard.ps1` replays the observed empty-policy mutation through the same comparison used by the live updater. Unchanged properties pass; policy loss throws. This regression does not call PAC or claim additional live negative-token tests.

### Solution ownership and effective updates

The first consumer export unexpectedly included the connector as root component type `372`, despite `--AddRequiredComponents false`. `New-ConsumerFlow.ps1` now removes only this duplicate **solution membership** after verifying central connector ownership; it does not delete the connector. `Test-ManagedPackages.ps1` prevents promotion if the consumer ZIP contains connector artifacts. Existing installs require a consumer **upgrade**, not just an update, to remove the obsolete consumer connector layer:

```powershell
.\scripts\Export-ManagedSolutions.ps1 -SourceEnvironmentUrl $BuildUrl
.\scripts\Import-ManagedDemo.ps1 @TargetParameters -Stage Consumer `
  -ConnectionId $ExistingConnectionId -StageAndUpgrade
```

Managed solution version alone is not proof that the effective connector changed. In this deployment, target solution `1.0.1.0` initially still exposed the original definition. Solution Layers showed an Active unmanaged layer above both managed solutions. The corrected consumer upgrade removed duplicate managed ownership. Removing an Active unmanaged customization requires separate approval and inspection, not an unconditional pipeline force-overwrite.

The user approved removing only this connector's Active customization through **Advanced > Remove active customizations** in the isolated target. Async operation `48bdcdef-29d9-f111-84e8-000d3a832b24` completed successfully. The effective definition became `1.0.1`, but the guard caught a real OAuth change: the managed layer contained Build's redirect and federation subject. The target's Entra federation credential itself was intact. This is not a harmless JSON-formatting difference; the target-specific Active layer was load-bearing.

After separate user approval, `Restore-TargetFederationMetadata.ps1` downloaded the updated target definition/properties, changed only the redirect URL and federation subject to their recorded target values, and required the **entire** resulting connection-parameter JSON to match the immutable baseline SHA256 before updating. It then supplied that updated definition and properties together. This restores necessary target-local metadata and may recreate an Active layer; repeat the guarded effective-definition/configuration comparison on future updates instead of assuming that layer is disposable.

```powershell
.\scripts\Restore-TargetFederationMetadata.ps1 @TargetParameters `
  -BaselineSnapshotPath .\out\target-before-update.local.json `
  -TargetSecurityPath .\out\target-security.local.json

.\scripts\Get-DemoTargetSnapshot.ps1 @TargetParameters `
  -OutputPath .\out\target-after-update.local.json
.\scripts\Test-ManagedUpdate.ps1 -BeforePath .\out\target-before-update.local.json `
  -AfterPath .\out\target-after-update.local.json
.\scripts\Test-ManagedUpdateGuard.ps1
```

Keep the original Connection/reference and verify the Entra federation independently. Raw connection-parameter hashes now exactly match baseline. The header policy's wrapper uses Pascal rather than camel case after import; the snapshot additionally normalizes only the known `templateId`/`title`/`parameters` wrapper names. The full normalized policy, including all parameter names/values, matches the original hash. The guard does not accept a missing or changed header policy. Definition comparison uses full JSON semantic equality during target metadata restoration because PAC can normalize serialization.

Finally rerun the real flow, not a direct HTTP proxy. The original managed flow succeeded before and after the effective update, with HTTP 200 on both runs and no reauthentication. Baseline run: `08584077183106224027230767590CU28`; post-update: `08584077153898941665765164881CU11`. Evidence is in ignored `out\baseline-run.local.json`, `out\after-update-run.local.json`, both target snapshots and `out\target-federation-after-update.local.json`.

## Azure DevOps

`azure-pipelines.yml` is a template, not evidence of an executed pipeline. Configure Azure WIF and Power Platform WIF service connections, install Power Platform Build Tools, and protect the named deployment environments with approvals. Both deployment switches default to false.

Its Solutions stage illustrates ordered export/import and package-ownership validation, not the complete compatible-update repair above. It deliberately does not remove Active layers or force-overwrite target customizations. For an existing installation, complete the separately approved target-layer inspection/restoration and runtime checks through the guarded local procedure. Do not equate a green template import with a successful effective update.

The Azure bootstrap script also uses Graph. A federated pipeline identity needs separately approved Graph application permissions and ownership for the demo registrations. A production arrangement should separate privileged tenant bootstrap from routine deployment.

Solution promotion needs source/target Dataverse application users and suitable solution privileges. Supply a secure deployment-settings file with the existing target Connection Reference binding. The pipeline does not create a delegated OAuth Connection or perform interactive consent.

On the first connector import, complete target federation and Connection setup before running consumer promotion. Subsequent compatible connector imports should retain that Connection; verify instead of assuming it.

## Cleanup

Obtain separate deletion approval. Delete only the explicitly identified demo resource group, demo Entra app registrations/service principals and the two approved demo environments after checking for unexpected user content. Stopping a command does not delete resources or stop their charges. Never delete existing customer/developer environments.
