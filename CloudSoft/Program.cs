using CloudSoft.Services;
using CloudSoft.Repositories;
using CloudSoft.Models;
using CloudSoft.Configurations;
using CloudSoft.Storage;
using MongoDB.Driver;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddControllersWithViews();

// Check if MongoDB should be used (default to false if not specified)
bool useMongoDb = builder.Configuration.GetValue<bool>("FeatureFlags:UseMongoDb");

if (useMongoDb)
{
    // Configure MongoDB options
    builder.Services.Configure<MongoDbOptions>(
        builder.Configuration.GetSection(MongoDbOptions.SectionName));

    // Configure MongoDB client
    builder.Services.AddSingleton<IMongoClient>(serviceProvider => {
        var mongoDbOptions = builder.Configuration.GetSection(MongoDbOptions.SectionName).Get<MongoDbOptions>();
        return new MongoClient(mongoDbOptions?.ConnectionString);
    });

    // Configure MongoDB collection
    builder.Services.AddSingleton<IMongoCollection<Subscriber>>(serviceProvider => {
        var mongoDbOptions = builder.Configuration.GetSection(MongoDbOptions.SectionName).Get<MongoDbOptions>();
        var mongoClient = serviceProvider.GetRequiredService<IMongoClient>();
        var database = mongoClient.GetDatabase(mongoDbOptions?.DatabaseName);
        return database.GetCollection<Subscriber>(mongoDbOptions?.SubscribersCollectionName);
    });

    // Register MongoDB repository
    builder.Services.AddSingleton<ISubscriberRepository, MongoDbSubscriberRepository>();

    Console.WriteLine("Using MongoDB repository");
}
else
{
    // Register in-memory repository as fallback
    builder.Services.AddSingleton<ISubscriberRepository, InMemorySubscriberRepository>();

    Console.WriteLine("Using in-memory repository");
}

// Register service (depends on repository)
builder.Services.AddScoped<INewsletterService, NewsletterService>();

// Add HttpContextAccessor for URL generation
builder.Services.AddHttpContextAccessor();

// Configure Azure Blob options
builder.Services.Configure<AzureBlobOptions>(
    builder.Configuration.GetSection(AzureBlobOptions.SectionName));

// Check if Azure Storage should be used
bool useAzureStorage = builder.Configuration.GetValue<bool>("FeatureFlags:UseAzureStorage");

if (useAzureStorage)
{
    // Register Azure Blob Storage image service for production
    builder.Services.AddSingleton<IImageService, AzureBlobImageService>();
    Console.WriteLine("Using Azure Blob Storage for images");
}
else
{
    // Register local image service for development
    builder.Services.AddSingleton<IImageService, LocalImageService>();
    Console.WriteLine("Using local storage for images");
}

var app = builder.Build();

// Configure the HTTP request pipeline.
if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Home/Error");
    // The default HSTS value is 30 days. You may want to change this for production scenarios, see https://aka.ms/aspnetcore-hsts.
    app.UseHsts();
}

app.UseStaticFiles();

app.UseHttpsRedirection();
app.UseRouting();

app.UseAuthorization();

app.MapStaticAssets();

app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Home}/{action=Index}/{id?}")
    .WithStaticAssets();


app.Run();
