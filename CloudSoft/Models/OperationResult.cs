namespace CloudSoft.Models;

public class OperationResult
{
    public bool IsSuccess { get; private set; }
    public string Message { get; private set; }

    private OperationResult(bool success, string message)
    {
        IsSuccess = success;
        Message = message;
    }

    public static OperationResult Success(string message) => new(true, message);
    public static OperationResult Failure(string message) => new(false, message);
}
