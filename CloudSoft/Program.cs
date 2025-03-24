using CloudSoft.Configurations;
using CloudSoft.Models;
using CloudSoft.Repositories;
using CloudSoft.Services;
using CloudSoft.Storage;
using MongoDB.Driver;
using Microsoft.Extensions.Options;

var builder = WebApplication.CreateBuilder(args);

// Lägg till controllers med views
builder.Services.AddControllersWithViews();

// Bind konfigurationen från sektionen "MongoDb" (se till att din appsettings.json har "MongoDb")
builder.Services.Configure<MongoDbOptions>(
    builder.Configuration.GetSection("MongoDb"));

// Beroende på feature flag, registrera MongoDB eller fallback (in-memory)
bool useMongoDb = builder.Configuration.GetValue<bool>("FeatureFlags:UseMongoDb");

if (useMongoDb)
{
    // Registrera MongoClient med säkerhetskontroll för connection string
    builder.Services.AddSingleton<IMongoClient>(sp =>
    {
        var options = sp.GetRequiredService<IOptions<MongoDbOptions>>().Value;
        if (string.IsNullOrWhiteSpace(options.ConnectionString))
        {
            throw new InvalidOperationException("MongoDB ConnectionString is not configured.");
        }
        return new MongoClient(options.ConnectionString);
    });

    // Registrera MongoDB collection för subscribers (med litet "s")
    builder.Services.AddSingleton<IMongoCollection<Subscriber>>(sp =>
    {
        var options = sp.GetRequiredService<IOptions<MongoDbOptions>>().Value;
        var client = sp.GetRequiredService<IMongoClient>();
        var database = client.GetDatabase(options.DatabaseName);
        // Se till att värdet i konfigurationen för collectionnamnet är "subscribers" (små bokstäver)
        return database.GetCollection<Subscriber>(options.SubscribersCollectionName);
    });

    // Registrera MongoDB repository
    builder.Services.AddSingleton<ISubscriberRepository, MongoDbSubscriberRepository>();

    Console.WriteLine("Using MongoDB repository");
}
else
{
    // Fallback: in-memory repository
    builder.Services.AddSingleton<ISubscriberRepository, InMemorySubscriberRepository>();

    Console.WriteLine("Using in-memory repository");
}

// Registrera Newsletter service (beroende av repository)
builder.Services.AddScoped<INewsletterService, NewsletterService>();

// Lägg till HttpContextAccessor
builder.Services.AddHttpContextAccessor();

// Konfigurera Azure Blob options från sektionen "AzureBlob"
builder.Services.Configure<AzureBlobOptions>(
    builder.Configuration.GetSection("AzureBlob"));

// Beroende på feature flag, registrera Azure Blob Storage image service
bool useAzureStorage = builder.Configuration.GetValue<bool>("FeatureFlags:UseAzureStorage");
if (useAzureStorage)
{
    builder.Services.AddSingleton<IImageService, AzureBlobImageService>();
    Console.WriteLine("Using Azure Blob Storage for images");
}
else
{
    builder.Services.AddSingleton<IImageService, LocalImageService>();
    Console.WriteLine("Using local storage for images");
}

var app = builder.Build();

// Konfigurera HTTP request pipeline för production
if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Home/Error");
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseStaticFiles();
app.UseRouting();
app.UseAuthorization();

app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Home}/{action=Index}/{id?}")
    .WithStaticAssets();

app.Run();
