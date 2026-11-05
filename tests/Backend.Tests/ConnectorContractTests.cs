using System.Text.Json;
using System.Xml.Linq;
using Xunit;

public sealed class ConnectorContractTests
{
    [Fact]
    public void SubscriptionKeyIsRequiredAndInjectedIntoRequestNotResponse()
    {
        using var document = ReadJson("auth-overlay.json");
        var properties = document.RootElement.GetProperty("properties");
        var parameter = properties.GetProperty("connectionParameters").GetProperty("api_key");
        Assert.Equal("securestring", parameter.GetProperty("type").GetString());
        Assert.Equal("true", parameter.GetProperty("uiDefinition").GetProperty("constraints")
            .GetProperty("required").GetString());
        var policy = properties.GetProperty("policyTemplateInstances")[0];
        Assert.Equal("setheader", policy.GetProperty("templateId").GetString());
        var settings = policy.GetProperty("parameters");
        Assert.Equal("Request", settings.GetProperty("x-ms-apimTemplate-policySection").GetString());
        Assert.Equal("Ocp-Apim-Subscription-Key", settings.GetProperty("x-ms-apimTemplateParameter.name").GetString());
        Assert.Equal("@connectionParameters('api_key', '')",
            settings.GetProperty("x-ms-apimTemplateParameter.value").GetString());
    }

    [Fact]
    public void GatewayAuthorizesDelegatedCallerBeforeAcquiringBackendToken()
    {
        var policy = XDocument.Load(Path.Combine(AppContext.BaseDirectory, "Fixtures", "api.xml"));
        var inbound = policy.Root!.Element("inbound")!.Elements().ToArray();
        var validation = Array.FindIndex(inbound, element => element.Name == "validate-azure-ad-token");
        var applicationAuthentication = Array.FindIndex(inbound, element => element.Name == "authentication-managed-identity");
        Assert.True(validation >= 0 && applicationAuthentication > validation);
        Assert.Equal("Demo.Read", inbound[validation].Element("required-claims")!.Element("claim")!.Element("value")!.Value);
        Assert.NotNull(inbound[validation].Element("client-application-ids"));
        Assert.NotNull(inbound[validation].Element("audiences"));
        Assert.Equal("false", inbound[applicationAuthentication].Attribute("ignore-error")!.Value);
    }

    [Fact]
    public void ConsumerCallsStableConnectorOperationViaConnectionReference()
    {
        using var connector = ReadJson("apiDefinition.json");
        using var flow = ReadJson("flowDefinition.json");
        var operationId = connector.RootElement.GetProperty("paths").GetProperty("/proof")
            .GetProperty("get").GetProperty("operationId").GetString();
        var properties = flow.RootElement.GetProperty("properties");
        Assert.Equal("cz_CZProofConnection", properties.GetProperty("connectionReferences").GetProperty("__API_NAME__")
            .GetProperty("connection").GetProperty("connectionReferenceLogicalName").GetString());
        Assert.Equal(operationId, properties.GetProperty("definition").GetProperty("actions")
            .GetProperty("Get_identity_proof").GetProperty("inputs").GetProperty("host").GetProperty("operationId").GetString());
    }

    private static JsonDocument ReadJson(string name) =>
        JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", name)));
}
