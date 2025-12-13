import json

def lambda_handler(event, context):
    """
    The main function that AWS Lambda calls when the function is executed.
    
    :param event: A dictionary containing data provided by the runtime or trigger source.
    :param context: An object providing methods and properties about the runtime 
                    environment, such as request ID, log group, and memory limits.
    :return: A dictionary (or other JSON serializable object) containing the function's result.
    """
    # TODO: Implement your function's logic here
    print("Hello from Lambda!") # Example logging
    
    return {
        'statusCode': 200,
        'body': json.dumps('Execution successful!')
    }
