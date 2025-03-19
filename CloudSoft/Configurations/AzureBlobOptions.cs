namespace CloudSoft.Configurations;

public class AzureBlobOptions
{
    public const string SectionName = "AzureBlob";

    public string ContainerUrl { get; set; } = string.Empty;
}
