import json
import os
import boto3
import requests

def get_secret(secret_id):
    client = boto3.client('secretsmanager', region_name=os.environ['AWS_REGION'])
    result = client.get_secret_value(SecretId=secret_id)
    return json.loads(result['SecretString'])

def explain(anomaly, secret=None):
    secret = secret or get_secret(os.environ['KODEKEY_SECRET_ID'])
    request_body = {
        'model': secret['model'],
        'messages': [{
            'role': 'user',
            'content': json.dumps({
                'instruction': 'Explain this FinOps anomaly using only the supplied evidence. Return structured JSON.',
                'anomaly': anomaly,
            })
        }],
        'temperature': 0.1,
    }
    response = requests.post(
        secret['base_url'],
        headers={'Authorization': f"Bearer {secret['api_key']}", 'Content-Type': 'application/json'},
        json=request_body,
        timeout=30,
    )
    response.raise_for_status()
    return request_body, response.json()
