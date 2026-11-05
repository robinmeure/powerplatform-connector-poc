using System.Net;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

public sealed class BackendHttpTests
{
    [Fact]
    public async Task ProtectedEndpointRejectsAnonymousCaller()
    {
        using var factory = CreateFactory();
        using var client = factory.CreateClient();
        using var response = await client.GetAsync("/proof");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task HealthDoesNotExposeProtectedProof()
    {
        using var factory = CreateFactory();
        using var client = factory.CreateClient();
        using var response = await client.GetAsync("/health");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.DoesNotContain("authentication", await response.Content.ReadAsStringAsync());
    }

    private static WebApplicationFactory<Program> CreateFactory() =>
        new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
        {
            builder.UseSetting("Identity:TenantId", "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa");
            builder.UseSetting("Identity:Audience", "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb");
            builder.UseSetting("Identity:ApimPrincipalId", "cccccccc-cccc-cccc-cccc-cccccccccccc");
            builder.UseSetting("Identity:ApimClientId", "dddddddd-dddd-dddd-dddd-dddddddddddd");
        });
}
