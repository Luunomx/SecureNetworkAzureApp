using CloudSoft.Models;

namespace CloudSoft.Repositories;

public interface ISubscriberRepository
{
    Task<IEnumerable<Subscriber>> GetAllAsync();
    Task<Subscriber?> GetByEmailAsync(string email);
    Task<bool> AddAsync(Subscriber subscriber);
    Task<bool> UpdateAsync(Subscriber subscriber);
    Task<bool> DeleteAsync(string email);
    Task<bool> ExistsAsync(string email);
}
