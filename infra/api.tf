# ==========================================
# BACKEND: IAM Execution Role for Lambda
# ==========================================
resource "aws_iam_role" "lambda_role" {
  name = "researchwatcher-lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}


resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_role.name
  
  # This managed policy grants CreateNetworkInterface, DescribeNetworkInterfaces, and DeleteNetworkInterface
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}
# ==========================================
# BACKEND: AWS Lambda Function (FastAPI)
# ==========================================


# Create a minimal dummy code string dynamically
data "archive_file" "lambda_placeholder" {
  type        = "zip"
  output_path = "${path.module}/dummy_lambda.zip"

  source {
    content  = <<EOF
def lambda_handler(event, context):
    return {
        'statusCode': 200,
        'body': 'Placeholder for CodePipeline'
    }
EOF
    filename = "lambda_function.py"
  }
}




resource "aws_lambda_function" "fastapi" {
  function_name = "researchwatcher-backend-staging"
  runtime       = "python3.13"
  handler       = "main.handler" # Points to your Mangum handler script
  role          = aws_iam_role.lambda_role.arn
  
  environment {
    variables = {
      # Resolves your dynamic CORS issue at deployment execution time!
      FRONTEND_ORIGIN = "http://${aws_s3_bucket_website_configuration.frontend_hosting.website_endpoint}"
    }
  }


  vpc_config {
    # Replace these with your actual VPC subnet and security group IDs/resources
    subnet_ids         = [aws_subnet.public_a.id]
    security_group_ids = [aws_security_group.vpc_internal.id]
  }
  # Pass the path to the dummy ZIP file created above
  filename         = data.archive_file.lambda_placeholder.output_path
  source_code_hash = data.archive_file.lambda_placeholder.output_base64sha256

  # Crucial for CodePipeline - ignore updating the code later
  lifecycle {
    ignore_changes = [
      filename,
      source_code_hash,
    ]
  }
}

# ==========================================
# BACKEND: API Gateway (HTTP API v2)
# ==========================================
resource "aws_apigatewayv2_api" "http_api" {
  name          = "researchwatcher-gateway-staging"
  protocol_type = "HTTP"
}

# Connects Gateway routes straight to your Lambda backend proxy function
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.http_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.fastapi.invoke_arn
}

# Catch-All Route matching /{proxy+} 
resource "aws_apigatewayv2_route" "catch_all" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# Auto-deploys the staging route instance configuration immediately
resource "aws_apigatewayv2_stage" "staging" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "staging"
  auto_deploy = true
}

# Grants permission for API Gateway to invoke your Lambda function
resource "aws_lambda_permission" "api_gw_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fastapi.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}