namespace CloudSoft.Configurations;

public class MongoDbOptions
{
    public const string SectionName = "MongoDb";

    public string ConnectionString { get; set; } = string.Empty;
    public string DatabaseName { get; set; } = string.Empty;
    public string SubscribersCollectionName { get; set; } = string.Empty;
}
