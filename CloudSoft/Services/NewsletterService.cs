using CloudSoft.Models;
using CloudSoft.Repositories;

namespace CloudSoft.Services;

public class NewsletterService : INewsletterService
{
    private readonly ISubscriberRepository _subscriberRepository;

    public NewsletterService(ISubscriberRepository subscriberRepository)
    {
        _subscriberRepository = subscriberRepository;
    }

    public async Task<OperationResult> SignUpForNewsletterAsync(Subscriber subscriber)
    {
        // Check subscriber is not null and has a valid email
        if (subscriber == null || string.IsNullOrWhiteSpace(subscriber.Email))
        {
            return OperationResult.Failure("Invalid subscriber information.");
        }

        // Check if the email is already subscribed
        if (await _subscriberRepository.ExistsAsync(subscriber.Email))
        {
            return OperationResult.Failure("You are already subscribed to our newsletter.");
        }

        // Add the subscriber to the repository
        var success = await _subscriberRepository.AddAsync(subscriber);
        
        if (!success)
        {
            return OperationResult.Failure("Failed to add your subscription. Please try again.");
        }

        // Return a success message
        return OperationResult.Success($"Welcome to our newsletter, {subscriber.Name}! You'll receive updates soon.");
    }

    public async Task<OperationResult> OptOutFromNewsletterAsync(string email)
    {
        // Check if the email is valid
        if (string.IsNullOrWhiteSpace(email))
        {
            return OperationResult.Failure("Invalid email address.");
        }

        // Find the subscriber by email
        var subscriber = await _subscriberRepository.GetByEmailAsync(email);

        if (subscriber == null)
        {
            return OperationResult.Failure("We couldn't find your subscription in our system.");
        }

        // Remove the subscriber from the repository
        var success = await _subscriberRepository.DeleteAsync(email);
        
        if (!success)
        {
            return OperationResult.Failure("Failed to remove your subscription. Please try again.");
        }

        // Return a success message
        return OperationResult.Success("You have been successfully removed from our newsletter. We're sorry to see you go!");
    }

    public async Task<IEnumerable<Subscriber>> GetActiveSubscribersAsync()
    {
        // Get all subscribers from the repository and convert to List to match the interface
        var subscribers = await _subscriberRepository.GetAllAsync();
        return subscribers.ToList();
    }
}
