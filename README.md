# Contoso Power Platform Custom Connector PoC

Working example of centrally managed Power Platform Custom Connectors over Azure API Management, with separate managed connector/consumer solutions and Azure DevOps deployment templates.

**Identity boundary:** delegated user OAuth plus an APIM Product subscription key from the connector to APIM; APIM managed identity with an application role from APIM to the backend. Generic custom connector OAuth does not support native `client_credentials`; its Managed identity option remains delegated.

See [architecture](docs/architecture.md), [deployment](docs/deployment.md), and [Microsoft sources/evidence status](docs/sources.md). The deployed managed flow returned HTTP 200 **before and after a compatible connector update**, with the same Connection and Connection Reference and no reauthentication. The backend verified the exact APIM application identity, required role and absence of delegated/user context.

The update was not a blind managed import: guards caught PAC dropping the subscription-header policy, duplicate connector packaging in the consumer, and an Active layer masking the update. The verified procedure preserves persisted properties and restores recorded target-specific federation metadata after the approved layer removal. See the deployment guide for these important ALM limitations. Azure DevOps remains an unexecuted template, not an automated-promotion proof.

Read the [detailed implementation summary](docs/implementation-summary.md) for what was built, why each step was necessary, the original four Contoso requirements, real run evidence, and the limitations discovered.

For a Dutch decision guide covering when to use delegated authentication or app-only alternatives, see [Delegated of app-only](docs/authenticatie-keuze.md).

For a browser presentation of the findings, including the follow-up questions and second-opinion corrections, open [the Dutch architecture briefing](docs/presentatie.html). It is a standalone, offline-capable HTML page with chapter navigation, expandable details and print/PDF support; no build or server is required. Repository source links need the accompanying files, and Microsoft documentation links require internet.

**Naming note:** Contoso names throughout this repository are illustrative replacements for the original demo names, including resource URLs and runtime identifiers in historical evidence. This source-only rename does not rename deployed resources or migrate existing solutions, Connections, federation metadata, or ignored local artifacts. Before using these scripts with an existing deployment, reconcile its actual names, ownership tags, identifiers and local configuration; the renamed URLs are not verified live endpoints.

## Retained demo inventory

The user chose to **keep the deployed demo**. These non-secret identifiers describe the verified deployment on 5 November 2026; they are not credentials or authorization to change resources.

