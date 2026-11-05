using System.Security.Claims;
using Xunit;

public sealed class BackendAuthorizationTests
{
    private const string ApimId = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
    private const string ClientId = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";

    [Fact]
    public void AcceptsAuthenticatedApimWithApplicationRole()
    {
        Assert.True(BackendAuthorization.IsAllowed(Principal(), ApimId, ClientId));
    }

    [Theory]
    [InlineData("upn")]
    [InlineData("preferred_username")]
    [InlineData("unique_name")]
    [InlineData("email")]
    public void RejectsUserContextEvenWithApplicationRoleAndType(string claimType)
    {
        var principal = Principal();
        ((ClaimsIdentity)principal.Identity!).AddClaim(new Claim(claimType, "test@example.invalid"));
        Assert.False(BackendAuthorization.IsAllowed(principal, ApimId, ClientId));
    }

    [Theory]
    [InlineData("missing-role")]
    [InlineData("wrong-role")]
    [InlineData("wrong-identity")]
    [InlineData("missing-identity")]
    [InlineData("invalid-identity")]
    [InlineData("delegated")]
    [InlineData("anonymous")]
    [InlineData("wrong-client")]
    [InlineData("missing-client")]
    [InlineData("missing-app-type")]
    public void RejectsUnauthorizedPrincipals(string scenario)
    {
        var claims = new List<Claim>
        {
            new("oid", ApimId), new("roles", "Demo.Invoke"),
            new("azp", ClientId), new("idtyp", "app")
        };
        if (scenario == "missing-role") claims.RemoveAll(claim => claim.Type == "roles");
        if (scenario == "wrong-role") claims[1] = new("roles", "Another.Role");
        if (scenario == "wrong-identity") claims[0] = new("oid", Guid.NewGuid().ToString());
        if (scenario == "missing-identity") claims.RemoveAll(claim => claim.Type == "oid");
        if (scenario == "invalid-identity") claims[0] = new("oid", "not-a-guid");
        if (scenario == "delegated") claims.Add(new("scp", "Demo.Read"));
        if (scenario == "wrong-client") claims[2] = new("azp", Guid.NewGuid().ToString());
        if (scenario == "missing-client") claims.RemoveAll(claim => claim.Type == "azp");
        if (scenario == "missing-app-type") claims.RemoveAll(claim => claim.Type == "idtyp");
        var principal = new ClaimsPrincipal(new ClaimsIdentity(claims,
            scenario == "anonymous" ? null : "UnitTest"));
        Assert.False(BackendAuthorization.IsAllowed(principal, ApimId, ClientId));
    }

    private static ClaimsPrincipal Principal() => new(new ClaimsIdentity(
        [new Claim("oid", ApimId), new Claim("roles", "Demo.Invoke"),
         new Claim("azp", ClientId), new Claim("idtyp", "app")], "UnitTest"));
}
