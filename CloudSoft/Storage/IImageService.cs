namespace CloudSoft.Storage;

public interface IImageService
{
    /// <summary>
    /// Gets the URL for an image based on the specified image name
    /// </summary>
    /// <param name="imageName">The name of the image (e.g. "hero.jpg")</param>
    /// <returns>The full URL to the image</returns>
    string GetImageUrl(string imageName);
}
