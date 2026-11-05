using System.Security.Claims;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;

var builder = WebApplication.CreateBuilder(args);
var tenantId = RequiredGuid(builder.Configuration, "Identity:TenantId");
var audience = RequiredGuid(builder.Configuration, "Identity:Audience");
var apimPrincipalId = RequiredGuid(builder.Configuration, "Identity:ApimPrincipalId");
var apimClientId = RequiredGuid(builder.Configuration, "Identity:ApimClientId");

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.Authority = $"https://login.microsoftonline.com/{tenantId}/v2.0";
        options.Audience = audience;
        options.MapInboundClaims = false;
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = $"https://login.microsoftonline.com/{tenantId}/v2.0",
            ValidateAudience = true,
            ValidAudience = audience,
            ValidateIssuerSigningKey = true,
            RequireSignedTokens = true,
            RequireExpirationTime = true,
            ValidateLifetime = true,
            RoleClaimType = "roles",
            ClockSkew = TimeSpan.FromSeconds(30)
        };
    });
builder.Services.AddAuthorization(options =>
    options.AddPolicy("ApimApplication", policy => policy
        .RequireAuthenticatedUser()
        .RequireAssertion(context => BackendAuthorization.IsAllowed(context.User, apimPrincipalId, apimClientId))));

var app = builder.Build();
app.UseAuthentication();
app.UseAuthorization();
app.MapGet("/health", () => Results.Ok(new { status = "ready" }));
app.MapGet("/proof", (ClaimsPrincipal user) => Results.Ok(new
{
    message = "CZ API reached through the authorized APIM application identity",
    version = app.Configuration["Demo:Version"] ?? "1.0.0",
    authentication = new
    {
        tokenType = "application",
        role = BackendAuthorization.RequiredRole,
        callerIsApim = user.FindFirstValue("oid") == apimPrincipalId,
        callerClientIsApim = user.FindFirstValue("azp") == apimClientId,
        delegatedScopePresent = user.HasClaim(claim => claim.Type == "scp"),
        userContextPresent = BackendAuthorization.HasUserContext(user)
    }
})).RequireAuthorization("ApimApplication");
app.Run();

static string RequiredGuid(IConfiguration configuration, string key)
{
    var value = configuration[key];
    if (!Guid.TryParse(value, out var parsed))
        throw new InvalidOperationException($"Configuration '{key}' must be a GUID.");
    return parsed.ToString();
}

public partial class Program;
