#pragma warning disable OPENAI001
using AgentWebApp.Services;
using Azure.Identity;
using Azure.Monitor.OpenTelemetry.AspNetCore;
using OpenAI.Responses;
using System.ClientModel.Primitives;

var builder = WebApplication.CreateBuilder(args);

// Note: Secrets are mounted as files from Azure Key Vault via CSI Driver
// The CSI driver mounts secrets from Key Vault as read-only files at /mnt/secrets-store/
// This is more secure than environment variables as secrets never exist as Kubernetes secrets
// No direct Key Vault access is needed from the application code.

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

// Load secrets from mounted files and add to configuration
builder.Configuration["ApplicationInsights:ConnectionString"] = ReadSecretFromFile("ApplicationInsights-ConnectionString");
builder.Configuration["Foundry:ModelEndpoint"] = ReadSecretFromFile("Foundry-ModelEndpoint");
builder.Configuration["Foundry:ModelDeploymentName"] ??= "gpt-5.4-mini";
builder.Configuration["AzureSearch:Endpoint"] = ReadSecretFromFile("AzureSearch-Endpoint");
var managedIdentityClientId = ReadSecretFromFile("AKS-ManagedIdentity-ClientId");

// Select the AKS managed identity when mounted; retain developer credentials locally.
var credentialOptions = new DefaultAzureCredentialOptions();
if (!string.IsNullOrWhiteSpace(managedIdentityClientId))
{
    credentialOptions.ManagedIdentityClientId = managedIdentityClientId;
}
var credential = new DefaultAzureCredential(credentialOptions);

// Add Azure Monitor (Application Insights) for telemetry
// Connection string is read from mounted secret file
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
    c.SwaggerDoc("v1", new() { 
        Title = "Conference Expert Agent API", 
        Version = "v1",
        Description = "AI Agent for answering questions about Microsoft Ignite and Build conferences"
    });
});

// Register Azure credential as a service
builder.Services.AddSingleton(credential);

// Register a Responses API client for direct model inference through Foundry.
var foundryModelEndpoint = builder.Configuration["Foundry:ModelEndpoint"];
if (string.IsNullOrEmpty(foundryModelEndpoint))
{
    throw new InvalidOperationException(
        "The Foundry model endpoint is not configured. " +
        "Ensure the Foundry-ModelEndpoint secret is mounted at /mnt/secrets-store/ or configured in appsettings.json");
}

builder.Services.AddSingleton(sp =>
{
    var cred = sp.GetRequiredService<DefaultAzureCredential>();
    Console.WriteLine($"Configuring Foundry Responses API client with endpoint: {foundryModelEndpoint}");
    var tokenPolicy = new BearerTokenPolicy(cred, "https://ai.azure.com/.default");
    return new ResponsesClient(
        authenticationPolicy: tokenPolicy,
        options: new ResponsesClientOptions { Endpoint = new Uri(foundryModelEndpoint) });
});

// Add HTTP client factory
builder.Services.AddHttpClient();

// Add application services
builder.Services.AddSingleton<ISearchService, SearchService>();
builder.Services.AddSingleton<IAgentService, AgentService>();

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
    service = "Conference Expert Agent API",
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
