import json
import os
import boto3
from datetime import datetime

s3_client = boto3.client('s3')

def lambda_handler(event, context):
    bucket_name = os.environ['S3_BUCKET_NAME']

    # Generate timestamped filename
    timestamp = datetime.utcnow().strftime('%Y-%m-%d_%H-%M-%S')
    object_key = f"mysql-backups/backup_{timestamp}.sql.gz"

    # Generate a Pre-Signed PUT URL valid for 30 minutes (1800 seconds)
    presigned_url = s3_client.generate_presigned_url(
        'put_object',
        Params={
            'Bucket': bucket_name,
            'Key': object_key,
            'ContentType': 'application/x-gzip'
        },
        ExpiresIn=1800
    )

    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({'upload_url': presigned_url, 'object_key': object_key})
    }
