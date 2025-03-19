using CloudSoft.Models;
using MongoDB.Driver;

namespace CloudSoft.Repositories;

public class MongoDbSubscriberRepository : ISubscriberRepository
{
    private readonly IMongoCollection<Subscriber> _subscribers;

    public MongoDbSubscriberRepository(IMongoCollection<Subscriber> subscribers)
    {
        _subscribers = subscribers;
    }

    public async Task<IEnumerable<Subscriber>> GetAllAsync()
    {
        return await _subscribers.Find(_ => true).ToListAsync();
    }

    public async Task<Subscriber?> GetByEmailAsync(string email)
    {
        if (string.IsNullOrEmpty(email))
        {
            return null;
        }

        return await _subscribers.Find(s => s.Email == email).FirstOrDefaultAsync();
    }

    public async Task<bool> AddAsync(Subscriber subscriber)
    {
        if (subscriber == null || string.IsNullOrEmpty(subscriber.Email))
        {
            return false;
        }

        // Check if subscriber with this email already exists
        var existingSubscriber = await GetByEmailAsync(subscriber.Email);
        if (existingSubscriber != null)
        {
            return false;
        }

        try
        {
            await _subscribers.InsertOneAsync(subscriber);
            return true;
        }
        catch
        {
            return false;
        }
    }

    public async Task<bool> UpdateAsync(Subscriber subscriber)
    {
        if (subscriber == null || string.IsNullOrEmpty(subscriber.Email))
        {
            return false;
        }

        try
        {
            var result = await _subscribers.ReplaceOneAsync(
                s => s.Email == subscriber.Email,
                subscriber,
                new ReplaceOptions { IsUpsert = false });

            return result.ModifiedCount > 0;
        }
        catch
        {
            return false;
        }
    }

    public async Task<bool> DeleteAsync(string email)
    {
        if (string.IsNullOrEmpty(email))
        {
            return false;
        }

        try
        {
            var result = await _subscribers.DeleteOneAsync(s => s.Email == email);
            return result.DeletedCount > 0;
        }
        catch
        {
            return false;
        }
    }

    public async Task<bool> ExistsAsync(string email)
    {
        if (string.IsNullOrEmpty(email))
        {
            return false;
        }

        return await _subscribers.CountDocumentsAsync(s => s.Email == email) > 0;
    }
}
