using AgentWebApp.Services;
using Azure.Core;
using Azure.Identity;
using Azure.Monitor.OpenTelemetry.AspNetCore;

var builder = WebApplication.CreateBuilder(args);

// Note: Secrets are mounted as files from Azure Key Vault via the CSI Driver.
// The CSI driver mounts secrets from Key Vault as read-only files at
// /mnt/secrets-store/. This is more secure than environment variables because the
// secrets never exist as Kubernetes secrets. No direct Key Vault access is needed
// from the application code.

// Helper function to read secrets from mounted files
string ReadSecretFromFile(string secretName)
{
    var secretsPath = builder.Configuration["SECRETS_PATH"] ?? "/mnt/secrets-store";
    var secretFilePath = Path.Combine(secretsPath, secretName);

    if (File.Exists(secretFilePath))
    {
        return File.ReadAllText(secretFilePath).Trim();
    }

    // Fallback to configuration (for local development)
    return builder.Configuration[secretName.Replace("-", ":")] ?? string.Empty;
}

// Load secrets from mounted files and add to configuration.
// Path 2 only needs the Foundry project endpoint + agent name (and telemetry).
// The agent's instructions, model, and knowledge base live in Foundry.
builder.Configuration["ApplicationInsights:ConnectionString"] = ReadSecretFromFile("ApplicationInsights-ConnectionString");
builder.Configuration["Foundry:ProjectEndpoint"] = ReadSecretFromFile("Foundry-ProjectEndpoint");
builder.Configuration["Foundry:AgentName"] = ReadSecretFromFile("Foundry-AgentName");
var managedIdentityClientId = ReadSecretFromFile("AKS-ManagedIdentity-ClientId");

// Configure Azure credentials - use Managed Identity in AKS with workload identity
var credential = new DefaultAzureCredential(new DefaultAzureCredentialOptions
{
    ManagedIdentityClientId = managedIdentityClientId,
    ExcludeVisualStudioCredential = true,
    ExcludeVisualStudioCodeCredential = true,
    ExcludeSharedTokenCacheCredential = true,
    ExcludeInteractiveBrowserCredential = true,
    ExcludeAzureCliCredential = true,
    ExcludeAzurePowerShellCredential = true,
    ExcludeAzureDeveloperCliCredential = true
});

// Add Azure Monitor (Application Insights) for telemetry
// Connection string is read from the mounted secret file
var appInsightsConnectionString = builder.Configuration["ApplicationInsights:ConnectionString"];
if (!string.IsNullOrEmpty(appInsightsConnectionString))
{
    builder.Services.AddOpenTelemetry()
        .UseAzureMonitor(options =>
        {
            options.ConnectionString = appInsightsConnectionString;
        });
}

// Add services to the container
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new()
    {
        Title = "Conference Expert Agent API (Foundry)",
        Version = "v1",
        Description = "Thin UI that calls a Microsoft Foundry prompt agent answering questions about Microsoft Ignite and Build conferences"
    });
});

// Register Azure credential as a service (as TokenCredential for the agent service)
builder.Services.AddSingleton<TokenCredential>(credential);

// The New Foundry prompt agent is invoked over the OpenAI Responses API bound to
// the agent endpoint, addressed by name:
//   {projectEndpoint}/agents/{agentName}/endpoint/protocols/openai/responses
// The project endpoint format is:
//   https://<resource>.services.ai.azure.com/api/projects/<project>
var projectEndpoint = builder.Configuration["Foundry:ProjectEndpoint"];
if (string.IsNullOrEmpty(projectEndpoint))
{
    throw new InvalidOperationException(
        "Foundry project endpoint is not configured. " +
        "Ensure the Foundry-ProjectEndpoint secret is mounted at /mnt/secrets-store/ or configured in appsettings.json");
}
Console.WriteLine($"Configuring Foundry agent client with project endpoint: {projectEndpoint}");

// Register the Foundry agent service backed by a typed HttpClient.
builder.Services.AddHttpClient<IAgentService, FoundryAgentService>();

// Add CORS for development
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowAll", policy =>
    {
        policy.AllowAnyOrigin()
              .AllowAnyMethod()
              .AllowAnyHeader();
    });
});

// Health checks
builder.Services.AddHealthChecks();

var app = builder.Build();

// Configure the HTTP request pipeline
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
    app.UseCors("AllowAll");
}

// Serve static files (index.html chat interface)
app.UseDefaultFiles();
app.UseStaticFiles();

app.UseHttpsRedirection();
app.UseAuthorization();

// API info endpoint
app.MapGet("/api", () => Results.Json(new
{
    service = "Conference Expert Agent API (Foundry)",
    status = "running",
    endpoints = new
    {
        home = "/",
        health = "/health",
        chat = "/api/chat (POST)",
        swagger = "/swagger (development only)"
    },
    version = "1.0.0"
}));

app.MapControllers();
app.MapHealthChecks("/health");

app.Run();
