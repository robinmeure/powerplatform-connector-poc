# CZ Power Platform Custom Connector PoC

Working example of centrally managed Power Platform Custom Connectors over Azure API Management, with separate managed connector/consumer solutions and Azure DevOps deployment templates.

**Identity boundary:** delegated user OAuth plus an APIM Product subscription key from the connector to APIM; APIM managed identity with an application role from APIM to the backend. Generic custom connector OAuth does not support native `client_credentials`; its Managed identity option remains delegated.

See [architecture](docs/architecture.md), [deployment](docs/deployment.md), and [Microsoft sources/evidence status](docs/sources.md). The deployed managed flow returned HTTP 200 **before and after a compatible connector update**, with the same Connection and Connection Reference and no reauthentication. The backend verified the exact APIM application identity, required role and absence of delegated/user context.

The update was not a blind managed import: guards caught PAC dropping the subscription-header policy, duplicate connector packaging in the consumer, and an Active layer masking the update. The verified procedure preserves persisted properties and restores recorded target-specific federation metadata after the approved layer removal. See the deployment guide for these important ALM limitations. Azure DevOps remains an unexecuted template, not an automated-promotion proof.

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

> Do not commit secrets. Tenant-specific values belong in local or pipeline configuration.
