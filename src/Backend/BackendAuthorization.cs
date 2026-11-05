using System.Security.Claims;

public static class BackendAuthorization
{
    public const string RequiredRole = "Demo.Invoke";

    public static bool HasUserContext(ClaimsPrincipal user) =>
        user.HasClaim(claim => claim.Type is "scp" or "upn" or "preferred_username" or "unique_name" or "email");

    public static bool IsAllowed(ClaimsPrincipal user, string apimPrincipalId, string apimClientId) =>
        user.Identity?.IsAuthenticated == true
        && !HasUserContext(user)
        && user.HasClaim("idtyp", "app")
        && user.HasClaim("roles", RequiredRole)
        && Guid.TryParse(user.FindFirstValue("oid"), out var caller)
        && Guid.TryParse(apimPrincipalId, out var expected)
        && caller == expected
        && Guid.TryParse(user.FindFirstValue("azp"), out var client)
        && Guid.TryParse(apimClientId, out var expectedClient)
        && client == expectedClient;
}