| Item | Retained value |
|------|----------------|
| Azure subscription | `ME-MngEnvMCAP935538-rmeure-1` / `17254a3c-2e67-4fec-9e2c-cfe17cfb579d` |
| Entra tenant | `63645c73-a00c-4659-b911-eb6c4c2d4a8f` |
| Resource group / Azure region | `rg-contoso-connector-poc-demo` / Sweden Central (`swedencentral`) |
| API Management | `contosoconnector-apim-hvngf2rwwvf7a`, Developer; [gateway](https://contosoconnector-apim-hvngf2rwwvf7a.azure-api.net), API `contoso-proof`, path `/contoso` |
| APIM Product / subscription | `contoso-developers` / `contoso-demo-connection`; key values are deliberately not included |
| Backend / App Service plan | `contosoconnector-api-hvngf2rwwvf7a` / `contosoconnector-plan-hvngf2rwwvf7a`, Linux B1; [.NET backend health](https://contosoconnector-api-hvngf2rwwvf7a.azurewebsites.net/health) |
| Authoring environment | **Contoso Connector PoC Build**, Developer, `5a181d17-9728-ebe9-ab82-31716241a959`; Switzerland North; [Dataverse](https://orgf976f77f.crm17.dynamics.com/), [maker solutions](https://make.powerapps.com/environments/5a181d17-9728-ebe9-ab82-31716241a959/solutions/) |
| Managed-solution target | **Contoso Connector PoC**, Developer, `9428be14-6fc4-e1a0-9f36-28db26e7b952`; Switzerland West; [Dataverse](https://orgc9d38663.crm17.dynamics.com/), [maker solutions](https://make.powerapps.com/environments/9428be14-6fc4-e1a0-9f36-28db26e7b952/solutions/) |
| Target connector solution | [ContosoPoCConnector](https://make.powerapps.com/environments/9428be14-6fc4-e1a0-9f36-28db26e7b952/solutions/09a336a4-a4bf-4c6e-acb9-68c1d93972b7), managed `1.0.1.0`; effective OpenAPI definition `1.0.1` |
| Target consumer solution | [ContosoPoCConsumer](https://make.powerautomate.com/environments/9428be14-6fc4-e1a0-9f36-28db26e7b952/solutions/1a2e4f0c-4d7e-4275-bc6d-ec636e92ebfd), managed `1.0.1.0` |
| Existing managed flow | [Contoso Identity Boundary Proof](https://make.powerautomate.com/environments/9428be14-6fc4-e1a0-9f36-28db26e7b952/solutions/~preferred/flows/6c551e3f-21d9-f111-84e8-70a8a5079ecf/details), On; workflow `6c551e3f-21d9-f111-84e8-70a8a5079ecf` |
| Existing Connection / Reference | `a70df4ce-b90d-43c4-9f07-5119-03bc0036` / `616ee0b0-092b-4313-9a4a-443ba727ec62`, logical reference `contoso_ContosoProofConnection` |

Both Power Platform environments use Dataverse and the existing Developer entitlement. Switzerland placement within **European Union & EFTA** was explicitly approved; it is not exact-Europe placement. "Managed target" means managed solution imports, not a licensed Managed Environment.

## Open and run the existing demo

1. Sign in to the approved tenant with an account that has access to the retained target, then open [Contoso Identity Boundary Proof](https://make.powerautomate.com/environments/9428be14-6fc4-e1a0-9f36-28db26e7b952/solutions/~preferred/flows/6c551e3f-21d9-f111-84e8-70a8a5079ecf/details). Confirm the environment is **Contoso Connector PoC**, not Build or an unrelated environment, accounting for the naming note above.
2. Select **Run > Run flow**. Use the existing Connection; there is no need to recreate or reconnect the verified entry merely to demonstrate the update.
3. Open the new run and expand **Get identity proof**. Expect HTTP `200`, `callerIsApim=true`, `callerClientIsApim=true`, role `Demo.Invoke`, `delegatedScopePresent=false`, and `userContextPresent=false`. Backend version remains `1.0.0`; connector definition version is independently `1.0.1`.

The saved [baseline run](https://make.powerautomate.com/environments/9428be14-6fc4-e1a0-9f36-28db26e7b952/solutions/~preferred/flows/6c551e3f-21d9-f111-84e8-70a8a5079ecf/runs/08584077183106224027230767590CU28) and [post-update run](https://make.powerautomate.com/environments/9428be14-6fc4-e1a0-9f36-28db26e7b952/solutions/~preferred/flows/6c551e3f-21d9-f111-84e8-70a8a5079ecf/runs/08584077153898941665765164881CU11) both succeeded. Run-history retention is finite; the summary preserves the essential non-secret observations.

If a later Connection expires or reports an error, inspect the cause before repair. Delegated sign-in may require its owner to interact again. Do not copy subscription keys or tokens into chat, Git, screenshots or deployment settings. Do not use the initial auth overlay to overwrite the federated connector.

## Continuing costs and cleanup

The approved planning estimate for **APIM Developer plus Linux App Service B1** was approximately **USD 0.084/hour**, or **USD 61 per 730 hours**, excluding taxes, traffic and Power Platform licensing. This is the disclosed demo estimate, not a fresh price quote or spending cap; actual billing and entitlement must be checked in the tenant. Keeping resources incurs ongoing charges even when the flow is idle.

All Azure/Entra resources, both Power Platform environments, Connections and flows are intentionally retained. **Cleanup requires separate explicit approval**, exact resource identification and a check for unexpected user content. Nothing in these instructions authorizes deletion or reconfiguration.

## Repository

| Folder | Purpose |
|--------|---------|
| `src/Backend` | .NET API with signed-token validation and exact APIM identity/application-role authorization |
| `infra` | Bicep and APIM caller-validation/backend-MI policy |
| `connector` | OpenAPI contract and separate initial OAuth/subscription-key overlay |
| `scripts` | Tenant bootstrap, deployment, connector export, solution setup and redacted live checks |
| `tests` | Backend authorization and HTTP tests |

```powershell
dotnet test .\tests\Backend.Tests\Backend.Tests.csproj
```

> Do not commit secrets. Runtime configuration and raw local evidence remain ignored; the inventory and summary intentionally contain only curated non-secret identifiers and results.
